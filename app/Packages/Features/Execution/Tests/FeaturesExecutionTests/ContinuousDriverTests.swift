// ContinuousDriverTests.swift
//
// Unit coverage for `ContinuousDriver`:
//   - restDuration always returns 0 — continuous effort has no rest.
//     Verified across well-formed, malformed, and wrong-mode configs.
//   - activeContent surfaces `target_duration_sec` in `repsDisplay` when
//     authored; falls through to `target_distance_m`; "—" otherwise.
//   - activeContent surfaces `target_pace_sec_per_km` in `loadDisplay`
//     when authored; falls through to `target_hr_zone` as "ZN"; "—"
//     otherwise.
//   - activeContent pins `setIndex = 1`, `totalSets = 1` — there are no
//     discrete sets in a continuous effort.
//   - activeContent returns nil when the cursor is out of range.
//   - onSetLogged returns an empty outcome regardless of inputs (no
//     autoreg per spec).
//
// Canonical fixtures: 30-min Z2 run, 5K tempo, and a mixed pace+duration
// authoring. All items author as `{}` — cardio prescriptions carry no
// reps / load.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ContinuousDriverTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let context: WorkoutContext
        let state: SessionState
        let itemIDs: [UUID]
    }

    private func makeFixture(
        configJSON: String,
        timingMode: TimingMode = .continuous,
        itemPrescriptionJSON: String = "{}",
        exerciseName: String = "Run",
        cursor: SessionState.Cursor? = nil
    ) -> Fixture {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "continuous",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: timingMode,
            timingConfigJSON: configJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: itemPrescriptionJSON
        )
        let context = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: exerciseName)],
            lastPerformed: [:]
        )
        let seed = SessionSeeder.seed(context: context)
        let finalCursor = cursor ?? SessionState.Cursor(
            blockIndex: 0, itemIndex: 0, setIndex: 1
        )
        let state = SessionState(
            workoutID: seed.workoutID,
            route: .active,
            cursor: finalCursor,
            items: seed.items,
            restEndsAt: nil,
            note: "",
            structure: seed.structure
        )
        return Fixture(context: context, state: state, itemIDs: [itemID])
    }

    // MARK: - restDuration

    func testRestDurationIsZeroForWellFormedConfig() {
        // 30-min Z2 run.
        let f = makeFixture(
            configJSON: #"""
            {"target_duration_sec":1800,"target_pace_sec_per_km":360,"target_hr_zone":2}
            """#
        )
        XCTAssertEqual(ContinuousDriver().restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationIsZeroForMalformedConfig() {
        let f = makeFixture(configJSON: "not json at all")
        XCTAssertEqual(ContinuousDriver().restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationIsZeroForWrongMode() {
        // Continuous is unbroken effort — even if the block were
        // misrouted with a different mode's config, rest stays 0.
        let f = makeFixture(
            configJSON: #"""
            {"rest_between_sets_sec":120,"rest_between_exercises_sec":180}
            """#,
            timingMode: .straightSets
        )
        XCTAssertEqual(ContinuousDriver().restDuration(state: f.state, context: f.context), 0)
    }

    // MARK: - activeContent

    func testActiveContentRendersDurationAndPace() {
        // 30-min Z2 run at 6:00 / km.
        let f = makeFixture(
            configJSON: #"""
            {"target_duration_sec":1800,"target_pace_sec_per_km":360,"target_hr_zone":2}
            """#
        )
        let content = ContinuousDriver().activeContent(state: f.state, context: f.context)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.exerciseName, "Run")
        // Duration preferred as primary target.
        XCTAssertEqual(content?.repsDisplay, "30 min")
        // Pace preferred as secondary (360 s/km → 6:00).
        XCTAssertEqual(content?.loadDisplay, "6:00 / km")
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 1)
        XCTAssertEqual(content?.reps, 0)
        XCTAssertNil(content?.loadKg)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentFallsThroughToDistanceAndZone() {
        // 5K tempo with zone only — no pace, no duration.
        let f = makeFixture(
            configJSON: #"""
            {"target_distance_m":5000,"target_hr_zone":4}
            """#
        )
        let content = ContinuousDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.repsDisplay, "5 km")
        XCTAssertEqual(content?.loadDisplay, "Z4")
    }

    func testActiveContentRendersPlaceholdersWhenAllTargetsMissing() {
        // `{}` is a legal (if unhelpful) continuous config — all targets
        // optional. Both display fields degrade to the em-dash placeholder.
        let f = makeFixture(configJSON: "{}")
        let content = ContinuousDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.repsDisplay, "—")
        XCTAssertEqual(content?.loadDisplay, "—")
        XCTAssertEqual(content?.exerciseName, "Run")
    }

    func testActiveContentRendersPlaceholdersOnMalformedConfig() {
        let f = makeFixture(configJSON: "not json")
        let content = ContinuousDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.repsDisplay, "—")
        XCTAssertEqual(content?.loadDisplay, "—")
    }

    func testActiveContentPinsSetIndexAndTotalSetsEvenWithDifferentCursor() {
        // The reducer/VM may at some point push the cursor past (0, 0, 1)
        // — continuous still declares setIndex=1, totalSets=1 since there
        // is only ever one continuous effort.
        let f = makeFixture(
            configJSON: #"{"target_duration_sec":1800}"#,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 3)
        )
        let content = ContinuousDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 1)
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let f = makeFixture(
            configJSON: #"{"target_duration_sec":1800}"#,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 5, setIndex: 1)
        )
        XCTAssertNil(ContinuousDriver().activeContent(state: f.state, context: f.context))
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcomeRegardlessOfInputs() {
        let f = makeFixture(
            configJSON: #"""
            {"target_duration_sec":1800,"target_pace_sec_per_km":360}
            """#
        )
        let driver = ContinuousDriver()

        let overshoot = driver.onSetLogged(
            state: f.state, context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0], setIndex: 1,
                loggedReps: 0, loggedRir: 5
            )
        )
        XCTAssertNil(overshoot.proposal)
        XCTAssertTrue(overshoot.mutations.isEmpty)

        let noRir = driver.onSetLogged(
            state: f.state, context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0], setIndex: 1,
                loggedReps: 0, loggedRir: nil
            )
        )
        XCTAssertNil(noRir.proposal)
        XCTAssertTrue(noRir.mutations.isEmpty)
    }
}
