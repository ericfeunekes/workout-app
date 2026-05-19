// ExecutionViewModelLogCurrentSetTests.swift
//
// Regression coverage for the R2.12 cardio-dispatch bug: pre-R2.12,
// `ActiveView`'s primary log button opened `LogSetSheet` for every
// block, so cardio sessions enqueued strength-shaped result rows
// (reps=0, durationSec=nil). The fix adds a VM-level `logCurrentSet`
// that inspects the current block's timing mode and routes to either
// `logSet(reps:rir:)` (strength) or `logCardioSet(...)` (cardio).
//
// These tests pin the routing contract:
//   * strength blocks → `logSet` path: the primitive log carries reps
//     and (if authored) weight.
//   * intervals blocks → `logCardioSet` path: the primitive log carries
//     durationSec derived from the timing config's work shape.
//   * continuous blocks → `logCardioSet` path: the primitive log carries
//     durationSec derived from elapsed `clock.now - workStartedAt`.
//   * ActiveView no longer calls `logSet(reps:rir:)` from its primary
//     button action — the only `logSet(reps:rir:)` reference left is
//     inside the strength-only `LogSetSheet` commit closure. Enforced
//     via source inspection so a future refactor can't silently re-
//     introduce the cardio dispatch bug.

import Foundation
import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelLogCurrentSetTests: XCTestCase {

    private static func primitiveContext(
        workout: Workout,
        block: Block,
        item: WorkoutItem,
        exerciseID: UUID,
        exerciseName: String,
        repeatCount: Int = 10,
        load: PrimitiveLoad? = nil
    ) -> WorkoutContext {
        let primitive = PrimitiveWorkout(
            id: workout.id,
            name: workout.name,
            blocks: [
                PrimitiveBlock(id: block.id, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: PrimitiveTiming(mode: .setBounded),
                        traversal: .sequential,
                        repeatCount: repeatCount,
                        slots: [
                            PrimitiveSlot(
                                id: item.id,
                                exerciseID: exerciseID,
                                workTargets: [],
                                load: load
                            ),
                        ]
                    ),
                ]),
            ]
        )
        return WorkoutContext(
            workout: workout,
            primitiveWorkout: primitive,
            primitiveExecutionPlan: try! ExecutionPlan.validated(workout: primitive),
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: exerciseName)]
        )
    }

    private static func primitiveLoad(from prescriptionJSON: String) -> PrimitiveLoad? {
        let unit: PrimitiveLoadUnit = prescriptionJSON.contains(#""weight_unit":"lb""#) ? .lb : .kg
        if prescriptionJSON.contains(#""load_kg":53"#) {
            return PrimitiveLoad(value: 53, unit: unit, unitType: .absolute)
        }
        if prescriptionJSON.contains(#""load_kg":40"#) {
            return PrimitiveLoad(value: 40, unit: unit, unitType: .absolute)
        }
        if prescriptionJSON.contains(#""load_kg":20"#) {
            return PrimitiveLoad(value: 20, unit: unit, unitType: .absolute)
        }
        if prescriptionJSON.contains(#""load_kg":100"#) {
            return PrimitiveLoad(value: 100, unit: unit, unitType: .absolute)
        }
        return nil
    }

    // MARK: - Fixtures (single-block workouts per timing mode)

    /// Strength straight-sets — 3 × 5 @ 100 kg bench press. Used to
    /// prove `logCurrentSet` routes to the strength path.
    private static func strengthContext() -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Strength",
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
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100,"weight_unit":"kg"}"#
        )
        let ctx = primitiveContext(
            workout: workout,
            block: block,
            item: item,
            exerciseID: exerciseID,
            exerciseName: "Bench",
            repeatCount: 3,
            load: PrimitiveLoad(value: 100, unit: .kg, unitType: .absolute)
        )
        return (ctx, itemID)
    }

    /// Distance-based intervals fixture — 10 × 400 m at 4:30 / km.
    /// `work_distance_m / 1000 * target_pace_sec_per_km` = 108 s.
    private static func intervalsContext() -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Intervals",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .intervals,
            timingConfigJSON: #"""
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":10,"target_pace_sec_per_km":270}
            """#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        let ctx = primitiveContext(
            workout: workout,
            block: block,
            item: item,
            exerciseID: exerciseID,
            exerciseName: "Run",
            repeatCount: 10
        )
        return (ctx, itemID)
    }
    /// Continuous — a 30 min Z2 run.
    private static func continuousContext() -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Continuous",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .continuous,
            timingConfigJSON: #"""
            {"target_duration_sec":1800,"target_pace_sec_per_km":360,"target_hr_zone":2}
            """#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        let ctx = primitiveContext(
            workout: workout,
            block: block,
            item: item,
            exerciseID: exerciseID,
            exerciseName: "Run",
            repeatCount: 1
        )
        return (ctx, itemID)
    }

    /// Circuit station with a unit-aware duration/distance target. This
    /// pins the "work kind + unit" cutover: targets are not fake reps,
    /// but loaded carries/holds still preserve their authored load.
    private static func targetedCircuitContext(
        prescriptionJSON: String,
        exerciseName: String
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Targeted circuit",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .circuit,
            timingConfigJSON: #"{"rest_between_exercises_sec":0,"rest_between_rounds_sec":60}"#,
            rounds: 1, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
        let ctx = primitiveContext(
            workout: workout,
            block: block,
            item: item,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            repeatCount: 1,
            load: primitiveLoad(from: prescriptionJSON)
        )
        return (ctx, itemID)
    }

    private static func targetedStraightSetsContext(
        prescriptionJSON: String,
        exerciseName: String
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Targeted straight sets",
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
            prescriptionJSON: prescriptionJSON
        )
        let ctx = primitiveContext(
            workout: workout,
            block: block,
            item: item,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            repeatCount: 3,
            load: primitiveLoad(from: prescriptionJSON)
        )
        return (ctx, itemID)
    }

    // MARK: - Routing

    func testLogCurrentSetRoutesToLogSetForStrength() async throws {
        // Strength straight-sets block: `logCurrentSet(reps: 5, rir: 2)`
        // must fall through to `logSet(reps:rir:)`. The pushed SetLog
        // carries reps / weight / weightUnit — strength-shaped — and
        // leaves durationSec / distanceM / hrAvgBpm nil.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let (ctx, itemID) = Self.strengthContext()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()

        XCTAssertFalse(
            vm.isCurrentBlockCardio,
            "straight-sets must be classified as strength"
        )
        vm.startCurrentSet()
        vm.logCurrentSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertEqual(log.reps, 5, "strength path carries reps")
        XCTAssertEqual(log.rir, 2)
        XCTAssertEqual(log.weight, 100)
        XCTAssertEqual(log.weightUnit, .kg)
        XCTAssertNil(log.durationSec, "strength path must NOT populate durationSec")
        XCTAssertNil(log.distanceM)
    }

    func testLogCurrentSetRoutesToLogCardioSetForIntervals() async throws {
        // Intervals distance-based block. `logCurrentSet()` (no reps /
        // rir) must dispatch the cardio path; the pushed SetLog carries
        // durationSec = elapsed `clock.now - workStartedAt`, NOT the
        // authored target_pace_sec_per_km × distance. Authored work_sec
        // / target pace are prescription targets — logging them would
        // echo the plan instead of what actually happened. A runner
        // pushing a 400 m interval at 25 s under target must see the
        // faster time land in the log, not the target 108 s.
        //
        // Distance still comes from the authored prescription (v1 has
        // no sensor integration), so `distanceM == 400`.
        let t0 = Date(timeIntervalSince1970: 1_700_001_000)
        let clock = AdvanceableClock(now: t0)
        let (ctx, itemID) = Self.intervalsContext()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        XCTAssertTrue(
            vm.isCurrentBlockCardio,
            "intervals must be classified as cardio"
        )
        // Runner comes in under target — 83 s vs the authored 108 s.
        clock.advance(by: 83)
        vm.logCurrentSet()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 1, "cardio path must push exactly one SetLog")
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertEqual(log.setIndex, 0)
        XCTAssertEqual(
            try XCTUnwrap(log.durationSec),
            83,
            accuracy: 0.001,
            "intervals duration = elapsed since workStartedAt, not target pace × distance"
        )
        XCTAssertEqual(log.distanceM, 400, "authored distance still flows through")
        // Cardio rows must not carry strength-shaped fields.
        XCTAssertNil(log.reps, "cardio path must NOT carry reps")
        XCTAssertNil(log.weight)
        XCTAssertNil(log.weightUnit)
        XCTAssertNil(log.rir)
    }

    func testLogCurrentSetRoutesToLogCardioSetForContinuous() async throws {
        // Continuous block. `logCurrentSet()` must route through the
        // cardio path with durationSec = elapsed since workStartedAt.
        // `start()` stamps workStartedAt = clock.now. Advance the clock
        // by 1805 s (just over the 30-min target), then log.
        let t0 = Date(timeIntervalSince1970: 1_700_002_000)
        let clock = AdvanceableClock(now: t0)
        let (ctx, itemID) = Self.continuousContext()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        XCTAssertTrue(
            vm.isCurrentBlockCardio,
            "continuous must be classified as cardio"
        )
        clock.advance(by: 1805)
        vm.logCurrentSet()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertEqual(
            try XCTUnwrap(log.durationSec),
            1805,
            accuracy: 0.001,
            "continuous duration = elapsed since workStartedAt"
        )
        XCTAssertNil(log.distanceM, "no authored distance → nil")
        XCTAssertNil(log.reps)
        XCTAssertNil(log.weight)
        // The block has no rest and the single set is the last one,
        // so the VM should land on .complete.
        XCTAssertEqual(vm.state.route, .complete)
    }

    func testUnitAwareDistanceTargetRendersAndLogsLoadedCarry() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_003_000)
        let clock = AdvanceableClock(now: t0)
        let (ctx, itemID) = Self.targetedCircuitContext(
            prescriptionJSON: #"""
            {"target":{"kind":"distance","value":200,"unit":"ft"},"load_kg":53,"weight_unit":"lb"}
            """#,
            exerciseName: "Farmer Carry"
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        let content = try XCTUnwrap(vm.activeContent)
        XCTAssertEqual(content.kind, .cardio)
        XCTAssertEqual(content.repsDisplay, "200 ft")
        XCTAssertEqual(content.loadDisplay, "53 lb")
        XCTAssertTrue(vm.isCurrentBlockCardio)

        vm.startCurrentSet()
        vm.logCurrentSet()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertNil(log.reps)
        XCTAssertEqual(log.weight, 53)
        XCTAssertEqual(log.weightUnit, .lb)
        XCTAssertEqual(try XCTUnwrap(log.distanceM), 60.96, accuracy: 0.001)
        XCTAssertNil(log.durationSec)
    }

    func testUnitAwareDurationTargetDisplaysAuthoredUnitButLogsElapsedSeconds() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_004_000)
        let clock = AdvanceableClock(now: t0)
        let (ctx, _) = Self.targetedCircuitContext(
            prescriptionJSON: #"""
            {"target":{"kind":"duration","value":2,"unit":"min"},"load_kg":40,"weight_unit":"lb"}
            """#,
            exerciseName: "Weighted Hang"
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        let content = try XCTUnwrap(vm.activeContent)
        XCTAssertEqual(content.kind, .cardio)
        XCTAssertEqual(content.repsDisplay, "2 min")
        XCTAssertEqual(content.loadDisplay, "40 lb")

        vm.startCurrentSet()
        clock.advance(by: 133)
        vm.logCurrentSet()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.reps)
        XCTAssertEqual(log.weight, 40)
        XCTAssertEqual(log.weightUnit, .lb)
        XCTAssertEqual(try XCTUnwrap(log.durationSec), 133, accuracy: 0.001)
        XCTAssertNil(log.distanceM)
    }

    func testSetMajorDurationTargetDoesNotCollapseToZeroReps() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_005_000)
        let clock = AdvanceableClock(now: t0)
        let (ctx, itemID) = Self.targetedStraightSetsContext(
            prescriptionJSON: #"""
            {"sets":2,"target":{"kind":"duration","value":30,"unit":"sec"},"load_kg":20,"weight_unit":"lb"}
            """#,
            exerciseName: "Weighted Plank"
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        let content = try XCTUnwrap(vm.activeContent)
        XCTAssertEqual(content.kind, .cardio)
        XCTAssertEqual(content.totalSets, 2)
        XCTAssertEqual(content.repsDisplay, "30 sec")
        XCTAssertEqual(content.loadDisplay, "20 lb")
        XCTAssertTrue(vm.isCurrentBlockCardio)

        vm.startCurrentSet()
        clock.advance(by: 37)
        vm.logCurrentSet()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertNil(log.reps)
        XCTAssertEqual(log.weight, 20)
        XCTAssertEqual(log.weightUnit, .lb)
        XCTAssertEqual(try XCTUnwrap(log.durationSec), 37, accuracy: 0.001)
        XCTAssertNil(log.distanceM)
    }

    // MARK: - Source inspection

    func testActiveViewCardioBlockDispatchesLogCurrentSet() throws {
        // Contract: ActiveView's primary log-button action MUST NOT call
        // a strength-only log path directly — that's the cardio-dispatch
        // bug. The only `logSet(loadKg:reps:rir:)` call left in the Active
        // screen's UI surface is inside `LogSetSheet`'s commit closure in
        // `ActiveView.swift`, which the cardio branch never presents.
        //
        // This test reads the two source files that constitute the
        // primary-button path — `ActiveView.swift` and
        // `ActiveView+LogButton.swift` — and asserts:
        //   * `ActiveView+LogButton.swift` dispatches `logCurrentSet`
        //     (the cardio-safe routing entry point).
        //   * `ActiveView+LogButton.swift` does NOT contain a strength-only
        //     `viewModel.logSet(` call — the button must not bypass routing.
        //   * `ActiveView+Sheets.swift` still has exactly one
        //     `logSet(loadKg:reps:rir:)` call (the strength-only
        //     `LogSetSheet` commit).
        let activeView = try loadSource(
            relativePath: "ActiveView.swift"
        )
        let activeViewLogButton = try loadSource(
            relativePath: "ActiveView+LogButton.swift"
        )
        let activeViewSheets = try loadSource(
            relativePath: "ActiveView+Sheets.swift"
        )

        // Count actual call sites (`viewModel.logSet(`) — ignore doc
        // comments and declarations by limiting the search to these view
        // files. The only permitted call is inside `ActiveView.swift`'s
        // LogSetSheet commit closure (strength only). `ActiveView+LogButton.swift`
        // must have zero.
        func callSiteCount(_ source: String) -> Int {
            source.components(separatedBy: "viewModel.logSet(").count - 1
        }
        func callCurrentSetCount(_ source: String) -> Int {
            source.components(separatedBy: "viewModel.logCurrentSet(").count - 1
        }

        XCTAssertGreaterThanOrEqual(
            callCurrentSetCount(activeViewLogButton),
            1,
            "the log button must dispatch viewModel.logCurrentSet for mode routing"
        )
        XCTAssertEqual(
            callSiteCount(activeViewLogButton),
            0,
            "the log button must not bypass routing by calling viewModel.logSet"
        )
        XCTAssertEqual(
            callSiteCount(activeView),
            0,
            "ActiveView should route strength sheet presentation through ActiveView+Sheets"
        )
        XCTAssertEqual(
            callSiteCount(activeViewSheets),
            1,
            "only the LogSetSheet's strength-specific commit may call viewModel.logSet"
        )
        XCTAssertTrue(
            activeViewLogButton.contains("case .custom:"),
            "cardio-shaped custom segments still need mode-native CTA copy"
        )
        XCTAssertTrue(
            activeViewLogButton.contains("log segment"),
            "custom segment logging must not fall back to generic set copy"
        )
        XCTAssertTrue(
            activeViewLogButton.contains("viewModel.canSkipCurrentSet"),
            "the active log affordance must expose the deliberate-skip gate"
        )
        XCTAssertTrue(
            activeViewLogButton.contains("viewModel.skipCurrentSet()"),
            "the active log affordance must route deliberate skips through the view model"
        )
        let batchModeRange = try XCTUnwrap(
            activeViewLogButton.range(of: "viewModel.isCurrentRoundRobinBatchMode")
        )
        let compositeModeRange = try XCTUnwrap(
            activeViewLogButton.range(of: "viewModel.isCurrentCompositeSet")
        )
        XCTAssertLessThan(
            batchModeRange.lowerBound,
            compositeModeRange.lowerBound,
            "batch-at-round-rest supersets must take precedence over composite logging so they do not open a mid-superset log sheet"
        )
    }

    // MARK: - Helpers

    /// Locate a sibling source file under the Execution package's
    /// `Sources/FeaturesExecution` directory relative to this test
    /// file's compile-time path. Works under both `swift test` and
    /// `xcodebuild test` because `#filePath` resolves to the test
    /// source's absolute path in both environments.
    private func loadSource(relativePath: String, file: StaticString = #filePath) throws -> String {
        let here = URL(fileURLWithPath: String(describing: file))
        // `here` = .../Execution/Tests/FeaturesExecutionTests/<this>.swift
        // Walk up to the package root, then into Sources.
        let packageRoot = here
            .deletingLastPathComponent() // FeaturesExecutionTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // Execution/
        let source = packageRoot
            .appendingPathComponent("Sources/FeaturesExecution/\(relativePath)")
        return try String(contentsOf: source, encoding: .utf8)
    }
}

// MARK: - Test Clocks

/// A `Clock` whose `now` can be advanced after construction. Enables the
/// continuous-duration test to prove `logCurrentSet` reads the VM's
/// injected clock at dispatch time (not at `start()` time).
///
/// Scoped `private` to this test file — `ExecutionViewModelTests.swift`
/// ships its own `MutableClock` with slightly different semantics, and
/// we don't want name / behavior collisions across the target.
private final class AdvanceableClock: Clock, @unchecked Sendable {
    private var _now: Date
    private let lock = NSLock()

    init(now: Date) {
        self._now = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }
}
