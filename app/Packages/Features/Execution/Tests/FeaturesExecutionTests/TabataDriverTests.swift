// TabataDriverTests.swift
//
// Unit coverage for `TabataDriver`:
//   - restDuration always returns 10 seconds — regardless of
//     `timing_config_json` contents (spec locks 20/10/8; the config is
//     `{}` by design). Verified with empty config, extraneous keys, and
//     malformed JSON.
//   - activeContent resolves the current round's item: exercise name +
//     prescribed reps/load; returns nil when the cursor is out of range.
//     Multi-item tabatas alternate per round in listed order.
//   - onSetLogged always returns an empty DriverLogOutcome — tabata has
//     no autoreg (per docs/prescription.md § "tabata"). Verified with
//     and without RIR to guard against a future copy-paste from a
//     load-based driver re-enabling autoreg here.
//
// Fixture shape: single-item tabatas are the usual case
// (`{"reps":N}` bodyweight or `{"reps":N,"load_kg":kg}`); multi-item
// coverage exercises the round-alternating mapping.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class TabataDriverTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a tabata block with the given items. Exercise names are
    /// injected into the context so `activeContent` can resolve them.
    /// `timingConfigJSON` defaults to `{}` (the spec shape) but can be
    /// overridden to prove the driver ignores its contents.
    private func makeTabataContext(
        timingConfigJSON: String = "{}",
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
            id: workoutID, userID: userID, name: "tabata",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .tabata,
            timingConfigJSON: timingConfigJSON,
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

    /// Standard single-item tabata — 20 air squats per 20s work window.
    /// Cursor parked on block 0, item 0, round 1, route `.active`.
    private func makeStandardTabataState(
        timingConfigJSON: String = "{}"
    ) -> (WorkoutContext, [UUID], SessionState) {
        let (ctx, itemIDs) = makeTabataContext(
            timingConfigJSON: timingConfigJSON,
            items: [
                (name: "Air Squats", prescriptionJSON: #"{"reps":20}"#),
            ]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active
        return (ctx, itemIDs, state)
    }

    // MARK: - restDuration

    func testRestDurationReturnsTenSecondsOnEmptyConfig() {
        let (ctx, _, state) = makeStandardTabataState(timingConfigJSON: "{}")
        XCTAssertEqual(
            TabataDriver().restDuration(state: state, context: ctx),
            10
        )
    }

    func testRestDurationIgnoresExtraneousConfigKeys() {
        // Spec: 20/10/8 is the definition. Even if an author litters
        // `rest_sec: 99` into the config, the driver must ignore it.
        let (ctx, _, state) = makeStandardTabataState(
            timingConfigJSON: #"{"rest_sec":99,"work_sec":45,"rounds":12}"#
        )
        XCTAssertEqual(
            TabataDriver().restDuration(state: state, context: ctx),
            10
        )
    }

    func testRestDurationReturnsTenSecondsOnMalformedJSON() {
        // TabataDriver never reads timingConfigJSON — a malformed blob
        // must still yield 10s so the flow survives authoring mistakes.
        let (ctx, _, state) = makeStandardTabataState(
            timingConfigJSON: "not json at all"
        )
        XCTAssertEqual(
            TabataDriver().restDuration(state: state, context: ctx),
            10
        )
    }

    func testRestDurationMatchesHardcodedConstant() {
        // Guard against drift between the exposed constant and the
        // returned value — this pair is the spec invariant.
        let (ctx, _, state) = makeStandardTabataState()
        XCTAssertEqual(
            TabataDriver().restDuration(state: state, context: ctx),
            TabataDriver.restSec
        )
        XCTAssertEqual(TabataDriver.restSec, 10)
        XCTAssertEqual(TabataDriver.workSec, 20)
        XCTAssertEqual(TabataDriver.rounds, 8)
    }

    // MARK: - activeContent

    func testActiveContentResolvesSingleItem() {
        let (ctx, _, state) = makeStandardTabataState()
        let content = TabataDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Air Squats")
        XCTAssertEqual(content?.reps, 20)
        XCTAssertEqual(content?.repsDisplay, "20")
        XCTAssertEqual(content?.loadDisplay, "BW")
        XCTAssertNil(content?.loadKg)
        // Round 1 of 8.
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, TabataDriver.rounds)
        XCTAssertEqual(content?.totalSets, 8)
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentResolvesLoadWhenPrescribed() {
        // Weighted tabata — 10 thrusters @ 20 kg per 20s window.
        let (ctx, _) = makeTabataContext(
            items: [
                (name: "Thruster", prescriptionJSON: #"{"reps":10,"load_kg":20}"#),
            ]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let content = TabataDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.exerciseName, "Thruster")
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.loadKg, 20)
        XCTAssertEqual(content?.loadDisplay, "20 lb")
    }

    func testActiveContentSurfacesRoundCounterViaSetIndex() {
        // Round 5 — the cursor's setIndex flows through unchanged so
        // the Active screen can render "round 5 of 8".
        let (ctx, _, initial) = makeStandardTabataState()
        var state = initial
        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 5)

        let content = TabataDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.setIndex, 5)
        XCTAssertEqual(content?.totalSets, 8)
    }

    func testActiveContentPinsToFirstItemAcrossRoundsWhenMultiItem() {
        // Spec (docs/prescription.md § "tabata"): tabata is single-item —
        // "one exercise." Authors that stamp > 1 item on a tabata block
        // trip the seed-time collapse (see
        // `testTabataMultiItemSeedRejects`), and the driver also pins to
        // items[0] so that render and auto-log always agree across the
        // 8 rounds. Regression guard for the prior per-round alternator
        // that made the screen and `autoLogAndRestForTabata` disagree on
        // the active exercise after round 1.
        let (ctx, _) = makeTabataContext(
            items: [
                (name: "Squats", prescriptionJSON: #"{"reps":20}"#),
                (name: "Push-ups", prescriptionJSON: #"{"reps":15}"#),
            ]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active

        let driver = TabataDriver()

        for round in 1...TabataDriver.rounds {
            state.cursor = SessionState.Cursor(
                blockIndex: 0, itemIndex: 0, setIndex: round
            )
            XCTAssertEqual(
                driver.activeContent(state: state, context: ctx)?.exerciseName,
                "Squats",
                "round \(round) must resolve to items[0]; no per-round alternation"
            )
        }
    }

    // MARK: - Multi-item seed collapse

    func testTabataMultiItemSeedRejects() {
        // `SessionSeeder.seed` collapses a multi-item tabata block to the
        // first item: one seeded ItemLog, one row in `itemsPerBlock`, no
        // SetPlan rows for items[1..] and beyond. The bug this guards
        // against: prior to the collapse the seeder emitted 8 rows per
        // item under `.roundRobin`, and the driver picked an item per
        // round — the two disagreed so the screen rendered item 1 while
        // the auto-log path wrote to item 0 (and vice versa).
        let (ctx, itemIDs) = makeTabataContext(
            items: [
                (name: "Squats", prescriptionJSON: #"{"reps":20}"#),
                (name: "Push-ups", prescriptionJSON: #"{"reps":15}"#),
                (name: "Burpees", prescriptionJSON: #"{"reps":10}"#),
            ]
        )

        let state = SessionSeeder.seed(context: ctx)

        XCTAssertEqual(state.structure.itemsPerBlock, [1],
                       "tabata must collapse to one seeded item")
        XCTAssertEqual(state.items.count, 1,
                       "only items[0] gets an ItemLog; extras dropped")
        XCTAssertEqual(state.items.first?.itemID, itemIDs[0])
        XCTAssertEqual(state.structure.setsPerItem, [[8]],
                       "items[0] still gets the 8 tabata rounds as SetPlans")

        // The extras exist in the context (a shell/upstream concern) but
        // the session state does NOT carry ItemLogs for them — so the
        // reducer can't route a log at them.
        XCTAssertFalse(state.items.contains { $0.itemID == itemIDs[1] })
        XCTAssertFalse(state.items.contains { $0.itemID == itemIDs[2] })
    }

    func testActiveContentReturnsNilForOutOfRangeCursors() {
        // Covers the four boundary cases: block index past end, round
        // below 1 (setIndex==0 is the "no active set" sentinel), round
        // past 8 (VM should have flipped to `.complete`), and zero-item
        // block (malformed authoring — driver bails rather than crash).
        let (ctx, _, initial) = makeStandardTabataState()
        let driver = TabataDriver()
        var state = initial

        state.cursor = SessionState.Cursor(blockIndex: 99, itemIndex: 0, setIndex: 1)
        XCTAssertNil(driver.activeContent(state: state, context: ctx))

        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 0)
        XCTAssertNil(driver.activeContent(state: state, context: ctx))

        state.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 9)
        XCTAssertNil(driver.activeContent(state: state, context: ctx))

        let (emptyCtx, _) = makeTabataContext(items: [])
        let emptyState = SessionSeeder.seed(context: emptyCtx)
        XCTAssertNil(driver.activeContent(state: emptyState, context: emptyCtx))
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcomeWithoutRIR() {
        let (ctx, itemIDs, state) = makeStandardTabataState()
        let outcome = TabataDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 20,
                loggedRir: nil
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }

    func testOnSetLoggedReturnsEmptyOutcomeEvenWithRIR() {
        // Spec: tabata has no autoreg. Supplying reps + RIR that would
        // classically trigger a proposal must NOT produce one — guards
        // against a future copy-paste re-enabling autoreg here.
        let (ctx, itemIDs, state) = makeStandardTabataState()
        let outcome = TabataDriver().onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: itemIDs[0],
                setIndex: 1,
                loggedReps: 15,   // below the prescribed 20 — classic undershoot
                loggedRir: 0      // failure — classic undershoot signal
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }
}
