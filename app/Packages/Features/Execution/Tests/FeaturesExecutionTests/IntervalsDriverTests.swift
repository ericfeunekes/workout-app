// IntervalsDriverTests.swift
//
// Unit coverage for `IntervalsDriver`:
//   - restDuration reads `rest_sec` directly for time-based configs.
//   - restDuration derives rest from `rest_distance_m / 1000 * pace` for
//     distance-based configs that author a pace.
//   - restDuration falls back to 0 when distance-based and pace is missing.
//   - restDuration falls back to 0 on malformed JSON and wrong timing mode.
//   - activeContent surfaces the distance/time target in `repsDisplay`,
//     the pace in `loadDisplay`, and `totalSets` = `interval_count`.
//   - activeContent returns nil when the cursor is out of range.
//   - onSetLogged returns an empty outcome regardless of reps / RIR
//     (no autoreg per spec).
//
// Canonical fixture: 10 × 400 m at 4:30 / km, with 200 m rest (matches
// `docs/prescription.md` § "10 × 400m at 5K pace"). Items author as `{}`
// per spec — cardio prescriptions carry no reps / load.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class IntervalsDriverTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let context: WorkoutContext
        let state: SessionState
        let itemIDs: [UUID]
    }

    private func makeFixture(
        configJSON: String,
        timingMode: TimingMode = .intervals,
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
            id: workoutID, userID: userID, name: "intervals",
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

    // Canonical shape — 10 × 400 m with 200 m rest at 4:30 / km.
    private func canonicalFixture() -> Fixture {
        makeFixture(
            configJSON: #"""
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":10,"target_pace_sec_per_km":270}
            """#
        )
    }

    // MARK: - restDuration

    func testRestDurationReadsRestSecForTimeBasedConfig() {
        // Time-based authoring: 30 s work / 30 s rest, 10 rounds.
        let f = makeFixture(
            configJSON: #"""
            {"work_sec":30,"rest_sec":30,"interval_count":10,"target_pace_sec_per_km":270}
            """#
        )
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 30)
    }

    func testRestDurationIsZeroOnFinalInterval() {
        // Cursor on the last interval (10 of 10) must surface rest=0
        // so `buildLogMutations` emits `.advanceFromRest` → the cursor
        // falls off the end of the block → route lands on `.complete`.
        // This is the R2.11 "no trailing rest after final interval" fix:
        // before the driver returned the authored rest_sec on every
        // interval, so the final log put the user on a rest screen that
        // counted down to a complete route anyway.
        let f = makeFixture(
            configJSON: #"""
            {"work_sec":30,"rest_sec":30,"interval_count":10,"target_pace_sec_per_km":270}
            """#,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 10)
        )
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationStillPositiveOnNonFinalInterval() {
        // Guard: the short-circuit fires only on the last interval —
        // every earlier interval still reads the authored rest.
        let f = makeFixture(
            configJSON: #"""
            {"work_sec":30,"rest_sec":30,"interval_count":10,"target_pace_sec_per_km":270}
            """#,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 9)
        )
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 30)
    }

    func testRestDurationDerivesFromDistanceAndPace() {
        // 200 m rest at 270 s / km → 200 / 1000 * 270 = 54 s.
        let f = canonicalFixture()
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 54)
    }

    func testRestDurationIsZeroWhenDistanceBasedAndPaceMissing() {
        // No pace authored — without a pace we cannot infer a rest time.
        // Return 0 so the VM's auto-advance collapses the rest; the user
        // taps "next lap" to start the rest-to-work transition in v1.
        let f = makeFixture(
            configJSON: #"""
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":10}
            """#
        )
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationIsZeroOnMalformedConfig() {
        let f = makeFixture(configJSON: "not json at all")
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationIsZeroWhenTimingModeIsWrong() {
        // Defensive: if the registry were misrouted, the typed config
        // will not discriminate as `.intervals` and restDuration falls
        // back to 0 rather than trying to coerce a different mode.
        let f = makeFixture(
            configJSON: #"""
            {"rest_between_sets_sec":90,"rest_between_exercises_sec":120}
            """#,
            timingMode: .straightSets
        )
        let driver = IntervalsDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    // MARK: - activeContent

    func testActiveContentRendersDistanceAndPace() {
        let f = canonicalFixture()
        let content = IntervalsDriver().activeContent(state: f.state, context: f.context)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.exerciseName, "Run")
        // Distance goes into repsDisplay for cardio modes — see driver
        // header for the repurposing convention.
        XCTAssertEqual(content?.repsDisplay, "400 m")
        // Pace (270 s/km → 4:30) goes into loadDisplay.
        XCTAssertEqual(content?.loadDisplay, "4:30 / km")
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 10)
        XCTAssertEqual(content?.reps, 0)
        XCTAssertNil(content?.loadKg)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentRendersTimeBasedWorkAndMissingPace() {
        // Time-based authoring, no pace: work renders as "30 s" and pace
        // degrades to "—".
        let f = makeFixture(
            configJSON: #"""
            {"work_sec":30,"rest_sec":30,"interval_count":8}
            """#
        )
        let content = IntervalsDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.repsDisplay, "30 s")
        XCTAssertEqual(content?.loadDisplay, "—")
        XCTAssertEqual(content?.totalSets, 8)
    }

    func testActiveContentTracksCursorSetIndexAsIntervalNumber() {
        // Cursor on interval 4 → setIndex flows through as the interval
        // counter (matches how AMRAP/EMOM surface round/interval).
        let f = makeFixture(
            configJSON: #"""
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":10,"target_pace_sec_per_km":270}
            """#,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 4)
        )
        let content = IntervalsDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.setIndex, 4)
        XCTAssertEqual(content?.totalSets, 10)
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let f = makeFixture(
            configJSON: #"""
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":10,"target_pace_sec_per_km":270}
            """#,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 5, setIndex: 1)
        )
        XCTAssertNil(IntervalsDriver().activeContent(state: f.state, context: f.context))
    }

    func testActiveContentFallsBackWhenConfigMalformed() {
        let f = makeFixture(configJSON: "{}")
        let content = IntervalsDriver().activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.repsDisplay, "—")
        XCTAssertEqual(content?.loadDisplay, "—")
        XCTAssertEqual(content?.totalSets, 0)
        // Exercise name still resolves — the failure mode is display-only.
        XCTAssertEqual(content?.exerciseName, "Run")
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcomeRegardlessOfInputs() {
        let f = canonicalFixture()
        let driver = IntervalsDriver()

        // Classic overshoot that would fire autoreg in straight_sets.
        let overshoot = driver.onSetLogged(
            state: f.state, context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0], setIndex: 1,
                loggedReps: 0, loggedRir: 5
            )
        )
        XCTAssertNil(overshoot.proposal)
        XCTAssertTrue(overshoot.mutations.isEmpty)

        // No RIR supplied — still an empty outcome.
        let noRir = driver.onSetLogged(
            state: f.state, context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0], setIndex: 5,
                loggedReps: 0, loggedRir: nil
            )
        )
        XCTAssertNil(noRir.proposal)
        XCTAssertTrue(noRir.mutations.isEmpty)
    }
}
