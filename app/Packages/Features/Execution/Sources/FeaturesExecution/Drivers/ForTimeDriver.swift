// ForTimeDriver.swift
//
// TimingDriver for `timing_mode = for_time` — "complete a prescribed body
// of work as fast as possible, log the time it took" (docs/prescription.md
// § "for_time"). Chipper-style block: one or more items cycled each round,
// with optional per-round rep counts via `rounds_rep_scheme` (the classic
// CrossFit 21-15-9 "Fran" shape).
//
// Scope of this driver (per the feature brief):
//   - `restDuration` returns 0. For-time is continuous effort — no rest
//     between items or rounds. The view model's auto-advance path collapses
//     the zero-duration rest and drops straight to the next (round, item).
//   - `activeContent` renders the current (round, item): reps come from
//     `rounds_rep_scheme[round - 1]` when the scheme is authored on the
//     block, else fall back to the item's prescription. Load comes from
//     the item. The cursor's `setIndex` is the 1-based round counter.
//   - `onSetLogged` returns an empty outcome. For-time has no autoreg
//     (spec explicitly excludes it).
//
// Time-cap enforcement lives outside this driver. Drivers are pure and do
// not read the wall clock; the view model owns the timer and flips the
// route to `.complete` when `time_cap_sec` elapses. That wiring lands in
// a separate pass — this file only covers the three TimingDriver methods.
//
// Cursor semantics (v1):
//   The cursor's `setIndex` is the 1-based round number (round 1, 2, 3...);
//   `itemIndex` selects the current item within the round. A chipper with
//   3 rounds of (thruster, pull-up) is a 3x2 grid — the reducer walks
//   item 0 then item 1 within each round, then advances setIndex. For-time
//   needs the structure's `setsPerItem[blockIndex][itemIndex]` to equal
//   `block.rounds` on every item so `advanceCursor` knows when to flip to
//   `.complete`. That seeding choice is the reducer/seeder's concern and
//   is described in the driver return notes; this driver only reads the
//   cursor that results.
//
// Rep-scheme parsing:
//   `block.roundsRepSchemeJSON` is a JSON array of ints (e.g. "[21, 15, 9]").
//   Malformed JSON or a missing scheme is graceful: we fall back to the
//   item's authored `reps`. A scheme that's too short for the current round
//   index also falls back to the item's `reps` — defensive, though Claude
//   is expected to keep `rounds_rep_scheme.count == block.rounds`.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct ForTimeDriver: TimingDriver {

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
        guard let block = context.block(at: c.blockIndex) else {
            return nil
        }
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }

        // The cursor's setIndex is the 1-based round number. Resolve reps
        // from the scheme (if present for this round), else fall back to
        // the item's authored prescription.
        let round = c.setIndex
        let (fallbackReps, loadKg, unit) = prescribedRepsAndLoad(for: item)
        let reps = scheme(from: block)
            .flatMap { $0[safe: round - 1] }
            ?? fallbackReps

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

        let totalRounds = block.rounds ?? 1

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: round,
            totalSets: totalRounds,
            loadDisplay: loadDisplay,
            repsDisplay: String(reps),
            loadKg: heroLoadKg,
            reps: reps,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// For-time has no between-sets or between-rounds rest — the whole
    /// block is continuous effort until all rounds are complete (or the
    /// time cap elapses). Returning 0 lets the view model's auto-advance
    /// path collapse the rest and route straight back to `.active` for
    /// the next (round, item).
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        0
    }

    // MARK: - Log outcome

    /// No autoreg on for_time (per `docs/prescription.md` § "for_time").
    /// The driver never proposes a change regardless of the logged
    /// reps/RIR.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Parse the block's `roundsRepSchemeJSON` as `[Int]`. Returns nil on
    /// missing or malformed input — callers fall back to the item's
    /// authored `reps`.
    private func scheme(from block: Block) -> [Int]? {
        guard
            let raw = block.roundsRepSchemeJSON,
            let data = raw.data(using: .utf8)
        else {
            return nil
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard let array = parsed as? [Any] else {
            return nil
        }
        var result: [Int] = []
        result.reserveCapacity(array.count)
        for value in array {
            if let i = value as? Int {
                result.append(i)
            } else if let d = value as? Double, d.truncatingRemainder(dividingBy: 1) == 0 {
                result.append(Int(d))
            } else {
                return nil
            }
        }
        return result
    }

    /// Extract the prescribed rep count and optional load_kg from a
    /// for_time item's prescription. For-time items typically author as
    /// `{"load_kg": kg}` (reps come from the scheme) or `{}` (both come
    /// from the block). Tolerates the common shapes defensively; unknown
    /// shapes collapse to (0, nil).
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

// MARK: - Utilities

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
