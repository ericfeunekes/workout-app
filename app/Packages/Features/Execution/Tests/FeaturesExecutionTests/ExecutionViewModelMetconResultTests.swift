// ExecutionViewModelMetconResultTests.swift
//
// Regression coverage for AMRAP / For Time result capture. AMRAP logs
// completed stations as the athlete taps next, then captures only the
// partial station at the finish sheet.

import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelMetconResultTests: XCTestCase {

    func testAMRAPNextLogsCompletedStationThenPartialResultRoutesToNextBlock() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_002_000))
        let fixture = Self.metconThenStrengthContext(
            firstMode: .amrap,
            firstTimingConfigJSON: #"{"time_cap_sec":600}"#,
            firstItems: [
                ("Pull-up", #"{"reps":5}"#),
                ("Push-up", #"{"reps":10}"#),
            ]
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: fixed, push: hooks)

        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: nil)

        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
        XCTAssertEqual(vm.state.cursor.itemIndex, 1)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        let partialRows = vm.amrapPartialResultItems()
        XCTAssertEqual(partialRows.map(\.state), [.completed, .current])

        vm.logAMRAPPartialResult(extraReps: 4)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logged = try XCTUnwrap(vm.state.items.first { $0.itemID == fixture.firstItemID })
        XCTAssertEqual(logged.sets.first?.reps, 5)
        XCTAssertEqual(logged.sets.first?.done, true)
        let partial = try XCTUnwrap(vm.state.items.first { $0.itemID == fixture.secondItemID })
        XCTAssertEqual(partial.sets.first?.reps, 4)
        XCTAssertEqual(partial.sets.first?.done, true)
        XCTAssertTrue(vm.state.note.contains("AMRAP result: 0 rounds + 9 reps. partial: Push-up 4 reps"))
        XCTAssertEqual(vm.state.route, .transition)
        vm.beginBlockTransition()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.map(\.workoutItemID), [fixture.firstItemID, fixture.secondItemID])
        XCTAssertEqual(logs.map(\.setIndex), [1, 1])
        XCTAssertEqual(logs.map(\.reps), [5, 4])
        XCTAssertTrue(logs.allSatisfy { $0.durationSec == nil })
    }

    func testAMRAPPartialResultIncludesPriorStationsWhenCurrentExtraIsZero() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_002_100))
        let fixture = Self.metconThenStrengthContext(
            firstMode: .amrap,
            firstTimingConfigJSON: #"{"time_cap_sec":600}"#,
            firstItems: [
                ("Pull-up", #"{"reps":5}"#),
                ("Push-up", #"{"reps":10}"#),
            ]
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: fixed)

        vm.start()
        vm.logAMRAPStation(reps: 5)
        vm.logAMRAPPartialResult(extraReps: 0)

        XCTAssertTrue(vm.state.note.contains("AMRAP result: 0 rounds + 5 reps. partial: no extra reps"))
        let partial = vm.state.items.first { $0.itemID == fixture.secondItemID }
        XCTAssertEqual(partial?.sets.first?.done, false)
    }

    func testAMRAPNextAfterCapDoesNotLogFullStation() async throws {
        let start = Date(timeIntervalSince1970: 1_700_002_200)
        let clock = MetconMutableClock(now: start)
        let fixture = Self.metconThenStrengthContext(
            firstMode: .amrap,
            firstTimingConfigJSON: #"{"time_cap_sec":30}"#,
            firstItems: [
                ("Pull-up", #"{"reps":5}"#),
                ("Push-up", #"{"reps":10}"#),
            ]
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: clock, push: hooks)

        vm.start()
        clock.now = start.addingTimeInterval(31)

        let didLog = vm.logAMRAPStation(reps: 5)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(didLog)
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.items.first { $0.itemID == fixture.firstItemID }?.sets.first?.done, false)
        let logs = await recorder.setLogs
        XCTAssertTrue(logs.isEmpty)
    }

    func testMetconResultEntryPointsIgnoreWrongModeAfterRouting() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_002_300))
        let fixture = Self.metconThenStrengthContext(
            firstMode: .amrap,
            firstTimingConfigJSON: #"{"time_cap_sec":600}"#,
            firstItems: [
                ("Pull-up", #"{"reps":5}"#),
                ("Push-up", #"{"reps":10}"#),
            ]
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: fixed)

        vm.start()
        vm.logAMRAPPartialResult(extraReps: 0)
        let noteAfterAMRAP = vm.state.note
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)

        vm.logAMRAPPartialResult(extraReps: 4)
        vm.logForTimeResult()

        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.note, noteAfterAMRAP)
    }

    func testForTimeResultLogsElapsedDurationAndRoutesToNextBlock() async throws {
        let start = Date(timeIntervalSince1970: 1_700_002_500)
        let clock = MetconMutableClock(now: start)
        let fixture = Self.metconThenStrengthContext(
            firstMode: .forTime,
            firstTimingConfigJSON: #"{"time_cap_sec":900}"#,
            firstItems: [
                ("Thruster", #"{"reps":21,"load_kg":43.1}"#),
                ("Pull-up", #"{"reps":21}"#),
            ]
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: clock, push: hooks)

        vm.start()
        clock.now = start.addingTimeInterval(7 * 60 + 35)
        vm.logForTimeResult()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logged = try XCTUnwrap(vm.state.items.first { $0.itemID == fixture.firstItemID })
        XCTAssertEqual(logged.sets.first?.durationSec, 455)
        XCTAssertEqual(logged.sets.first?.done, true)
        XCTAssertTrue(vm.state.note.contains("For Time result: 7:35"))
        XCTAssertEqual(vm.state.route, .transition)
        vm.beginBlockTransition()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 1)
        let pushed = try XCTUnwrap(logs.first)
        XCTAssertEqual(pushed.workoutItemID, fixture.firstItemID)
        XCTAssertEqual(pushed.setIndex, 1)
        XCTAssertNil(pushed.reps)
        XCTAssertEqual(pushed.durationSec, 455)
        XCTAssertEqual(pushed.startedAt, start)
        XCTAssertEqual(pushed.completedAt, clock.now)
    }

    func testForTimeCapDoesNotAutoCompleteBeforeFinish() async throws {
        let start = Date(timeIntervalSince1970: 1_700_002_700)
        let clock = MetconMutableClock(now: start)
        let fixture = Self.metconThenStrengthContext(
            firstMode: .forTime,
            firstTimingConfigJSON: #"{"time_cap_sec":60}"#,
            firstItems: [
                ("Thruster", #"{"reps":21,"load_kg":43.1}"#),
                ("Pull-up", #"{"reps":21}"#),
            ]
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: clock, push: hooks)

        vm.start()
        clock.now = start.addingTimeInterval(75)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
        XCTAssertEqual(vm.state.blockEndsAt, start.addingTimeInterval(60))
        var logs = await recorder.setLogs
        XCTAssertTrue(logs.isEmpty)

        vm.logForTimeResult()
        try await Task.sleep(nanoseconds: 50_000_000)

        let logged = try XCTUnwrap(vm.state.items.first { $0.itemID == fixture.firstItemID })
        XCTAssertEqual(logged.sets.first?.durationSec, 75)
        XCTAssertTrue(vm.state.note.contains("For Time result: 1:15"))
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        logs = await recorder.setLogs
        XCTAssertEqual(logs.first?.durationSec, 75)
    }

    func testAMRAPResultRecordsPrimitiveSetResultOnLiveCompletionPath() async throws {
        let start = Date(timeIntervalSince1970: 1_700_003_000)
        let clock = MetconMutableClock(now: start)
        let fixture = Self.metconThenStrengthContext(
            firstMode: .amrap,
            firstTimingConfigJSON: #"{"time_cap_sec":300}"#,
            firstItems: [
                ("Pull-up", #"{"reps":5}"#),
                ("Push-up", #"{"reps":10}"#),
            ],
            includePrimitive: true
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: clock, push: hooks)

        vm.start()
        vm.logAMRAPStation(reps: 5)
        clock.now = start.addingTimeInterval(300)
        vm.logAMRAPPartialResult(extraReps: 4)
        vm.complete()
        vm.saveAndDone()

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        let completion = try XCTUnwrap(completions.first)
        let primitive = try XCTUnwrap(completion.primitiveSetLogs.first)
        XCTAssertEqual(primitive.role, .setResult)
        XCTAssertEqual(primitive.workoutID, fixture.context.workout.id)
        XCTAssertEqual(primitive.setIndex, 0)
        XCTAssertEqual(primitive.rounds, 0)
        XCTAssertEqual(primitive.reps, 4)
        XCTAssertEqual(primitive.durationSec, 300)
        XCTAssertEqual(primitive.completedAt, clock.now)
    }

    func testAMRAPPrimitiveSetResultUsesCapTimeWhenSubmittedAfterExpiry() async throws {
        let start = Date(timeIntervalSince1970: 1_700_003_250)
        let clock = MetconMutableClock(now: start)
        let fixture = Self.metconThenStrengthContext(
            firstMode: .amrap,
            firstTimingConfigJSON: #"{"time_cap_sec":300}"#,
            firstItems: [
                ("Pull-up", #"{"reps":5}"#),
                ("Push-up", #"{"reps":10}"#),
            ],
            includePrimitive: true
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: clock, push: hooks)

        vm.start()
        vm.logAMRAPStation(reps: 5)
        clock.now = start.addingTimeInterval(317)
        vm.logAMRAPPartialResult(extraReps: 4)
        vm.complete()
        vm.saveAndDone()

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        let completion = try XCTUnwrap(completions.first)
        let primitive = try XCTUnwrap(completion.primitiveSetLogs.first)
        XCTAssertEqual(primitive.durationSec, 300)
        XCTAssertEqual(primitive.completedAt, start.addingTimeInterval(300))
    }

    func testForTimeResultRecordsPrimitiveBlockResultOnLiveCompletionPath() async throws {
        let start = Date(timeIntervalSince1970: 1_700_003_500)
        let clock = MetconMutableClock(now: start)
        let fixture = Self.metconThenStrengthContext(
            firstMode: .forTime,
            firstTimingConfigJSON: #"{"time_cap_sec":900}"#,
            firstItems: [
                ("Thruster", #"{"reps":21,"load_kg":43.1}"#),
                ("Pull-up", #"{"reps":21}"#),
            ],
            includePrimitive: true
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(context: fixture.context, clock: clock, push: hooks)

        vm.start()
        clock.now = start.addingTimeInterval(455)
        vm.logForTimeResult()
        vm.complete()
        vm.saveAndDone()

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        let completion = try XCTUnwrap(completions.first)
        let primitive = try XCTUnwrap(completion.primitiveSetLogs.first)
        XCTAssertEqual(primitive.role, .blockResult)
        XCTAssertEqual(primitive.workoutID, fixture.context.workout.id)
        XCTAssertEqual(primitive.setIndex, 0)
        XCTAssertNil(primitive.rounds)
        XCTAssertNil(primitive.reps)
        XCTAssertEqual(primitive.durationSec, 455)
        XCTAssertEqual(primitive.completedAt, clock.now)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let context: WorkoutContext
        let firstItemID: UUID
        let secondItemID: UUID
    }

    private static func metconThenStrengthContext(
        firstMode: TimingMode,
        firstTimingConfigJSON: String,
        firstItems: [(String, String)],
        includePrimitive: Bool = false
    ) -> Fixture {
        let userID = UUID()
        let workoutID = UUID()
        let metconBlockID = UUID()
        let strengthBlockID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Metcon then strength",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
        let metconBlock = Block(
            id: metconBlockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: nil,
            timingMode: firstMode,
            timingConfigJSON: firstTimingConfigJSON,
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let strengthBlock = Block(
            id: strengthBlockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 1,
            name: nil,
            timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":90,"rest_between_exercises_sec":120}"#,
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )

        var exercises: [UUID: Exercise] = [:]
        let metconItems = firstItems.enumerated().map { offset, item in
            let exerciseID = UUID()
            let itemID = UUID()
            exercises[exerciseID] = Exercise(id: exerciseID, name: item.0)
            return WorkoutItem(
                id: itemID,
                blockID: metconBlockID,
                position: offset,
                exerciseID: exerciseID,
                prescriptionJSON: item.1
            )
        }
        let strengthExerciseID = UUID()
        let strengthItem = WorkoutItem(
            id: UUID(),
            blockID: strengthBlockID,
            position: 0,
            exerciseID: strengthExerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        exercises[strengthExerciseID] = Exercise(id: strengthExerciseID, name: "Back Squat")
        let primitiveWorkout = includePrimitive
            ? makePrimitiveWorkout(
                workoutID: workoutID,
                name: workout.name,
                blockID: metconBlockID,
                mode: firstMode,
                items: metconItems
            )
            : nil

        return Fixture(
            context: WorkoutContext(
                workout: workout,
                primitiveWorkout: primitiveWorkout,
                primitiveExecutionPlan: primitiveWorkout.map { ExecutionPlan(workout: $0) },
                blocks: [metconBlock, strengthBlock],
                itemsByBlock: [metconItems, [strengthItem]],
                exercises: exercises
            ),
            firstItemID: metconItems[0].id,
            secondItemID: metconItems[min(1, metconItems.count - 1)].id
        )
    }

    private static func makePrimitiveWorkout(
        workoutID: UUID,
        name: String,
        blockID: UUID,
        mode: TimingMode,
        items: [WorkoutItem]
    ) -> PrimitiveWorkout {
        let slots = items.map { item in
            PrimitiveSlot(
                id: UUID(),
                exerciseID: item.exerciseID,
                workTargets: [
                    PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 1, role: .completion),
                ]
            )
        }
        let primitiveSet: PrimitiveSet
        let blockTargets: [PrimitiveWorkTarget]
        switch mode {
        case .amrap:
            blockTargets = []
            primitiveSet = PrimitiveSet(
                id: UUID(),
                timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                traversal: .amrap,
                workTargets: [
                    PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                ],
                slots: slots
            )
        case .forTime:
            blockTargets = [
                PrimitiveWorkTarget(metric: .duration, valueForm: .open, role: .observation),
            ]
            primitiveSet = PrimitiveSet(
                id: UUID(),
                timing: PrimitiveTiming(mode: .setBounded),
                traversal: .sequential,
                slots: slots
            )
        default:
            blockTargets = []
            primitiveSet = PrimitiveSet(
                id: UUID(),
                timing: PrimitiveTiming(mode: .setBounded),
                traversal: .sequential,
                slots: slots
            )
        }
        return PrimitiveWorkout(
            id: workoutID,
            name: name,
            blocks: [
                PrimitiveBlock(
                    id: blockID,
                    workTargets: blockTargets,
                    sets: [primitiveSet]
                ),
            ]
        )
    }
}

private final class MetconMutableClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
