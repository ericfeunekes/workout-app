// WorkoutContextLastPerformedTests.swift
//
// Regression for qa-020 — the swap sheet's "LAST · …" row renders blank
// even when the server's pulled `last_performed` snapshot contained
// entries for the alternative exercise. The root cause was wiring up-
// stream of the Execution layer (Shell didn't thread the map through
// `buildWorkoutContext`); the WorkoutContext itself already exposes the
// per-exercise map.
//
// This test pins the Execution-side contract: once Shell (or any other
// caller) hands in a populated `lastPerformed` map, `WorkoutContext`
// surfaces it to consumers — in particular, the closure SwapSheet reads
// from (`context.lastPerformed[id]`).

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class WorkoutContextLastPerformedTests: XCTestCase {

    /// The SwapSheet's alternative-row builder reads
    /// `viewModel.context.lastPerformed[alt.exerciseID]` (see
    /// `ActiveView+Swap.swift`). This test confirms the map is carried
    /// through WorkoutContext's init + lookup surface without mutation.
    func testWorkoutContextCarriesLastPerformedForSwapSheet() {
        let workoutID = UUID()
        let blockID = UUID()
        let itemID = UUID()
        let benchID = UUID()
        let inclineID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: UUID(), name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#
        )
        let alternative = ExerciseAlternative(
            id: UUID(),
            workoutItemID: itemID,
            exerciseID: inclineID,
            reason: "shoulder bias",
            parameterOverridesJSON: nil
        )
        let exercises: [UUID: Exercise] = [
            benchID: Exercise(id: benchID, name: "Barbell Bench Press"),
            inclineID: Exercise(id: inclineID, name: "Incline DB Press"),
        ]
        let lastPerformed: [UUID: String] = [
            benchID: "4×5 @ 100 kg · RIR 2",
            inclineID: "3×8 @ 30 kg · RIR 1",
        ]

        let context = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: exercises,
            lastPerformed: lastPerformed,
            alternativesByItem: [itemID: [alternative]]
        )

        // The planned exercise's chip — surfaces on ActiveView's
        // "LAST TIME" chip (docs/features/today.md parity carried into
        // execution).
        XCTAssertEqual(
            context.lastPerformed[benchID],
            "4×5 @ 100 kg · RIR 2"
        )
        // The alternative's chip — SwapSheet's
        // `lastPerformed: { id in viewModel.context.lastPerformed[id] }`
        // resolves off this exact lookup.
        XCTAssertEqual(
            context.lastPerformed[inclineID],
            "3×8 @ 30 kg · RIR 1"
        )
        // Missing exercise id → nil so the chip hides.
        XCTAssertNil(context.lastPerformed[UUID()])
        // Alternatives lookup still works under the same init — proves
        // the new wiring didn't stomp the existing field.
        XCTAssertEqual(context.alternatives(for: itemID).count, 1)
        XCTAssertEqual(
            context.alternatives(for: itemID).first?.exerciseID,
            inclineID
        )
    }

    /// Empty map is the legacy default — SwapSheet's closure returns
    /// nil for every lookup and the "LAST · …" row is omitted rather
    /// than rendered blank. Confirms the pre-qa-020 shape still works.
    func testWorkoutContextDefaultsToEmptyLastPerformedMap() {
        let workoutID = UUID()
        let blockID = UUID()
        let now = Date()

        let context = WorkoutContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "X",
                scheduledDate: now, status: .planned, source: .claude,
                notes: nil, createdAt: now, updatedAt: now,
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [Block(
                id: blockID, workoutID: workoutID, parentBlockID: nil,
                position: 0, name: nil, timingMode: .straightSets,
                timingConfigJSON: "{}", rounds: nil,
                roundsRepSchemeJSON: nil, notes: nil
            )],
            itemsByBlock: [[]],
            exercises: [:]
            // lastPerformed + alternativesByItem default to empty.
        )
        XCTAssertTrue(context.lastPerformed.isEmpty)
        XCTAssertNil(context.lastPerformed[UUID()])
    }
}
