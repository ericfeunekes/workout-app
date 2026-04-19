// AMRAPDriver.swift
//
// TimingDriver for `timing_mode = amrap` — "As Many Rounds As Possible" in
// a fixed time cap. Metcon-style block: one or more items, each with a
// prescribed rep count (and optional load). The user rotates through the
// items round-robin until the block's `time_cap_sec` elapses.
//
// Scope of this driver (per the feature brief):
//   - `restDuration` returns 0. AMRAP is a continuous effort — no between-
//     sets rest. The view model's auto-advance path collapses the zero-
//     duration rest and drops straight to the next set.
//   - `activeContent` renders the current item's exercise name, reps, and
//     load, using the cursor's `setIndex` as the round counter. `totalSets`
//     is 0 — the ActiveView progress-dot contract (`totalSets > 0`
//     required to render dots) collapses the dot row and the meta line's
//     denominator, because rounds are unbounded at authoring time (the
//     time cap terminates the block, not a set count). Bug-037 was
//     the 999-sentinel variant that rendered 999 dots and blew the
//     layout off-screen.
//   - `onSetLogged` returns an empty outcome. AMRAP has no autoreg (spec
//     explicitly excludes it), so no proposal ever fires.
//
// Time-cap enforcement lives outside this driver. Drivers are pure and do
// not read the wall clock; the view model owns the timer and flips the
// route to `.complete` when `time_cap_sec` elapses. That slice lands in a
// separate pass — this file only covers the three TimingDriver methods.
//
// Cursor semantics (v1):
//   AMRAP items typically parse as `.straightSets(sets: nil, reps: ...,
//   loadKg: ...)` because the authoring shape is `{"reps": N}` with no
//   `sets` key. The seeder produces one SetPlan row per item (setIndex=1).
//   The driver reads reps/load directly from the parsed prescription —
//   never from `itemLog.sets` — so the display stays correct across rounds
//   even when only one SetPlan row is seeded. The cursor's setIndex is
//   surfaced as the round counter (round 1, 2, 3, ...).

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct AMRAPDriver: TimingDriver {

    /// Semantic "no bound" for AMRAP's `ActiveContent.totalSets`. Rounds
    /// are bounded by the time cap, not by an authored set count. The
    /// ActiveView contract is: `totalSets > 0` shows the progress-dot
    /// row and "SET N OF M" denominator; `totalSets == 0` hides the
    /// dots and renders "ROUND N" instead. See
    /// `docs/features/execute-loop.md` § "Progress-dot contract" and
    /// `docs/features/timing-modes.md` § "amrap".
    ///
    /// (A prior variant passed a 999 sentinel and bug-037 rendered 999
    /// progress dots, pushing the header off-screen. 0-means-unbounded
    /// is the explicit contract now.)
    public static let unboundedRoundsCount: Int = 0

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    public func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }

        // Reps and load come from the authored prescription — AMRAP items
        // typically seed as a single SetPlan row (setIndex=1) regardless
        // of how many rounds the user ends up completing.
        let (reps, loadKg, unit) = prescribedRepsAndLoad(for: item)

        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

        // Bodyweight (no load authored) renders as "BW"; anything else
        // formats via the shared helper so fractional plates and unit
        // suffix match the straight-sets display.
        let loadDisplay: String
        let heroLoadKg: Double?
        if let kg = loadKg {
            loadDisplay = formatLoad(weight: kg, unit: LoadUnit(setPlanUnit: unit))
            heroLoadKg = kg
        } else {
            loadDisplay = "BW"
            heroLoadKg = nil
        }

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: c.setIndex,
            totalSets: AMRAPDriver.unboundedRoundsCount,
            loadDisplay: loadDisplay,
            repsDisplay: String(reps),
            loadKg: heroLoadKg,
            reps: reps,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// AMRAP has no between-sets rest — the whole block is continuous
    /// effort until the time cap elapses. Returning 0 lets the view
    /// model's auto-advance path collapse the rest and route straight
    /// back to `.active` for the next item in the round-robin.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        0
    }

    // MARK: - Log outcome

    /// No autoreg on AMRAP (per `docs/prescription.md` § "amrap"). The
    /// driver never proposes a change regardless of the logged reps/RIR.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Extract the prescribed rep count and optional load_kg from an
    /// AMRAP item's prescription. AMRAP items author as `{"reps": N}` or
    /// `{"reps": N, "load_kg": kg}`, which parse as `.straightSets` with
    /// `sets: nil`. We also tolerate `.bodyweight` and `.cluster` shapes
    /// defensively — parsers drift and we'd rather render something than
    /// blow up. Unknown shapes collapse to (0, nil).
    private func prescribedRepsAndLoad(
        for item: WorkoutItem
    ) -> (reps: Int, loadKg: Double?, unit: WeightUnit) {
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            return repsAndLoad(from: p)
        case .failure:
            return (0, nil, .lb)
        }
    }

    private func repsAndLoad(
        from prescription: Prescription
    ) -> (reps: Int, loadKg: Double?, unit: WeightUnit) {
        switch prescription {
        case .straightSets(_, let reps, let loadKg, let unit, _, _, _, _):
            return (intReps(from: reps), loadKg, unit)
        case .bodyweight(_, let reps, _):
            return (reps, nil, .lb)
        case .cluster(_, let reps, let loadKg, let unit, _, _, _):
            return (reps, loadKg, unit)
        case .repRange(_, _, let repsMax, let loadKg, let unit, _, _):
            return (repsMax, loadKg, unit)
        case .warmup(_, let reps, let loadKg, let unit):
            return (reps, loadKg, unit)
        case .setsDetail, .percentOf1RM, .amrapToken, .empty:
            return (0, nil, .lb)
        }
    }

    private func intReps(from rc: RepCount?) -> Int {
        guard let rc else { return 0 }
        if case .count(let n) = rc { return n }
        return 0
    }
}
