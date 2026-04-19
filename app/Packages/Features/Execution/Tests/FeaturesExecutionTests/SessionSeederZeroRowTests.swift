// SessionSeederZeroRowTests.swift
//
// Regression coverage for the zero-row prescription edge case. Prior
// to the fix, `.empty` (`{}`) and `.amrapToken` (`{"reps":"amrap"}`)
// inside set-major blocks (straight_sets / custom) produced empty
// SetPlan arrays. The reducer's cursor started at `(b, i, 1)` with no
// matching row; drivers rendered nothing and the user sat on a frozen
// screen. The seeder now produces a single manual placeholder so the
// UI can render and `advanceCursor` walks the cursor forward.
//
// These tests pin:
//   - straight_sets + `.empty` prescription → 1 placeholder row
//   - straight_sets + `.amrapToken` prescription → 1 placeholder row
//   - custom + `.empty` prescription → 1 placeholder row
//   - SessionReducer.nextCursor advances past the placeholder after a
//     single log, rather than spinning on the zero-row item.

import XCTest
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class SessionSeederZeroRowTests: XCTestCase {

    // MARK: - Fixtures

    private func buildContext(
        timingMode: TimingMode,
        timingConfigJSON: String,
        rounds: Int?,
        items: [(name: String, prescriptionJSON: String)]
    ) -> (WorkoutContext, [UUID]) {
        let blockID = UUID()
        let workoutID = UUID()
        let userID = UUID()
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
            id: workoutID, userID: userID, name: "zero-row",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: rounds, roundsRepSchemeJSON: nil, notes: nil
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises
        )
        return (ctx, itemIDs)
    }

    // MARK: - Straight-sets + zero-row prescription

    func testSessionSeederZeroRowStraightSeedsManualPlaceholder() {
        // `{}` → `.empty`. Pre-fix seeder returned []; reducer cursor
        // sat on `(0, 0, 1)` with no matching row. Post-fix: one
        // placeholder row at setIndex=1.
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(name: "Mystery Lift", prescriptionJSON: "{}")]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertNotNil(itemLog)
        XCTAssertEqual(itemLog?.sets.count, 1)
        XCTAssertEqual(itemLog?.sets.first?.setIndex, 1)
        XCTAssertEqual(itemLog?.sets.first?.done, false)
        XCTAssertEqual(state.structure.setsPerItem[0][0], 1)
    }

    func testSessionSeederZeroRowAmrapTokenSeedsManualPlaceholder() {
        // `{"reps":"amrap"}` discriminates as `.amrapToken`. Same
        // failure mode as `.empty` inside a set-major block.
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(name: "Open Set", prescriptionJSON: #"{"reps":"amrap"}"#)]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertEqual(itemLog?.sets.count, 1)
        XCTAssertEqual(itemLog?.sets.first?.setIndex, 1)
        XCTAssertEqual(state.structure.setsPerItem[0][0], 1)
    }

    /// Regression: R2.9 collapsed `.amrapToken` seeding with `.empty`,
    /// which dropped the authored `load_kg` + unit + target_rir. A
    /// weighted AMRAP token (kettlebell snatch @ 24 kg, AMRAP) was
    /// rendering / logging as "0 kg". Post-fix: the seeder preserves
    /// load and unit on the single open-entry row, and `.empty` keeps
    /// its existing placeholder shape.
    func testAmrapTokenSeedsWithAuthoredLoadAndRir() {
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(
                name: "KB Snatch",
                prescriptionJSON: #"{"reps":"amrap","load_kg":24,"weight_unit":"kg","target_rir":0}"#
            )]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertEqual(itemLog?.sets.count, 1, "AMRAP token seeds a single open-entry row")
        let row = itemLog?.sets.first
        XCTAssertEqual(row?.setIndex, 1)
        XCTAssertEqual(row?.loadKg, 24, "authored load preserved")
        XCTAssertEqual(row?.unit, .kg, "authored weight_unit preserved")
        XCTAssertEqual(row?.reps, 0, "open-entry sentinel — user enters the observed count")
        XCTAssertEqual(row?.done, false)
    }

    /// Bodyweight prescription (`{"sets":N,"reps":M}`) seeds every set
    /// with `loadKg = nil`. Regression guard for the bug where the
    /// seeder wrote loadKg = 0 on BW rows; the 0 then propagated into
    /// SetLog.weight = 0 and History rendered "0 lb" for a BW set.
    func testSessionSeederSeedsNilLoadForBodyweight() {
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(name: "Pull-ups", prescriptionJSON: #"{"sets":3,"reps":8}"#)]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertEqual(itemLog?.sets.count, 3)
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.loadKg == nil } ?? false,
            "every BW seed row carries loadKg == nil, not 0"
        )
    }

    /// Loadless AMRAP token (e.g. `{"reps":"amrap"}` — pull-ups to
    /// failure) seeds a single open-entry row with loadKg = nil and
    /// the `.lb` default unit. Carrying the loadless-ness as nil
    /// (rather than a numeric 0) is what lets the push + History path
    /// render "BW" rather than fabricating "0 lb" downstream.
    func testSessionSeederSeedsNilLoadForLoadlessAmrapToken() {
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(name: "Pull-ups", prescriptionJSON: #"{"reps":"amrap"}"#)]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        let row = itemLog?.sets.first
        XCTAssertNil(row?.loadKg, "loadless AMRAP token → nil seed")
    }

    /// Alias retained for the existing integration test that hit the
    /// old `loadKg == 0` assertion shape. New name reads against the
    /// loadless AMRAP-token case; the renamed method covers the same
    /// scenario under the Optional-load contract.
    func testAmrapTokenSeedsLoadlessRowWhenNoLoadAuthored() {
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(name: "Pull-ups", prescriptionJSON: #"{"reps":"amrap"}"#)]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertEqual(itemLog?.sets.count, 1)
        let row = itemLog?.sets.first
        XCTAssertNil(row?.loadKg, "no authored load → nil seed, driver renders BW")
        XCTAssertEqual(row?.reps, 0)
    }

    func testSessionSeederZeroRowCustomSeedsManualPlaceholder() {
        // Custom blocks read per-item prescriptions via `seedSets`; an
        // empty prescription is the common "segment describes the
        // work" shape from docs/prescription.md § "custom". The
        // placeholder lets CustomDriver render "1 of 1".
        let (ctx, itemIDs) = buildContext(
            timingMode: .custom,
            timingConfigJSON: #"{"segments":[{"type":"work","duration_sec":60}]}"#,
            rounds: nil,
            items: [(name: "Threshold Run", prescriptionJSON: "{}")]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertEqual(itemLog?.sets.count, 1)
        XCTAssertEqual(itemLog?.sets.first?.setIndex, 1)
        XCTAssertEqual(state.structure.setsPerItem[0][0], 1)
    }

    // MARK: - Autoreg parse failure — base prescription still seeds

    func testSessionSeederIsolatesAutoregParseFailure() {
        // Bug: an unsupported autoreg `apply_to` value (e.g. "all") used
        // to fail the whole prescription parse; the seeder caught the
        // failure and replaced the item's SetPlan with a zero-row
        // placeholder — the whole item silently became `0 kg / 0 reps`.
        //
        // Post-fix: the base prescription still seeds the authored
        // reps/load, and autoreg is dropped. The zero-row placeholder is
        // reserved for items whose BASE prescription is also malformed.
        let badAutoregJSON = #"""
        {"sets":4,"reps":5,"load_kg":102.5,"target_rir":2,
         "autoreg":{"apply_to":"all","overshoot_step_kg":2.5}}
        """#
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [(name: "Bench Press", prescriptionJSON: badAutoregJSON)]
        )

        let state = SessionSeeder.seed(context: ctx)

        let itemLog = state.items.first { $0.itemID == itemIDs[0] }
        XCTAssertEqual(itemLog?.sets.count, 4, "base `sets` seeds 4 rows, not the zero-row fallback")
        XCTAssertEqual(state.structure.setsPerItem[0][0], 4)
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.loadKg == 102.5 && $0.reps == 5 } ?? false,
            "base load/reps preserved; autoreg was stripped but base prescription survived"
        )
    }

    // MARK: - Reducer interaction — cursor advances past placeholder

    func testReducerAdvancesPastPlaceholderInsteadOfStalling() {
        // Two straight-sets items: item 0 is `.empty` (placeholder),
        // item 1 is a normal 2-set lift. After one advance the cursor
        // must reach item 1 — before the fix it stalled on item 0.
        let (ctx, itemIDs) = buildContext(
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            items: [
                (name: "Mystery Lift", prescriptionJSON: "{}"),
                (name: "Back Squat", prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":80}"#),
            ]
        )

        var state = SessionSeeder.seed(context: ctx)
        state.route = .active
        XCTAssertEqual(state.cursor.blockIndex, 0)
        XCTAssertEqual(state.cursor.itemIndex, 0)
        XCTAssertEqual(state.cursor.setIndex, 1)

        // Log the placeholder set, then advance from rest. The reducer
        // should move the cursor off item 0.
        state = SessionReducer.reduce(
            state,
            .logSet(itemID: itemIDs[0], setIndex: 1, loggedReps: 0, loggedRir: nil,
                    now: Date(timeIntervalSince1970: 1_700_000_000))
        )
        state = SessionReducer.reduce(state, .advanceFromRest)

        XCTAssertEqual(state.cursor.blockIndex, 0)
        XCTAssertEqual(state.cursor.itemIndex, 1)
        XCTAssertEqual(state.cursor.setIndex, 1)
    }
}
