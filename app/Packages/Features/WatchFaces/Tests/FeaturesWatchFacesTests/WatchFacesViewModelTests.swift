// WatchFacesViewModelTests.swift
//
// Tests the v1 contract:
//
//   inbound:
//     .pushActiveBlock      → face becomes .active(<payload>)
//     .pushRestTimer        → face becomes .rest(<payload>)
//     .pushWorkoutComplete  → face returns to .idle
//
//   outbound:
//     tap in .active → bridge receives .setStarted(...)
//     tap in .rest   → bridge receives .setEnded(...)
//
// `FakeWatchBridge.deliver(_:)` is synchronous and the view model's
// `start()` subscribes via `for await`; we kick the view-model loop on a
// detached Task, deliver messages, then poll `face` briefly for the
// expected value. Polling beats a fixed sleep — tests stay fast on a
// quiet machine and don't flake on a busy one.

import XCTest
import HealthKitBridge
import WatchBridge
@testable import FeaturesWatchFaces

@MainActor
final class WatchFacesViewModelTests: XCTestCase {

    // MARK: - Inbound → face

    func testPushActiveBlockTransitionsToActive() async throws {
        let bridge = FakeWatchBridge()
        let vm = WatchFacesViewModel(bridge: bridge)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        let payload = ActiveBlockPayload(
            exerciseName: "Bench",
            prescription: "5 × 102.5 kg",
            setNumber: 2,
            setCount: 5,
            targetRir: 2
        )
        bridge.deliver(.pushActiveBlock(payload))

        try await waitFor { vm.face != .idle }

        switch vm.face {
        case .active(let active):
            XCTAssertEqual(active.exerciseName, "Bench")
            XCTAssertEqual(active.prescription, "5 × 102.5 kg")
            XCTAssertEqual(active.setNumber, 2)
            XCTAssertEqual(active.setCount, 5)
            XCTAssertEqual(active.targetRir, 2)
        default:
            XCTFail("expected .active, got \(vm.face)")
        }
    }

    func testPushRestTimerTransitionsToRest() async throws {
        let bridge = FakeWatchBridge()
        let vm = WatchFacesViewModel(bridge: bridge)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        // Prime with an active block so the rest payload carries the
        // exercise name — this is the realistic wire order.
        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Row",
            prescription: "8 × 80 kg",
            setNumber: 1,
            setCount: 4,
            targetRir: nil
        )))
        try await waitFor {
            if case .active = vm.face { return true }
            return false
        }

        let endsAt = Date().addingTimeInterval(90)
        bridge.deliver(.pushRestTimer(endsAt: endsAt))

        try await waitFor {
            if case .rest = vm.face { return true }
            return false
        }

        switch vm.face {
        case .rest(let rest):
            XCTAssertEqual(rest.endsAt, endsAt)
            XCTAssertEqual(rest.exerciseName, "Row")
        default:
            XCTFail("expected .rest, got \(vm.face)")
        }
    }

    func testPushWorkoutCompleteReturnsToIdle() async throws {
        let bridge = FakeWatchBridge()
        let vm = WatchFacesViewModel(bridge: bridge)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Row",
            prescription: "8 × 80 kg",
            setNumber: 1,
            setCount: 4,
            targetRir: nil
        )))
        try await waitFor {
            if case .active = vm.face { return true }
            return false
        }

        bridge.deliver(.pushWorkoutComplete)
        try await waitFor { vm.face == .idle }

        XCTAssertEqual(vm.face, .idle)
    }

    // MARK: - Outbound (tap)

    func testTapInActiveSendsSetStarted() async throws {
        let bridge = FakeWatchBridge()
        let vm = WatchFacesViewModel(bridge: bridge)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Bench",
            prescription: "5 × 102.5 kg",
            setNumber: 3,
            setCount: 5,
            targetRir: 2
        )))
        try await waitFor {
            if case .active = vm.face { return true }
            return false
        }

        vm.tap()

        try await waitFor {
            bridge.sentMessages().contains { msg in
                if case .setStarted = msg { return true }
                return false
            }
        }

        let sent = bridge.sentMessages()
        let setStarted = sent.first { msg in
            if case .setStarted = msg { return true }
            return false
        }
        switch setStarted {
        case .setStarted(_, let setIndex, _):
            XCTAssertEqual(setIndex, 3)
        default:
            XCTFail("expected .setStarted in sent log, got \(sent)")
        }
    }

    func testTapInRestSendsSetEnded() async throws {
        let bridge = FakeWatchBridge()
        let vm = WatchFacesViewModel(bridge: bridge)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        // Prime with an active block, then flip to rest.
        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Bench",
            prescription: "5 × 102.5 kg",
            setNumber: 3,
            setCount: 5,
            targetRir: 2
        )))
        try await waitFor {
            if case .active = vm.face { return true }
            return false
        }
        bridge.deliver(.pushRestTimer(endsAt: Date().addingTimeInterval(60)))
        try await waitFor {
            if case .rest = vm.face { return true }
            return false
        }

        vm.tap()

        try await waitFor {
            bridge.sentMessages().contains { msg in
                if case .setEnded = msg { return true }
                return false
            }
        }

        let sent = bridge.sentMessages()
        let setEnded = sent.first { msg in
            if case .setEnded = msg { return true }
            return false
        }
        switch setEnded {
        case .setEnded(_, let setIndex, _, let bpmAvg, let bpmMax):
            XCTAssertEqual(setIndex, 3)
            XCTAssertNil(bpmAvg)
            XCTAssertNil(bpmMax)
        default:
            XCTFail("expected .setEnded in sent log, got \(sent)")
        }
    }

    func testTapInIdleIsNoOp() async throws {
        let bridge = FakeWatchBridge()
        let vm = WatchFacesViewModel(bridge: bridge)

        vm.tap()

        // Small grace window — no detached Task should have fired.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(
            bridge.sentMessages().isEmpty,
            "idle tap must not send; got \(bridge.sentMessages())"
        )
    }

    // MARK: - Live metrics

    func testMetricSourceUpdatesActiveFaceHeartRate() async throws {
        let bridge = FakeWatchBridge()
        let source = FixtureWorkoutMetricSource(replay: WorkoutMetricReplay(events: [
            .sessionStarted(elapsedSeconds: 0),
            .metric(WorkoutMetricTick(elapsedSeconds: 1, heartRateBPM: 121.4)),
            .metric(WorkoutMetricTick(elapsedSeconds: 2, heartRateBPM: nil, activeEnergyKCal: 1.2)),
            .paused(elapsedSeconds: 3),
            .resumed(elapsedSeconds: 4),
            .metric(WorkoutMetricTick(elapsedSeconds: 5, heartRateBPM: 138.6)),
        ]))
        let vm = WatchFacesViewModel(bridge: bridge, metricSource: source)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Run",
            prescription: "20 min easy",
            setNumber: 1,
            setCount: 1,
            targetRir: nil
        )))

        try await waitFor {
            if case .active(let active) = vm.face {
                return active.heartRateBPM == 139
            }
            return false
        }

        switch vm.face {
        case .active(let active):
            XCTAssertEqual(active.heartRateBPM, 139)
            XCTAssertEqual(source.startCallCount, 1)
        default:
            XCTFail("expected .active with HR, got \(vm.face)")
        }
    }

    func testMetricSourceFailureIsExposedWithoutBreakingBridgeMessages() async throws {
        let bridge = FakeWatchBridge()
        let source = FixtureWorkoutMetricSource(
            replay: WorkoutMetricReplay(events: []),
            shouldFailWith: .notAuthorized
        )
        let vm = WatchFacesViewModel(bridge: bridge, metricSource: source)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Bench",
            prescription: "5 × 100 kg",
            setNumber: 1,
            setCount: 5,
            targetRir: 2
        )))

        try await waitFor {
            if case .active = vm.face {
                return vm.metricError == .notAuthorized
            }
            return false
        }
        switch vm.face {
        case .active(let active):
            XCTAssertNil(active.heartRateBPM)
            XCTAssertEqual(active.exerciseName, "Bench")
        default:
            XCTFail("expected .active after metric failure, got \(vm.face)")
        }
    }

    func testTapInRestSendsLatestHeartRateWithSetEnded() async throws {
        let bridge = FakeWatchBridge()
        let source = FixtureWorkoutMetricSource(replay: WorkoutMetricReplay(events: [
            .metric(WorkoutMetricTick(elapsedSeconds: 1, heartRateBPM: 142)),
        ]))
        let vm = WatchFacesViewModel(bridge: bridge, metricSource: source)
        let loop = Task { await vm.start() }
        defer {
            bridge.finish()
            loop.cancel()
        }
        try await awaitSubscription()

        bridge.deliver(.pushActiveBlock(ActiveBlockPayload(
            exerciseName: "Bench",
            prescription: "5 × 102.5 kg",
            setNumber: 2,
            setCount: 5,
            targetRir: 2
        )))
        try await waitFor {
            if case .active(let active) = vm.face {
                return active.heartRateBPM == 142
            }
            return false
        }
        bridge.deliver(.pushRestTimer(endsAt: Date().addingTimeInterval(60)))
        try await waitFor {
            if case .rest = vm.face { return true }
            return false
        }

        vm.tap()

        try await waitFor {
            bridge.sentMessages().contains { msg in
                if case .setEnded = msg { return true }
                return false
            }
        }

        let sent = bridge.sentMessages()
        let setEnded = sent.first { msg in
            if case .setEnded = msg { return true }
            return false
        }
        switch setEnded {
        case .setEnded(_, let setIndex, _, let bpmAvg, let bpmMax):
            XCTAssertEqual(setIndex, 2)
            XCTAssertEqual(bpmAvg, 142)
            XCTAssertEqual(bpmMax, 142)
        default:
            XCTFail("expected .setEnded in sent log, got \(sent)")
        }
    }

    // MARK: - Helpers

    /// Yield until `vm.start()` has registered its inbound subscription on
    /// the bridge. The view-model's `for await bridge.messages()` runs in
    /// a spawned `Task` — until it hits the `messages()` call, any
    /// `bridge.deliver(_:)` is dropped. A short sleep gives the MainActor-
    /// hopped Task a chance to subscribe before we push test messages.
    private func awaitSubscription() async throws {
        // 50ms — enough for the Task to schedule and `messages()` to
        // register the continuation under the bridge's lock. Empirically
        // reliable on CI; bump if we see flakes.
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    /// Poll `condition` until it's true or the deadline elapses. XCTest
    /// has `XCTestExpectation`, but it is awkward to bridge to a synchronous
    /// predicate on `@MainActor` state. A tiny sleep-and-check loop is
    /// clearer for the shape of our assertions and does not add noticeable
    /// wall time on a passing test.
    private func waitFor(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor @Sendable () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        XCTFail("waitFor timed out after \(timeout)s", file: file, line: line)
    }
}
