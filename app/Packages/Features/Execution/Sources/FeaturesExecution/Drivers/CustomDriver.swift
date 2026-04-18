// CustomDriver.swift
//
// TimingDriver for `timing_mode = custom` — the catch-all for mixed-
// segment sessions that don't fit another mode (docs/prescription.md
// § "custom"). The block's `timing_config_json` carries a free-form
// `segments` array; items carry whatever prescription the author needs
// at that segment. The app does not impose a state machine — each item
// renders what its prescription describes and the user logs when done.
//
// Scope of this driver (v1, simplified):
//   - `activeContent` resolves the current item's exercise name, reps
//     and load from its prescription. `setIndex` is the cursor's 1-based
//     set counter (matches the seeded SetPlan rows); `totalSets` is the
//     parsed `sets` for the item (or 1 if omitted / not sets-shaped).
//   - `restDuration` returns 0. Custom blocks do not enforce between-set
//     rest — any timing the author wants lives in the segment descriptor
//     (consumed by the VM/segment-walker, not this driver).
//   - `onSetLogged` returns an empty outcome. No autoreg by default
//     (spec: "Usually no — if a segment is a load-based strength piece,
//     add `autoreg` to that item"). v1 leaves autoreg off uniformly;
//     adding per-item autoreg reuses the StraightSets path and lands in
//     a later slice.
//
// Spec latitude note:
//   docs/prescription.md § "custom" is intentionally loose: items can be
//   empty, sets-shaped, or bodyweight, and segments can be work or rest.
//   v1 treats the driver as a thin renderer — the reducer seeds SetPlan
//   rows per the item prescription, and the user ticks through them
//   without app-imposed cadence.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct CustomDriver: TimingDriver {

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

        let parsed = parser.parse(prescriptionJSON: item.prescriptionJSON)
        let (reps, loadKg, totalSets) = resolve(parsed: parsed, itemLog: itemLog)

        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

        let loadDisplay: String
        let heroLoadKg: Double?
        if let kg = loadKg {
            loadDisplay = formatLoad(kg: kg)
            heroLoadKg = kg
        } else {
            loadDisplay = "BW"
            heroLoadKg = nil
        }

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: c.setIndex,
            totalSets: totalSets,
            loadDisplay: loadDisplay,
            repsDisplay: String(reps),
            loadKg: heroLoadKg,
            reps: reps,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// Custom does not enforce rest between sets — segments do, and
    /// those are the VM's concern. Returning 0 lets the auto-advance
    /// path collapse the rest straight to the next set / segment.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        0
    }

    // MARK: - Log outcome

    /// No autoreg on custom by default (per spec). The driver never
    /// proposes a change.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Pull reps, optional load, and total-sets-for-this-item out of the
    /// parsed prescription. Falls back to the seeded `itemLog.sets.count`
    /// for the total so the Active screen renders something sensible even
    /// when the item ships as `{}` (empty prescription — common in custom
    /// blocks where the segment describes the work).
    private func resolve(
        parsed: Result<Prescription, ParseError>,
        itemLog: SessionState.ItemLog
    ) -> (reps: Int, loadKg: Double?, totalSets: Int) {
        let fallbackTotal = max(itemLog.sets.count, 1)
        switch parsed {
        case .success(let p):
            switch p {
            case .straightSets(let sets, let reps, let loadKg, _, _, _, _):
                return (intReps(from: reps), loadKg, sets ?? fallbackTotal)
            case .bodyweight(let sets, let reps, _):
                return (reps, nil, sets)
            case .repRange(let sets, _, let repsMax, let loadKg, _, _):
                return (repsMax, loadKg, sets)
            case .cluster(let sets, let reps, let loadKg, _, _, _):
                return (reps, loadKg, sets)
            case .warmup(let sets, let reps, let loadKg):
                return (reps, loadKg, sets)
            case .setsDetail(let details, _, _):
                return (0, nil, max(details.count, 1))
            case .percentOf1RM(let sets, let reps, _, _):
                return (reps, nil, sets)
            case .amrapToken, .empty:
                return (0, nil, fallbackTotal)
            }
        case .failure:
            return (0, nil, fallbackTotal)
        }
    }

    private func intReps(from rc: RepCount?) -> Int {
        guard let rc else { return 0 }
        if case .count(let n) = rc { return n }
        return 0
    }
}
