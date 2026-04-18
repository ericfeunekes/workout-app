// TabataDriver.swift
//
// TimingDriver for `timing_mode = tabata` — the fixed 8-round, 20-seconds-
// work / 10-seconds-rest protocol. Per `docs/prescription.md` § "tabata",
// the configuration is locked by spec: `timing_config_json = {}` and the
// 20/10/8 constants are part of the definition, NOT authored values. The
// parser returns `.tabata` unconditionally for this mode (see
// `CorePrescription/TimingConfig.swift` § `.tabata`).
//
// Scope of this driver:
//   - `restDuration` returns 10 seconds, hardcoded. Tabata rest is ALWAYS
//     10s between rounds. The 20s "work" interval is not a rest — it is
//     the active-screen phase during which the user is executing reps.
//     Ticking the 20s work window is the view model / reducer's job; the
//     driver only answers "how long is rest after this round".
//   - `activeContent` renders the current round's item. `setIndex` =
//     round number (1..8); `totalSets` = 8. For multi-item tabata blocks
//     the driver alternates per round (round 1 → items[0], round 2 →
//     items[1], round 3 → items[0], ...). Single-item tabatas (the usual
//     case) collapse to the same item every round.
//   - `onSetLogged` returns an empty outcome. Tabata has no autoreg
//     (spec explicitly excludes it); no proposal ever fires.
//
// Hardcoded constants live here as private `let`s; they intentionally are
// NOT read from `timing_config_json`. Authors cannot change them — the
// spec forbids it, and reading the JSON would invite drift.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct TabataDriver: TimingDriver {

    /// Work-phase duration per round. Hardcoded per `docs/prescription.md`
    /// § "tabata" — "Fixed 8 rounds of 20s work / 10s rest. Configuration
    /// locked." Not read from `timing_config_json`.
    public static let workSec: TimeInterval = 20

    /// Rest-phase duration per round. Hardcoded per the same spec section.
    public static let restSec: TimeInterval = 10

    /// Total rounds in a tabata block. Hardcoded per the same spec section.
    public static let rounds: Int = 8

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    /// Resolve the active item for the current round. When the block has
    /// multiple items they alternate per round in listed order —
    /// `items[(roundIndex) % items.count]` — so a two-item tabata walks
    /// A, B, A, B, ... over the 8 rounds.
    ///
    /// `setIndex` on the returned content is the 1-based round counter
    /// (1...rounds). `totalSets` is the hardcoded `rounds` constant so the
    /// Active screen renders "round N of 8" without consulting the
    /// `SessionState.structure` (which carries the seeded SetPlan count,
    /// not the tabata round total).
    public func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent? {
        let c = state.cursor
        guard c.blockIndex < context.itemsByBlock.count else { return nil }
        let blockItems = context.itemsByBlock[c.blockIndex]
        guard !blockItems.isEmpty else { return nil }

        // Cursor's setIndex is 1-based and carries the round number.
        // Defensive range check — a cursor beyond `rounds` is out of range
        // for this block and the view model should have flipped to
        // `.complete`. Return nil so ActiveView renders its empty state.
        let round = c.setIndex
        guard round >= 1, round <= TabataDriver.rounds else { return nil }

        // Round-to-item mapping: round N (1-based) → items[(N-1) % count].
        // Single-item blocks collapse to index 0 every round.
        let itemIdx = (round - 1) % blockItems.count
        let item = blockItems[itemIdx]

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

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: round,
            totalSets: TabataDriver.rounds,
            loadDisplay: loadDisplay,
            repsDisplay: String(reps),
            loadKg: heroLoadKg,
            reps: reps,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// Tabata rest is always 10 seconds — regardless of
    /// `timing_config_json` contents, regardless of parse outcome, and
    /// regardless of which round just finished. Per spec the config blob
    /// is `{}` and the 10-second value is part of the protocol definition.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        TabataDriver.restSec
    }

    // MARK: - Log outcome

    /// No autoreg on tabata (per `docs/prescription.md` § "tabata"). The
    /// driver never proposes a change regardless of the logged reps/RIR.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Extract the prescribed rep count and optional load_kg from a tabata
    /// item's prescription. Tabata items typically author as
    /// `{"reps": N, "load_kg": kg?}` (parses as `.straightSets` with
    /// `sets: nil`) or `{"reps": N}` bodyweight. Mirrors the tolerant
    /// extraction in AMRAPDriver so renders stay coherent across modes.
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
