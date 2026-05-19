// SyncAPI.swift
//
// The facade Features see. Composes `PullService`, `PushQueue`, and
// `ConnectionManager` — but each is also usable on its own, so Features that
// only need one collaborator can inject just that one.
//
// `SyncAPI` is the place that turns sync errors into `ConnectionEvent`s.
// That wiring lives here (not in each service) so a future swap of
// `PullService` or `PushQueue` does not each have to re-implement the
// 401 → tokenRejected routing.

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation

public final class SyncAPI: Sendable {
    public let pull: PullService
    public let push: PushQueue
    public let connection: ConnectionManager
    private let tokenProvider: @Sendable () async -> String?
    /// Emitter for network.* events. Defaults to a no-op emitter in tests /
    /// previews; production Shell wires the persisted emitter at bootstrap.
    private let telemetry: TelemetryEmitter

    public init(
        pull: PullService,
        push: PushQueue,
        connection: ConnectionManager,
        tokenProvider: @escaping @Sendable () async -> String?,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        self.pull = pull
        self.push = push
        self.connection = connection
        self.tokenProvider = tokenProvider
        self.telemetry = telemetry
    }

    /// Stream of connection state transitions. Rendered by the offline pill.
    public func states() async -> AsyncStream<ConnectionState> {
        await connection.states()
    }

    /// One convenience init: build a `PullService` + `PushQueue` over the
    /// same transport, and a fresh `ConnectionManager`. The telemetry
    /// emitter is threaded into `PushQueue` so the dead-letter path (see
    /// `PushQueue.handlePersistent4xx`) can record
    /// `execution.push_item_dead_lettered` events without needing its own
    /// emitter injection point at the call site.
    public convenience init(
        transport: HTTPTransport,
        store: PushQueueStore,
        clock: any Clock = SystemClock(),
        tokenProvider: @escaping @Sendable () async -> String?,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        self.init(
            pull: PullService(transport: transport),
            push: PushQueue(
                store: store,
                transport: transport,
                clock: clock,
                telemetry: telemetry
            ),
            connection: ConnectionManager(),
            tokenProvider: tokenProvider,
            telemetry: telemetry
        )
    }

    /// Run a pull and feed the outcome into `ConnectionManager`. Returns the
    /// Domain values on success; throws on failure after publishing the
    /// appropriate event.
    public func pullLatest(since: Date?) async throws -> PullResult {
        guard let token = await tokenProvider() else {
            await connection.observe(.tokenRejected)
            throw SyncError.tokenRejected
        }
        if await !connection.allowsRequests {
            throw SyncError.tokenRejected
        }
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "network",
            name: "network.pull_latest",
            dataJSON: since.map { #"{"since":"\#($0)"}"# }
        ))
        await connection.observe(.syncStarted)
        do {
            let result = try await pull.pull(since: since, bearerToken: token)
            telemetry.emit(Event(
                sessionID: TelemetrySession.id,
                kind: "network",
                name: "network.response",
                dataJSON: #"{"path":"/api/sync/pull","status":200}"#
            ))
            await connection.observe(.pullSucceeded(at: result.serverTime))
            return result
        } catch let err as SyncError {
            telemetry.emit(Event(
                sessionID: TelemetrySession.id,
                kind: "network",
                name: "network.error",
                dataJSON: #"{"path":"/api/sync/pull","error":"\#(err)"}"#
            ))
            try await publish(err)
            throw err
        }
    }

    public func pushPrimitiveLog(_ logs: [CoreDomain.PrimitiveSetLog]) async throws {
        try await push.enqueuePrimitiveSetLogs(logs)
    }

    /// Enqueue a workout status change. See `docs/sync.md` § "Push protocol".
    ///
    /// `notes` rides on the terminal status push so the server is
    /// authoritative for the user-authored post-workout note (without
    /// this the next `sync/pull` would overwrite a freshly-typed note
    /// with the server's stale value). Non-terminal flips pass nil.
    public func pushStatus(
        workoutID: WorkoutID,
        status: CoreDomain.WorkoutStatus,
        completedAt: Date?,
        notes: String? = nil
    ) async throws {
        try await push.enqueueStatusUpdate(
            workoutID: workoutID,
            status: status,
            completedAt: completedAt,
            notes: notes
        )
    }

    /// Enqueue an app-owned completed-workout record as one grouped
    /// `/api/sync/results` publication. This keeps final set_logs and the
    /// completed status together for REST while leaving the domain record
    /// transport-neutral for future replication surfaces.
    public func pushCompletion(_ record: CoreDomain.WorkoutCompletionRecord) async throws {
        try await push.enqueueCompletionResults(record)
    }

    /// Enqueue a reset for a same-day workout the user accidentally logged.
    /// The server deletes associated set_logs and returns the workout to
    /// planned so future pulls match the local History reset.
    public func resetWorkout(workoutID: WorkoutID) async throws {
        try await push.enqueueWorkoutReset(workoutID: workoutID)
    }

    /// Enqueue a `user_parameter` append. Returns immediately; the push
    /// happens on the next `flushPushQueue(...)` tick. Body weight, 1RM,
    /// and anything the app writes back to the append-only user-parameter
    /// log flows through this path.
    public func pushUserParameter(_ param: CoreDomain.UserParameter) async throws {
        try await push.enqueueUserParameter(param)
    }

    /// Drive the push queue. Callers should invoke this after each log write
    /// and on the foreground retry tick (~60s per `docs/sync.md`).
    @discardableResult
    public func flushPushQueue() async throws -> FlushResult {
        guard let token = await tokenProvider() else {
            await connection.observe(.tokenRejected)
            throw SyncError.tokenRejected
        }
        if await !connection.allowsRequests {
            return FlushResult(pushed: 0, remaining: -1, tokenRejected: true, networkFailed: false)
        }
        let result = try await push.flush(bearerToken: token)
        if result.tokenRejected {
            await connection.observe(.tokenRejected)
        } else if result.networkFailed {
            await connection.observe(.networkFailed)
        } else if result.pushed > 0 {
            await connection.observe(.pushSucceeded(at: Date()))
        }
        return result
    }

    // MARK: - Private

    private func publish(_ err: SyncError) async throws {
        switch err {
        case .tokenRejected:
            await connection.observe(.tokenRejected)
        case .network:
            await connection.observe(.networkFailed)
        case .server:
            await connection.observe(.networkFailed)
        case .decode, .encode:
            // Decode/encode errors are programmer / server-data problems.
            // Leave the state untouched — the offline pill shouldn't light up
            // because the server sent malformed JSON.
            break
        }
    }
}
