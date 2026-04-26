import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class AccumulateDriverTests: XCTestCase {
    func testAccumulateRepsLogsChunksUntilTargetComplete() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableAccumulateClock(now: start)
        let ctx = makeAccumulateContext(
            configJSON: #"{"target_reps":100}"#,
            prescriptionJSON: #"{"reps":25}"#
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.activeContent?.repsDisplay, "0 / 100")
        XCTAssertTrue(vm.requiresExplicitSetStartForCurrentWork)
        XCTAssertFalse(vm.isCurrentWorkStarted)

        for chunk in 1...3 {
            vm.startCurrentSet()
            vm.logSet(reps: 25, rir: nil)
            XCTAssertEqual(vm.state.route, .active)
            XCTAssertEqual(vm.state.cursor.setIndex, chunk + 1)
            XCTAssertEqual(vm.activeContent?.repsDisplay, "\(chunk * 25) / 100")
            XCTAssertFalse(vm.isCurrentWorkStarted)
        }

        vm.startCurrentSet()
        vm.logSet(reps: 25, rir: nil)

        XCTAssertEqual(vm.state.route, .complete)
    }

    func testAccumulateDurationLogsFreeRestBoutsUntilTargetComplete() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableAccumulateClock(now: start)
        let ctx = makeAccumulateContext(
            configJSON: #"{"target_duration_sec":120}"#,
            prescriptionJSON: "{}"
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        vm.startCurrentSet()
        clock.now = start.addingTimeInterval(77)
        vm.logCurrentSet()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.activeContent?.repsDisplay, "1:17 / 2:00")
        XCTAssertEqual(vm.timerPresentation(now: clock.now)?.inlineText, "READY 0:00")

        vm.startCurrentSet()
        clock.now = start.addingTimeInterval(125)
        vm.logCurrentSet()

        XCTAssertEqual(vm.state.route, .complete)
    }

    func testAccumulateDoesNotExposeDeliberateSkip() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableAccumulateClock(now: start)
        let ctx = makeAccumulateContext(
            configJSON: #"{"target_reps":100}"#,
            prescriptionJSON: #"{"reps":25}"#
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertFalse(vm.canSkipCurrentSet)
        vm.skipCurrentSet()
        XCTAssertEqual(vm.activeContent?.repsDisplay, "0 / 100")
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
    }

    func testAccumulateTargetRoutesToNextBlockWhenComposed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableAccumulateClock(now: start)
        let ctx = makeAccumulateContext(
            configJSON: #"{"target_reps":50}"#,
            prescriptionJSON: #"{"reps":25}"#,
            appendStraightSetBlock: true
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 25, rir: nil)
        vm.startCurrentSet()
        vm.logSet(reps: 25, rir: nil)

        XCTAssertEqual(vm.state.route, .transition)
        vm.beginBlockTransition()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        XCTAssertTrue(vm.requiresExplicitSetStartForCurrentWork)
        XCTAssertFalse(vm.isCurrentWorkStarted)
        XCTAssertEqual(vm.activeContent?.exerciseName, "Back Squat")
    }

    func testAccumulateSwapSetsOverrideDoesNotShrinkTargetSentinel() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableAccumulateClock(now: start)
        let ctx = makeAccumulateContext(
            configJSON: #"{"target_reps":100}"#,
            prescriptionJSON: #"{"reps":25}"#,
            alternativeOverridesJSON: #"{"sets":1,"reps":10}"#
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        let itemID = ctx.itemsByBlock[0][0].id
        let alternativeID = ctx.alternatives(for: itemID)[0].id

        vm.start()
        vm.swap(itemID: itemID, alternativeID: alternativeID)
        vm.startCurrentSet()
        vm.logSet(reps: 10, rir: nil)

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.structure.advancementByBlock, [.roundRobin])
        XCTAssertGreaterThan(vm.state.items[0].sets.count, 1)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)
        XCTAssertEqual(vm.activeContent?.repsDisplay, "10 / 100")
    }

    private func makeAccumulateContext(
        configJSON: String,
        prescriptionJSON: String,
        appendStraightSetBlock: Bool = false,
        alternativeOverridesJSON: String? = nil
    ) -> WorkoutContext {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let nextBlockID = UUID()
        let exerciseID = UUID()
        let alternativeID = UUID()
        let alternativeExerciseID = UUID()
        let nextExerciseID = UUID()
        let itemID = UUID()
        let nextItemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "accumulate",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .accumulate,
            timingConfigJSON: configJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
        let nextBlock = Block(
            id: nextBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let nextItem = WorkoutItem(
            id: nextItemID, blockID: nextBlockID, position: 0,
            exerciseID: nextExerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5}"#
        )
        let blocks = appendStraightSetBlock ? [block, nextBlock] : [block]
        let itemsByBlock = appendStraightSetBlock ? [[item], [nextItem]] : [[item]]
        var exercises = [
            exerciseID: Exercise(id: exerciseID, name: "Push-Up"),
        ]
        if appendStraightSetBlock {
            exercises[nextExerciseID] = Exercise(id: nextExerciseID, name: "Back Squat")
        }
        let alternativesByItem: [UUID: [ExerciseAlternative]]
        if let alternativeOverridesJSON {
            exercises[alternativeExerciseID] = Exercise(id: alternativeExerciseID, name: "Incline Push-Up")
            alternativesByItem = [
                itemID: [
                    ExerciseAlternative(
                        id: alternativeID,
                        workoutItemID: itemID,
                        exerciseID: alternativeExerciseID,
                        reason: "scale volume",
                        parameterOverridesJSON: alternativeOverridesJSON
                    ),
                ],
            ]
        } else {
            alternativesByItem = [:]
        }
        return WorkoutContext(
            workout: workout,
            blocks: blocks,
            itemsByBlock: itemsByBlock,
            exercises: exercises,
            alternativesByItem: alternativesByItem
        )
    }
}

private final class MutableAccumulateClock: Clock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
