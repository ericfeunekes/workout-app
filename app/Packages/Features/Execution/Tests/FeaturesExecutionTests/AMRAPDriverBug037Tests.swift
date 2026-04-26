// AMRAPDriverBug037Tests.swift
//
// Dedicated regression suite for bug-037: AMRAP Active screen
// horizontally overflowed by rendering ~999 progress dots. Root cause
// was `AMRAPDriver.activeContent` returning `totalSets = 999` as an
// "unbounded rounds" sentinel, which `ActiveView` rendered literally
// as "SET 1 OF 999" + a 999-element progress-dot row, pushing the
// exercise name / sub-header / log button ~5800 px off-screen.
//
// Fix: AMRAPDriver reports `totalSets = 0` (`unboundedRoundsCount`)
// as the explicit "no bound" semantic. `ActiveView` gates its
// progress-dot row and the "OF M" denominator suffix on
// `totalSets > 0`; when unbounded, the meta line collapses to
// "ROUND N" (see `ActiveViewMetaLineTests`).
//
// This file pins the DRIVER end of that contract. The VIEW end lives
// in `ActiveViewMetaLineTests`. Separate file mainly because the
// existing `AMRAPDriverTests` hit SwiftLint's `type_body_length` cap.

import XCTest
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class AMRAPDriverBug037Tests: XCTestCase {

    /// Minimal single-item AMRAP fixture. Keeps the file small —
    /// `AMRAPDriverTests` already covers multi-item / weighted cases.
    private func makeAMRAPState(
        timeCapSec: Int = 300
    ) -> (WorkoutContext, SessionState) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let exercise = Exercise(id: exerciseID, name: "Burpee")
        let item = WorkoutItem(
            id: itemID,
            blockID: blockID,
            position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":5}"#
        )
        let workout = Workout(
            id: workoutID, userID: userID, name: "metcon",
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
            itemsByBlock: [[item]],
            exercises: [exerciseID: exercise]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active
        return (ctx, state)
    }

    /// Bug-037 core contract: `totalSets` on an AMRAP ActiveContent is
    /// the explicit "unbounded" value (0), NEVER a visible integer.
    /// Previously 999 — the view's `ForEach(1...totalSets)` rendered
    /// 999 progress dots off-screen. Covers every round number a
    /// future regression might compute out of the cursor.
    func testAMRAPDriverTotalSetsIsZeroForUnboundedRounds() {
        let (ctx, initial) = makeAMRAPState()
        let driver = AMRAPDriver()
        for roundNumber in [1, 2, 5, 37, 120, 999] {
            var state = initial
            state.cursor = SessionState.Cursor(
                blockIndex: 0,
                itemIndex: 0,
                setIndex: roundNumber
            )
            let content = driver.activeContent(state: state, context: ctx)
            XCTAssertEqual(
                content?.totalSets,
                0,
                "AMRAP must always report totalSets=0 (unbounded); round=\(roundNumber)"
            )
        }
    }

    /// The exported constant is the public API for other call sites
    /// (contract tests, docs, future modes that want the same
    /// semantic). Pin its value so a rename doesn't silently
    /// reintroduce a non-zero sentinel.
    func testUnboundedRoundsCountIsZero() {
        XCTAssertEqual(AMRAPDriver.unboundedRoundsCount, 0)
    }
}
