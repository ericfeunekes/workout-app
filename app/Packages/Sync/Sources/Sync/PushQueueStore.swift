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

/// What we're pushing: a batch of set_logs, a single workout-status flip,
/// a batch of telemetry events, or a single user_parameter row. The first
/// two hit `/api/sync/results`; `.events` hits `/api/telemetry/events`;
/// `.userParameter` hits `/api/user-parameters`. See `docs/sync.md` §
/// "Push protocol" and the telemetry scope note.
public struct PushItem: Sendable, Equatable {
    public enum Payload: Sendable, Equatable {
        case setLogs([CoreDomain.SetLog])
        case statusUpdate(workoutID: WorkoutID, status: CoreDomain.WorkoutStatus, completedAt: Date?)
        case events([CoreTelemetry.Event])
        case userParameter(CoreDomain.UserParameter)
    }

    public let id: PushItemID
    public let payload: Payload
    public let enqueuedAt: Date
    public let attempts: Int

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

    /// Read up to `max` oldest items without removing them. Callers use
    /// `remove(ids:)` after a successful push. FIFO order by `enqueuedAt`.
    func peek(max: Int) async throws -> [PushItem]

    /// Remove a set of items by ID. No error for unknown IDs.
    func remove(ids: [PushItemID]) async throws

    /// Replace an existing row with an updated copy (typically with a bumped
    /// `attempts` counter). No-op for unknown IDs.
    func update(_ item: PushItem) async throws

    /// Whether the queue has zero items pending.
    func isEmpty() async throws -> Bool
}
