// AutoregSetsDetailSuppressionTests.swift
//
// qa-044 regression: autoreg must NOT propose a load change for items
// whose prescription is `sets_detail` (per-set pyramid) or any other
// shape that authors per-set variation. Previously, `StraightSetsDriver
// .autoregAndTarget` returned `(autoreg, target)` for `.setsDetail`,
// which caused `onSetLogged` to call `Autoreg.propose` against the
// first set's load — silently overwriting the pyramid's authored
// targets for sets 2+.
//
// Contract (docs/autoreg.md § S17): "Non-straight-sets shapes must not
// propose." This test pins the suppression for `sets_detail`; the
// same guard also applies to `cluster`, `percent_of_1rm`, `bodyweight`,
// `warmup`, `amrap_token`, and `.empty` — all routed through the same
// switch with a single `(nil, nil)` case.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class AutoregSetsDetailSuppressionTests: XCTestCase {

    /// Log set 1 of a `sets_detail` pyramid at RIR 4 (a value that
    /// would normally trigger the overshoot step on a `straight_sets`
    /// item). The driver must return an empty outcome — no proposal,
    /// no mutation — and the remaining pending sets must keep their
    /// authored loads.
    func testAutoregSuppressedForSetsDetailShape() {
        let (ctx, itemID, state) = Self.setsDetailContext()
        let driver = StraightSetsDriver()
        let event = SetLogEvent(
            itemID: itemID, setIndex: 1,
            loggedReps: 12, loggedRir: 4
        )

        let outcome = driver.onSetLogged(state: state, context: ctx, event: event)

        XCTAssertNil(
            outcome.proposal,
            "sets_detail must not trigger an autoreg proposal — qa-044"
        )
        XCTAssertTrue(
            outcome.mutations.isEmpty,
            "sets_detail must not carry any autoreg mutations"
        )

        // Sanity: the seeded SetPlan rows carry the authored pyramid
        // loads (45, 47.5, 50). No proposal means the pending rows
        // stay at their authored values — the next set's display
        // should show 47.5, not 47.5-derived-from-autoreg.
        let sets = state.items.first(where: { $0.itemID == itemID })?.sets ?? []
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[0].loadKg, 45)
        XCTAssertEqual(sets[1].loadKg, 47.5)
        XCTAssertEqual(sets[2].loadKg, 50)
    }

    // MARK: - Fixtures

    /// 3-set `sets_detail` pyramid: 45 → 47.5 → 50. `target_rir` and
    /// `autoreg` are authored so a broken suppression path WOULD
    /// produce a proposal — without them the test would pass for the
    /// wrong reason (nil autoreg short-circuits `resolveAutoreg`).
    static func setsDetailContext() -> (WorkoutContext, UUID, SessionState) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "PyramidBench",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON:
                #"{"rest_between_sets_sec":90,"rest_between_exercises_sec":120}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"""
            {
                "sets_detail": [
                    {"reps":12,"load_kg":45},
                    {"reps":10,"load_kg":47.5},
                    {"reps":8,"load_kg":50}
                ],
                "target_rir": 2,
                "autoreg": {}
            }
            """#
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")],
            lastPerformed: [:]
        )
        var state = SessionSeeder.seed(context: ctx)
        state.route = .active
        return (ctx, itemID, state)
    }
}
