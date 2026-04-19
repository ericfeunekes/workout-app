// AMRAPDriverTests.swift
//
// Unit coverage for `AMRAPDriver`:
//   - restDuration always returns 0 (no between-sets rest; AMRAP is
//     continuous effort until time cap). Also verified for malformed
//     timing config — we never read it, so parse failure is irrelevant.
//   - activeContent resolves the current item's exercise name, reps, and
//     load from the parsed prescription; returns nil when the cursor is
//     out of range.
//   - onSetLogged always returns an empty DriverLogOutcome — AMRAP has
//     no autoreg (per docs/prescription.md § "amrap"). Verified with and
//     without RIR.
//
// Fixtures build an AMRAP block with three items (standard CrossFit
// round-robin shape): 10 pull-ups, 15 push-ups, 20 air-squats. Items
// author as `{"reps": N}` (bodyweight) or `{"reps": N, "load_kg": kg}`
// (weighted), which parse as `.straightSets` with `sets: nil`.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class AMRAPDriverTests: XCTestCase {

    // MARK: - Fixtures

    /// Build an AMRAP block with the given items. Exercise names are
    /// injected into the context so `activeContent` can resolve them.
    private func makeAMRAPContext(
        timeCapSec: Int = 720,
        items: [(name: String, prescriptionJSON: String)]
    ) -> (WorkoutContext, [UUID]) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let now = Date()

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

        let workout = Workout(
            id: workoutID, userID: userID, name: "amrap",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":\#(timeCapSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises
        )
        return (ctx, itemIDs)
    }

    /// Build a 3-item AMRAP state (pull-ups / push-ups / air-squats) with
    /// the cursor parked on block 0, item 0, set 1, route `.active`.
    private func makeStandardAMRAPState(
        timeCapSec: Int = 720
    ) -> (WorkoutContext, [UUID], SessionState) {
        let (ctx, itemIDs) = makeAMRAPContext(
            timeCapSec: timeCapSec,
            items: [
                (name: "Pull-ups", prescriptionJSON: #"{"reps":10}"#),
                (name: "Push-ups", prescriptionJSON: #"{"reps":15}"#),
                (name: "Air Squats", prescriptionJSON: #"{"reps":20}"#),
            ]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active
        return (ctx, itemIDs, state)
    }

    // MARK: - restDuration

    func testRestDurationReturnsZeroRegardlessOfTimeCap() {
        let (ctx, _, state) = makeStandardAMRAPState(timeCapSec: 720)
        let driver = AMRAPDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 0)
    }

    func testRestDurationReturnsZeroOnMalformedTimingConfig() {
        // AMRAPDriver never reads timingConfigJSON for rest purposes —
        // parse failure must still yield 0, matching the continuous-
        // effort contract.
        let (ctx, _) = makeAMRAPContext(
            timeCapSec: 0,
            items: [(name: "Burpees", prescriptionJSON: #"{"reps":10}"#)]
        )
        // Build a block with a deliberately broken timing config; swap it
        // into the context manually (WorkoutContext is a value type).
        let brokenBlock = Block(
            id: ctx.blocks[0].id,
            workoutID: ctx.workout.id,
            parentBlockID: nil,
            position: 0,
            name: nil,
            timingMode: .amrap,
            timingConfigJSON: "not json at all",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let brokenCtx = WorkoutContext(
            workout: ctx.workout,
            blocks: [brokenBlock],
            itemsByBlock: ctx.itemsByBlock,
            exercises: ctx.exercises
        )
        var state = SessionSeeder.seed(context: brokenCtx)
        state.route = .active
        let driver = AMRAPDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: brokenCtx), 0)
    }

    // MARK: - activeContent

    func testActiveContentResolvesFirstItem() {
        let (ctx, _, state) = makeStandardAMRAPState()
        let content = AMRAPDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Pull-ups")
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.repsDisplay, "10")
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg)
        // Round counter — setIndex 1 means round 1 on this item.
        XCTAssertEqual(content?.setIndex, 1)
        // Unbounded rounds: `totalSets == 0` is the "no bound" semantic
        // (bug-037). ActiveView's progress-dot row and meta-line
        // denominator both gate on `totalSets > 0` and collapse to a
        // round counter instead.
        XCTAssertEqual(content?.totalSets, 0)
        XCTAssertEqual(content?.totalSets, AMRAPDriver.unboundedRoundsCount)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentFollowsCursorToNextItem() {
        let (ctx, _, initial) = makeStandardAMRAPState()
        // Round-robin: move cursor to item 1 (push-ups).
        var state = initial
        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 1)

        let content = AMRAPDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.exerciseName, "Push-ups")
        XCTAssertEqual(content?.reps, 15)
        XCTAssertEqual(content?.loadDisplay, "BW")
    }

    func testActiveContentResolvesLoadWhenPrescribed() {
        // Weighted AMRAP station — 10 Power Cleans @ 95 kg.
        let (ctx, _) = makeAMRAPContext(
            timeCapSec: 600,
            items: [
                (name: "Power Clean", prescriptionJSON: #"{"reps":10,"load_kg":95}"#),
            ]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = AMRAPDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.exerciseName, "Power Clean")
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.loadKg, 95)
        // R2.10: pound-default renders as " lb" suffix when JSON omits `weight_unit`.
        XCTAssertEqual(content?.loadDisplay, "95 lb")
    }

    func testActiveContentSurfacesRoundCounterViaSetIndex() {
        // Completing round 1 of item 0 should advance the setIndex on
        // the same item — mirrors what the reducer will do once round-
        // robin advancement lands. For the driver's Active render, all
        // that matters is that setIndex flows through as the round count.
        let (ctx, _, initial) = makeStandardAMRAPState()
        var state = initial
        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 3)

        let content = AMRAPDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.setIndex, 3)
    }

    func testActiveContentReturnsNilWhenCursorOutOfRange() {
        let (ctx, _, initial) = makeStandardAMRAPState()
        var state = initial
        // itemIndex 99 is past the end of the 3-item block.
        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 99, setIndex: 1)

        XCTAssertNil(AMRAPDriver().activeContent(state: state, context: ctx))
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcomeWithoutRIR() {
        let (ctx, itemIDs, state) = makeStandardAMRAPState()
        let outcome = AMRAPDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 10,
                loggedRir: nil
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }

    func testOnSetLoggedReturnsEmptyOutcomeEvenWithRIR() {
        // Spec: AMRAP has no autoreg. Supplying an RIR value must NOT
        // produce a proposal — this guards against a future copy-paste
        // from StraightSetsDriver re-enabling autoreg here.
        let (ctx, itemIDs, state) = makeStandardAMRAPState()
        let outcome = AMRAPDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 8,    // overshoot the prescribed 10 — classic autoreg trigger
                loggedRir: 4      // high RIR — more classic autoreg trigger
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }
}
