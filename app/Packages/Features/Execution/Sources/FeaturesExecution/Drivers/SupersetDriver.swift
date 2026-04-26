// SupersetDriver.swift
//
// TimingDriver for `timing_mode = superset` — two or more exercises
// performed back-to-back with one shared rest between rounds
// (docs/prescription.md § "superset"). The block carries `rounds`
// (commonly 3); items are N≥2 one-per-exercise rows.
//
// Cursor semantics (v1, round-robin within rounds — mirrors Circuit):
//   - `cursor.itemIndex` walks 0..N-1 within a round.
//   - `cursor.setIndex`  is the 1-based round counter.
//
// Scope of this driver:
//   - `activeContent` renders the current exercise in the superset.
//     `setIndex` = round counter; `totalSets` = `block.rounds`.
//   - `restDuration` returns 0 between items within a round (back-to-back
//     lifts) and `rest_between_rounds_sec` after the last item of a non-
//     last round. Last item of the last round never rests — the VM routes
//     to `.complete`; defensive fallback returns 0 there.
//   - `onSetLogged` returns an empty outcome. Spec § "When autoreg
//     applies" marks superset as YES but v1 does not propose: autoreg
//     for supersets needs "applies to remaining rounds of the superset"
//     semantics that the reducer does not support yet. Left for a later
//     slice; flagged in the feature brief.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct SupersetDriver: TimingDriver {

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
        guard let block = context.block(at: c.blockIndex) else { return nil }
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }

        // Prefer the live SetPlan row at the cursor — the reducer mirrors
        // swap `reps` / `load_kg` / `weight_unit` overrides onto non-done
        // rows, so reading the SetPlan reflects post-swap state. Re-parsing
        // `prescriptionJSON` would return the pre-swap authored values and
        // strand the Active screen on stale load/reps after a swap.
        let activeSet = itemLog.sets.first(where: { $0.setIndex == c.setIndex })
        let (reps, loadKg, unit) = resolveRepsAndLoad(for: item, itemLog: itemLog, cursor: c)
        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

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

        let repsDisplay = activeSet.map(displayText(for:)) ?? String(reps)
        let kind = activeSet.map(activeKind(for:)) ?? .strength

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: c.setIndex,
            totalSets: totalRounds,
            loadDisplay: loadDisplay,
            repsDisplay: repsDisplay,
            loadKg: heroLoadKg,
            reps: reps,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID],
            kind: kind
        )
    }

    // MARK: - Rest duration

    /// Zero between items within a round; `rest_between_rounds_sec` at
    /// the end of every round except the last. Malformed / missing
    /// config → 0.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else { return 0 }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            guard case .superset(let rbr, _) = config else { return 0 }
            let itemsInBlock = itemsInCurrentBlock(state: state)
            let isLastItem = c.itemIndex + 1 == itemsInBlock
            let totalRounds = block.rounds ?? 1
            let isLastRound = c.setIndex >= totalRounds
            if isLastItem && !isLastRound {
                return rbr
            }
            // Within a round (back-to-back), or defensively at the tail
            // of the last round (the VM flips to .complete first).
            return 0
        case .failure:
            return 0
        }
    }

    // MARK: - Log outcome

    /// No autoreg for supersets in v1 — returning an empty outcome keeps
    /// parity with Circuit / AMRAP / For-Time until the round-aware
    /// autoreg wiring lands.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    private func itemsInCurrentBlock(state: SessionState) -> Int {
        let b = state.cursor.blockIndex
        guard b < state.structure.itemsPerBlock.count else { return 0 }
        return state.structure.itemsPerBlock[b]
    }

    /// Resolve `(reps, loadKg, unit)` for the active round. The SetPlan row
    /// at `cursor.setIndex` is the source of truth for live numeric values
    /// (reps / loadKg / unit) — the reducer mirrors swap overrides onto
    /// non-done rows so reading the SetPlan reflects the post-swap plan.
    /// `set.loadKg == nil` is the loadless sentinel (BW item, loadless
    /// AMRAP token) — it passes straight through to the caller as nil
    /// so the display renders "BW".
    private func resolveRepsAndLoad(
        for item: WorkoutItem,
        itemLog: SessionState.ItemLog,
        cursor: SessionState.Cursor
    ) -> (reps: Int, loadKg: Double?, unit: WeightUnit) {
        if let set = itemLog.sets.first(where: { $0.setIndex == cursor.setIndex }) {
            return (set.reps, set.loadKg, set.unit)
        }
        // Fallback when no SetPlan row matches the cursor (defensive —
        // the seeder produces one row per round). Parse the prescription
        // as a last resort so the Active screen still renders.
        return prescribedRepsAndLoad(for: item)
    }

    /// Superset items author as `{reps, load_kg?, target_rir?, autoreg?}`
    /// (parses as `.straightSets` with `sets: nil`). Bodyweight lifts
    /// omit `load_kg`. Tolerant extraction across related shapes so
    /// renders stay coherent on authoring drift. Used only as the fallback
    /// when no SetPlan row matches the cursor — normal reads go through
    /// `resolveRepsAndLoad`.
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
        case .cluster(_, let reps, let loadKg, let unit, _, _, _, _):
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
