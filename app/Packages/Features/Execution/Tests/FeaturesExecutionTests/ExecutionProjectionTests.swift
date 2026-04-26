// ExecutionProjectionTests.swift
//
// Contract tests for the shared execution read model. These tests pin the
// state questions later surfaces need to answer without scraping SwiftUI:
// what the athlete should do now, what remains, what comes next, and which
// interactions are valid in the current route.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionProjectionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testStraightSetsProjectionShowsTaskIntentProgressAndEditability() {
        let itemID = UUID()
        let (context, _) = Self.context(
            timingMode: .straightSets,
            blockName: "Main lift",
            blockIntent: "Keep the bar speed crisp",
            timingConfigJSON: #"{"rest_between_sets_sec":90,"rest_between_exercises_sec":90}"#,
            items: [
                Self.item(
                    id: itemID,
                    blockID: Self.blockID,
                    exerciseID: Self.exerciseID,
                    prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":100,"weight_unit":"kg"}"#
                )
            ],
            exercises: [Self.exerciseID: "Bench"],
            alternativesByItem: [
                itemID: [
                    ExerciseAlternative(
                        id: UUID(),
                        workoutItemID: itemID,
                        exerciseID: UUID(),
                        reason: "Shoulder-friendly option"
                    )
                ]
            ]
        )
        let vm = ExecutionViewModel(context: context, clock: FixedClock(now: now))

        let beforeStart = vm.executionProjection(now: now)
        XCTAssertEqual(beforeStart.currentTask.kind, .today)
        XCTAssertEqual(beforeStart.currentTask.title, "Bench")
        XCTAssertEqual(beforeStart.currentTask.detail, "Set 1 of 2")
        XCTAssertEqual(beforeStart.currentTask.blockIntent, "Keep the bar speed crisp")
        XCTAssertEqual(beforeStart.upcomingWork?.label, "next set")
        XCTAssertEqual(beforeStart.upcomingWork?.title, "Bench")
        XCTAssertEqual(beforeStart.remainingWork.totalSets, 2)
        XCTAssertEqual(beforeStart.remainingWork.completedSets, 0)
        XCTAssertEqual(beforeStart.blockProgress?.blockName, "Main lift")
        XCTAssertEqual(beforeStart.blockProgress?.remainingSets, 2)

        vm.start()
        let active = vm.executionProjection(now: now)

        XCTAssertEqual(active.currentTask.kind, .active)
        XCTAssertEqual(active.currentTask.blockIndex, 0)
        XCTAssertEqual(active.currentTask.blockCount, 1)
        XCTAssertEqual(active.currentTask.blockName, "Main lift")
        XCTAssertEqual(active.currentTask.blockIntent, "Keep the bar speed crisp")
        XCTAssertEqual(active.currentTask.exerciseName, "Bench")
        XCTAssertEqual(active.currentTask.title, "Bench")
        XCTAssertEqual(active.currentTask.detail, "Set 1 of 2")
        XCTAssertEqual(active.currentTask.primaryMetric, "100 kg")
        XCTAssertEqual(active.currentTask.secondaryMetric, "5 reps")
        XCTAssertEqual(active.currentTask.side, .bilateral)
        XCTAssertFalse(active.currentTask.skipped)
        XCTAssertEqual(active.remainingWork.completedSets, 0)
        XCTAssertEqual(active.remainingWork.totalSets, 2)
        XCTAssertEqual(active.remainingWork.remainingSets, 2)
        XCTAssertEqual(active.blockProgress?.completedSets, 0)
        XCTAssertEqual(active.blockProgress?.totalSets, 2)
        XCTAssertEqual(active.blockProgress?.blockIntent, "Keep the bar speed crisp")
        XCTAssertEqual(active.upcomingWork?.label, "next set")
        XCTAssertEqual(active.upcomingWork?.title, "Bench")
        XCTAssertEqual(active.upcomingWork?.detail, "100 kg · 5 reps")
        XCTAssertTrue(active.editability.canStartCurrentSet)
        XCTAssertFalse(active.editability.canLogCurrentWork)
        XCTAssertTrue(active.editability.canEditPendingSet)
        XCTAssertFalse(active.editability.canEditLoggedSet)
        XCTAssertTrue(active.editability.canSwapExercise)
        XCTAssertFalse(active.editability.canExtendRest)

        vm.startCurrentSet()
        let started = vm.executionProjection(now: now)
        XCTAssertFalse(started.editability.canStartCurrentSet)
        XCTAssertTrue(started.editability.canLogCurrentWork)
        XCTAssertEqual(started.timer?.label, "SET ELAPSED")
        XCTAssertEqual(started.timer?.direction, .elapsed)
    }

    func testRestProjectionKeepsNextUpAndRemainingWorkVisible() throws {
        let itemID = UUID()
        let (context, _) = Self.context(
            timingMode: .straightSets,
            blockIntent: nil,
            timingConfigJSON: #"{"rest_between_sets_sec":75,"rest_between_exercises_sec":75}"#,
            items: [
                Self.item(
                    id: itemID,
                    blockID: Self.blockID,
                    exerciseID: Self.exerciseID,
                    prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":100,"weight_unit":"kg"}"#
                )
            ],
            exercises: [Self.exerciseID: "Bench"]
        )
        let vm = ExecutionViewModel(context: context, clock: FixedClock(now: now))
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)

        let projection = vm.executionProjection(now: now)

        XCTAssertEqual(projection.currentTask.kind, .rest)
        XCTAssertEqual(projection.currentTask.title, "Rest")
        XCTAssertNil(projection.currentTask.blockIntent)
        XCTAssertEqual(projection.remainingWork.completedSets, 1)
        XCTAssertEqual(projection.remainingWork.totalSets, 2)
        XCTAssertEqual(projection.remainingWork.remainingSets, 1)
        XCTAssertEqual(projection.blockProgress?.completedSets, 1)
        XCTAssertEqual(projection.blockProgress?.remainingSets, 1)
        XCTAssertEqual(projection.upcomingWork?.label, "next set")
        XCTAssertEqual(projection.upcomingWork?.title, "Bench")
        XCTAssertEqual(projection.upcomingWork?.detail, "100 kg · 5 reps")
        XCTAssertEqual(projection.timer?.label, "REST")
        XCTAssertEqual(projection.timer?.direction, .countdown)
        XCTAssertTrue(projection.editability.canAdvance)
        XCTAssertTrue(projection.editability.canExtendRest)
        XCTAssertFalse(projection.editability.canLogCurrentWork)
        XCTAssertTrue(projection.editability.canEditLoggedSet)

        let overdue = vm.executionProjection(now: try XCTUnwrap(vm.state.restEndsAt).addingTimeInterval(5))
        XCTAssertEqual(overdue.timer?.label, "OVER REST")
        XCTAssertEqual(overdue.timer?.direction, .elapsed)
        XCTAssertEqual(try XCTUnwrap(overdue.timer?.seconds), 5, accuracy: 0.001)
    }

    func testSupersetProjectionUsesRoundRobinUpcomingWork() {
        let itemA = UUID()
        let itemB = UUID()
        let exerciseA = UUID()
        let exerciseB = UUID()
        let (context, _) = Self.context(
            timingMode: .superset,
            blockName: "Pairing",
            blockIntent: "Move cleanly between stations",
            timingConfigJSON: #"{"rest_between_rounds_sec":60}"#,
            rounds: 2,
            items: [
                Self.item(
                    id: itemA,
                    blockID: Self.blockID,
                    exerciseID: exerciseA,
                    position: 0,
                    prescriptionJSON: #"{"sets":2,"reps":8,"load_kg":50,"weight_unit":"kg"}"#
                ),
                Self.item(
                    id: itemB,
                    blockID: Self.blockID,
                    exerciseID: exerciseB,
                    position: 1,
                    prescriptionJSON: #"{"sets":2,"reps":10}"#
                )
            ],
            exercises: [
                exerciseA: "Row",
                exerciseB: "Push-up"
            ]
        )
        let vm = ExecutionViewModel(context: context, clock: FixedClock(now: now))
        vm.start()

        let projection = vm.executionProjection(now: now)

        XCTAssertEqual(projection.currentTask.title, "Row")
        XCTAssertEqual(projection.currentTask.detail, "Set 1 of 2")
        XCTAssertEqual(projection.currentTask.blockIntent, "Move cleanly between stations")
        XCTAssertEqual(projection.remainingWork.totalSets, 4)
        XCTAssertEqual(projection.blockProgress?.totalSets, 4)
        XCTAssertEqual(projection.upcomingWork?.label, "next exercise")
        XCTAssertEqual(projection.upcomingWork?.title, "Push-up")
        XCTAssertEqual(projection.upcomingWork?.detail, "BW · 10 reps")
    }

    func testAMRAPProjectionKeepsUnboundedRoundsReadable() {
        let pullUpItem = UUID()
        let pushUpItem = UUID()
        let squatItem = UUID()
        let pullUp = UUID()
        let pushUp = UUID()
        let squat = UUID()
        let (context, _) = Self.context(
            timingMode: .amrap,
            blockName: "AMRAP",
            blockIntent: "Keep moving for quality reps",
            timingConfigJSON: #"{"time_cap_sec":720}"#,
            items: [
                Self.item(
                    id: pullUpItem,
                    blockID: Self.blockID,
                    exerciseID: pullUp,
                    position: 0,
                    prescriptionJSON: #"{"reps":10}"#
                ),
                Self.item(
                    id: pushUpItem,
                    blockID: Self.blockID,
                    exerciseID: pushUp,
                    position: 1,
                    prescriptionJSON: #"{"reps":15}"#
                ),
                Self.item(
                    id: squatItem,
                    blockID: Self.blockID,
                    exerciseID: squat,
                    position: 2,
                    prescriptionJSON: #"{"reps":20}"#
                )
            ],
            exercises: [
                pullUp: "Pull-up",
                pushUp: "Push-up",
                squat: "Air Squat"
            ]
        )
        let vm = ExecutionViewModel(context: context, clock: FixedClock(now: now))
        vm.start()

        let projection = vm.executionProjection(now: now)

        XCTAssertEqual(projection.currentTask.kind, .active)
        XCTAssertEqual(projection.currentTask.title, "Pull-up")
        XCTAssertEqual(projection.currentTask.detail, "Round 1")
        XCTAssertEqual(projection.currentTask.primaryMetric, "BW")
        XCTAssertEqual(projection.currentTask.secondaryMetric, "10 reps")
        XCTAssertEqual(projection.currentTask.blockIntent, "Keep moving for quality reps")
        XCTAssertEqual(projection.remainingWork.totalSets, 0)
        XCTAssertEqual(projection.remainingWork.remainingSets, 0)
        XCTAssertEqual(projection.blockProgress?.totalSets, 0)
        XCTAssertEqual(projection.upcomingWork?.label, "next exercise")
        XCTAssertEqual(projection.upcomingWork?.title, "Push-up")
        XCTAssertEqual(projection.timer?.label, "AMRAP CAP")
        XCTAssertEqual(projection.timer?.direction, .countdown)
    }

    func testRestBlockProjectionHandlesZeroItemBlocks() {
        let context = Self.zeroItemRestContext()
        let vm = ExecutionViewModel(context: context, clock: FixedClock(now: now))
        vm.start()

        let projection = vm.executionProjection(now: now)

        XCTAssertEqual(projection.currentTask.kind, .rest)
        XCTAssertEqual(projection.currentTask.blockName, "Reset")
        XCTAssertEqual(projection.currentTask.blockIntent, "Bring breathing back down")
        XCTAssertEqual(projection.remainingWork.completedSets, 0)
        XCTAssertEqual(projection.remainingWork.totalSets, 0)
        XCTAssertEqual(projection.blockProgress?.totalSets, 0)
        XCTAssertEqual(projection.blockProgress?.remainingSets, 0)
        XCTAssertEqual(projection.upcomingWork?.title, "Finish workout")
        XCTAssertEqual(projection.timer?.label, "REST")
        XCTAssertTrue(projection.editability.canAdvance)
        XCTAssertFalse(projection.editability.canLogCurrentWork)
    }

    func testContinuousProjectionUsesCardioMetricOrder() {
        let itemID = UUID()
        let (context, _) = Self.context(
            timingMode: .continuous,
            blockName: "Tempo",
            blockIntent: "Hold a steady aerobic rhythm",
            timingConfigJSON: #"""
            {"target_duration_sec":1800,"target_pace_sec_per_km":270,"target_hr_zone":4}
            """#,
            items: [
                Self.item(
                    id: itemID,
                    blockID: Self.blockID,
                    exerciseID: Self.exerciseID,
                    prescriptionJSON: "{}"
                )
            ],
            exercises: [Self.exerciseID: "Run"]
        )
        let vm = ExecutionViewModel(context: context, clock: FixedClock(now: now))
        vm.start()

        let projection = vm.executionProjection(now: now)

        XCTAssertEqual(projection.currentTask.kind, .active)
        XCTAssertEqual(projection.currentTask.title, "Run")
        XCTAssertEqual(projection.currentTask.detail, "Continuous")
        XCTAssertEqual(projection.currentTask.primaryMetric, "30 min")
        XCTAssertEqual(projection.currentTask.secondaryMetric, "4:30 / km")
        XCTAssertEqual(projection.currentTask.blockIntent, "Hold a steady aerobic rhythm")
        XCTAssertEqual(projection.timer?.label, "TARGET")
        XCTAssertEqual(projection.timer?.direction, .countdown)
        XCTAssertTrue(projection.editability.canLogCurrentWork)
        XCTAssertFalse(projection.editability.canStartCurrentSet)
    }

    // MARK: - Fixtures

    private static let workoutID = UUID()
    private static let blockID = UUID()
    private static let exerciseID = UUID()

    private static func context(
        timingMode: TimingMode,
        blockName: String? = nil,
        blockIntent: String?,
        timingConfigJSON: String,
        rounds: Int? = nil,
        items: [WorkoutItem],
        exercises: [UUID: String],
        alternativesByItem: [UUID: [ExerciseAlternative]] = [:]
    ) -> (WorkoutContext, UUID) {
        let now = Date()
        let workout = Workout(
            id: workoutID,
            userID: UUID(),
            name: "Projection",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
        let block = Block(
            id: blockID,
            workoutID: workoutID,
            position: 0,
            name: blockName,
            timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: rounds,
            intent: blockIntent
        )
        let exerciseMap = Dictionary(
            uniqueKeysWithValues: exercises.map {
                ($0.key, Exercise(id: $0.key, name: $0.value))
            }
        )
        return (
            WorkoutContext(
                workout: workout,
                blocks: [block],
                itemsByBlock: [items],
                exercises: exerciseMap,
                alternativesByItem: alternativesByItem
            ),
            items.first?.id ?? UUID()
        )
    }

    private static func item(
        id: UUID = UUID(),
        blockID: UUID,
        exerciseID: UUID,
        position: Int = 0,
        prescriptionJSON: String
    ) -> WorkoutItem {
        WorkoutItem(
            id: id,
            blockID: blockID,
            position: position,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
    }

    private static func zeroItemRestContext() -> WorkoutContext {
        let now = Date()
        let workout = Workout(
            id: workoutID,
            userID: UUID(),
            name: "Reset",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
        let block = Block(
            id: blockID,
            workoutID: workoutID,
            position: 0,
            name: "Reset",
            timingMode: .rest,
            timingConfigJSON: #"{"duration_sec":90}"#,
            intent: "Bring breathing back down"
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[]],
            exercises: [:]
        )
    }
}
