// AppSyncCoordinatorTests.swift
//
// Pins the Shell-owned foreground sync coordinator: pull/cache writeback,
// flusher lifecycle, token rejection, and lifecycle telemetry live behind
// one app-level owner rather than leaking back into RootView or Today.

import XCTest
import CoreTelemetry
import Persistence
import Sync
import WorkoutCoreFoundation
@testable import Shell

@MainActor
final class AppSyncCoordinatorTests: XCTestCase {

    func testRefreshPullsSavesCacheAndLastSyncAt() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let telemetry = ShellTelemetryRecorder()
        let coordinator = makeCoordinator(
            factory: factory,
            transport: transport,
            telemetry: telemetry
        )

        let result = await coordinator.refresh(trigger: .bootstrap)

        XCTAssertEqual(result, .pulled(serverTime: fixture.serverTime))
        let stored = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertEqual(stored, fixture.serverTime)
        let workouts = try await factory.workoutCache.loadWorkouts(status: .planned, since: nil)
        XCTAssertEqual(workouts.map(\.id), [fixture.domainWorkout.id])
        let names = telemetry.events.map(\.name)
        XCTAssertTrue(names.contains("sync.pull_started"))
        XCTAssertTrue(names.contains("sync.cache_write_succeeded"))
        XCTAssertTrue(names.contains("sync.pull_succeeded"))
        let succeeded = try XCTUnwrap(telemetry.events.first {
            $0.name == "sync.pull_succeeded"
        })
        let payload = try decodePayload(succeeded)
        XCTAssertEqual(payload["trigger"] as? String, "bootstrap")
        XCTAssertEqual(payload["outcome"] as? String, "succeeded")
        XCTAssertEqual(payload["sincePresent"] as? Bool, false)
        XCTAssertEqual(payload["pulledWorkoutCount"] as? Int, 1)
    }

    func testForegroundLifecycleStartsStopsAndRestartsFlusher() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json), .ok(fixture.json)]
        )
        let telemetry = ShellTelemetryRecorder()
        let flusher = RecordingFlusher()
        let coordinator = makeCoordinator(
            factory: factory,
            transport: transport,
            telemetry: telemetry,
            flusher: flusher
        )

        _ = await coordinator.enterForeground()
        _ = await coordinator.enterBackground()
        _ = await coordinator.enterForeground()

        let counts = await flusher.counts()
        XCTAssertEqual(counts.start, 2)
        XCTAssertEqual(counts.stop, 1)
        let names = telemetry.events.map(\.name)
        XCTAssertTrue(names.contains("sync.lifecycle_foreground_requested"))
        XCTAssertTrue(names.contains("sync.lifecycle_background"))
        XCTAssertTrue(names.contains("sync.flusher_started"))
        XCTAssertTrue(names.contains("sync.flusher_restarted"))
    }

    func testTokenRejectedStopsFlusherAndDoesNotAdvanceMetadata() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        await factory.syncMetadataStore.setLastSyncAt(fixture.serverTime)
        let transport = ScriptedTransport(getOutcomes: [.error(.tokenRejected)])
        let telemetry = ShellTelemetryRecorder()
        let flusher = RecordingFlusher()
        let coordinator = makeCoordinator(
            factory: factory,
            transport: transport,
            telemetry: telemetry,
            flusher: flusher
        )

        let result = await coordinator.refresh(trigger: .manualTodayRefresh)

        XCTAssertEqual(result, .tokenRejected)
        let stored = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertEqual(stored, fixture.serverTime)
        let counts = await flusher.counts()
        XCTAssertEqual(counts.stop, 1)
        let names = telemetry.events.map(\.name)
        XCTAssertTrue(names.contains("sync.token_rejected"))
        XCTAssertTrue(names.contains("sync.pull_token_rejected"))
        let rejected = try XCTUnwrap(telemetry.events.first {
            $0.name == "sync.pull_token_rejected"
        })
        let payload = try decodePayload(rejected)
        XCTAssertEqual(payload["trigger"] as? String, "manualTodayRefresh")
        XCTAssertEqual(payload["outcome"] as? String, "token_rejected")
    }

    func testNetworkFailureFallsBackWithoutClearingCache() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let initialTransport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let initial = makeCoordinator(factory: factory, transport: initialTransport)
        _ = await initial.refresh(trigger: .bootstrap)

        let failingTransport = ScriptedTransport(getOutcomes: [.error(.network("dns"))])
        let coordinator = makeCoordinator(factory: factory, transport: failingTransport)

        let result = await coordinator.refresh(trigger: .foreground)

        guard case .fallback = result else {
            return XCTFail("expected fallback, got \(result)")
        }
        let workouts = try await factory.workoutCache.loadWorkouts(status: .planned, since: nil)
        XCTAssertEqual(workouts.map(\.id), [fixture.domainWorkout.id])
        let stored = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertEqual(stored, fixture.serverTime)
    }

    func testManualFlushTokenRejectedStopsFlusherAndRoutesRecovery() async throws {
        let factory = try makeFactory()
        let telemetry = ShellTelemetryRecorder()
        let flusher = RecordingFlusher(flushResult: .tokenRejected)
        var recoveryCount = 0
        let coordinator = makeCoordinator(
            factory: factory,
            transport: ScriptedTransport(),
            telemetry: telemetry,
            flusher: flusher,
            onTokenRejected: {
                recoveryCount += 1
            }
        )

        let result = await coordinator.flushNow()

        XCTAssertEqual(result, .tokenRejected)
        XCTAssertEqual(recoveryCount, 1)
        let counts = await flusher.counts()
        XCTAssertEqual(counts.flushNow, 1)
        XCTAssertEqual(counts.stop, 1)
        let names = telemetry.events.map(\.name)
        XCTAssertTrue(names.contains("sync.flusher_manual_kicked"))
        XCTAssertTrue(names.contains("sync.push_token_rejected"))
        XCTAssertTrue(names.contains("sync.token_rejected"))
        let rejected = try XCTUnwrap(telemetry.events.first {
            $0.name == "sync.push_token_rejected"
        })
        let payload = try decodePayload(rejected)
        XCTAssertEqual(payload["trigger"] as? String, "foreground")
        XCTAssertEqual(payload["outcome"] as? String, "token_rejected")
    }

    func testForegroundRefreshHandlerRunsAfterSuccessfulForegroundPull() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let coordinator = makeCoordinator(factory: factory, transport: transport)
        var handled: [(AppSyncTrigger, AppSyncRefreshResult)] = []
        coordinator.setForegroundRefreshHandler { trigger, result in
            handled.append((trigger, result))
        }

        _ = await coordinator.enterForeground()

        XCTAssertEqual(handled.count, 1)
        XCTAssertEqual(handled[0].0, .foreground)
        XCTAssertEqual(handled[0].1, .pulled(serverTime: fixture.serverTime))
    }

    func testBackgroundDuringForegroundPullDoesNotRestartFlusherOrRefreshVisibleState() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = BlockingGetTransport(outcome: .ok(fixture.json))
        let flusher = RecordingFlusher()
        let coordinator = makeCoordinator(
            factory: factory,
            transport: transport,
            flusher: flusher
        )
        var handled: [(AppSyncTrigger, AppSyncRefreshResult)] = []
        coordinator.setForegroundRefreshHandler { trigger, result in
            handled.append((trigger, result))
        }

        let foreground = Task { @MainActor in
            await coordinator.enterForeground()
        }
        await transport.waitUntilRequested()
        _ = await coordinator.enterBackground()
        await transport.release()
        _ = await foreground.value

        XCTAssertTrue(handled.isEmpty)
        let counts = await flusher.counts()
        XCTAssertEqual(counts.start, 0)
        XCTAssertEqual(counts.stop, 1)
    }

    func testRetiredCoordinatorDoesNotWriteStalePullToCache() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = BlockingGetTransport(outcome: .ok(fixture.json))
        let coordinator = makeCoordinator(factory: factory, transport: transport)

        let task = Task { @MainActor in
            await coordinator.refresh(trigger: .foreground)
        }
        await transport.waitUntilRequested()
        let retire = Task { @MainActor in
            await coordinator.retire()
        }
        await transport.release()
        await retire.value
        let result = await task.value

        guard case .fallback = result else {
            return XCTFail("expected retired fallback, got \(result)")
        }
        let workouts = try await factory.workoutCache.loadWorkouts(status: .planned, since: nil)
        XCTAssertTrue(workouts.isEmpty)
        let stored = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertNil(stored)
    }

    func testOverlappingRefreshesCoalesceToOnePull() async throws {
        let factory = try makeFactory()
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = BlockingGetTransport(outcome: .ok(fixture.json))
        let coordinator = makeCoordinator(factory: factory, transport: transport)

        let first = Task { @MainActor in
            await coordinator.refresh(trigger: .foreground)
        }
        await transport.waitUntilRequested()
        let second = Task { @MainActor in
            await coordinator.refresh(trigger: .manualTodayRefresh)
        }
        await transport.release()
        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertEqual(firstResult, .pulled(serverTime: fixture.serverTime))
        XCTAssertEqual(secondResult, .pulled(serverTime: fixture.serverTime))
        let getCount = await transport.getCount()
        XCTAssertEqual(getCount, 1)
    }


    private func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    private func makeCoordinator(
        factory: PersistenceFactory,
        transport: any HTTPTransport,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        flusher: (any ForegroundPushFlushing)? = nil,
        onTokenRejected: (@Sendable @MainActor () async -> Void)? = nil
    ) -> AppSyncCoordinator {
        let api = SyncAPI(
            transport: transport,
            store: factory.pushQueueStore,
            tokenProvider: { "tok" },
            telemetry: telemetry
        )
        return AppSyncCoordinator(
            syncAPI: api,
            persistence: factory,
            telemetry: telemetry,
            flusher: flusher,
            onTokenRejected: onTokenRejected
        )
    }

    private func decodePayload(_ event: Event) throws -> [String: Any] {
        let raw = try XCTUnwrap(event.dataJSON)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(decoded as? [String: Any])
    }
}

private actor RecordingFlusher: ForegroundPushFlushing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var flushNowCount = 0
    private let flushResult: AppSyncPushResult

    init(flushResult: AppSyncPushResult = .completed) {
        self.flushResult = flushResult
    }

    func start() async {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func flushNow() async -> AppSyncPushResult {
        flushNowCount += 1
        return flushResult
    }

    func counts() -> (start: Int, stop: Int, flushNow: Int) {
        (start: startCount, stop: stopCount, flushNow: flushNowCount)
    }
}

private actor BlockingGetTransport: HTTPTransport {
    private let outcome: ScriptedOutcome
    private var requested = false
    private var requests = 0
    private var released = false
    private var requestContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(outcome: ScriptedOutcome) {
        self.outcome = outcome
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { continuation in
            requestContinuations.append(continuation)
        }
    }

    func release() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func get(
        path: String,
        query: [(String, String)],
        bearerToken: String
    ) async throws -> HTTPResponse {
        requested = true
        requests += 1
        let continuations = requestContinuations
        requestContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
        if !released {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }
        return try resolve(outcome)
    }

    func getCount() -> Int {
        requests
    }

    func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse {
        HTTPResponse(status: 200, body: Data())
    }

    private func resolve(_ outcome: ScriptedOutcome) throws -> HTTPResponse {
        switch outcome {
        case .ok(let data):
            return HTTPResponse(status: 200, body: data)
        case .status(let status, let data):
            return HTTPResponse(status: status, body: data)
        case .error(let err):
            throw err
        }
    }
}
