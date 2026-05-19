// PushQueueStore.swift
//
// Protocol for persistent push-queue storage. Sync defines it; `Persistence`
// will implement it against SwiftData when that package lands. Keeping the
// protocol here — not in `Persistence` — lets Sync own its own vocabulary
// (the `PushItem` shape) and avoids a reverse dependency (Persistence →
// Sync) that would violate the graph in `docs/architecture/swift-packages.md`.
//
// In-memory `FakePushQueueStore` lives in `Tests/SyncTests/` — the test
// harness uses it to verify queue behavior without touching disk.

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation

public typealias PushItemID = UUID

/// What we're pushing: primitive result rows, a single workout-status flip,
/// a batch of telemetry events, or a single user_parameter row. The first
/// two hit `/api/sync/results`; `.events` hits `/api/telemetry/events`;
/// `.userParameter` hits `/api/user-parameters`. See `docs/sync.md` §
/// "Push protocol" and the telemetry scope note.
public struct PushItem: Sendable, Equatable {
    public enum Payload: Sendable, Equatable {
        case primitiveSetLogs([CoreDomain.PrimitiveSetLog])
        /// `notes` rides on the terminal status push so the server is
        /// authoritative for the user-authored post-workout note. `nil`
        /// leaves the existing server-side notes alone; a non-nil value
        /// replaces them. Non-terminal status flips (e.g. `.active`)
        /// pass `nil`.
        case statusUpdate(
            workoutID: WorkoutID,
            status: CoreDomain.WorkoutStatus,
            completedAt: Date?,
            notes: String?
        )
        /// Terminal workout completion published as one `/api/sync/results`
        /// body containing all final set_logs plus the completed status.
        /// This is a REST publication detail over the app-owned
        /// `WorkoutCompletionRecord`, not the domain authority itself.
        case completionResults(
            workoutID: WorkoutID,
            completedAt: Date?,
            notes: String?,
            primitiveSetLogs: [CoreDomain.PrimitiveSetLog]
        )
        case workoutReset(workoutID: WorkoutID)
        case events([CoreTelemetry.Event])
        case userParameter(CoreDomain.UserParameter)

        /// Drain priority inside a flush cycle. Lower values flush first.
        /// Results (set logs / status updates / user_parameters) are all
        /// `0`; telemetry is `1`. Telemetry shares the single push queue
        /// with results, so a verbose-mode burst of events could otherwise
        /// shove a freshly-logged set behind a long tail. Weighting keeps
        /// user data ahead of diagnostics without splitting the queue into
        /// two tables.
        public var priority: Int {
            switch self {
            case .primitiveSetLogs, .statusUpdate, .completionResults, .workoutReset, .userParameter:
                return 0
            case .events:
                return 1
            }
        }

        /// Stable string key that identifies the logical row this payload
        /// represents. `nil` means the payload does not participate in
        /// dedup (multi-log batch set_logs and telemetry events are both
        /// nil — see `PushQueue+Dedup.swift` for the matching rules).
        ///
        /// Persisted on `PushItemModel.dedupKey` so `PushQueue+Dedup.swift`
        /// can drop prior matching rows with a single `FetchDescriptor`
        /// predicate instead of scanning + decoding the whole queue. The
        /// shape of the key is an internal contract between Sync and the
        /// store — callers never parse it, they just pass it through.
        public var dedupKey: String? {
            switch self {
            case .primitiveSetLogs(let logs):
                guard logs.count == 1 else { return nil }
                return "primitiveSetLog:\(logs[0].id.uuidString.lowercased())"
            case .statusUpdate(let workoutID, let status, _, _):
                return "status:\(workoutID.uuidString.lowercased()):\(status.rawValue)"
            case .completionResults(let workoutID, _, _, _):
                return "completion:\(workoutID.uuidString.lowercased())"
            case .workoutReset(let workoutID):
                return "reset:\(workoutID.uuidString.lowercased())"
            case .userParameter(let param):
                return "userParam:\(param.id.uuidString.lowercased())"
            case .events:
                return nil
            }
        }
    }

    public let id: PushItemID
    public let payload: Payload
    public let enqueuedAt: Date
    public let attempts: Int
    /// Cached priority — derived from `payload` at init time so
    /// `PushFlusher` / sorting paths don't need to re-match on the enum
    /// every comparison. Derived, not user-supplied.
    public let priority: Int
    /// Cached dedup key — see `Payload.dedupKey`. Nil for payloads that
    /// don't participate in dedup.
    public let dedupKey: String?

    public init(
        id: PushItemID = UUID(),
        payload: Payload,
        enqueuedAt: Date,
        attempts: Int = 0
    ) {
        self.id = id
        self.payload = payload
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.priority = payload.priority
        self.dedupKey = payload.dedupKey
    }

    /// Returns a copy with `attempts` incremented. Used by `PushQueue` on
    /// each flush iteration where an item couldn't be pushed.
    public func incrementingAttempts() -> PushItem {
        PushItem(id: id, payload: payload, enqueuedAt: enqueuedAt, attempts: attempts + 1)
    }
}

/// Durable queue interface. Operations are async so a SwiftData-backed
/// implementation can await actor isolation; in-memory implementations just
/// `return`.
public protocol PushQueueStore: Sendable {
    /// Append an item. Duplicate IDs replace the existing row (idempotent).
    func enqueue(_ item: PushItem) async throws

    /// Read up to `max` items without removing them, ordered by drain
    /// priority first (lower value first — results before telemetry) and
    /// FIFO by `enqueuedAt` within each priority class. Callers use
    /// `remove(ids:)` after a successful push. This ordering is what
    /// keeps a verbose-mode telemetry burst from stalling a freshly-
    /// logged set behind a long tail: `.events` sorts *after* result rows
    /// / `.statusUpdate` / `.userParameter` even when the event rows are
    /// chronologically older.
    func peek(max: Int) async throws -> [PushItem]

    /// Remove a set of items by ID. No error for unknown IDs.
    func remove(ids: [PushItemID]) async throws

    /// Replace an existing row with an updated copy (typically with a bumped
    /// `attempts` counter). No-op for unknown IDs.
    func update(_ item: PushItem) async throws

    /// Remove every queued row whose persisted dedup key equals `key`.
    /// Returns the number of rows removed. The production implementation
    /// uses a scoped `FetchDescriptor` predicate on a persisted
    /// `dedupKey` column, so one enqueue triggers one scoped fetch — not
    /// a full-table scan + in-memory decode pass. `PushQueue+Dedup.swift`
    /// builds the key via `PushItem.Payload.dedupKey` and calls this;
    /// callers never parse the string themselves.
    func removeMatchingDedupKey(_ key: String) async throws -> Int

    /// Atomically remove every queued row whose persisted dedup key is in
    /// `keys`, then enqueue `item`. Production stores must commit the
    /// delete+insert as one durable mutation so a crash cannot strand the
    /// queue between stale-row removal and replacement insertion.
    func enqueue(_ item: PushItem, replacingDedupKeys keys: Set<String>) async throws

    /// Whether the queue has zero items pending.
    func isEmpty() async throws -> Bool

    /// Remove every queued row. Used when the local server identity is being
    /// discarded, so old queued mutations cannot flush to the next server.
    func clear() async throws
}
