// CircuitDriverTests.swift
//
// Unit coverage for `CircuitDriver`:
//   - activeContent resolves exercise name + reps + load at the cursor
//   - activeContent returns nil when the cursor is out of range
//   - restDuration returns between-exercises rest within a round
//   - restDuration returns between-rounds rest after the last item of a
//     non-last round
//   - restDuration on the last item of the last round — defensive
//     fallback (VM flips to .complete; the driver returns rest-between-
//     exercises rather than lying about a phantom round)
//   - restDuration on weighted vs bodyweight stations (same branch logic,
//     independent of load)
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
final class CircuitDriverTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a circuit block of N stations with the given
    /// `rest_between_exercises_sec` / `rest_between_rounds_sec` /
    /// `rounds`. Seeded SessionState's cursor starts at (0, 0, 1) —
    /// override via `cursor` where needed.
    private func makeCircuit(
        rounds: Int? = 3,
        restBetweenExercisesSec: Double? = 0,
        restBetweenRoundsSec: Double? = 120,
        items: [(name: String, prescriptionJSON: String)],
        cursor: SessionState.Cursor? = nil
    ) -> (WorkoutContext, [UUID], SessionState) {
        let blockID = UUID()
        let (workoutItems, exercises, itemIDs) = buildItems(blockID: blockID, items: items)
        let configJSON = buildConfigJSON(rbe: restBetweenExercisesSec, rbr: restBetweenRoundsSec)
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

    private func buildConfigJSON(rbe: Double?, rbr: Double?) -> String {
        switch (rbe, rbr) {
        case let (rbe?, rbr?):
            return #"{"rest_between_exercises_sec":\#(rbe),"rest_between_rounds_sec":\#(rbr)}"#
        case (nil, nil):
            return "{}"
        case let (rbe?, nil):
            return #"{"rest_between_exercises_sec":\#(rbe)}"#
        case let (nil, rbr?):
            return #"{"rest_between_rounds_sec":\#(rbr)}"#
        }
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
            id: workoutID, userID: userID, name: "circuit",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .circuit,
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

    /// Three-station circuit with the spec's canonical config:
    /// `rest_between_exercises_sec: 0, rest_between_rounds_sec: 120`,
    /// 3 rounds, A→B→C. Cursor at (0, 0, 1) by default.
    private func makeStandardCircuit(
        cursor: SessionState.Cursor? = nil
    ) -> (WorkoutContext, [UUID], SessionState) {
        makeCircuit(
            rounds: 3,
            restBetweenExercisesSec: 0,
            restBetweenRoundsSec: 120,
            items: [
                (name: "Goblet Squat", prescriptionJSON: #"{"reps":12,"load_kg":20}"#),
                (name: "Push-up", prescriptionJSON: #"{"reps":15}"#),
                (name: "KB Swing", prescriptionJSON: #"{"reps":20,"load_kg":24}"#),
            ],
            cursor: cursor
        )
    }

    // MARK: - activeContent

    func testActiveContentResolvesFirstStation() {
        let (ctx, _, state) = makeStandardCircuit()
        let content = CircuitDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Goblet Squat")
        XCTAssertEqual(content?.reps, 12)
        XCTAssertEqual(content?.repsDisplay, "12")
        XCTAssertEqual(content?.loadKg, 20)
        XCTAssertEqual(content?.loadDisplay, "20 kg")
        // Round 1 of 3.
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 3)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentResolvesBodyweightStation() {
        let (ctx, _, state) = makeStandardCircuit(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 2)
        )
        let content = CircuitDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Push-up")
        XCTAssertEqual(content?.reps, 15)
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg)
        XCTAssertEqual(content?.setIndex, 2)
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let (ctx, _, state) = makeStandardCircuit(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 99, setIndex: 1)
        )
        XCTAssertNil(CircuitDriver().activeContent(state: state, context: ctx))
    }

    // MARK: - restDuration

    func testRestDurationBetweenExercisesWithinRound() {
        // Cursor on item 0 of 3, round 1 of 3 → mid-round → RBE (=0).
        let (ctx, _, state) = makeCircuit(
            rounds: 3,
            restBetweenExercisesSec: 15,
            restBetweenRoundsSec: 120,
            items: [
                (name: "A", prescriptionJSON: #"{"reps":10}"#),
                (name: "B", prescriptionJSON: #"{"reps":10}"#),
                (name: "C", prescriptionJSON: #"{"reps":10}"#),
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1)
        )
        XCTAssertEqual(
            CircuitDriver().restDuration(state: state, context: ctx),
            15
        )
    }

    func testRestDurationBetweenRoundsAfterLastItem() {
        // Last item of round 1 (non-last round) → RBR (=120).
        let (ctx, _, state) = makeCircuit(
            rounds: 3,
            restBetweenExercisesSec: 15,
            restBetweenRoundsSec: 120,
            items: [
                (name: "A", prescriptionJSON: #"{"reps":10}"#),
                (name: "B", prescriptionJSON: #"{"reps":10}"#),
                (name: "C", prescriptionJSON: #"{"reps":10}"#),
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 2, setIndex: 1)
        )
        XCTAssertEqual(
            CircuitDriver().restDuration(state: state, context: ctx),
            120
        )
    }

    func testRestDurationLastItemOfLastRoundFallsBackToRBE() {
        // Last item, last round — the VM flips to .complete, so this
        // rest never actually shows. Defensive branch returns RBE
        // rather than lying about another round.
        let (ctx, _, state) = makeCircuit(
            rounds: 3,
            restBetweenExercisesSec: 15,
            restBetweenRoundsSec: 120,
            items: [
                (name: "A", prescriptionJSON: #"{"reps":10}"#),
                (name: "B", prescriptionJSON: #"{"reps":10}"#),
                (name: "C", prescriptionJSON: #"{"reps":10}"#),
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 2, setIndex: 3)
        )
        XCTAssertEqual(
            CircuitDriver().restDuration(state: state, context: ctx),
            15
        )
    }

    func testRestDurationMidRoundOnWeightedStation() {
        // Load on the station does not change the rest branch — guard
        // against future "apply weighted-only rest" drift.
        let (ctx, _, state) = makeStandardCircuit(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1)
        )
        XCTAssertEqual(
            CircuitDriver().restDuration(state: state, context: ctx),
            0  // RBE=0 in the canonical spec example
        )
    }

    func testRestDurationZeroOnMalformedConfig() {
        // Missing both required keys → parse failure → 0.
        let (ctx, _, state) = makeCircuit(
            rounds: 3,
            restBetweenExercisesSec: nil,
            restBetweenRoundsSec: nil,
            items: [(name: "A", prescriptionJSON: #"{"reps":10}"#)]
        )
        XCTAssertEqual(
            CircuitDriver().restDuration(state: state, context: ctx),
            0
        )
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcome() {
        let (ctx, itemIDs, state) = makeStandardCircuit()
        let outcome = CircuitDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 12,
                loggedRir: 2
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }
}
