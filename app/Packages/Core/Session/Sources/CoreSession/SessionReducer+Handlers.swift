// SessionReducer+Handlers.swift
//
// Per-mutation handlers and the cursor-advance helpers, split out of
// `SessionReducer.swift` so the parent enum stays under SwiftLint's
// `type_body_length` cap. Pure functions only — no I/O, no state outside
// the arguments.

import Foundation
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

extension SessionReducer {

    // MARK: - Save / log / edit

    static func applySave(
        state: SessionState,
        freshItems: [SessionState.ItemLog],
        freshStructure: SessionState.Structure
    ) -> SessionState {
        // Return a pristine state derived from the caller's seed.
        // workoutID is preserved — the Features layer decides whether
        // to swap state entirely for the next workout or keep this
        // one as the "Today" card.
        SessionState(
            workoutID: state.workoutID,
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: freshItems,
            restEndsAt: nil,
            blockEndsAt: nil,
            workEndsAt: nil,
            note: "",
            structure: freshStructure
        )
    }

    static func applyLogSet(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        loggedReps: Int,
        loggedRir: Int?
    ) -> SessionState {
        updateSet(in: state, itemID: itemID, setIndex: setIndex) { old in
            // `logSet` is always marked done, regardless of prior state.
            // rir may be nil (user skipped the picker); reps overwrites
            // the prescribed value with the observed.
            SetPlan(
                setIndex: old.setIndex,
                loadKg: old.loadKg,
                reps: loggedReps,
                done: true,
                adjust: old.adjust,
                rir: loggedRir
            )
        }
    }

    static func applyEditPendingSet(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?
    ) -> SessionState {
        updateSet(in: state, itemID: itemID, setIndex: setIndex) { old in
            // Only applies to non-done sets. If the set has been logged
            // already, the edit is silently dropped — the caller should
            // have dispatched `.editPastSet` instead.
            guard !old.done else { return old }
            return SetPlan(
                setIndex: old.setIndex,
                loadKg: loadKg ?? old.loadKg,
                reps: reps ?? old.reps,
                done: old.done,
                adjust: .manual,
                rir: old.rir
            )
        }
    }

    static func applyEditPastSet(
        state: SessionState,
        edit: PastSetEdit
    ) -> SessionState {
        updateSet(in: state, itemID: edit.itemID, setIndex: edit.setIndex) { old in
            // Only applies to done sets. Pending edits should go through
            // `.editPendingSet`.
            guard old.done else { return old }
            // Adjust precedence: a past-set edit always produces `.manual`.
            // Matches docs/prescription.md § "Edits don't retrigger" and
            // § "Autoreg + manual edit · per-set adjust precedence".
            return SetPlan(
                setIndex: old.setIndex,
                loadKg: edit.loadKg ?? old.loadKg,
                reps: edit.reps ?? old.reps,
                done: old.done,
                adjust: .manual,
                rir: edit.rir ?? old.rir
            )
        }
    }

    static func applyAutoregProposal(
        state: SessionState,
        itemID: WorkoutItemID,
        proposal: AutoregProposal
    ) -> SessionState {
        // Delegate to CoreAutoreg. The `apply` function preserves
        // `.manual` and `done` by design. Unknown itemID is a no-op.
        guard let idx = state.items.firstIndex(where: { $0.itemID == itemID }) else {
            return state
        }
        var next = state
        next.items[idx].sets = Autoreg.apply(proposal: proposal, to: next.items[idx].sets)
        return next
    }

    static func applySwap(
        state: SessionState,
        itemID: WorkoutItemID,
        toExerciseID: ExerciseID,
        overrides: AlternativeOverrides?
    ) -> SessionState {
        guard let idx = state.items.firstIndex(where: { $0.itemID == itemID }) else {
            return state
        }
        var next = state
        next.items[idx].performedExerciseID = toExerciseID
        // Store overrides on the ItemLog. `target_rir` cannot live on
        // SetPlan and is read by drivers from here; reps/load also live
        // here (for history / persistence) and are mirrored onto remaining
        // non-done SetPlan rows below so the Active screen renders them.
        if let overrides, !overrides.isEmpty {
            next.items[idx].overrides = overrides
            next.items[idx].sets = applyOverridesToSetPlans(
                next.items[idx].sets,
                overrides: overrides
            )
        } else {
            next.items[idx].overrides = nil
        }
        // Do NOT reset autoregHeld: the hold is session-scoped by design.
        // docs/prescription.md § "Hold scope".
        return next
    }

    /// Mirror `reps` / `load_kg` from `AlternativeOverrides` onto every
    /// non-done, non-manual SetPlan row. A `.manual` row has been
    /// explicitly edited by the user before the swap — we preserve that
    /// choice so the swap doesn't silently undo manual work. Done rows
    /// are history and never touched. `adjust` is left unchanged for the
    /// overridden rows — autoreg is still free to propose against them
    /// in subsequent logs.
    static func applyOverridesToSetPlans(
        _ sets: [SetPlan],
        overrides: AlternativeOverrides
    ) -> [SetPlan] {
        sets.map { set in
            if set.done { return set }
            if set.adjust == .manual { return set }
            let newLoad = overrides.loadKg ?? set.loadKg
            let newReps = overrides.reps ?? set.reps
            if newLoad == set.loadKg && newReps == set.reps { return set }
            return SetPlan(
                setIndex: set.setIndex,
                loadKg: newLoad,
                reps: newReps,
                done: set.done,
                adjust: set.adjust,
                rir: set.rir
            )
        }
    }

    static func applyHoldAutoreg(
        state: SessionState,
        itemID: WorkoutItemID
    ) -> SessionState {
        guard let idx = state.items.firstIndex(where: { $0.itemID == itemID }) else {
            return state
        }
        var next = state
        next.items[idx].autoregHeld = true
        return next
    }

    static func applyAppendNote(
        state: SessionState,
        text: String
    ) -> SessionState {
        guard !text.isEmpty else { return state }
        var next = state
        if next.note.isEmpty {
            next.note = text
        } else {
            next.note = next.note + "\n" + text
        }
        return next
    }

    // MARK: - Cursor helpers

    /// Find an item and a set by (itemID, setIndex), apply a pure update
    /// to the matched SetPlan, and return the resulting state. Returns the
    /// input state unchanged if either lookup fails.
    static func updateSet(
        in state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        transform: (SetPlan) -> SetPlan
    ) -> SessionState {
        guard let itemIdx = state.items.firstIndex(where: { $0.itemID == itemID }) else {
            return state
        }
        guard let setIdx = state.items[itemIdx].sets.firstIndex(where: { $0.setIndex == setIndex }) else {
            return state
        }
        var next = state
        next.items[itemIdx].sets[setIdx] = transform(state.items[itemIdx].sets[setIdx])
        return next
    }

    /// Advance the cursor to the next set / item / block, and set the
    /// route. Clears `restEndsAt`. Used by `.advanceFromRest`.
    ///
    /// Order of advancement:
    ///   1. Per `structure.advancementByBlock[b]` — set-major or round-robin.
    ///   2. Next block, if any. itemIndex → 0, setIndex → 1.
    ///   3. Otherwise: route → .complete, cursor unchanged.
    ///
    /// Zero-item blocks (a standalone `rest` block has `itemsPerBlock[b] == 0`
    /// — see `RestBlockDriver` for the driver-side design) are LANDED on here
    /// with cursor `(b, 0, 1)`. The view model detects the zero-item shape on
    /// arrival and routes to `.rest` with the driver's `restDuration`. This is
    /// the Option A1 cursor model from the driver header: the cursor uses the
    /// sentinel `(b, 0, 1)` for rest blocks; typing stays uniform.
    ///
    /// On block change, `blockEndsAt` and `workEndsAt` are cleared — the VM
    /// re-derives them on block entry via `enterBlockTimerIfNeeded` when the
    /// new block is time-capped (AMRAP, ForTime, EMOM, Tabata). `restEndsAt`
    /// is always cleared.
    static func advanceCursor(from state: SessionState) -> SessionState {
        var next = state
        next.restEndsAt = nil

        if let nextCursor = nextCursor(from: state.cursor, structure: state.structure) {
            if nextCursor.blockIndex != state.cursor.blockIndex {
                next.blockEndsAt = nil
                next.workEndsAt = nil
            }
            next.cursor = nextCursor
            next.route = .active
            return next
        }

        // Last set of last item of last block → complete.
        next.blockEndsAt = nil
        next.workEndsAt = nil
        next.route = .complete
        return next
    }

    /// Compute the cursor position after advancing. Returns `nil` when the
    /// current cursor is the end of the last block, in which case the caller
    /// should transition to `.complete`. Split out of `advanceCursor` so
    /// neither function exceeds SwiftLint's body-length cap.
    ///
    /// Branches on `structure.advancementByBlock[b]`:
    /// * `.setMajor` — walk sets of item 0, then item 1, ... (straight sets).
    /// * `.roundRobin` — within one "round" (one value of `setIndex`), walk
    ///   items 0..N-1; then bump `setIndex` (= round) and restart at item 0.
    ///   Used for circuit, superset, amrap, emom, forTime, tabata.
    /// * `.zeroItem` — landing only; advancing FROM jumps to the next block.
    static func nextCursor(
        from cursor: SessionState.Cursor,
        structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let b = cursor.blockIndex
        let blockCount = structure.itemsPerBlock.count
        guard b < blockCount else { return nil }

        let policy = advancementForBlock(b, in: structure)

        // Advancing FROM a zero-item block: jump straight to the next block.
        // A zero-item block has no sets to walk.
        if policy == .zeroItem || structure.itemsPerBlock[b] == 0 {
            return firstCursorOfNextBlock(after: b, in: structure)
        }

        switch policy {
        case .setMajor:
            return nextCursorSetMajor(from: cursor, structure: structure)
        case .roundRobin:
            return nextCursorRoundRobin(from: cursor, structure: structure)
        case .zeroItem:
            return firstCursorOfNextBlock(after: b, in: structure)
        }
    }

    /// Look up the advancement policy for a block, defensively falling
    /// back to `.setMajor` when the index is out of range (shouldn't
    /// happen in practice — the seeder populates the array fully).
    private static func advancementForBlock(
        _ b: Int,
        in structure: SessionState.Structure
    ) -> SessionState.BlockAdvancement {
        guard b < structure.advancementByBlock.count else { return .setMajor }
        return structure.advancementByBlock[b]
    }

    /// Walk all sets of item 0, then item 1, ... Used for straight sets.
    private static func nextCursorSetMajor(
        from cursor: SessionState.Cursor,
        structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let b = cursor.blockIndex
        let i = cursor.itemIndex
        let s = cursor.setIndex
        guard i < structure.setsPerItem[b].count else { return nil }
        let setsInItem = structure.setsPerItem[b][i]
        let itemsInBlock = structure.itemsPerBlock[b]
        if s < setsInItem {
            return SessionState.Cursor(blockIndex: b, itemIndex: i, setIndex: s + 1)
        }
        if i + 1 < itemsInBlock {
            return SessionState.Cursor(blockIndex: b, itemIndex: i + 1, setIndex: 1)
        }
        return firstCursorOfNextBlock(after: b, in: structure)
    }

    /// Within one round (= setIndex), walk items 0..N-1; then bump
    /// setIndex and restart at item 0. Used for circuit / superset /
    /// amrap / emom / forTime / tabata.
    private static func nextCursorRoundRobin(
        from cursor: SessionState.Cursor,
        structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let b = cursor.blockIndex
        let i = cursor.itemIndex
        let s = cursor.setIndex
        let itemsInBlock = structure.itemsPerBlock[b]
        // All items share the same "rounds" count in round-robin modes —
        // the seeder replicates `block.rounds` across every item.
        guard i < structure.setsPerItem[b].count else { return nil }
        let roundsInBlock = structure.setsPerItem[b][i]
        if i + 1 < itemsInBlock {
            return SessionState.Cursor(blockIndex: b, itemIndex: i + 1, setIndex: s)
        }
        if s < roundsInBlock {
            return SessionState.Cursor(blockIndex: b, itemIndex: 0, setIndex: s + 1)
        }
        return firstCursorOfNextBlock(after: b, in: structure)
    }

    /// Cursor at position (b+1, 0, 1), or nil if no next block.
    private static func firstCursorOfNextBlock(
        after b: Int,
        in structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let nb = b + 1
        if nb < structure.itemsPerBlock.count {
            return SessionState.Cursor(blockIndex: nb, itemIndex: 0, setIndex: 1)
        }
        return nil
    }
}
