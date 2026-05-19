// ExecutionViewModelLogCardioSetTests.swift
//
// Coverage for `ExecutionViewModel.logCardioSet(...)` — the cardio sibling
// of `logSet(reps:rir:)` introduced in the R2.11 cardio cutover. These
// tests pin two load-bearing behaviors that the pre-R2.11 cardio drivers
// violated:
//
//   1. A cardio log enqueues a `SetLog` with `durationSec` / `distanceM`
//      / `hrAvgBpm` / `cadenceAvgSpm` populated — not as empty rows with
//      only `weight` / `reps` set (which is what `logSet` produces).
//
//   2. `IntervalsDriver` routes the final interval's log straight to
//      `.complete`, with no trailing rest screen. Before R2.11 the
//      driver returned the authored `rest_sec` on every interval, so
//      the last log put the user on a rest screen that counted down
//      to a complete route anyway.

import XCTest
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelLogCardioSetTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a 10 × 400 m intervals workout context (the canonical
    /// cardio fixture from `docs/prescription.md` § "10 × 400m at 5K
    /// pace"). `intervalCount` is parametric so tests can construct
    /// shorter runs for "final interval" scenarios.
    private static func intervalsContext(
        intervalCount: Int = 10
    ) -> (WorkoutContext, UUID) {
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
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":\#(intervalCount),"target_pace_sec_per_km":270}
            """#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")]
        )
        return (ctx, itemID)
    }

    /// Time-owned intervals: the app owns the work/rest boundaries and can
    /// auto-transition exactly at zero without sensor support.
    private static func timeIntervalsContext(
        intervalCount: Int = 2,
        workSec: Int = 5,
        restSec: Int = 3
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Time Intervals",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .intervals,
            timingConfigJSON: #"""
            {"work_sec":\#(workSec),"rest_sec":\#(restSec),"interval_count":\#(intervalCount)}
            """#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bike")]
        )
        return (ctx, itemID)
    }

    /// Build a continuous context — a 30-min Z2 run with an authored
    /// pace + HR zone. Shape matches the `continuous` fixture in
    /// `docs/prescription.md` § "continuous".
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
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")]
        )
        return (ctx, itemID)
    }

    private static func continuousThenStraightSetsContext() -> (WorkoutContext, UUID, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let runBlockID = UUID()
        let pressBlockID = UUID()
        let runExerciseID = UUID()
        let pressExerciseID = UUID()
        let runItemID = UUID()
        let pressItemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Run Then Press",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let runBlock = Block(
            id: runBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "Easy run", timingMode: .continuous,
            timingConfigJSON: #"{"target_duration_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let pressBlock = Block(
            id: pressBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: "Press", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":90}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let runItem = WorkoutItem(
            id: runItemID, blockID: runBlockID, position: 0,
            exerciseID: runExerciseID,
            prescriptionJSON: "{}"
        )
        let pressItem = WorkoutItem(
            id: pressItemID, blockID: pressBlockID, position: 0,
            exerciseID: pressExerciseID,
            prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [runBlock, pressBlock],
            itemsByBlock: [[runItem], [pressItem]],
            exercises: [
                runExerciseID: Exercise(id: runExerciseID, name: "Run"),
                pressExerciseID: Exercise(id: pressExerciseID, name: "Bench Press"),
            ]
        )
        return (ctx, runItemID, pressItemID)
    }

    // MARK: - Cardio log shape

    func testIntervalsDriverLogsDurationSec() async throws {
        // Log an interval (400m, 96.5s, 165bpm). The pushed SetLog must
        // carry every cardio field — not the strength-shaped (weight,
        // reps, rir) tuple that `logSet` emits.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_500))
        let (ctx, itemID) = Self.intervalsContext(intervalCount: 10)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()

        let startedAt = fixed.now.addingTimeInterval(-96.5)
        vm.logCardioSet(
            durationSec: 96.5,
            distanceM: 400.0,
            hrAvgBpm: 165,
            cadenceAvgSpm: 184,
            startedAt: startedAt
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertEqual(log.setIndex, 0)
        XCTAssertEqual(log.durationSec, 96.5)
        XCTAssertEqual(log.distanceM, 400.0)
        XCTAssertEqual(log.completedAt, fixed.now)
        // Cardio rows must NOT carry strength-shaped fields.
        XCTAssertNil(log.reps)
        XCTAssertNil(log.weight)
        XCTAssertNil(log.weightUnit)
        XCTAssertNil(log.rir)
        XCTAssertFalse(log.isWarmup)
    }

    func testContinuousDriverLogsDurationAndDistance() async throws {
        // A continuous effort logs once with duration + distance. The
        // cursor pins setIndex=1 and totalSets=1 per the spec, so the
        // log lands on set 1 and the VM routes to `.complete`.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_600))
        let (ctx, itemID) = Self.continuousContext()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()

        vm.logCardioSet(
            durationSec: 1805.0,
            distanceM: 5000.0,
            hrAvgBpm: 142,
            cadenceAvgSpm: 172,
            startedAt: fixed.now.addingTimeInterval(-1805)
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.slotID, itemID)
        XCTAssertEqual(log.durationSec, 1805.0)
        XCTAssertEqual(log.distanceM, 5000.0)
        // Continuous has no rest — the VM should route to .complete
        // after the single log.
        XCTAssertEqual(vm.state.route, .complete)
    }

    func testCardioFinalLogRearmsSetStartOnNextExplicitStartBlock() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_000))
        let (ctx, _, pressItemID) = Self.continuousThenStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()

        vm.logCardioSet(durationSec: 60, distanceM: nil, startedAt: fixed.now.addingTimeInterval(-60))

        XCTAssertEqual(vm.state.route, .transition)
        vm.beginBlockTransition()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        XCTAssertTrue(vm.requiresExplicitSetStartForCurrentWork)
        XCTAssertFalse(vm.isCurrentWorkStarted)
        XCTAssertNotNil(vm.state.workReadyAt)
        XCTAssertNil(vm.state.workStartedAt)

        vm.logSet(reps: 5, rir: 2)
        let pressItem = vm.state.items.first { $0.itemID == pressItemID }
        XCTAssertEqual(pressItem?.sets.first?.done, false, "Done cannot bypass Set Start after cardio transition")
    }

    // MARK: - Trailing-rest fix

    func testIntervalsDriverFinalIntervalSkipsRestGoesComplete() async throws {
        // Walk the cursor to the last interval and log it. The driver's
        // `restDuration` returns 0 on the final interval, so
        // `buildLogMutations` emits `.advanceFromRest` which falls off
        // the end of the block and routes to `.complete`. No trailing
        // rest screen.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_700))
        let (ctx, _) = Self.timeIntervalsContext(intervalCount: 2)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()

        // Interval 1 — non-final. Log it; the driver surfaces the
        // authored rest.
        vm.logCardioSet(
            durationSec: 5.0, distanceM: nil,
            hrAvgBpm: nil, cadenceAvgSpm: nil, startedAt: nil
        )
        XCTAssertEqual(vm.state.route, .rest, "intermediate interval must rest")
        vm.advance()
        XCTAssertEqual(vm.state.cursor.setIndex, 2)

        // Interval 2 — final. Log it; the route must land on .complete
        // without transiting through .rest.
        vm.logCardioSet(
            durationSec: 5.0, distanceM: nil,
            hrAvgBpm: nil, cadenceAvgSpm: nil, startedAt: nil
        )
        XCTAssertEqual(
            vm.state.route,
            .complete,
            "final interval must route to .complete with no trailing rest"
        )
    }

    func testTimeIntervalAutoLogsWorkThenAutoAdvancesRestAtBoundary() {
        let start = Date(timeIntervalSince1970: 1_700_000_800)
        let clock = MutableCardioClock(now: start)
        let (ctx, _) = Self.timeIntervalsContext(intervalCount: 2, workSec: 5, restSec: 3)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertEqual(vm.state.workEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 5)

        clock.now = start.addingTimeInterval(5)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        XCTAssertEqual(vm.state.restEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 8)
        XCTAssertEqual(vm.state.items.first?.sets.first?.done, true)
        XCTAssertEqual(vm.state.items.first?.sets.first?.durationSec, 5)

        clock.now = start.addingTimeInterval(8)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)
        XCTAssertEqual(vm.state.workEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 13)
    }

    func testDistanceIntervalsDoNotInferAutomaticWorkBoundaryWithoutSensors() {
        let start = Date(timeIntervalSince1970: 1_700_000_900)
        let clock = MutableCardioClock(now: start)
        let (ctx, _) = Self.intervalsContext(intervalCount: 2)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertNil(vm.state.workEndsAt)

        clock.now = start.addingTimeInterval(120)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        XCTAssertEqual(vm.state.items.first?.sets.first?.done, false)
    }
}

private final class MutableCardioClock: Clock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
