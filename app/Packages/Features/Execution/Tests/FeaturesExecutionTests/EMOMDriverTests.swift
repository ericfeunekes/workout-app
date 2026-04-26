// EMOMDriverTests.swift
//
// Unit coverage for `EMOMDriver`:
//   - restDuration reads `timing_config_json.interval_sec`
//   - restDuration defaults to 0 on missing / malformed config
//   - restDuration defaults to 0 when the block's timing_mode is wrong
//     (defensive — registry routes by mode, but parse result discriminates)
//   - activeContent resolves exercise name + reps + load for the item
//     the cursor points at
//   - activeContent returns nil when the cursor is out of range
//   - onSetLogged returns an empty outcome (no autoreg on EMOM)
//
// Built against a single-item and a multi-item EMOM block. The round-
// robin cursor ticking across intervals is VM work; the driver still
// derives the athlete-facing global interval ordinal from that cursor.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class EMOMDriverTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let context: WorkoutContext
        let state: SessionState
        let itemIDs: [UUID]
        let exerciseIDs: [UUID]
    }

    private func makeEmomFixture(
        configJSON: String,
        items: [(exerciseName: String, prescriptionJSON: String)],
        timingMode: TimingMode = .emom,
        cursor: SessionState.Cursor? = nil
    ) -> Fixture {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "emom",
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

        var workoutItems: [WorkoutItem] = []
        var exercises: [UUID: Exercise] = [:]
        var itemIDs: [UUID] = []
        var exerciseIDs: [UUID] = []
        for (idx, spec) in items.enumerated() {
            let exerciseID = UUID()
            let itemID = UUID()
            exerciseIDs.append(exerciseID)
            itemIDs.append(itemID)
            exercises[exerciseID] = Exercise(
                id: exerciseID, name: spec.exerciseName
            )
            workoutItems.append(WorkoutItem(
                id: itemID,
                blockID: blockID,
                position: idx,
                exerciseID: exerciseID,
                prescriptionJSON: spec.prescriptionJSON
            ))
        }

        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises
        )
        var state = SessionSeeder.seed(context: ctx)
        if let override = cursor {
            state = SessionState(
                workoutID: state.workoutID,
                route: state.route,
                cursor: override,
                items: state.items,
                restEndsAt: state.restEndsAt,
                note: state.note,
                structure: state.structure
            )
        }
        return Fixture(
            context: ctx,
            state: state,
            itemIDs: itemIDs,
            exerciseIDs: exerciseIDs
        )
    }

    // MARK: - restDuration

    func testRestDurationReturnsIntervalSec() {
        let f = makeEmomFixture(
            configJSON: #"{"interval_sec":60,"total_minutes":12}"#,
            items: [("KB Swing", #"{"reps":10,"load_kg":24}"#)]
        )
        let driver = EMOMDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 60)
    }

    func testRestDurationReturnsZeroOnMalformedConfig() {
        // Missing `interval_sec` → parse failure → 0.
        let f = makeEmomFixture(
            configJSON: "{}",
            items: [("KB Swing", #"{"reps":10,"load_kg":24}"#)]
        )
        let driver = EMOMDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationReturnsZeroOnNonJSONConfig() {
        let f = makeEmomFixture(
            configJSON: "not json at all",
            items: [("KB Swing", #"{"reps":10,"load_kg":24}"#)]
        )
        let driver = EMOMDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    func testRestDurationReturnsZeroWhenTimingModeIsWrong() {
        // Defensive: if the registry were misrouted (or the block carries
        // a non-emom mode), the typed config will not discriminate as
        // .emom and restDuration falls back to 0 rather than lying.
        let f = makeEmomFixture(
            configJSON: #"{"rest_between_sets_sec":90,"rest_between_exercises_sec":120}"#,
            items: [("Bench", #"{"sets":3,"reps":5,"load_kg":100}"#)],
            timingMode: .straightSets
        )
        let driver = EMOMDriver()
        XCTAssertEqual(driver.restDuration(state: f.state, context: f.context), 0)
    }

    // MARK: - activeContent

    func testActiveContentResolvesExerciseNameRepsAndLoad() {
        let f = makeEmomFixture(
            configJSON: #"{"interval_sec":60,"total_minutes":12}"#,
            items: [("KB Swing", #"{"reps":10,"load_kg":24}"#)]
        )
        let driver = EMOMDriver()
        let content = driver.activeContent(state: f.state, context: f.context)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.exerciseName, "KB Swing")
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.repsDisplay, "10")
        XCTAssertEqual(content?.loadKg, 24)
        XCTAssertEqual(content?.loadDisplay, "24 lb")
        // Cursor starts at setIndex 1 (interval 1). Total intervals =
        // 12 minutes * 60s / 60s = 12.
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 12)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentResolvesCursorPointedItemInMultiItemBlock() {
        // Two items — driver resolves whichever the cursor points at.
        // Cursor setIndex is the round; itemIndex is the station within
        // that round. Athlete-facing "interval N" is derived globally.
        let f = makeEmomFixture(
            configJSON: #"{"interval_sec":60,"total_minutes":10}"#,
            items: [
                ("Burpee", #"{"reps":5}"#),
                ("Power Clean", #"{"reps":3,"load_kg":60}"#)
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 1)
        )
        let driver = EMOMDriver()
        let content = driver.activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.exerciseName, "Power Clean")
        XCTAssertEqual(content?.reps, 3)
        XCTAssertEqual(content?.loadKg, 60)
        XCTAssertEqual(content?.setIndex, 2)
        XCTAssertEqual(content?.totalSets, 10)
    }

    func testActiveContentGlobalOrdinalUsesRoundAndItemInMultiItemBlock() {
        let f = makeEmomFixture(
            configJSON: #"{"interval_sec":60,"total_minutes":10}"#,
            items: [
                ("Burpee", #"{"reps":5}"#),
                ("Power Clean", #"{"reps":3,"load_kg":60}"#)
            ],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 2)
        )
        let driver = EMOMDriver()
        let content = driver.activeContent(state: f.state, context: f.context)
        XCTAssertEqual(content?.exerciseName, "Power Clean")
        XCTAssertEqual(content?.setIndex, 4,
            "round 2 station 2 is global interval 4, not round number 2")
        XCTAssertEqual(content?.totalSets, 10)
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let f = makeEmomFixture(
            configJSON: #"{"interval_sec":60,"total_minutes":12}"#,
            items: [("KB Swing", #"{"reps":10,"load_kg":24}"#)],
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 5, setIndex: 1)
        )
        let driver = EMOMDriver()
        XCTAssertNil(driver.activeContent(state: f.state, context: f.context))
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcomeRegardlessOfRirOrReps() {
        let f = makeEmomFixture(
            configJSON: #"{"interval_sec":60,"total_minutes":12}"#,
            items: [("KB Swing", #"{"reps":10,"load_kg":24}"#)]
        )
        let driver = EMOMDriver()

        // RIR 0 (failure) — straight_sets would propose here; EMOM never does.
        let failure = driver.onSetLogged(
            state: f.state,
            context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0],
                setIndex: 1,
                loggedReps: 10,
                loggedRir: 0
            )
        )
        XCTAssertNil(failure.proposal)
        XCTAssertTrue(failure.mutations.isEmpty)

        // Big overshoot (RIR 5) — straight_sets would propose here too.
        let overshoot = driver.onSetLogged(
            state: f.state,
            context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0],
                setIndex: 1,
                loggedReps: 10,
                loggedRir: 5
            )
        )
        XCTAssertNil(overshoot.proposal)
        XCTAssertTrue(overshoot.mutations.isEmpty)

        // Undershoot on reps — also a no-op for EMOM.
        let undershoot = driver.onSetLogged(
            state: f.state,
            context: f.context,
            event: SetLogEvent(
                itemID: f.itemIDs[0],
                setIndex: 1,
                loggedReps: 3,
                loggedRir: nil
            )
        )
        XCTAssertNil(undershoot.proposal)
        XCTAssertTrue(undershoot.mutations.isEmpty)
    }
}
