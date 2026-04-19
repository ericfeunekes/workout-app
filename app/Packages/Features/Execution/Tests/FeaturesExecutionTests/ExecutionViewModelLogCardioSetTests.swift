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

    // MARK: - Cardio log shape

    func testIntervalsDriverLogsDurationSec() async throws {
        // Log an interval (400m, 96.5s, 165bpm). The pushed SetLog must
        // carry every cardio field — not the strength-shaped (weight,
        // reps, rir) tuple that `logSet` emits.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_500))
        let (ctx, itemID) = Self.intervalsContext(intervalCount: 10)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
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

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.workoutItemID, itemID)
        XCTAssertEqual(log.setIndex, 1)
        XCTAssertEqual(log.durationSec, 96.5)
        XCTAssertEqual(log.distanceM, 400.0)
        XCTAssertEqual(log.hrAvgBpm, 165)
        XCTAssertEqual(log.cadenceAvgSpm, 184)
        XCTAssertEqual(log.startedAt, startedAt)
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
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
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

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.workoutItemID, itemID)
        XCTAssertEqual(log.durationSec, 1805.0)
        XCTAssertEqual(log.distanceM, 5000.0)
        XCTAssertEqual(log.hrAvgBpm, 142)
        XCTAssertEqual(log.cadenceAvgSpm, 172)
        // Continuous has no rest — the VM should route to .complete
        // after the single log.
        XCTAssertEqual(vm.state.route, .complete)
    }

    // MARK: - Trailing-rest fix

    func testIntervalsDriverFinalIntervalSkipsRestGoesComplete() async throws {
        // Walk the cursor to the last interval and log it. The driver's
        // `restDuration` returns 0 on the final interval, so
        // `buildLogMutations` emits `.advanceFromRest` which falls off
        // the end of the block and routes to `.complete`. No trailing
        // rest screen.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_700))
        let (ctx, _) = Self.intervalsContext(intervalCount: 2)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()

        // Interval 1 — non-final. Log it; the driver surfaces the
        // authored rest (derived from 200 m / 270 s/km = 54 s).
        vm.logCardioSet(
            durationSec: 96.0, distanceM: 400.0,
            hrAvgBpm: nil, cadenceAvgSpm: nil, startedAt: nil
        )
        XCTAssertEqual(vm.state.route, .rest, "intermediate interval must rest")
        vm.advance()
        XCTAssertEqual(vm.state.cursor.setIndex, 2)

        // Interval 2 — final. Log it; the route must land on .complete
        // without transiting through .rest.
        vm.logCardioSet(
            durationSec: 95.0, distanceM: 400.0,
            hrAvgBpm: nil, cadenceAvgSpm: nil, startedAt: nil
        )
        XCTAssertEqual(
            vm.state.route,
            .complete,
            "final interval must route to .complete with no trailing rest"
        )
    }
}
