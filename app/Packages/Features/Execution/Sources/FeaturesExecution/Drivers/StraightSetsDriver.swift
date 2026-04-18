// StraightSetsDriver.swift
//
// TimingDriver conformance for `timing_mode = straight_sets` — the only
// mode wired up in v0. Handles the straight-sets behavior described in
// `docs/design/src/hifi.jsx` § "Active set screen" and the rest screen.
//
// The driver resolves three things from the raw JSON blobs:
//   - Active content: the exercise name, set counter, load/reps displays.
//   - Rest duration: from the block's `timing_config_json`
//     (`rest_between_sets_sec`; `rest_between_exercises_sec` kicks in on
//     the last set of an item).
//   - Autoreg outcome: runs `Autoreg.propose` against the just-logged
//     set (honors `autoregHeld`) and returns the proposal. The view model
//     dispatches `.applyAutoregProposal` on Accept (default) and
//     `.holdAutoreg` on Undo.
//
// Behavior that lives here (and only here) because it's straight-sets-
// specific, per HS-2:
//   - The distinction between "rest between sets" and "rest between
//     exercises" — only straight_sets exposes both.
//   - The last-time chip derivation from `context.lastPerformed`.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct StraightSetsDriver: TimingDriver {

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
        guard let set = itemLog.sets.first(where: { $0.setIndex == c.setIndex }) else {
            return nil
        }

        // Honor swap override when resolving the display name.
        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

        // The load in the display honors whatever the session state has
        // for this set (which reflects autoreg/manual edits via the
        // reducer). Bodyweight cases come through as `loadKg == 0`
        // here — straight_sets items that are truly bodyweight are
        // discriminated as `.bodyweight` and render via the same driver
        // with the "BW" sentinel in SetPlan seeding. The seeding choice
        // lives in `SessionSeeder` below.
        let loadDisplay: String = {
            // The SetPlan stores 0 for bodyweight-only rows (see
            // `SessionSeeder`); render as plain "BW" in that case.
            if set.loadKg == 0 && isBodyweightItem(item) {
                return "BW"
            }
            return formatLoad(kg: set.loadKg)
        }()

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: set.setIndex,
            totalSets: itemLog.sets.count,
            loadDisplay: loadDisplay,
            repsDisplay: String(set.reps),
            loadKg: set.loadKg == 0 && isBodyweightItem(item) ? nil : set.loadKg,
            reps: set.reps,
            adjustGlyph: set.adjust,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else { return 0 }

        // Default to between-sets rest. If this is the last set of the
        // current item and there's another item in the block, use the
        // longer between-exercises rest instead. If this is the last
        // set of the last item of the block, the view model is about to
        // flip the route to `.active` on the next block (or `.complete`
        // if none) — we still return the between-exercises value since
        // the user's muscles don't know about block boundaries.
        let itemCount = context.itemsByBlock[safe: c.blockIndex]?.count ?? 0
        let isLastSetOfItem = isLastSetOfCurrentItem(state: state)
        let nextItemExists = c.itemIndex + 1 < itemCount

        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            guard case .straightSets(let rbs, let rbe) = config else { return rbs(from: config) }
            if isLastSetOfItem && nextItemExists {
                return rbe
            }
            return rbs
        case .failure:
            return 0
        }
    }

    // MARK: - Log outcome

    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        let itemID = event.itemID
        let setIndex = event.setIndex
        let loggedReps = event.loggedReps
        let loggedRir = event.loggedRir
        guard let itemLog = state.items.first(where: { $0.itemID == itemID }) else {
            return DriverLogOutcome()
        }
        // Resolve the item via cursor — the itemID we got should match
        // the cursor position in normal flow, but we walk the context to
        // find the authored prescription either way.
        guard
            let item = findItem(id: itemID, in: context),
            let prescribed = prescribed(for: item, setIndex: setIndex, in: itemLog)
        else {
            return DriverLogOutcome()
        }

        // Pull autoreg config + target RIR from the item's prescription.
        let autoregConfig: CorePrescription.Autoreg?
        let parsedTargetRir: Int?
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            (autoregConfig, parsedTargetRir) = autoregAndTarget(from: p)
        case .failure:
            autoregConfig = nil
            parsedTargetRir = nil
        }

        // An alternative swap may have shadowed `target_rir`. The override
        // wins when present (the user swapped to a movement Claude rated
        // at a different stimulus); fall back to the prescription's
        // authored target otherwise.
        let resolvedTargetRir = itemLog.overrides?.targetRir ?? parsedTargetRir

        guard let autoreg = autoregConfig, let target = resolvedTargetRir else {
            return DriverLogOutcome()
        }

        // Don't propose on the last set of the item — there are no
        // remaining sets to adjust. This mirrors the JSX prototype
        // (`hasRemaining = si + 1 < block.sets`).
        let remaining = itemLog.sets.contains(where: { !$0.done && $0.setIndex > setIndex })
        guard remaining else {
            return DriverLogOutcome()
        }

        let proposal = Autoreg.propose(Autoreg.Input(
            prescribedLoadKg: prescribed.loadKg,
            prescribedReps: prescribed.reps,
            loggedReps: loggedReps,
            loggedRir: loggedRir,
            targetRir: target,
            autoreg: autoreg,
            autoregHeld: itemLog.autoregHeld
        ))

        return DriverLogOutcome(proposal: proposal)
    }

    // MARK: - Helpers

    private func prescribed(
        for item: WorkoutItem,
        setIndex: Int,
        in itemLog: SessionState.ItemLog
    ) -> (loadKg: Double, reps: Int)? {
        guard let set = itemLog.sets.first(where: { $0.setIndex == setIndex }) else {
            return nil
        }
        return (set.loadKg, set.reps)
    }

    private func findItem(id: UUID, in context: WorkoutContext) -> WorkoutItem? {
        for row in context.itemsByBlock {
            if let hit = row.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    /// Pull `autoreg` config + the resolved `target_rir` out of a
    /// parsed Prescription, for the straight-sets-adjacent shapes that
    /// may carry them.
    private func autoregAndTarget(
        from prescription: Prescription
    ) -> (CorePrescription.Autoreg?, Int?) {
        switch prescription {
        case .straightSets(_, _, _, let target, let autoreg, _, _):
            return (autoreg, target)
        case .repRange(_, _, _, _, let target, let autoreg):
            return (autoreg, target)
        case .setsDetail(_, let target, let autoreg):
            return (autoreg, target)
        case .percentOf1RM, .cluster, .amrapToken, .bodyweight, .warmup, .empty:
            return (nil, nil)
        }
    }

    private func isLastSetOfCurrentItem(state: SessionState) -> Bool {
        let c = state.cursor
        guard c.blockIndex < state.structure.setsPerItem.count else { return false }
        let perItem = state.structure.setsPerItem[c.blockIndex]
        guard c.itemIndex < perItem.count else { return false }
        return c.setIndex >= perItem[c.itemIndex]
    }

    /// `{sets, reps}` with no `load_kg` discriminates as `.bodyweight`
    /// in the parser. The SetPlan row carries `loadKg = 0` for these
    /// (see `SessionSeeder`) — we render "BW" at the display layer.
    private func isBodyweightItem(_ item: WorkoutItem) -> Bool {
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(.bodyweight):
            return true
        default:
            return false
        }
    }
}

// MARK: - Utilities

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Fallback that should never trigger — the caller's switch already
/// matched `.straightSets`. Present only so the outer switch compiles
/// without a spurious `@unknown` branch on future mode additions.
private func rbs(from _: TimingConfig) -> TimeInterval { 0 }
