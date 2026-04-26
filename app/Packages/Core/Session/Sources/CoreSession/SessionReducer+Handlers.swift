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
            compositeSets: [],
            restEndsAt: nil,
            blockEndsAt: nil,
            workEndsAt: nil,
            intervalAnchorAt: nil,
            note: "",
            structure: freshStructure
        )
    }

    static func applyLogSet(
        state: SessionState,
        input: LogSetInput
    ) -> SessionState {
        // `startedAt` is the working-set start instant: when the previous
        // rest ended (or when the session started, for the very first
        // set). We read it from `state.workStartedAt` — set by the view
        // model on `.start` and rest-end via direct state mutation.
        // Falling back to the existing `old.startedAt` preserves previously-
        // stamped values (important for cardio drivers that stamp it on
        // `.logCardioSet` and for defensive re-logs); nil in the rare
        // pathological case where no anchor is available (better than
        // folding rest into set time — see file header).
        let resolvedStart = state.workStartedAt
        var next = updateSet(in: state, itemID: input.itemID, setIndex: input.setIndex) { old in
            // `logSet` is always marked done, regardless of prior state.
            // rir may be nil (user skipped the picker); reps overwrites
            // the prescribed value with the observed. `completedAt` is
            // stamped with the caller's `now` — the Features layer passes
            // its injected clock. Subsequent corrective edits (editPastSet)
            // preserve the original timestamp rather than overwriting it;
            // fixing the time would rewrite the workout timeline, which
            // corrective edits must not do.
            //
            // `startedAt` is stamped from `state.workStartedAt` — the
            // wall-clock instant the previous rest ended. Chaining via the
            // previous set's `completedAt` would fold rest time INTO the
            // set's duration (a 10s bench press with 90s rest would look
            // like a 100s set), which is semantically wrong for working-
            // time analysis. See `SessionState.workStartedAt`.
            //
            // Cardio fields are carried through unchanged — the strength
            // log path leaves them nil. Cardio drivers dispatch
            // `.logCardioSet` instead, which stamps those columns.
            SetPlan(
                setIndex: old.setIndex,
                loadKg: old.loadKg,
                unit: old.unit,
                reps: input.loggedReps,
                workTarget: old.workTarget,
                done: true,
                adjust: old.adjust,
                rir: input.loggedRir,
                completedAt: input.now,
                durationSec: old.durationSec,
                distanceM: old.distanceM,
                hrAvgBpm: old.hrAvgBpm,
                cadenceAvgSpm: old.cadenceAvgSpm,
                startedAt: resolvedStart ?? old.startedAt,
                skipped: false,
                side: old.side
            )
        }
        // Consume the anchor: the set has been logged, so the next set's
        // `startedAt` must be freshly stamped by `.advanceFromRest` (or
        // the VM's equivalent entry helper). Clearing here makes "missing
        // anchor" visible instead of silently reusing a stale one across
        // sets.
        next.workStartedAt = nil
        return next
    }

    static func applySkipSet(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        now: Date
    ) -> SessionState {
        var next = updateSet(in: state, itemID: itemID, setIndex: setIndex) { old in
            SetPlan(
                setIndex: old.setIndex,
                loadKg: old.loadKg,
                unit: old.unit,
                reps: old.reps,
                workTarget: old.workTarget,
                done: true,
                adjust: old.adjust,
                rir: nil,
                completedAt: now,
                durationSec: nil,
                distanceM: nil,
                hrAvgBpm: nil,
                cadenceAvgSpm: nil,
                startedAt: state.workStartedAt ?? old.startedAt,
                skipped: true,
                side: old.side
            )
        }
        next.compositeSets.removeAll {
            $0.itemID == itemID && $0.setIndex == setIndex
        }
        next.workStartedAt = nil
        next.workReadyAt = nil
        return next
    }

    static func applyStartCompositeSlot(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        slotIndex: Int,
        startedAt: Date
    ) -> SessionState {
        guard let idx = state.compositeSets.firstIndex(where: {
            $0.itemID == itemID && $0.setIndex == setIndex
        }) else {
            return state
        }
        var next = state
        var progress = next.compositeSets[idx]
        let safeSlot = min(max(slotIndex, 1), progress.slotCount)
        progress.phase = .working(slotIndex: safeSlot, startedAt: startedAt)
        if progress.firstStartedAt == nil {
            progress.firstStartedAt = startedAt
        }
        next.compositeSets[idx] = progress
        next.workStartedAt = startedAt
        next.workReadyAt = nil
        return next
    }

    static func applyCompleteCompositeSlot(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        now: Date
    ) -> SessionState {
        guard let idx = state.compositeSets.firstIndex(where: {
            $0.itemID == itemID && $0.setIndex == setIndex
        }) else {
            return state
        }
        var next = state
        var progress = next.compositeSets[idx]
        let currentSlot: Int
        switch progress.phase {
        case .working(let slotIndex, _):
            currentSlot = slotIndex
        case .ready(let slotIndex):
            currentSlot = slotIndex
        case .intraRest, .completePendingLog:
            return state
        }
        progress.completedSlots = max(progress.completedSlots, currentSlot)
        if currentSlot >= progress.slotCount {
            progress.phase = .completePendingLog
        } else {
            progress.phase = .intraRest(
                afterSlotIndex: currentSlot,
                endsAt: now.addingTimeInterval(progress.intraRestSec)
            )
        }
        next.compositeSets[idx] = progress
        next.workStartedAt = nil
        next.workReadyAt = currentSlot >= progress.slotCount ? nil : now
        return next
    }

    static func applyFinalizeCompositeSet(
        state: SessionState,
        input: LogSetInput
    ) -> SessionState {
        guard let progressIdx = state.compositeSets.firstIndex(where: {
            $0.itemID == input.itemID && $0.setIndex == input.setIndex
        }) else {
            return applyLogSet(state: state, input: input)
        }
        let progress = state.compositeSets[progressIdx]
        let startedAt = progress.firstStartedAt ?? state.workStartedAt
        let durationSec = startedAt.map { max(0, input.now.timeIntervalSince($0)) }
        var next = updateSet(in: state, itemID: input.itemID, setIndex: input.setIndex) { old in
            SetPlan(
                setIndex: old.setIndex,
                loadKg: old.loadKg,
                unit: old.unit,
                reps: input.loggedReps,
                workTarget: old.workTarget,
                done: true,
                adjust: old.adjust,
                rir: input.loggedRir,
                completedAt: input.now,
                durationSec: durationSec,
                distanceM: old.distanceM,
                hrAvgBpm: old.hrAvgBpm,
                cadenceAvgSpm: old.cadenceAvgSpm,
                startedAt: startedAt ?? old.startedAt,
                skipped: false,
                side: old.side
            )
        }
        next.compositeSets.removeAll {
            $0.itemID == input.itemID && $0.setIndex == input.setIndex
        }
        next.workStartedAt = nil
        next.workReadyAt = nil
        return next
    }

    static func applyLogCardioSet(
        state: SessionState,
        input: LogCardioSetInput
    ) -> SessionState {
        var next = updateSet(in: state, itemID: input.itemID, setIndex: input.setIndex) { old in
            // Cardio log path. Stamps duration / distance / HR / cadence
            // on the SetPlan plus `done=true` and `completedAt=now`.
            // `reps` is set to 0 — cardio intervals carry no reps, but
            // SetPlan.reps is non-optional (it's load-bearing for
            // strength logging). The push path reads 0 and emits a
            // SetLog with reps=nil when the driver is cardio (see the
            // +Push extension's `enqueueLoggedCardioSet`).
            //
            // `startedAt` is passed through explicitly so cardio logs
            // carry the real start instant for the interval (cardio
            // drivers know it at log time). Falls back to
            // `state.workStartedAt` when the driver omits it, so cardio
            // paths inherit the same rest-end anchor strength uses.
            SetPlan(
                setIndex: old.setIndex,
                loadKg: old.loadKg,
                unit: old.unit,
                reps: 0,
                workTarget: old.workTarget,
                done: true,
                adjust: old.adjust,
                rir: nil,
                completedAt: input.now,
                durationSec: input.durationSec,
                distanceM: input.distanceM,
                hrAvgBpm: input.hrAvgBpm,
                cadenceAvgSpm: input.cadenceAvgSpm,
                startedAt: input.startedAt ?? state.workStartedAt,
                skipped: false,
                side: old.side
            )
        }
        // Consume the anchor — same rationale as applyLogSet.
        next.workStartedAt = nil
        return next
    }

    static func applyEditPendingSet(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?,
        rir: Int?,
        startedAt: Date?
    ) -> SessionState {
        updateSet(in: state, itemID: itemID, setIndex: setIndex) { old in
            // Only applies to non-done sets. If the set has been logged
            // already, the edit is silently dropped — the caller should
            // have dispatched `.editPastSet` instead.
            guard !old.done else { return old }
            return SetPlan(
                setIndex: old.setIndex,
                loadKg: loadKg ?? old.loadKg,
                unit: old.unit,
                reps: reps ?? old.reps,
                workTarget: old.workTarget,
                done: old.done,
                adjust: .manual,
                rir: rir ?? old.rir,
                durationSec: old.durationSec,
                distanceM: old.distanceM,
                hrAvgBpm: old.hrAvgBpm,
                cadenceAvgSpm: old.cadenceAvgSpm,
                startedAt: startedAt ?? old.startedAt,
                skipped: old.skipped,
                side: old.side
            )
        }
    }

    static func applyMarkPendingSetStarted(
        state: SessionState,
        itemID: WorkoutItemID,
        setIndex: Int,
        startedAt: Date
    ) -> SessionState {
        updateSet(in: state, itemID: itemID, setIndex: setIndex) { old in
            guard !old.done else { return old }
            return SetPlan(
                setIndex: old.setIndex,
                loadKg: old.loadKg,
                unit: old.unit,
                reps: old.reps,
                workTarget: old.workTarget,
                done: old.done,
                adjust: old.adjust,
                rir: old.rir,
                durationSec: old.durationSec,
                distanceM: old.distanceM,
                hrAvgBpm: old.hrAvgBpm,
                cadenceAvgSpm: old.cadenceAvgSpm,
                startedAt: startedAt,
                skipped: old.skipped,
                side: old.side
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
            // `completedAt` is preserved — a corrective edit fixes
            // reps/rir/load, not the wall-clock time the set happened.
            // Cardio fields are carried through unchanged — past-set edit
            // is the strength corrective path and doesn't mutate cardio
            // measurements.
            return SetPlan(
                setIndex: old.setIndex,
                loadKg: edit.loadKg ?? old.loadKg,
                unit: old.unit,
                reps: edit.reps ?? old.reps,
                workTarget: old.workTarget,
                done: old.done,
                adjust: .manual,
                rir: edit.rir ?? old.rir,
                completedAt: old.completedAt,
                durationSec: old.durationSec,
                distanceM: old.distanceM,
                hrAvgBpm: old.hrAvgBpm,
                cadenceAvgSpm: old.cadenceAvgSpm,
                startedAt: old.startedAt,
                skipped: old.skipped,
                side: old.side
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
        // Store overrides on the ItemLog. `target_rir` / `per_side` /
        // `autoreg` cannot live on SetPlan and are read by drivers from
        // here; reps/load also live here (for history / persistence) and
        // are mirrored onto remaining non-done SetPlan rows below so the
        // Active screen renders them. A `sets` override adjusts the non-
        // done tail — extending seeds new rows at the override values,
        // truncating drops pending rows that would otherwise sit past the
        // new end of the item.
        //
        // `sets`-override scope: ONLY set-major blocks honor the override.
        // Round-robin/unbounded-target blocks (superset / circuit / AMRAP /
        // EMOM / Tabata / forTime / accumulate) replicate a single `rounds`
        // count across every item or use target completion rather than row count;
        // rewriting one item's row count would either skew the cursor walk
        // (rows past the block's rounds never run) or implicitly collapse
        // every item to the new count (silently corrupting the other
        // items' plans). The semantics are ambiguous, so we drop the
        // `sets` portion and apply the rest of the override. Documented
        // in `docs/prescription.md` § "Alternative prescription (overrides)"
        // and `docs/features/exercise-swap.md` § "Known issues / gaps".
        if let overrides, !overrides.isEmpty {
            let compositeRows = next.compositeSets.filter { $0.itemID == itemID }
            let compositeSlotCount = compositeRows.first?.slotCount
            let compositeRepsPerSlot = compositeSlotCount == nil ? nil : overrides.reps
            let runtimeOverrides: AlternativeOverrides
            if let reps = overrides.reps, let slotCount = compositeSlotCount {
                runtimeOverrides = AlternativeOverrides(
                    sets: overrides.sets,
                    reps: reps * slotCount,
                    loadKg: overrides.loadKg,
                    unit: overrides.unit,
                    targetRir: overrides.targetRir,
                    perSide: overrides.perSide,
                    autoreg: overrides.autoreg
                )
            } else {
                runtimeOverrides = overrides
            }
            let position = findBlockItemPosition(flatIndex: idx, in: state.structure)
            let blockAdvancement = position.flatMap { pos -> SessionState.BlockAdvancement? in
                guard pos.blockIndex < state.structure.advancementByBlock.count else { return nil }
                return state.structure.advancementByBlock[pos.blockIndex]
            }
            let allowSetsResize = (blockAdvancement ?? .setMajor) == .setMajor
            next.items[idx].overrides = overrides
            next.items[idx].sets = applyOverridesToSetPlans(
                next.items[idx].sets,
                overrides: runtimeOverrides,
                allowSetsResize: allowSetsResize
            )
            if allowSetsResize || compositeRepsPerSlot != nil {
                next.compositeSets = syncCompositeProgress(
                    next.compositeSets,
                    itemID: itemID,
                    setPlans: next.items[idx].sets,
                    targetRepsPerSlot: compositeRepsPerSlot
                )
            }
            if allowSetsResize,
               let newSetsCount = overrides.sets,
               let (blockIndex, itemInBlock) = position {
                next.structure = updatingSetsPerItem(
                    state.structure,
                    blockIndex: blockIndex,
                    itemInBlock: itemInBlock,
                    newCount: max(newSetsCount, next.items[idx].sets.count)
                )
            }
        } else {
            next.items[idx].overrides = nil
        }
        // Do NOT reset autoregHeld: the hold is session-scoped by design.
        // docs/prescription.md § "Hold scope".
        return next
    }

    private static func syncCompositeProgress(
        _ progress: [SessionState.CompositeSetProgress],
        itemID: WorkoutItemID,
        setPlans: [SetPlan],
        targetRepsPerSlot: Int?
    ) -> [SessionState.CompositeSetProgress] {
        let validSetIndices = Set(setPlans.map(\.setIndex))
        let existingForItem = progress.filter { $0.itemID == itemID }
        var next = progress.compactMap { row -> SessionState.CompositeSetProgress? in
            guard row.itemID == itemID else { return row }
            guard validSetIndices.contains(row.setIndex) else { return nil }
            guard let targetRepsPerSlot else { return row }
            let matchingSet = setPlans.first { $0.setIndex == row.setIndex }
            if matchingSet?.done == true || matchingSet?.adjust == .manual {
                return row
            }
            return SessionState.CompositeSetProgress(
                itemID: row.itemID,
                setIndex: row.setIndex,
                kind: row.kind,
                targetRepsPerSlot: targetRepsPerSlot,
                slotCount: row.slotCount,
                intraRestSec: row.intraRestSec,
                firstStartedAt: row.firstStartedAt,
                phase: row.phase,
                completedSlots: row.completedSlots
            )
        }
        guard let template = existingForItem.sorted(by: { $0.setIndex < $1.setIndex }).last else {
            return next
        }
        let templateRepsPerSlot = targetRepsPerSlot ?? template.targetRepsPerSlot
        var existingSetIndices = Set(next.filter { $0.itemID == itemID }.map { $0.setIndex })
        let missingPendingSets = setPlans
            .filter { !$0.done && !existingSetIndices.contains($0.setIndex) }
            .sorted { $0.setIndex < $1.setIndex }
        for set in missingPendingSets {
            next.append(
                SessionState.CompositeSetProgress(
                    itemID: itemID,
                    setIndex: set.setIndex,
                    kind: template.kind,
                    targetRepsPerSlot: templateRepsPerSlot,
                    slotCount: template.slotCount,
                    intraRestSec: template.intraRestSec
                )
            )
            existingSetIndices.insert(set.setIndex)
        }
        return next
    }

    // swap-related helpers (applyOverridesToSetPlans, resizedSetPlans,
    // findBlockItemPosition, updatingSetsPerItem) live in
    // `SessionReducer+SwapOverrides.swift` so neither this file nor the
    // swap helpers exceed SwiftLint's `file_length` cap.

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
                next.intervalAnchorAt = nil
            }
            next.cursor = nextCursor
            next.route = .active
            return next
        }

        // Last set of last item of last block → complete.
        next.blockEndsAt = nil
        next.workEndsAt = nil
        next.intervalAnchorAt = nil
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
