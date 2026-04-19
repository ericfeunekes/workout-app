// AmrapTokenRenderTests.swift
//
// Regression coverage for `.amrapToken` rendering across the drivers that
// can surface one inside a set-major block (straight_sets / custom).
//
// R2.9 collapsed `.amrapToken` seeding with `.empty`, dropping the
// authored `load_kg` + unit + `target_rir`. A weighted AMRAP token
// (kettlebell snatch @ 24 kg, AMRAP) then rendered / logged as "0 kg"
// or "BW". Post-fix: the seeder preserves load/unit on the single
// open-entry row, and drivers render the authored load. Loadless AMRAP
// tokens (plain `{"reps":"amrap"}` — pull-ups to failure) still render
// as "BW" via the loadless discriminator.
//
// These tests pin:
//   - StraightSetsDriver renders an AMRAP-token item's authored load
//     ("24 kg") rather than 0 / BW.
//   - StraightSetsDriver renders a loadless AMRAP-token as "BW".
//   - CustomDriver does the same for both cases.

import XCTest
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class AmrapTokenRenderTests: XCTestCase {

    // MARK: - Fixtures

    private func buildContext(
        timingMode: TimingMode,
        timingConfigJSON: String,
        prescriptionJSON: String,
        exerciseName: String = "KB Snatch"
    ) -> (WorkoutContext, UUID) {
        let blockID = UUID()
        let workoutID = UUID()
        let userID = UUID()
        let itemID = UUID()
        let exerciseID = UUID()
        let now = Date()

        let item = WorkoutItem(
            id: itemID,
            blockID: blockID,
            position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
        let workout = Workout(
            id: workoutID, userID: userID, name: "amrap-token",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: exerciseName)]
        )
        return (ctx, itemID)
    }

    // MARK: - StraightSetsDriver

    func testStraightSetsRendersAmrapTokenWithLoad() {
        // Weighted AMRAP token (kettlebell snatch @ 24 kg, AMRAP). The
        // seeder preserves load + unit on the single open-entry row; the
        // driver must render "24 kg", not 0 / BW.
        let (ctx, _) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            prescriptionJSON: #"{"reps":"amrap","load_kg":24,"weight_unit":"kg"}"#
        )

        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = StraightSetsDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadKg, 24, "authored load surfaces through the driver")
        XCTAssertEqual(content?.loadDisplay, "24 kg")
        XCTAssertEqual(content?.reps, 0, "open-entry sentinel — numpad opens at 0")
    }

    func testStraightSetsRendersLoadlessAmrapTokenAsBW() {
        // `{"reps":"amrap"}` — pull-ups to failure. No authored load →
        // loadless → "BW".
        let (ctx, _) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            prescriptionJSON: #"{"reps":"amrap"}"#,
            exerciseName: "Pull-ups"
        )

        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = StraightSetsDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg, "loadless → nil so the numpad renders without a load row")
    }

    // MARK: - CustomDriver

    func testCustomDriverRendersAmrapTokenWithLoad() {
        let (ctx, _) = buildContext(
            timingMode: .custom,
            timingConfigJSON: #"{"segments":[{"type":"work","duration_sec":60}]}"#,
            prescriptionJSON: #"{"reps":"amrap","load_kg":24,"weight_unit":"kg"}"#
        )

        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = CustomDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadKg, 24)
        XCTAssertEqual(content?.loadDisplay, "24 kg")
        XCTAssertEqual(content?.reps, 0)
    }

    func testCustomDriverRendersLoadlessAmrapTokenAsBW() {
        let (ctx, _) = buildContext(
            timingMode: .custom,
            timingConfigJSON: #"{"segments":[{"type":"work","duration_sec":60}]}"#,
            prescriptionJSON: #"{"reps":"amrap"}"#,
            exerciseName: "Pull-ups"
        )

        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = CustomDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg)
    }

    // MARK: - Bodyweight SetPlan → BW display

    /// The loadless-end-to-end contract: a bodyweight prescription seeds
    /// `SetPlan.loadKg = nil`, the driver feeds nil into
    /// `formatLoad(weight: nil, ...)`, and the result is "BW" — not "0 lb".
    func testActiveContentRendersBWForNilLoadSetPlan() {
        let (ctx, _) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            prescriptionJSON: #"{"sets":3,"reps":8}"#,
            exerciseName: "Pull-ups"
        )

        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = StraightSetsDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg)
    }
}
