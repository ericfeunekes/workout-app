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
        // reducer). `set.loadKg == nil` is the loadless sentinel — a
        // bodyweight row, a loadless AMRAP token, or a `.empty`
        // placeholder. `formatLoad(weight: nil, ...)` renders "BW" for
        // those; numeric rows render through the unit-aware formatter.
        let loadDisplay = formatLoad(
            weight: set.loadKg,
            unit: LoadUnit(setPlanUnit: set.unit)
        )

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: set.setIndex,
            totalSets: itemLog.sets.count,
            loadDisplay: loadDisplay,
            repsDisplay: displayText(for: set),
            loadKg: set.loadKg,
            reps: set.reps,
            adjustGlyph: set.adjust,
            lastTime: context.lastPerformed[item.exerciseID],
            kind: activeKind(for: set)
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
        guard let itemLog = state.items.first(where: { $0.itemID == event.itemID }),
              let item = findItem(id: event.itemID, in: context),
              let prescribed = prescribed(for: item, setIndex: event.setIndex, in: itemLog)
        else {
            return DriverLogOutcome()
        }
        // No autoreg for loadless sets — autoreg proposes numeric kg
        // adjustments, which have no meaning for a BW row. Matches
        // `Autoreg.apply` which also skips nil-load rows.
        guard let prescribedLoadKg = prescribed.loadKg,
              let (autoreg, target) = resolveAutoreg(item: item, itemLog: itemLog)
        else {
            return DriverLogOutcome()
        }
        // Don't propose on the last set of the item — there are no
        // remaining sets to adjust. This mirrors the JSX prototype
        // (`hasRemaining = si + 1 < block.sets`).
        let remaining = itemLog.sets.contains {
            !$0.done && $0.setIndex > event.setIndex
        }
        guard remaining else { return DriverLogOutcome() }

        let proposal = Autoreg.propose(Autoreg.Input(
            prescribedLoadKg: prescribedLoadKg,
            prescribedReps: prescribed.reps,
            loggedReps: event.loggedReps,
            loggedRir: event.loggedRir,
            targetRir: target,
            autoreg: autoreg,
            autoregHeld: itemLog.autoregHeld
        ))

        return DriverLogOutcome(proposal: proposal)
    }

    /// Pull the autoreg config + resolved target RIR for an item.
    /// Returns nil when the prescription carries neither (so the caller
    /// skips proposing). An alternative swap may have shadowed
    /// `target_rir`; the override wins when present — fall back to the
    /// prescription's authored target otherwise.
    private func resolveAutoreg(
        item: WorkoutItem,
        itemLog: SessionState.ItemLog
    ) -> (CorePrescription.Autoreg, Int)? {
        let autoregConfig: CorePrescription.Autoreg?
        let parsedTargetRir: Int?
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            (autoregConfig, parsedTargetRir) = autoregAndTarget(from: p)
        case .failure:
            return nil
        }
        let resolvedTargetRir = itemLog.overrides?.targetRir ?? parsedTargetRir
        guard let autoreg = autoregConfig, let target = resolvedTargetRir else {
            return nil
        }
        return (autoreg, target)
    }

    // MARK: - Helpers

    private func prescribed(
        for item: WorkoutItem,
        setIndex: Int,
        in itemLog: SessionState.ItemLog
    ) -> (loadKg: Double?, reps: Int)? {
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
    ///
    /// Only shapes with a single uniform top-level `{reps, load}` plan may propose:
    /// `straight_sets`, `rep_range`, and top-level `cluster`. Per `docs/autoreg.md` S17, shapes
    /// that author per-set variation (`sets_detail` pyramid / warm-up /
    /// cluster drops) already encode the author's intended load trajectory
    /// — a flat autoreg adjustment against the first set's load would
    /// silently overwrite the pyramid's authored set-2+ targets. Cluster
    /// proposes only after the top-level composed set logs; sub-slots never
    /// trigger autoreg. Same reasoning applies to `percent_of_1rm`
    /// (resolver-derived, not yet wired), bodyweight/warmup (loadless),
    /// amrap_token (open-entry), and `.empty` (placeholder). qa-044: the
    /// earlier `.setsDetail` branch returned `(autoreg, target)` and
    /// collided with authored pyramid loads — now returns `(nil, nil)`
    /// so `onSetLogged` bails out before calling `Autoreg.propose`.
    private func autoregAndTarget(
        from prescription: Prescription
    ) -> (CorePrescription.Autoreg?, Int?) {
        switch prescription {
        case .straightSets(_, _, _, _, let target, let autoreg, _, _):
            return (autoreg, target)
        case .repRange(_, _, _, _, _, let target, let autoreg):
            return (autoreg, target)
        case .cluster(_, _, _, _, _, _, let target, let autoreg):
            return (autoreg, target)
        case .setsDetail, .percentOf1RM, .amrapToken, .bodyweight, .warmup, .empty:
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
