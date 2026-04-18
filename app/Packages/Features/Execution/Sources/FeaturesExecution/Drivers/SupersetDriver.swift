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

        let (reps, loadKg) = prescribedRepsAndLoad(for: item)
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

        let totalRounds = block.rounds ?? 1

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: c.setIndex,
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
            guard case .superset(let rbr) = config else { return 0 }
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

    /// Superset items author as `{reps, load_kg?, target_rir?, autoreg?}`
    /// (parses as `.straightSets` with `sets: nil`). Bodyweight lifts
    /// omit `load_kg`. Tolerant extraction across related shapes so
    /// renders stay coherent on authoring drift.
    private func prescribedRepsAndLoad(
        for item: WorkoutItem
    ) -> (reps: Int, loadKg: Double?) {
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            return repsAndLoad(from: p)
        case .failure:
            return (0, nil)
        }
    }

    private func repsAndLoad(
        from prescription: Prescription
    ) -> (reps: Int, loadKg: Double?) {
        switch prescription {
        case .straightSets(_, let reps, let loadKg, _, _, _, _):
            return (intReps(from: reps), loadKg)
        case .bodyweight(_, let reps, _):
            return (reps, nil)
        case .cluster(_, let reps, let loadKg, _, _, _):
            return (reps, loadKg)
        case .repRange(_, _, let repsMax, let loadKg, _, _):
            return (repsMax, loadKg)
        case .warmup(_, let reps, let loadKg):
            return (reps, loadKg)
        case .setsDetail, .percentOf1RM, .amrapToken, .empty:
            return (0, nil)
        }
    }

    private func intReps(from rc: RepCount?) -> Int {
        guard let rc else { return 0 }
        if case .count(let n) = rc { return n }
        return 0
    }
}
