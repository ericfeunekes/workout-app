// ExecutionViewModelMetconResultTests.swift
//
// Regression coverage for AMRAP / For Time result capture. AMRAP logs
// completed stations as the athlete taps next, then captures only the
// partial station at the finish sheet.

import XCTest
import CoreDomain
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

    // MARK: - Fixtures

    private struct Fixture {
        let context: WorkoutContext
        let firstItemID: UUID
        let secondItemID: UUID
    }

    private static func metconThenStrengthContext(
        firstMode: TimingMode,
        firstTimingConfigJSON: String,
        firstItems: [(String, String)]
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

        return Fixture(
            context: WorkoutContext(
                workout: workout,
                blocks: [metconBlock, strengthBlock],
                itemsByBlock: [metconItems, [strengthItem]],
                exercises: exercises
            ),
            firstItemID: metconItems[0].id,
            secondItemID: metconItems[min(1, metconItems.count - 1)].id
        )
    }
}

private final class MetconMutableClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
