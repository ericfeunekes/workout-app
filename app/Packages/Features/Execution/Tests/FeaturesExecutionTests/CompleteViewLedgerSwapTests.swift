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

    func testBlockResultsSummarizeAccumulatedRepsAgainstTarget() {
        let exerciseID = UUID()
        let itemID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Push-Up")],
            timingMode: .accumulate,
            timingConfigJSON: #"{"target_reps":100}"#,
            blockName: "Push-up volume"
        )
        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: [
                makeSet(index: 1, load: nil, unit: .lb, reps: 25, rir: nil),
                makeSet(index: 2, load: nil, unit: .lb, reps: 25, rir: nil),
                makeSet(index: 3, load: nil, unit: .lb, reps: 25, rir: nil),
                makeSet(index: 4, load: nil, unit: .lb, reps: 25, rir: nil),
            ]
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [itemLog],
            note: ""
        )

        XCTAssertEqual(entries.first?.title, "Push-up volume")
        XCTAssertEqual(entries.first?.subtitle, "accumulate")
        XCTAssertEqual(entries.first?.summary, "100 / 100 reps")
    }

    func testBlockResultsPreferAMRAPScoreNote() {
        let exerciseID = UUID()
        let itemID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Thruster")],
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":600}"#,
            blockName: "Ten minute AMRAP"
        )
        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: [makeSet(index: 1, load: 40, unit: .kg, reps: 10, rir: nil)]
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [itemLog],
            note: "AMRAP result: 3 rounds + 4 reps"
        )

        XCTAssertEqual(entries.first?.summary, "AMRAP result: 3 rounds + 4 reps")
    }

    func testBlockResultsAMRAPFallbackCountsLoggedStationsWithoutSentinelTotal() {
        let exerciseID = UUID()
        let itemID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Burpee")],
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":600}"#,
            blockName: "Ten minute AMRAP"
        )
        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: [
                makeSet(index: 1, load: nil, unit: .kg, reps: 10, rir: nil),
                makeSet(index: 2, load: nil, unit: .kg, reps: 10, rir: nil, done: false),
            ]
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [itemLog],
            note: ""
        )

        XCTAssertEqual(entries.first?.summary, "1 stations logged")
        XCTAssertFalse(
            entries.first?.summary.contains("2") ?? true,
            "AMRAP fallback should not render a denominator when the metcon note is absent"
        )
    }

    func testBlockResultsDoNotRenderEMOMSentinelRowsAsCompletionTotal() {
        let exerciseID = UUID()
        let itemID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Deadlift")],
            timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":60,"total_minutes":12}"#,
            blockName: "Strength Density EMOM"
        )
        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: (1...300).map { index in
                makeSet(index: index, load: 140, unit: .kg, reps: 3, rir: nil, done: false)
            }
        )

        let entries = CompleteView.blockResultEntries(context: context, items: [itemLog], note: "")

        XCTAssertEqual(entries.first?.summary, "0 sets logged")
        XCTAssertFalse(
            entries.first?.summary.contains("300") ?? true,
            "EMOM completion summary must not render internal sentinel row counts"
        )
    }

    func testForTimeFallbackDoesNotExposeRowsLoggedCopy() {
        let exerciseID = UUID()
        let itemID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Thruster")],
            timingMode: .forTime,
            timingConfigJSON: #"{"time_cap_sec":600}"#,
            blockName: "For Time"
        )
        let itemLog = SessionState.ItemLog(
            itemID: itemID,
            sets: [makeSet(index: 1, load: 40, unit: .kg, reps: 10, rir: nil)]
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [itemLog],
            note: ""
        )

        XCTAssertEqual(entries.first?.summary, "1 result logged")
        XCTAssertFalse(entries.first?.summary.contains("rows logged") ?? true)
    }

    func testBlockResultsPreferPrimitiveAggregateSetResults() {
        let exerciseID = UUID()
        let itemID = UUID()
        let blockID = UUID()
        let setID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")],
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":1200}"#,
            blockName: "Mixed AMRAP",
            blockID: blockID,
            primitiveExecutionPlan: ExecutionPlan(
                workoutID: UUID(),
                blocks: [
                    ExecutionBlock(
                        blockID: blockID,
                        blockRepeat: 1,
                        workTargets: [],
                        sets: []
                    )
                ]
            )
        )
        let result = PrimitiveSetLog(
            id: UUID(),
            role: .setResult,
            setID: setID,
            blockID: blockID,
            setIndex: 0,
            reps: 12,
            durationSec: 1_200,
            distanceM: 1_000,
            rounds: 4,
            completedAt: Date()
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [],
            note: "AMRAP result: stale legacy note",
            primitiveSetLogs: [result]
        )

        XCTAssertEqual(entries.first?.summary, "4 rounds + 12 reps + 20:00 + 1.0 km")
    }

    func testBlockResultsFallBackToLegacySummaryWhenPrimitiveHasNoAggregateRows() {
        let exerciseID = UUID()
        let itemID = UUID()
        let blockID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")],
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":1200}"#,
            blockName: "Mixed AMRAP",
            blockID: blockID,
            primitiveExecutionPlan: ExecutionPlan(
                workoutID: UUID(),
                blocks: [
                    ExecutionBlock(
                        blockID: blockID,
                        blockRepeat: 1,
                        workTargets: [],
                        sets: []
                    )
                ]
            )
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [],
            note: "AMRAP result: stale legacy note",
            primitiveSetLogs: []
        )

        XCTAssertEqual(entries.first?.summary, "AMRAP result: stale legacy note")
    }

    func testBlockResultsSummarizePrimitiveSlotRowsWhenNoAggregateRowsExist() {
        let exerciseID = UUID()
        let itemID = UUID()
        let blockID = UUID()
        let context = makeContext(
            itemID: itemID,
            plannedExerciseID: exerciseID,
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Carry")],
            timingMode: .straightSets,
            blockName: "Carry work",
            blockID: blockID,
            primitiveExecutionPlan: ExecutionPlan(
                workoutID: UUID(),
                blocks: [
                    ExecutionBlock(
                        blockID: blockID,
                        blockRepeat: 1,
                        workTargets: [],
                        sets: []
                    )
                ]
            )
        )
        let slot = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            blockID: blockID,
            setIndex: 0,
            reps: 20,
            weight: 53,
            weightUnit: .lb,
            distanceM: 50,
            completedAt: Date()
        )

        let entries = CompleteView.blockResultEntries(
            context: context,
            items: [],
            note: "",
            primitiveSetLogs: [slot]
        )

        XCTAssertEqual(entries.first?.summary, "20 reps + 50 m + 53 lb")
    }

    // MARK: - Fixtures

    private func makeSet(
        index: Int,
        load: Double?,
        unit: WeightUnit,
        reps: Int,
        rir: Int?,
        done: Bool = true
    ) -> SetPlan {
        SetPlan(
            setIndex: index,
            loadKg: load,
            unit: unit,
            reps: reps,
            done: done,
            adjust: nil,
            rir: rir
        )
    }

    private func makeContext(
        itemID: UUID,
        plannedExerciseID: UUID,
        exercises: [UUID: Exercise],
        timingMode: TimingMode = .straightSets,
        timingConfigJSON: String = "{}",
        blockName: String? = nil,
        blockID requestedBlockID: UUID? = nil,
        primitiveExecutionPlan: ExecutionPlan? = nil
    ) -> WorkoutContext {
        let now = Date()
        let userID = UUID()
        let workoutID = UUID()
        let blockID = requestedBlockID ?? UUID()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Swap Ledger Test",
            scheduledDate: now, status: .completed, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: now, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: blockName, timingMode: timingMode,
            timingConfigJSON: timingConfigJSON, rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: plannedExerciseID, prescriptionJSON: "{}"
        )
        return WorkoutContext(
            workout: workout,
            primitiveExecutionPlan: primitiveExecutionPlan,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: exercises
        )
    }
}
