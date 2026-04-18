// CircuitDriver.swift
//
// TimingDriver for `timing_mode = circuit` — N exercises in a loop for
// `block.rounds` rounds, with an optional short between-exercises rest
// and a longer between-rounds rest (docs/prescription.md § "circuit").
//
// Cursor semantics (v1, round-robin within rounds):
//   - `cursor.blockIndex` — which block the user is on.
//   - `cursor.itemIndex` — which station of the circuit (0..N-1).
//   - `cursor.setIndex`  — 1-based round counter (1..block.rounds).
//
// The reducer walks item 0 → item 1 → ... → item N-1 within a round,
// then bumps setIndex and restarts at item 0. The seeder mirrors this by
// seeding `setsPerItem[b][i] == block.rounds` for every item in the
// block; `itemsPerBlock[b] == N`. That shape is what lets `nextCursor`
// stop and flip to `.complete` at (last item of last round).
//
// Scope of this driver:
//   - `activeContent` resolves the current station's exercise name, reps
//     and load. `setIndex` surfaces the round counter; `totalSets` is
//     `block.rounds` (so the Active screen renders "round N of M").
//   - `restDuration` differentiates between two rest windows per spec:
//       * After the last item of a non-last round → `rest_between_rounds_sec`.
//       * After any other item within a round → `rest_between_exercises_sec`.
//     The view model routes to `.complete` after the last item of the
//     last round, so we never need to invent a third case — the driver
//     defensively returns `rest_between_exercises_sec` there.
//   - `onSetLogged` returns an empty outcome. Circuit is movement-based;
//     the spec permits autoreg but notes it is "typically unused" —
//     v1 keeps autoreg off for circuit (see docs/prescription.md §
//     "When autoreg applies").

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct CircuitDriver: TimingDriver {

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

    /// Return the longer between-rounds rest after the last item of a
    /// non-last round; otherwise the (typically zero) between-exercises
    /// rest. Malformed / missing config → 0 (matches every other driver's
    /// parse-failure fallback).
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
            guard case .circuit(let rbe, let rbr) = config else { return 0 }
            let itemsInBlock = itemsInCurrentBlock(state: state)
            let isLastItem = c.itemIndex + 1 == itemsInBlock
            let totalRounds = block.rounds ?? 1
            let isLastRound = c.setIndex >= totalRounds
            // Last item of a non-last round → between-rounds rest.
            // Anywhere else (mid-round, or last item of last round — the
            // VM flips to .complete before this matters) → between-
            // exercises rest.
            if isLastItem && !isLastRound {
                return rbr
            }
            return rbe
        case .failure:
            return 0
        }
    }

    // MARK: - Log outcome

    /// Circuit has no autoreg in v1 — the driver never proposes a change.
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

    /// Extract prescribed reps + load from a circuit station's prescription.
    /// Circuit stations author as `{reps, load_kg?}` (weighted or BW) or
    /// `{reps: "amrap"}` (open-ended at this station). Unknown shapes
    /// collapse to (0, nil) rather than crashing.
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
