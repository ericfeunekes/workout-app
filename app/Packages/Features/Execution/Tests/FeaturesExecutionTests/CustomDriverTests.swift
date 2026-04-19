// CustomDriverTests.swift
//
// Unit coverage for `CustomDriver`:
//   - activeContent resolves exercise name + reps + load from the item's
//     sets-shaped prescription
//   - activeContent handles bodyweight items (no `load_kg`)
//   - activeContent returns nil when the cursor is out of range
//   - activeContent falls back gracefully on empty / malformed
//     prescriptions
//   - restDuration always returns 0 (custom does not enforce rest)
//   - restDuration returns 0 on malformed config (never read, always 0)
//   - onSetLogged returns an empty outcome

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class CustomDriverTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a custom block. `timingConfigJSON` defaults to a plausible
    /// segments array per docs/prescription.md § "custom"; tests that
    /// want to prove malformed-config resilience override it.
    private func makeCustom(
        timingConfigJSON: String = #"{"segments":[{"type":"work","duration_sec":60}]}"#,
        items: [(name: String, prescriptionJSON: String)],
        cursor: SessionState.Cursor? = nil
    ) -> (WorkoutContext, [UUID], SessionState) {
        let blockID = UUID()
        let (workoutItems, exercises, itemIDs) = buildItems(blockID: blockID, items: items)
        let ctx = buildContext(
            blockID: blockID,
            configJSON: timingConfigJSON,
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
        workoutItems: [WorkoutItem],
        exercises: [UUID: Exercise]
    ) -> WorkoutContext {
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "custom",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .custom,
            timingConfigJSON: configJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises
        )
    }

    /// Sets-shaped custom item — 3×5 @ 80 kg.
    private func makeStandardCustom(
        cursor: SessionState.Cursor? = nil
    ) -> (WorkoutContext, [UUID], SessionState) {
        makeCustom(
            items: [
                (name: "Back Squat", prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":80}"#),
            ],
            cursor: cursor
        )
    }

    // MARK: - activeContent

    func testActiveContentResolvesExerciseNameRepsAndLoad() {
        let (ctx, _, state) = makeStandardCustom()
        let content = CustomDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Back Squat")
        XCTAssertEqual(content?.reps, 5)
        XCTAssertEqual(content?.repsDisplay, "5")
        XCTAssertEqual(content?.loadKg, 80)
        XCTAssertEqual(content?.loadDisplay, "80 lb")
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 3)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentSurfacesCursorSetIndex() {
        let (ctx, _, state) = makeStandardCustom(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2)
        )
        let content = CustomDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.setIndex, 2)
        XCTAssertEqual(content?.totalSets, 3)
    }

    func testActiveContentHandlesBodyweightItem() {
        let (ctx, _, state) = makeCustom(
            items: [
                (name: "Plank", prescriptionJSON: #"{"sets":2,"reps":1}"#),
            ]
        )
        let content = CustomDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.exerciseName, "Plank")
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg)
        XCTAssertEqual(content?.totalSets, 2)
    }

    func testActiveContentHandlesEmptyPrescriptionGracefully() {
        // `{}` parses as `.empty` — driver falls back to itemLog.sets.count
        // (the seeder produces zero rows for `.empty`, so totalSets ≥ 1
        // via max). Don't crash.
        let (ctx, _, state) = makeCustom(
            items: [
                (name: "Threshold Run", prescriptionJSON: "{}"),
            ]
        )
        let content = CustomDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.exerciseName, "Threshold Run")
        XCTAssertEqual(content?.reps, 0)
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertGreaterThanOrEqual(content?.totalSets ?? 0, 1)
    }

    func testCustomDriverZeroRowItemRendersNoActivity() {
        // If an ItemLog has no SetPlan rows (defensive — e.g. legacy
        // persisted state predating the manual-placeholder seeder
        // fix), the driver must NOT fabricate a "1 of 1" display. A
        // logSet dispatch against a fabricated index would vanish into
        // the reducer (no matching SetPlan row).
        let (ctx, _, baseState) = makeStandardCustom()
        var state = baseState
        // Manually strip the SetPlan rows to simulate an empty ItemLog.
        state.items = state.items.map { item in
            SessionState.ItemLog(
                itemID: item.itemID,
                autoregHeld: item.autoregHeld,
                sets: [],
                performedExerciseID: item.performedExerciseID,
                overrides: item.overrides
            )
        }

        XCTAssertNil(CustomDriver().activeContent(state: state, context: ctx))
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let (ctx, _, state) = makeStandardCustom(
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 99, setIndex: 1)
        )
        XCTAssertNil(CustomDriver().activeContent(state: state, context: ctx))
    }

    // MARK: - restDuration

    func testRestDurationIsZero() {
        let (ctx, _, state) = makeStandardCustom()
        XCTAssertEqual(
            CustomDriver().restDuration(state: state, context: ctx),
            0
        )
    }

    func testRestDurationIsZeroOnMalformedConfig() {
        // CustomDriver never reads timingConfigJSON — malformed must
        // still yield 0.
        let (ctx, _, state) = makeCustom(
            timingConfigJSON: "not json at all",
            items: [(name: "Back Squat", prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":80}"#)]
        )
        XCTAssertEqual(
            CustomDriver().restDuration(state: state, context: ctx),
            0
        )
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcome() {
        let (ctx, itemIDs, state) = makeStandardCustom()
        let outcome = CustomDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 5,
                loggedRir: 2
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }

    // MARK: - Swap override

    /// Regression: prior to this fix, CustomDriver re-parsed
    /// `prescriptionJSON` in `activeContent`, so swap overrides on load /
    /// reps / unit were ignored — the exercise NAME updated but load/reps
    /// stayed stale. Post-fix: the driver reads the live SetPlan row at
    /// the cursor (which the reducer mirrors override values onto at
    /// swap time).
    func testCustomDriverRespectsSwapOverride() {
        let (ctx, itemIDs, baseState) = makeStandardCustom()

        // Simulate post-swap: item 0 (Back Squat, originally 3×5 @ 80 kg
        // rendered in lb via R2.10 default) now has overrides mirrored
        // onto its SetPlan rows at 70 kg / 6 reps.
        var state = baseState
        let swappedExerciseID = UUID()
        state.items = state.items.map { log in
            guard log.itemID == itemIDs[0] else { return log }
            let mirrored = log.sets.map { set -> SetPlan in
                SetPlan(
                    setIndex: set.setIndex,
                    loadKg: 70,
                    unit: .kg,
                    reps: 6,
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
                overrides: AlternativeOverrides(reps: 6, loadKg: 70, unit: .kg)
            )
        }

        // Advance cursor into set 2.
        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2)

        let content = CustomDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadKg, 70, "post-swap SetPlan load wins")
        XCTAssertEqual(content?.reps, 6, "post-swap SetPlan reps win")
        XCTAssertEqual(content?.loadDisplay, "70 kg", "unit override carries through")
    }
}
