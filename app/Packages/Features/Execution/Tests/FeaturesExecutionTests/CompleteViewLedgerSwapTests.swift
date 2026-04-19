// CompleteViewLedgerSwapTests.swift
//
// qa-021 — S12 of exercise-swap.md: the Complete screen's per-item
// ledger must render under the PERFORMED exercise name when the user
// mid-workout swaps, not under the originally planned exercise. The
// title comes from `log.performedExerciseID` when non-nil and falls
// back to the WorkoutItem's planned `exerciseID` otherwise.
//
// The test targets `CompleteView.ledgerEntries(context:items:)` — the
// pure-swift entry point behind `allLedgerEntries()` — so we can
// exercise the title + summary shape without standing up a SwiftUI view.

import XCTest
import CoreAutoreg
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class CompleteViewLedgerSwapTests: XCTestCase {

    func testCompleteViewLedgerShowsPerformedExerciseNameAfterSwap() {
        // Two exercises in the catalog — the planned Bench Press and
        // the swap target Dumbbell Bench Press. Both must sit in
        // `context.exercises` since AppBootstrap seeds alternatives'
        // target ids into the dictionary at pull time.
        let plannedID = UUID()
        let performedID = UUID()
        let itemID = UUID()
        let exercises: [UUID: Exercise] = [
            plannedID: Exercise(id: plannedID, name: "Bench Press"),
            performedID: Exercise(id: performedID, name: "Dumbbell Bench Press"),
        ]
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: plannedID,
            exercises: exercises
        )

        // One ItemLog with three done sets, swapped mid-workout to the
        // Dumbbell Bench alternative. The ledger must render the alt
        // name (Dumbbell Bench Press), not the planned name (Bench
        // Press), per exercise-swap.md S12.
        let sets: [SetPlan] = [
            makeSet(index: 1, load: 70, unit: .lb, reps: 10, rir: 2),
            makeSet(index: 2, load: 70, unit: .lb, reps: 10, rir: 2),
            makeSet(index: 3, load: 70, unit: .lb, reps: 10, rir: 2),
        ]
        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: sets,
            performedExerciseID: performedID
        )

        let entries = CompleteView.ledgerEntries(
            context: context,
            items: [itemLog]
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entries.first?.name,
            "Dumbbell Bench Press",
            "Ledger title must follow log.performedExerciseID when non-nil"
        )
        XCTAssertEqual(entries.first?.summary, "3×10 @ 70 lb · RIR 2")
    }

    func testCompleteViewLedgerFallsBackToPlannedNameWhenNoSwap() {
        // Regression guard: when the user DIDN'T swap, the ledger
        // still renders the planned exercise name. Without this the
        // swap fix could easily regress the non-swap default.
        let plannedID = UUID()
        let itemID = UUID()
        let exercises: [UUID: Exercise] = [
            plannedID: Exercise(id: plannedID, name: "Bench Press"),
        ]
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: plannedID,
            exercises: exercises
        )

        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: [makeSet(index: 1, load: 100, unit: .kg, reps: 5, rir: 2)],
            performedExerciseID: nil
        )

        let entries = CompleteView.ledgerEntries(
            context: context,
            items: [itemLog]
        )

        XCTAssertEqual(entries.first?.name, "Bench Press")
    }

    // MARK: - Fixtures

    private func makeSet(
        index: Int,
        load: Double?,
        unit: WeightUnit,
        reps: Int,
        rir: Int?
    ) -> SetPlan {
        SetPlan(
            setIndex: index,
            loadKg: load,
            unit: unit,
            reps: reps,
            done: true,
            adjust: nil,
            rir: rir
        )
    }

    private func makeContext(
        itemID: UUID,
        plannedExerciseID: UUID,
        exercises: [UUID: Exercise]
    ) -> WorkoutContext {
        let now = Date()
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Swap Ledger Test",
            scheduledDate: now, status: .completed, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: now, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: plannedExerciseID, prescriptionJSON: "{}"
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: exercises
        )
    }
}
