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
    private let store: PushQueueStore
    private let transport: HTTPTransport
    private let clock: any Clock
    private let encoder: JSONEncoder
    /// The number of items pulled per flush. Small enough to bound memory, big
    /// enough that the steady-state (one set per log) drains in one pass.
    private let batchSize: Int

    public init(
        store: PushQueueStore,
        transport: HTTPTransport,
        clock: any Clock = SystemClock(),
        batchSize: Int = 32
    ) {
        self.store = store
        self.transport = transport
        self.clock = clock
        self.encoder = JSONEncoder.workoutDB()
        self.batchSize = batchSize
    }

    /// Enqueue a batch of set_logs. Callers typically pass the single log
    /// that was just written; batching at workout completion is also fine.
    public func enqueueSetLogs(_ logs: [CoreDomain.SetLog]) async throws {
        let item = PushItem(
            payload: .setLogs(logs),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    public func enqueueStatusUpdate(
        workoutID: WorkoutID,
        status: CoreDomain.WorkoutStatus,
        completedAt: Date?
    ) async throws {
        let item = PushItem(
            payload: .statusUpdate(workoutID: workoutID, status: status, completedAt: completedAt),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    /// Enqueue a batch of telemetry events. Routed to `/api/telemetry/events`
    /// at push time — a separate endpoint from set_logs/status_updates so
    /// telemetry failures never block user data and vice versa.
    public func enqueueEvents(_ events: [CoreTelemetry.Event]) async throws {
        let item = PushItem(
            payload: .events(events),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

    /// Enqueue a single `user_parameter` row. Routed to
    /// `/api/user-parameters` at push time. `user_parameters` is append-
    /// only on the server; the app's UUID is not sent (the server assigns
    /// its own id per insert).
    public func enqueueUserParameter(_ param: CoreDomain.UserParameter) async throws {
        let item = PushItem(
            payload: .userParameter(param),
            enqueuedAt: clock.now
        )
        try await store.enqueue(item)
    }

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
            try await store.remove(ids: [item.id])
            return .pushed
        case 401:
            try await store.update(item.incrementingAttempts())
            return .tokenRejected
        default:
            // 4xx (non-401) and 5xx both land here. Leave the item for
            // retry — server errors are transient; 4xx other than 401
            // for us is "server rejected this specific body" and we'd
            // rather re-push than silently drop.
            try await store.update(item.incrementingAttempts())
            return .networkFailed
        }
    }

    // MARK: - Private

    /// Route a payload to its endpoint. Set logs + status updates share
    /// `/api/sync/results`; telemetry has its own endpoint so failures on
    /// one path don't block the other; user_parameters have their own
    /// endpoint and are append-only.
    private func pushPath(for payload: PushItem.Payload) -> String {
        switch payload {
        case .setLogs, .statusUpdate:
            return "/api/sync/results"
        case .events:
            return "/api/telemetry/events"
        case .userParameter:
            return "/api/user-parameters"
        }
    }

    private func encodeBody(for item: PushItem) throws -> Data {
        switch item.payload {
        case .setLogs(let logs):
            let payload = WorkoutDBSchema.SyncResultsPayload(
                setLogs: logs.map(DTOMapping.toDTO),
                statusUpdates: []
            )
            return try encoder.encode(payload)
        case .statusUpdate(let workoutID, let status, let completedAt):
            // `CoreDomain.WorkoutStatus` and `WorkoutDBSchema.WorkoutStatus`
            // share their string-backed cases by construction (contract test
            // `test_swift_schema_parity.py` enforces parity). The force-unwrap
            // cannot fail without a concurrent schema drift that CI would
            // have rejected.
            // swiftlint:disable:next force_unwrapping
            let wireStatus = WorkoutDBSchema.WorkoutStatus(rawValue: status.rawValue)!
            let dto = WorkoutDBSchema.WorkoutStatusUpdate(
                workoutId: workoutID.uuidString,
                status: wireStatus,
                completedAt: completedAt
            )
            let payload = WorkoutDBSchema.SyncResultsPayload(
                setLogs: [],
                statusUpdates: [dto]
            )
            return try encoder.encode(payload)
        case .events(let events):
            let dtoEvents = events.map { event -> WorkoutDBSchema.TelemetryEvent in
                WorkoutDBSchema.TelemetryEvent(
                    id: event.id.uuidString.lowercased(),
                    timestamp: event.timestamp,
                    sessionId: event.sessionID.uuidString.lowercased(),
                    kind: event.kind,
                    name: event.name,
                    dataJson: event.dataJSON,
                    workoutId: event.workoutID?.uuidString.lowercased(),
                    setLogId: event.setLogID?.uuidString.lowercased()
                )
            }
            let payload = WorkoutDBSchema.TelemetryEventsPayload(events: dtoEvents)
            return try encoder.encode(payload)
        case .userParameter(let param):
            // Server's `POST /api/user-parameters` expects an array of
            // `UserParameterIn` — `{key, value, source, updated_at?}`. The
            // server assigns the row id and resolves user_id from the
            // bearer token; we do not send our local UUID. See
            // `server/workoutdb_server/api/user_parameters.py`.
            let body = [DTOMapping.toInDTO(param)]
            return try encoder.encode(body)
        }
    }
}
