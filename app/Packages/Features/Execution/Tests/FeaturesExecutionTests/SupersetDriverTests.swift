// SupersetDriverTests.swift
//
// Unit coverage for `SupersetDriver`:
//   - activeContent resolves exercise name + reps + load at the cursor
//   - activeContent returns nil when the cursor is out of range
//   - restDuration returns 0 between items within a round (back-to-back)
//   - restDuration returns `rest_between_rounds_sec` after the last item
//     of a non-last round
//   - restDuration on the last item of the last round falls back to 0
//     (VM routes to .complete; defensive branch)
//   - restDuration handles weighted vs bodyweight items identically
//   - restDuration = 0 on malformed timing config
//   - onSetLogged returns an empty outcome

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class SupersetDriverTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSuperset(
        rounds: Int? = 3,
        restBetweenRoundsSec: Double? = 90,
        items: [(name: String, prescriptionJSON: String)],
        cursor: SessionState.Cursor? = nil
    ) -> (WorkoutContext, [UUID], SessionState) {
        let blockID = UUID()
        let (workoutItems, exercises, itemIDs) = buildItems(blockID: blockID, items: items)
        let configJSON = restBetweenRoundsSec.map { #"{"rest_between_rounds_sec":\#($0)}"# } ?? "{}"
        let ctx = buildContext(
            blockID: blockID,
            configJSON: configJSON,
            rounds: rounds,
            workoutItems: workoutItems,
            exercises: exercises
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active
        if let c = cursor {
            state.cursor = c
        }
        return (ctx, itemIDs, state)
    }

    private func buildItems(
        blockID: UUID,
        items: [(name: String, prescriptionJSON: String)]
    ) -> (workoutItems: [WorkoutItem], exercises: [UUID: Exercise], itemIDs: [UUID]) {
        var workoutItems: [WorkoutItem] = []
        var exercises: [UUID: Exercise] = [:]
        var itemIDs: [UUID] = []
        for (position, spec) in items.enumerated() {
            let exerciseID = UUID()
            let itemID = UUID()
            exercises[exerciseID] = Exercise(id: exerciseID, name: spec.name)
            workoutItems.append(WorkoutItem(
                id: itemID,
                blockID: blockID,
                position: position,
                exerciseID: exerciseID,
                prescriptionJSON: spec.prescriptionJSON
            ))
            itemIDs.append(itemID)
        }
        return (workoutItems, exercises, itemIDs)
    }

    private func buildContext(
        blockID: UUID,
        configJSON: String,
        rounds: Int?,
        workoutItems: [WorkoutItem],
        exercises: [UUID: Exercise]
    ) -> WorkoutContext {
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "superset",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .superset,
            timingConfigJSON: configJSON,
            rounds: rounds, roundsRepSchemeJSON: nil, notes: nil
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises
        )
    }

    /// Canonical 2-item / 3-round superset: bench + row.
    private func makeStandardSuperset(
        cursor: SessionState.Cursor? = nil
    ) -> (WorkoutContext, [UUID], SessionState) {
        makeSuperset(
            rounds: 3,
            restBetweenRoundsSec: 90,
            items: [
                (name: "Bench Press", prescriptionJSON: #"{"reps":10,"load_kg":60}"#),
                (name: "Bent Row", prescriptionJSON: #"{"reps":10,"load_kg":60}"#),
            ],
            cursor: cursor
        )
    }

    // MARK: - activeContent

    func testActiveContentResolvesFirstItem() {
        let (ctx, _, state) = makeStandardSuperset()
        let content = SupersetDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Bench Press")
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.repsDisplay, "10")
        XCTAssertEqual(content?.loadKg, 60)
        XCTAssertEqual(content?.loadDisplay, "60 lb")
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 3)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentFollowsCursorToSecondItem() {
        let (ctx, _, state) = makeStandardSuperset(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 2)
        )
        let content = SupersetDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.exerciseName, "Bent Row")
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.setIndex, 2)
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let (ctx, _, state) = makeStandardSuperset(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 99, setIndex: 1)
        )
        XCTAssertNil(SupersetDriver().activeContent(state: state, context: ctx))
    }

    // MARK: - restDuration

    func testRestDurationIsZeroBetweenItemsWithinRound() {
        // Cursor on item 0 of 2, round 1 of 3 → back-to-back → 0.
        let (ctx, _, state) = makeStandardSuperset(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1)
        )
        XCTAssertEqual(
            SupersetDriver().restDuration(state: state, context: ctx),
            0
        )
    }

    func testRestDurationReturnsRestBetweenRoundsAfterLastItem() {
        // Cursor on item 1 (last) of 2, round 1 of 3 → RBR (=90).
        let (ctx, _, state) = makeStandardSuperset(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 1)
        )
        XCTAssertEqual(
            SupersetDriver().restDuration(state: state, context: ctx),
            90
        )
    }

    func testRestDurationZeroOnLastItemOfLastRound() {
        // Cursor on item 1 (last) of 2, round 3 of 3 → 0 (VM flips
        // to .complete; defensive fallback).
        let (ctx, _, state) = makeStandardSuperset(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 3)
        )
        XCTAssertEqual(
            SupersetDriver().restDuration(state: state, context: ctx),
            0
        )
    }

    func testRestDurationBodyweightItemsBehaveIdentically() {
        // Load on items does not change the rest branch.
        let (ctx, _, state) = makeSuperset(
            rounds: 3,
            restBetweenRoundsSec: 60,
            items: [
                (name: "Push-up", prescriptionJSON: #"{"reps":15}"#),
                (name: "Pull-up", prescriptionJSON: #"{"reps":10}"#),
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 1)
        )
        XCTAssertEqual(
            SupersetDriver().restDuration(state: state, context: ctx),
            60
        )
    }

    func testRestDurationZeroOnMalformedConfig() {
        // Missing `rest_between_rounds_sec` → parse failure → 0.
        let (ctx, _, state) = makeSuperset(
            rounds: 3,
            restBetweenRoundsSec: nil,
            items: [
                (name: "Bench", prescriptionJSON: #"{"reps":10,"load_kg":60}"#),
                (name: "Row", prescriptionJSON: #"{"reps":10,"load_kg":60}"#),
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 1)
        )
        XCTAssertEqual(
            SupersetDriver().restDuration(state: state, context: ctx),
            0
        )
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcome() {
        let (ctx, itemIDs, state) = makeStandardSuperset()
        let outcome = SupersetDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 10,
                loggedRir: 2
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }

    // MARK: - Swap override

    /// Regression: R2.10 widened the override parser + added unit; the
    /// reducer mirrors `reps` / `load_kg` / `weight_unit` overrides onto
    /// non-done SetPlan rows. Prior to this fix, SupersetDriver re-parsed
    /// `prescriptionJSON` in `activeContent`, so the exercise NAME updated
    /// after a swap but load/reps stayed stale. Post-fix: activeContent
    /// reads the live SetPlan row so the override wins.
    func testSupersetDriverRespectsSwapOverride() {
        let (ctx, itemIDs, baseState) = makeStandardSuperset()

        // Simulate a post-swap state: item 0 has a performedExerciseID,
        // overrides with load_kg=72.5 & reps=8, and the non-done SetPlan
        // rows have been mirrored (by the reducer at swap time) to carry
        // the override values. The driver should render those directly.
        var state = baseState
        let swappedExerciseID = UUID()
        state.items = state.items.map { log in
            guard log.itemID == itemIDs[0] else { return log }
            let mirrored = log.sets.map { set -> SetPlan in
                SetPlan(
                    setIndex: set.setIndex,
                    loadKg: 72.5,
                    unit: .kg,
                    reps: 8,
                    done: set.done,
                    adjust: set.adjust,
                    rir: set.rir
                )
            }
            return SessionState.ItemLog(
                itemID: log.itemID,
                autoregHeld: log.autoregHeld,
                sets: mirrored,
                performedExerciseID: swappedExerciseID,
                overrides: AlternativeOverrides(reps: 8, loadKg: 72.5, unit: .kg)
            )
        }

        // Advance cursor into round 2 (still item 0, setIndex=2).
        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2)

        let content = SupersetDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(
            content?.loadKg, 72.5,
            "post-swap SetPlan load wins over re-parsed prescriptionJSON"
        )
        XCTAssertEqual(content?.reps, 8, "post-swap SetPlan reps win")
        XCTAssertEqual(
            content?.loadDisplay, "72.5 kg",
            "unit override (.kg) is carried through to the display"
        )
    }
}
