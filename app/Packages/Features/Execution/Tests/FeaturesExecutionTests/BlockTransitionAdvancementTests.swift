// BlockTransitionAdvancementTests.swift
//
// qa-041 regression: crossing a block boundary from a set-major block
// (straight_sets) into a round-robin block (superset) must re-read the
// new block's advancement policy. Prior to this coverage, the reducer
// logic was known-correct in isolation but the full seeder → reducer
// loop hadn't been exercised end-to-end for a set-major → round-robin
// transition.
//
// The test seeds a real 2-block context via `SessionSeeder.seed(context:)`,
// walks through block 1 (straight_sets, 1 item × 2 sets), crosses into
// block 2 (superset, 2 items × 2 rounds), and pins the round-robin walk:
//   (1, 0, 1) → logSet + advance → (1, 1, 1)
//   (1, 1, 1) → logSet + advance → (1, 0, 2) — alternates back to item 0
//
// If the advancement policy isn't re-read at the block boundary, the
// cursor would stay on item 1 (inheriting set-major semantics) and the
// test's final assertion would fail.

import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class BlockTransitionAdvancementTests: XCTestCase {

    func testWorkBlockBoundaryRoutesThroughTransitionBeforeNextActiveBlock() {
        let ctx = makeWorkToCarryContext()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: FixedClock(now: Date(timeIntervalSince1970: 10_000))
        )

        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        XCTAssertEqual(vm.state.route, .rest)

        vm.advance()

        XCTAssertEqual(vm.state.route, .transition)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertNil(vm.timerPresentation(now: Date(timeIntervalSince1970: 10_000)))
        let presentation = vm.blockTransitionPresentation
        XCTAssertEqual(presentation?.finishedTitle, "Press primer")
        XCTAssertEqual(presentation?.nextTitle, "Carry test")
        XCTAssertEqual(presentation?.timingMode, "straight sets")
        XCTAssertEqual(presentation?.firstTask, "Farmer Carry · 100 ft · 53 lb")
        XCTAssertEqual(presentation?.setup, "Farmer Carry · 100 ft · 53 lb")

        vm.beginBlockTransition()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertTrue(vm.requiresExplicitSetStartForCurrentWork)
        XCTAssertFalse(vm.isCurrentWorkStarted)
    }

    func testSkippedZeroRestFinalSetRoutesThroughTransition() {
        let ctx = makeWorkToCarryContext(restSec: 0)
        let vm = ExecutionViewModel(context: ctx)

        vm.start()
        vm.startCurrentSet()
        vm.skipCurrentSet()

        XCTAssertEqual(vm.state.route, .transition)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.blockTransitionPresentation?.nextTitle, "Carry test")
    }

    func testCompositeZeroRestFinalSetRoutesThroughTransition() {
        let ctx = makeClusterToCarryContext(restSec: 0)
        let vm = ExecutionViewModel(context: ctx)

        vm.start()
        vm.startCurrentSet()
        vm.completeCurrentCompositeSlot()
        vm.startCurrentSet()
        vm.logSet(reps: 10, rir: 1)

        XCTAssertEqual(vm.state.route, .transition)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.blockTransitionPresentation?.finishedTitle, "Cluster primer")
        XCTAssertEqual(vm.blockTransitionPresentation?.nextTitle, "Carry test")
    }

    func testStandaloneRestBlockDoesNotChainIntoDuplicateTransition() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 20_000))
        let (ctx, _, _) = makeWorkRestWorkContext(restSec: 10, restBlockDurationSec: 5)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)

        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.advance()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.advance()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 5
        )

        vm.advance()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 2)
    }

    func testBlockTransitionResetsAdvancementMode() {
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()

        // Block 0: straight_sets, 1 item × 2 sets.
        let straightBlockID = UUID()
        let straightExerciseID = UUID()
        let straightItemID = UUID()
        let straightItem = WorkoutItem(
            id: straightItemID,
            blockID: straightBlockID,
            position: 0,
            exerciseID: straightExerciseID,
            prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":100}"#
        )
        let straightBlock = Block(
            id: straightBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":90,"rest_between_exercises_sec":120}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )

        // Block 1: superset, 2 items × 2 rounds.
        let supersetBlockID = UUID()
        let supersetExercise0 = UUID()
        let supersetExercise1 = UUID()
        let supersetItem0 = UUID()
        let supersetItem1 = UUID()
        let supersetItems = [
            WorkoutItem(
                id: supersetItem0,
                blockID: supersetBlockID,
                position: 0,
                exerciseID: supersetExercise0,
                prescriptionJSON: #"{"reps":10,"load_kg":60}"#
            ),
            WorkoutItem(
                id: supersetItem1,
                blockID: supersetBlockID,
                position: 1,
                exerciseID: supersetExercise1,
                prescriptionJSON: #"{"reps":10,"load_kg":60}"#
            ),
        ]
        let supersetBlock = Block(
            id: supersetBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .superset,
            timingConfigJSON: #"{"rest_between_rounds_sec":90}"#,
            rounds: 2, roundsRepSchemeJSON: nil, notes: nil
        )

        let workout = Workout(
            id: workoutID, userID: userID, name: "strength + superset",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let exercises: [UUID: Exercise] = [
            straightExerciseID: Exercise(id: straightExerciseID, name: "Bench Press"),
            supersetExercise0: Exercise(id: supersetExercise0, name: "DB Curl"),
            supersetExercise1: Exercise(id: supersetExercise1, name: "Triceps Pushdown"),
        ]
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [straightBlock, supersetBlock],
            itemsByBlock: [[straightItem], supersetItems],
            exercises: exercises
        )

        var state = SessionSeeder.seed(context: ctx)

        // Sanity-check the seed: set-major for block 0, round-robin for block 1.
        XCTAssertEqual(state.structure.itemsPerBlock, [1, 2])
        XCTAssertEqual(state.structure.setsPerItem, [[2], [2, 2]])
        XCTAssertEqual(
            state.structure.advancementByBlock,
            [.setMajor, .roundRobin],
            "seeder must tag superset blocks as round-robin"
        )

        // Walk block 0 to completion.
        state = SessionReducer.reduce(
            state,
            .logSet(itemID: straightItemID, setIndex: 1, loggedReps: 5, loggedRir: 2, now: now)
        )
        state = SessionReducer.reduce(state, .advanceFromRest)
        XCTAssertEqual(state.cursor, SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2))

        state = SessionReducer.reduce(
            state,
            .logSet(itemID: straightItemID, setIndex: 2, loggedReps: 5, loggedRir: 2, now: now)
        )
        state = SessionReducer.reduce(state, .advanceFromRest)
        // Crossed into block 1, first item, first round.
        XCTAssertEqual(state.cursor, SessionState.Cursor(blockIndex: 1, itemIndex: 0, setIndex: 1))

        // Block 1 round 1 · item 0 → item 1 (round-robin within a round).
        state = SessionReducer.reduce(
            state,
            .logSet(itemID: supersetItem0, setIndex: 1, loggedReps: 10, loggedRir: 2, now: now)
        )
        state = SessionReducer.reduce(state, .advanceFromRest)
        XCTAssertEqual(
            state.cursor, SessionState.Cursor(blockIndex: 1, itemIndex: 1, setIndex: 1),
            "round-robin must advance to item 1 within round 1"
        )

        // Block 1 round 1 last item → round 2 first item. qa-041: this must
        // alternate back to item 0, NOT stay on item 1 with setIndex bumped.
        state = SessionReducer.reduce(
            state,
            .logSet(itemID: supersetItem1, setIndex: 1, loggedReps: 10, loggedRir: 2, now: now)
        )
        state = SessionReducer.reduce(state, .advanceFromRest)
        XCTAssertEqual(
            state.cursor, SessionState.Cursor(blockIndex: 1, itemIndex: 0, setIndex: 2),
            "round-robin must alternate back to item 0 at the round boundary — qa-041 regression"
        )
    }

    private func makeWorkToCarryContext(restSec: Int = 10) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let pressBlockID = UUID()
        let carryBlockID = UUID()
        let pressExerciseID = UUID()
        let carryExerciseID = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "transition setup",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let pressBlock = Block(
            id: pressBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "Press primer", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let carryBlock = Block(
            id: carryBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: "Carry test", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let pressItem = WorkoutItem(
            id: UUID(), blockID: pressBlockID, position: 0,
            exerciseID: pressExerciseID,
            prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":80,"weight_unit":"kg"}"#
        )
        let carryItem = WorkoutItem(
            id: UUID(), blockID: carryBlockID, position: 0,
            exerciseID: carryExerciseID,
            prescriptionJSON: #"{"sets":1,"target":{"kind":"distance","value":100,"unit":"ft"},"load_kg":53,"weight_unit":"lb"}"#
        )
        return WorkoutContext(
            workout: workout,
            blocks: [pressBlock, carryBlock],
            itemsByBlock: [[pressItem], [carryItem]],
            exercises: [
                pressExerciseID: Exercise(id: pressExerciseID, name: "Bench Press"),
                carryExerciseID: Exercise(id: carryExerciseID, name: "Farmer Carry"),
            ],
            lastPerformed: [:]
        )
    }

    private func makeClusterToCarryContext(restSec: Int) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let clusterBlockID = UUID()
        let carryBlockID = UUID()
        let clusterExerciseID = UUID()
        let carryExerciseID = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "cluster transition",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let clusterBlock = Block(
            id: clusterBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "Cluster primer", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let carryBlock = Block(
            id: carryBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: "Carry test", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let clusterItem = WorkoutItem(
            id: UUID(), blockID: clusterBlockID, position: 0,
            exerciseID: clusterExerciseID,
            prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":80,"weight_unit":"kg","sub_sets":2,"intra_set_rest_sec":1}"#
        )
        let carryItem = WorkoutItem(
            id: UUID(), blockID: carryBlockID, position: 0,
            exerciseID: carryExerciseID,
            prescriptionJSON: #"{"sets":1,"target":{"kind":"distance","value":100,"unit":"ft"},"load_kg":53,"weight_unit":"lb"}"#
        )
        return WorkoutContext(
            workout: workout,
            blocks: [clusterBlock, carryBlock],
            itemsByBlock: [[clusterItem], [carryItem]],
            exercises: [
                clusterExerciseID: Exercise(id: clusterExerciseID, name: "Cluster Press"),
                carryExerciseID: Exercise(id: carryExerciseID, name: "Farmer Carry"),
            ],
            lastPerformed: [:]
        )
    }

    private func makeWorkRestWorkContext(
        restSec: Int,
        restBlockDurationSec: Int
    ) -> (WorkoutContext, UUID, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let blockA = UUID()
        let blockRest = UUID()
        let blockB = UUID()
        let exerciseA = UUID()
        let exerciseB = UUID()
        let itemA = UUID()
        let itemB = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "work rest work",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let workA = Block(
            id: blockA, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "A", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let rest = Block(
            id: blockRest, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: "Rest", timingMode: .rest,
            timingConfigJSON: #"{"duration_sec":\#(restBlockDurationSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let workB = Block(
            id: blockB, workoutID: workoutID, parentBlockID: nil,
            position: 2, name: "B", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        return (WorkoutContext(
            workout: workout,
            blocks: [workA, rest, workB],
            itemsByBlock: [
                [WorkoutItem(
                    id: itemA, blockID: blockA, position: 0,
                    exerciseID: exerciseA,
                    prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":50}"#
                )],
                [],
                [WorkoutItem(
                    id: itemB, blockID: blockB, position: 0,
                    exerciseID: exerciseB,
                    prescriptionJSON: #"{"sets":1,"reps":6,"load_kg":40}"#
                )],
            ],
            exercises: [
                exerciseA: Exercise(id: exerciseA, name: "A"),
                exerciseB: Exercise(id: exerciseB, name: "B"),
            ],
            lastPerformed: [:]
        ), itemA, itemB)
    }
}
