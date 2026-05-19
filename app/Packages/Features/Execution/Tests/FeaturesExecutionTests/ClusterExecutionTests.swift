import Foundation
import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ClusterExecutionTests: XCTestCase {

    func testSeederPreservesClusterShapeAsCompositeProgress() throws {
        let (context, itemID) = Self.clusterContext()

        let state = SessionSeeder.seed(context: context)

        let itemLog = try XCTUnwrap(state.items.first { $0.itemID == itemID })
        XCTAssertEqual(itemLog.sets.count, 2)
        XCTAssertEqual(itemLog.sets.map(\.reps), [10, 10])
        XCTAssertEqual(itemLog.sets.map(\.loadKg), [100, 100])

        XCTAssertEqual(state.compositeSets.count, 2)
        let first = try XCTUnwrap(state.compositeSets.first { $0.itemID == itemID && $0.setIndex == 1 })
        XCTAssertEqual(first.kind, .cluster)
        XCTAssertEqual(first.targetRepsPerSlot, 5)
        XCTAssertEqual(first.slotCount, 2)
        XCTAssertEqual(first.intraRestSec, 15)
        XCTAssertEqual(first.phase, .ready(slotIndex: 1))
    }

    func testSeederPreservesClusterShapeInsideRoundRobinBlocks() throws {
        let (context, itemID) = Self.roundRobinClusterContext(mode: .superset)

        let state = SessionSeeder.seed(context: context)

        let itemLog = try XCTUnwrap(state.items.first { $0.itemID == itemID })
        XCTAssertEqual(itemLog.sets.count, 2)
        XCTAssertEqual(itemLog.sets.map(\.reps), [10, 10])
        XCTAssertEqual(itemLog.sets.map(\.loadKg), [24, 24])

        XCTAssertEqual(state.compositeSets.count, 2)
        let first = try XCTUnwrap(state.compositeSets.first { $0.itemID == itemID && $0.setIndex == 1 })
        XCTAssertEqual(first.targetRepsPerSlot, 5)
        XCTAssertEqual(first.slotCount, 2)
        XCTAssertEqual(first.intraRestSec, 5)
    }

    func testRoundRobinClusterExecutesSlotsBeforeAdvancingStation() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_010_000)
        let clock = MutableClusterClock(now: t0)
        let (context, itemID) = Self.roundRobinClusterContext(mode: .superset)
        let vm = ExecutionViewModel(context: context, clock: clock)

        vm.start()
        XCTAssertTrue(vm.isCurrentCompositeSet)
        XCTAssertEqual(vm.currentCompositeButtonTitle, "set start")
        XCTAssertEqual(vm.currentCompositeRepsDisplay, "5 reps · cluster 1/2")
        let content = try XCTUnwrap(vm.activeContent)
        XCTAssertEqual(content.loadDisplay, "24 kg")
        XCTAssertEqual(content.reps, 10)

        vm.startCurrentSet()
        clock.advance(by: 3)
        vm.completeCurrentCompositeSlot()

        var set = try XCTUnwrap(vm.state.items.first { $0.itemID == itemID }?.sets.first)
        XCTAssertFalse(set.done)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.currentCompositeButtonTitle, "start cluster 2")

        clock.advance(by: 5)
        vm.startCurrentSet()
        clock.advance(by: 4)
        vm.advanceRoundRobinBatchStation()

        set = try XCTUnwrap(vm.state.items.first { $0.itemID == itemID }?.sets.first)
        XCTAssertFalse(set.done)
        XCTAssertEqual(vm.state.cursor.itemIndex, 1)
        XCTAssertEqual(vm.activeContent?.exerciseName, "Row")

        vm.advanceRoundRobinBatchStation()
        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertTrue(vm.isRoundRobinBatchRoundRest)

        vm.editRoundRobinBatchSet(itemID: itemID, setIndex: 1, loadKg: 24, reps: 10, rir: 2)
        vm.advance()

        set = try XCTUnwrap(vm.state.items.first { $0.itemID == itemID }?.sets.first)
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.reps, 10)
        XCTAssertEqual(set.rir, 2)
        XCTAssertTrue(vm.state.compositeSets.allSatisfy { $0.itemID != itemID || $0.setIndex != 1 })
    }

    func testNextUpShowsCompositeSetShapeInsteadOfOnlyTotalReps() throws {
        let (context, _) = Self.clusterContext()
        let vm = ExecutionViewModel(context: context)

        vm.start()

        XCTAssertEqual(vm.nextUpPresentation?.label, "next set")
        XCTAssertEqual(vm.nextUpPresentation?.title, "Bench Press")
        XCTAssertEqual(vm.nextUpPresentation?.detail, "100 lb · 5 reps × 2 clusters (10 total)")
    }

    func testClusterSlotsDoNotLogUntilFinalTopLevelSet() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_010_000)
        let clock = MutableClusterClock(now: t0)
        let (context, itemID) = Self.clusterContext()
        let recorder = EnqueueRecorder()
        let vm = ExecutionViewModel(
            context: context,
            clock: clock,
            push: ExecutionPushHooks(onPrimitiveSetLogged: { [recorder] log in
                await recorder.appendPrimitiveSet(log)
            })
        )

        vm.start()
        vm.startCurrentSet()
        clock.advance(by: 10)
        vm.completeCurrentCompositeSlot()

        var set = try XCTUnwrap(vm.state.items.first { $0.itemID == itemID }?.sets.first)
        XCTAssertFalse(set.done, "non-final cluster slot must not commit the top-level set")
        let logsAfterFirstSlot = await recorder.primitiveSetLogs
        XCTAssertEqual(logsAfterFirstSlot.count, 0)
        let restTimer = try XCTUnwrap(vm.timerPresentation(now: clock.now))
        XCTAssertEqual(restTimer.label, "CLUSTER REST")
        XCTAssertEqual(restTimer.seconds, 15, accuracy: 0.001)

        clock.advance(by: 15)
        vm.startCurrentSet()
        clock.advance(by: 8)
        vm.logSet(loadKg: 100, reps: 10, rir: 1)
        try await Task.sleep(nanoseconds: 50_000_000)

        set = try XCTUnwrap(vm.state.items.first { $0.itemID == itemID }?.sets.first)
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.reps, 10)
        XCTAssertEqual(set.rir, 1)
        XCTAssertEqual(set.completedAt, clock.now)
        XCTAssertEqual(try XCTUnwrap(set.durationSec), 33, accuracy: 0.001)
        XCTAssertTrue(vm.state.compositeSets.allSatisfy { $0.setIndex != 1 })
        XCTAssertEqual(vm.state.route, .rest)

        let pushedLogs = await recorder.primitiveSetLogs
        let pushed = try XCTUnwrap(pushedLogs.first)
        XCTAssertEqual(pushed.reps, 10)
        XCTAssertEqual(pushed.weight, 100)
        XCTAssertEqual(pushed.weightUnit, .lb)
        XCTAssertEqual(pushed.rir, 1)
        XCTAssertEqual(try XCTUnwrap(pushed.durationSec), 33, accuracy: 0.001)
        XCTAssertNil(pushed.distanceM)
    }

    func testClusterAutoregRunsOnceAtTopLevelSet() throws {
        let (context, itemID) = Self.clusterContext(
            prescriptionJSON: #"""
            {
              "sets": 2, "reps": 5, "load_kg": 100, "weight_unit": "lb",
              "sub_sets": 2, "intra_set_rest_sec": 15, "target_rir": 1,
              "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 5,
                            "undershoot_at": 2, "undershoot_step_kg": 5,
                            "apply_to": "remaining" }
            }
            """#
        )
        let state = SessionSeeder.seed(context: context)
        let driver = StraightSetsDriver()

        let outcome = driver.onSetLogged(
            state: state,
            context: context,
            event: SetLogEvent(itemID: itemID, setIndex: 1, loggedReps: 10, loggedRir: 4)
        )

        let proposal = try XCTUnwrap(outcome.proposal)
        XCTAssertEqual(proposal.direction, .up)
        XCTAssertEqual(proposal.newLoadKg, 105)
    }

    private static func clusterContext(
        prescriptionJSON: String = #"""
        {"sets":2,"reps":5,"load_kg":100,"weight_unit":"lb","sub_sets":2,"intra_set_rest_sec":15,"target_rir":1}
        """#
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Cluster",
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
            parentBlockID: nil,
            position: 0,
            name: "Bench Cluster",
            timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":90}"#,
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let item = WorkoutItem(
            id: itemID,
            blockID: blockID,
            position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
        let primitiveWorkout = PrimitiveWorkout(
            id: workoutID,
            name: workout.name,
            blocks: [
                PrimitiveBlock(
                    id: blockID,
                    sets: [
                        PrimitiveSet(
                            id: UUID(),
                            timing: PrimitiveTiming(mode: .setBounded),
                            traversal: .sequential,
                            slots: [
                                PrimitiveSlot(
                                    id: itemID,
                                    exerciseID: exerciseID,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .reps,
                                            valueForm: .single,
                                            value: 5,
                                            role: .completion
                                        ),
                                    ],
                                    load: PrimitiveLoad(value: 100, unit: .lb, unitType: .absolute)
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )
        return (
            WorkoutContext(
                workout: workout,
                primitiveWorkout: primitiveWorkout,
                primitiveExecutionPlan: ExecutionPlan(workout: primitiveWorkout),
                blocks: [block],
                itemsByBlock: [[item]],
                exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench Press")]
            ),
            itemID
        )
    }

    private static func roundRobinClusterContext(mode: TimingMode) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let clusterExerciseID = UUID()
        let rowExerciseID = UUID()
        let clusterItemID = UUID()
        let rowItemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Round Robin Cluster",
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
            parentBlockID: nil,
            position: 0,
            name: "Cluster Pair",
            timingMode: mode,
            timingConfigJSON: #"{"rest_between_rounds_sec":8}"#,
            rounds: 2,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let cluster = WorkoutItem(
            id: clusterItemID,
            blockID: blockID,
            position: 0,
            exerciseID: clusterExerciseID,
            prescriptionJSON: #"{"reps":5,"load_kg":24,"weight_unit":"kg","sub_sets":2,"intra_set_rest_sec":5,"target_rir":1}"#
        )
        let row = WorkoutItem(
            id: rowItemID,
            blockID: blockID,
            position: 1,
            exerciseID: rowExerciseID,
            prescriptionJSON: #"{"reps":10,"load_kg":22,"weight_unit":"kg","target_rir":2}"#
        )
        let primitiveWorkout = PrimitiveWorkout(
            id: workoutID,
            name: workout.name,
            blocks: [
                PrimitiveBlock(
                    id: blockID,
                    sets: [
                        PrimitiveSet(
                            id: UUID(),
                            timing: PrimitiveTiming(mode: .setBounded),
                            traversal: .sequential,
                            slots: [
                                PrimitiveSlot(
                                    id: clusterItemID,
                                    exerciseID: clusterExerciseID,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .reps,
                                            valueForm: .single,
                                            value: 5,
                                            role: .completion
                                        ),
                                    ],
                                    load: PrimitiveLoad(value: 24, unit: .kg, unitType: .absolute)
                                ),
                                PrimitiveSlot(
                                    id: rowItemID,
                                    exerciseID: rowExerciseID,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .reps,
                                            valueForm: .single,
                                            value: 10,
                                            role: .completion
                                        ),
                                    ],
                                    load: PrimitiveLoad(value: 22, unit: .kg, unitType: .absolute)
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )
        return (
            WorkoutContext(
                workout: workout,
                primitiveWorkout: primitiveWorkout,
                primitiveExecutionPlan: ExecutionPlan(workout: primitiveWorkout),
                blocks: [block],
                itemsByBlock: [[cluster, row]],
                exercises: [
                    clusterExerciseID: Exercise(id: clusterExerciseID, name: "Cluster Press"),
                    rowExerciseID: Exercise(id: rowExerciseID, name: "Row"),
                ]
            ),
            clusterItemID
        )
    }
}

private final class MutableClusterClock: Clock, @unchecked Sendable {
    private var current: Date
    private let lock = NSLock()

    init(now: Date) {
        current = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}
