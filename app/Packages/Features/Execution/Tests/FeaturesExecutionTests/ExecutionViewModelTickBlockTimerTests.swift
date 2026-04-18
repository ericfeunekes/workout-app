// ExecutionViewModelTickBlockTimerTests.swift
//
// Bug-042 regression coverage. `ExecutionViewModel.tickBlockTimer()`
// exists + is unit-tested, but prior to this fix no view invoked it at
// runtime — AMRAP / ForTime / EMOM / Tabata caps were dead code. This
// test file pins two complementary invariants:
//
//   1. **View wiring (source inspection).** `ActiveView.swift` and
//      `RestView.swift` both instantiate a `Timer.publish(every: 1, ...)`,
//      gate on `state.blockEndsAt != nil`, and call
//      `viewModel.tickBlockTimer()` on each tick. Swift has no ViewInspector
//      analogue in this repo — previews + `xcodebuild` are the visual
//      check — so we read the source files and assert the canonical
//      wiring strings are present. Any refactor that removes the tick
//      trips these tests, not the runtime.
//
//   2. **VM tick behavior under a moving clock.** `tickBlockTimer()`
//      increments `tickCallCount` on every call (even no-ops) and
//      dispatches `.complete` once `clock.now >= state.blockEndsAt`.
//      We drive the VM's `tickBlockTimer()` directly three times across
//      advancing wall-clock instants to mirror "TimelineView fires the
//      view's `.onReceive` once per second" without booting a SwiftUI
//      runtime in tests.
//
// If SwiftUI view testing ever becomes practical in this harness, swap
// the source-inspection half for a mounted-view assertion. Until then
// this is the strongest check available.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelTickBlockTimerTests: XCTestCase {

    // MARK: - VM behavior

    /// `testActiveViewInvokesTickBlockTimerOncePerSecond` — contract from
    /// the bug-042 brief. We can't mount a SwiftUI `TimelineView` in a
    /// unit test harness, so we mirror its effect: call
    /// `viewModel.tickBlockTimer()` three times, advancing the clock by
    /// 1s between each call. Asserts `tickCallCount >= 3` and that the
    /// final call flips the route to `.complete` once the cap elapses.
    func testActiveViewInvokesTickBlockTimerOncePerSecond() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeAMRAPContext(timeCapSec: 2)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 2,
            "AMRAP start must stamp blockEndsAt = now + time_cap_sec"
        )

        // Tick 1: 1s after start — cap not yet elapsed, no-op.
        clock.now = start.addingTimeInterval(1)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.tickCallCount, 1)
        XCTAssertNotEqual(vm.state.route, .complete)

        // Tick 2: 2s after start — cap elapsed, VM dispatches `.complete`.
        clock.now = start.addingTimeInterval(2)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.tickCallCount, 2)
        XCTAssertEqual(vm.state.route, .complete)

        // Tick 3: 3s after start — route already complete, no-op but
        // count still increments (safe to call every second regardless
        // of state).
        clock.now = start.addingTimeInterval(3)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.tickCallCount, 3)
        XCTAssertEqual(vm.state.route, .complete)
    }

    /// Calling `tickBlockTimer` when `blockEndsAt == nil` (straight_sets
    /// block) is a no-op. Guards the contract in the view's gate:
    /// `if viewModel.state.blockEndsAt != nil { viewModel.tickBlockTimer() }`
    /// is a pure optimization — correctness doesn't depend on it.
    func testTickBlockTimerIsSafeWhenNoBlockEndsAt() {
        let (ctx, _) = makeStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        XCTAssertNil(vm.state.blockEndsAt)

        for _ in 0..<5 {
            vm.tickBlockTimer()
        }
        XCTAssertEqual(vm.tickCallCount, 5)
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertNil(vm.state.blockEndsAt)
    }

    // MARK: - View wiring (source inspection)

    func testActiveViewWiresTickBlockTimerViaPeriodicTimer() throws {
        let source = try loadFeatureSource(named: "ActiveView.swift")
        XCTAssertTrue(
            source.contains("Timer.publish(every: 1"),
            "ActiveView must carry a 1-second Timer.publish for the bug-042 tick source"
        )
        XCTAssertTrue(
            source.contains(".autoconnect()"),
            "ActiveView's tick timer must autoconnect so the publisher starts/stops with view lifecycle"
        )
        XCTAssertTrue(
            source.contains(".onReceive(tickTimer)"),
            "ActiveView must attach .onReceive(tickTimer) so the VM's tick fires on each interval"
        )
        XCTAssertTrue(
            source.contains("viewModel.tickBlockTimer()"),
            "ActiveView must invoke viewModel.tickBlockTimer() — the behavior guarded by bug-042"
        )
        XCTAssertTrue(
            source.contains("state.blockEndsAt != nil"),
            "ActiveView's tick must gate on state.blockEndsAt != nil so non-time-capped blocks don't wake the VM every second"
        )
    }

    func testRestViewWiresTickBlockTimerViaPeriodicTimer() throws {
        let source = try loadFeatureSource(named: "RestView.swift")
        XCTAssertTrue(
            source.contains("Timer.publish(every: 1"),
            "RestView must carry a 1-second Timer.publish — block caps can elapse during rest"
        )
        XCTAssertTrue(
            source.contains(".autoconnect()"),
            "RestView's tick timer must autoconnect"
        )
        XCTAssertTrue(
            source.contains(".onReceive(tickTimer)"),
            "RestView must attach .onReceive(tickTimer)"
        )
        XCTAssertTrue(
            source.contains("viewModel.tickBlockTimer()"),
            "RestView must invoke viewModel.tickBlockTimer() — an EMOM / For-Time cap can expire while the user rests"
        )
        XCTAssertTrue(
            source.contains("state.blockEndsAt != nil"),
            "RestView's tick must gate on state.blockEndsAt != nil"
        )
    }

    // MARK: - Helpers

    private func makeAMRAPContext(
        timeCapSec: Int
    ) -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "amrap",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":\#(timeCapSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":10}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Pull-ups")]
        )
        return (ctx, itemID)
    }

    private func makeStraightSetsContext() -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "ss",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
        return (ctx, itemID)
    }

    /// Load a source file from `../../Sources/FeaturesExecution` relative
    /// to this test file via `#filePath`. The swift package layout is
    /// stable (tests sit next to sources in a standard SwiftPM tree), so
    /// the relative walk is safe across machines and CI.
    private func loadFeatureSource(
        named filename: String,
        filePath: String = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: filePath)
        // .../Tests/FeaturesExecutionTests/<thisfile>
        // → .../Tests/FeaturesExecutionTests/
        // → .../Tests/
        // → .../
        // → .../Sources/FeaturesExecution/<filename>
        let pkgRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = pkgRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FeaturesExecution")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

// MARK: - Helpers

/// A class-backed mutable clock. `FixedClock` is a value type — tests that
/// need to advance the clock after the VM captures it need reference-
/// typed storage. Local-scoped to this file (mirrors the pattern in
/// `ExecutionViewModelTests.swift`).
private final class MutableTickClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
