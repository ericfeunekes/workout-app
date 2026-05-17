// PushQueue.swift
//
// The third responsibility split out of SyncManager per HS-1. Holds pending
// `set_log` and status-update rows, pushes them in batches, removes on 2xx.
//
// Idempotency: each `SetLog` carries its app-assigned UUID. Re-pushing is
// safe because the server upserts on UUID (per `docs/sync.md` § "Push
// protocol"). So on transient failure the queue re-pushes on the next flush
// with no extra reasoning.
//
// Error handling, per `docs/sync.md`:
//   • 2xx  → remove item from queue, fire `.pushSucceeded`
//   • 401  → leave all items, fire `.tokenRejected`, stop this flush
//   • 5xx  → leave this item for retry, bump attempts, fire `.networkFailed`
//           (queue may still continue to the next item — server may just be
//           rejecting this specific batch)
//   • network-level throw → leave item for retry, fire `.networkFailed`
//
// The queue does NOT own retry cadence — `ConnectionManager` (or a caller
// above it) decides when `flush()` is next invoked. Per `docs/sync.md`
// § "Cadence" that's ~60s while foregrounded, no exponential backoff.

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
import WorkoutDBSchema

/// Outcome of a single `flush()` call. `pushed` and `remaining` are counts —
/// callers typically just care whether the queue is drained.
public struct FlushResult: Sendable, Equatable {
    public let pushed: Int
    public let remaining: Int
    public let tokenRejected: Bool
    public let networkFailed: Bool

    public init(pushed: Int, remaining: Int, tokenRejected: Bool, networkFailed: Bool) {
        self.pushed = pushed
        self.remaining = remaining
        self.tokenRejected = tokenRejected
        self.networkFailed = networkFailed
    }
}

public actor PushQueue {
    /// The durable queue. `internal` (not `private`) so
    /// `PushQueue+Dedup.swift` can peek for logical-identity collisions
    /// before a new enqueue lands. Only other `PushQueue` extensions in
    /// the Sync module can see it.
    let store: PushQueueStore
    private let transport: HTTPTransport
    private let clock: any Clock
    /// JSON encoder shared across encode paths. `internal` so
    /// `PushQueue+Encoding.swift` can reach it without a parameter.
    let encoder: JSONEncoder
    /// The number of items pulled per flush. Small enough to bound memory, big
    /// enough that the steady-state (one set per log) drains in one pass.
    private let batchSize: Int
    /// Fire-and-forget telemetry sink. Used to record
    /// `execution.push_item_dead_lettered` when the queue drops a row
    /// whose persistent 4xx (non-401) count crosses
    /// `PushBackoff.deadLetterThreshold`. A no-op emitter is the default
    /// so existing callers don't have to wire anything.
    private let telemetry: TelemetryEmitter
    /// Per-item count of consecutive persistent-4xx (non-401) failures.
    /// NOT persisted — if the process restarts the counter resets, which
    /// is the correct behavior: a cold start is a fresh shot at the
    /// server. Cleared when an item is removed (via dead-letter or 2xx)
    /// or when a fresh enqueue replaces the id in the store.
    private var persistent4xxAttempts: [PushItemID: Int] = [:]

    public init(
        store: PushQueueStore,
        transport: HTTPTransport,
        clock: any Clock = SystemClock(),
        batchSize: Int = 32,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        self.store = store
        self.transport = transport
        self.clock = clock
        self.encoder = JSONEncoder.workoutDB()
        self.batchSize = batchSize
        self.telemetry = telemetry
    }

    /// Enqueue a batch of set_logs. Callers typically pass the single log
    /// that was just written; batching at workout completion is also fine.
    ///
    /// Logical dedup: for a single-log payload we drop any queued item that
    /// carries a `.setLogs` payload containing the same SetLog.id BEFORE
    /// inserting the fresh one. Otherwise a correction to a just-logged
    /// set would queue a stale and a fresh copy side-by-side — the server
    /// upserts on id so both get collapsed, but the stale copy gets pushed
    /// first and transiently overwrites the corrected bytes on the server
    /// until the second push resolves. Batch payloads (multi-log arrays)
    /// are NOT deduped — a workout-completion batch is a distinct logical
    /// unit and shouldn't shadow individual single-log enqueues.
    public func enqueueSetLogs(_ logs: [CoreDomain.SetLog]) async throws {
        if logs.count == 1 {
            try await dropExistingSetLog(id: logs[0].id)
        }
        let item = PushItem(
            payload: .setLogs(logs),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    public func enqueuePrimitiveSetLogs(_ logs: [CoreDomain.PrimitiveSetLog]) async throws {
        if logs.count == 1 {
            try await dropExistingPrimitiveSetLog(id: logs[0].id)
        }
        let item = PushItem(
            payload: .primitiveSetLogs(logs),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    /// Enqueue a terminal-status update for a workout. Logical dedup: any
    /// previously-queued status update for the same (workoutID, status)
    /// pair is dropped first. Real-world trigger: the user taps End, then
    /// Save & Done — without dedup we'd queue two identical updates.
    ///
    /// `notes` rides on the terminal push so the server becomes
    /// authoritative for the user-authored post-workout note. Without
    /// this the next `sync/pull` overwrote the just-typed note with the
    /// server's stale value. `nil` leaves the existing server-side note
    /// untouched (non-terminal flips pass nil).
    public func enqueueStatusUpdate(
        workoutID: WorkoutID,
        status: CoreDomain.WorkoutStatus,
        completedAt: Date?,
        notes: String? = nil
    ) async throws {
        try await dropExistingStatusUpdate(workoutID: workoutID, status: status)
        let item = PushItem(
            payload: .statusUpdate(
                workoutID: workoutID,
                status: status,
                completedAt: completedAt,
                notes: notes
            ),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    /// Enqueue a terminal completed-workout result as one logical REST
    /// publication. The input is the app-owned local completion artifact;
    /// this method turns it into the `/api/sync/results` queue item that
    /// keeps final set_logs and completed status atomic on the server.
    public func enqueueCompletionResults(_ record: CoreDomain.WorkoutCompletionRecord) async throws {
        let item = PushItem(
            payload: .completionResults(
                workoutID: record.workoutID,
                completedAt: record.completedAt,
                notes: record.notes,
                setLogs: record.setLogs,
                primitiveSetLogs: record.primitiveSetLogs
            ),
            enqueuedAt: clock.now
        )
        var keys = Set(record.setLogs.map { "setLog:\($0.id.uuidString.lowercased())" })
        for log in record.primitiveSetLogs {
            keys.insert("primitiveSetLog:\(log.id.uuidString.lowercased())")
        }
        keys.insert("status:\(record.workoutID.uuidString.lowercased()):\(CoreDomain.WorkoutStatus.completed.rawValue)")
        keys.insert("completion:\(record.workoutID.uuidString.lowercased())")
        try await store.enqueue(item, replacingDedupKeys: keys)
    }

    /// Enqueue a workout reset. This is used when the user deletes an
    /// accidentally logged same-day workout from History: the server must
    /// delete the associated set_logs and return the workout to `planned`
    /// or the next pull would rehydrate the completed row locally.
    public func enqueueWorkoutReset(workoutID: WorkoutID) async throws {
        try await dropExistingWorkoutReset(workoutID: workoutID)
        let item = PushItem(
            payload: .workoutReset(workoutID: workoutID),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    /// Enqueue a batch of telemetry events. Routed to `/api/telemetry/events`
    /// at push time — a separate endpoint from set_logs/status_updates so
    /// telemetry failures never block user data and vice versa.
    ///
    /// Events are NOT deduped — diagnostics are append-only and a replay
    /// is just another event row on the server. Duplicates are cheap.
    public func enqueueEvents(_ events: [CoreTelemetry.Event]) async throws {
        let item = PushItem(
            payload: .events(events),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    /// Enqueue a single `user_parameter` row. Routed to
    /// `/api/user-parameters` at push time. `user_parameters` is append-
    /// only on the server but the app owns the id end-to-end, so an
    /// in-queue replay of the same id upserts server-side.
    ///
    /// Logical dedup: any queued item with the same `UserParameter.id` is
    /// dropped first. Trigger: user edits the bodyweight again before the
    /// first push flushes — we want the latest value, not a stale-then-
    /// fresh sequence that transiently overwrites.
    public func enqueueUserParameter(_ param: CoreDomain.UserParameter) async throws {
        try await dropExistingUserParameter(id: param.id)
        let item = PushItem(
            payload: .userParameter(param),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    // Logical dedup helpers (`dropExisting*`) live in
    // `PushQueue+Dedup.swift` so the actor body stays under SwiftLint's
    // `type_body_length` cap.

    public func isEmpty() async throws -> Bool {
        try await store.isEmpty()
    }

    /// Push up to `batchSize` oldest items. Returns a `FlushResult` the
    /// caller can hand to `ConnectionManager.observe(...)`. On 401 the flush
    /// short-circuits — subsequent items are not attempted until the token
    /// is rotated and the caller calls `flush` again.
    public func flush(bearerToken: String) async throws -> FlushResult {
        let items = try await store.peek(max: batchSize)
        if items.isEmpty {
            let remaining = try await store.isEmpty() ? 0 : 1
            return FlushResult(
                pushed: 0,
                remaining: remaining,
                tokenRejected: false,
                networkFailed: false
            )
        }

        var pushed = 0
        var networkFailed = false
        var tokenRejected = false

        for item in items where !tokenRejected {
            switch try await pushOne(item, bearerToken: bearerToken) {
            case .pushed:
                pushed += 1
            case .networkFailed:
                networkFailed = true
            case .tokenRejected:
                tokenRejected = true
            }
        }

        let remaining = try await store.peek(max: batchSize).count
        return FlushResult(
            pushed: pushed,
            remaining: remaining,
            tokenRejected: tokenRejected,
            networkFailed: networkFailed
        )
    }

    /// Outcome of a single item push. Collapses the "encode + transport +
    /// status code" branching so `flush` stays short.
    private enum PushOutcome {
        case pushed
        case networkFailed
        case tokenRejected
    }

    /// Encode, transport, and classify the outcome for a single queue item.
    /// Caller is responsible for bumping the per-item attempt counter only
    /// when we return a non-`.pushed` outcome; we do that here so `flush`
    /// does not need to know the bookkeeping rules.
    private func pushOne(_ item: PushItem, bearerToken: String) async throws -> PushOutcome {
        let body: Data
        do {
            body = try encodeBody(for: item)
        } catch {
            throw SyncError.encode("push body: \(error)")
        }

        let path = pushPath(for: item.payload)
        let response: HTTPResponse
        do {
            response = try await transport.post(
                path: path,
                body: body,
                bearerToken: bearerToken
            )
        } catch let err as SyncError {
            try await store.update(item.incrementingAttempts())
            if case .tokenRejected = err {
                return .tokenRejected
            }
            return .networkFailed
        } catch {
            try await store.update(item.incrementingAttempts())
            return .networkFailed
        }

        switch response.status {
        case 200...299:
            persistent4xxAttempts[item.id] = nil
            try await store.remove(ids: [item.id])
            return .pushed
        case 401:
            // 401 is its own signal path — the bearer is bad, not the
            // body. Don't count it against the persistent-4xx budget;
            // reauth replaces the token and the same row ships again.
            try await store.update(item.incrementingAttempts())
            return .tokenRejected
        case 400...499:
            // Persistent 4xx (non-401): the server is saying "this body
            // will never be accepted". Count it, and after
            // `PushBackoff.deadLetterThreshold` consecutive hits drop the
            // row + emit telemetry so it can't block the queue forever.
            return try await handlePersistent4xx(item: item, status: response.status)
        default:
            // 5xx / 1xx / 3xx — transient by convention. Leave the item
            // for retry; `PushBackoff` slows the loop on consecutive
            // failures at the caller level.
            try await store.update(item.incrementingAttempts())
            return .networkFailed
        }
    }

    /// Persistent-4xx bookkeeping. Increments the in-memory counter for
    /// this item; on the Nth consecutive hit we emit a telemetry event and
    /// drop the row from the store. Returning `.networkFailed` for
    /// sub-threshold attempts keeps the existing `FlushResult` contract
    /// honest — the caller can slow the loop on consecutive network
    /// failures. A dead-lettered drop also returns `.networkFailed` (the
    /// flush ultimately did not land) so the caller's backoff counter
    /// behaves identically.
    private func handlePersistent4xx(
        item: PushItem,
        status: Int
    ) async throws -> PushOutcome {
        let nextCount = (persistent4xxAttempts[item.id] ?? 0) + 1
        if nextCount >= PushBackoff.deadLetterThreshold {
            persistent4xxAttempts[item.id] = nil
            telemetry.emit(Event(
                sessionID: TelemetrySession.id,
                kind: "state",
                name: "execution.push_item_dead_lettered",
                dataJSON: deadLetterDataJSON(
                    item: item, status: status, attempts: nextCount
                )
            ))
            try await store.remove(ids: [item.id])
            return .networkFailed
        }
        persistent4xxAttempts[item.id] = nextCount
        try await store.update(item.incrementingAttempts())
        return .networkFailed
    }

    // Implementation note: new enqueues get a fresh `PushItem.id`, so a
    // dedup-replaced row's old counter is orphaned in the dictionary —
    // harmless (no correctness impact, trivial memory) and keeps this
    // file off `PushQueue+Dedup.swift`'s back. The "fresh enqueue resets
    // counter" property tested in SyncTests holds via the new id, not
    // via explicit clearing.

    // Body encoding + endpoint routing live in
    // `PushQueue+Encoding.swift`; dead-letter telemetry payload builders
    // live in `PushQueue+DeadLetter.swift`. Both splits keep the actor
    // body under SwiftLint's `type_body_length` cap.
}
