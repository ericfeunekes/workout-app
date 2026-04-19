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
}
