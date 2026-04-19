// ExecutionViewModel+Swap.swift
//
// The `swap(itemID:alternativeID:)` intent, split out of
// `ExecutionViewModel.swift` so the class body stays under SwiftLint's
// `type_body_length` cap. See `docs/features/exercise-swap.md` for the
// behavioral contract.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import CoreTelemetry

extension ExecutionViewModel {

    /// Swap the current item to an alternative. Resolves the alternative
    /// from `context.alternatives(for:)`, parses any
    /// `parameter_overrides_json`, and dispatches `.swap` through the
    /// reducer with the parsed overrides. The reducer mirrors reps / load
    /// from the overrides onto the remaining non-done `SetPlan` rows and
    /// stores `target_rir` on `ItemLog.overrides` for the driver's
    /// autoreg path to read.
    ///
    /// Logged (done) sets and the workout template are both preserved by
    /// design — see `docs/features/exercise-swap.md`. Telemetry:
    /// `execution.exercise_swap` carries
    /// `{itemID, fromExerciseID, toExerciseID, hadOverrides}`. When a
    /// `sets` override is authored against a round-robin block (superset /
    /// circuit / AMRAP / EMOM / Tabata / forTime) the reducer drops the
    /// `sets` portion — see `docs/prescription.md` § "Alternative
    /// prescription (overrides)" — and we emit
    /// `execution.swap_sets_override_rejected` so the rejection is visible
    /// in production.
    ///
    /// Unknown `alternativeID` or an itemID with no authored alternatives
    /// is a silent no-op; the long-press UI should not have opened the
    /// sheet in that case, but we guard defensively.
    public func swap(itemID: UUID, alternativeID: UUID) {
        let alts = context.alternatives(for: itemID)
        guard let alt = alts.first(where: { $0.id == alternativeID }) else {
            return
        }
        // A malformed override is rejected wholesale by the parser — we do
        // NOT silently drop the bad key and accept the rest. The swap UX
        // still wins: we perform the exercise substitution the user asked
        // for, just without the overrides. A structured log entry surfaces
        // the parse failure so the authoring-side drift is visible when
        // someone goes looking.
        let overrides: AlternativeOverrides
        switch AlternativeOverrides.parse(alt.parameterOverridesJSON) {
        case .success(let parsed):
            overrides = parsed
        case .failure:
            overrides = AlternativeOverrides()
        }
        let hadOverrides = !overrides.isEmpty
        // Resolve the exercise id we're swapping FROM — honoring an earlier
        // swap if one happened this session. Falls back to the item's
        // authored exerciseID.
        let fromExerciseID: UUID? = state.items
            .first(where: { $0.itemID == itemID })?
            .performedExerciseID
            ?? findItem(id: itemID, in: context)?.exerciseID
        // Detect a `sets`-override-on-round-robin combination BEFORE we
        // dispatch — the reducer will silently drop the `sets` portion in
        // that case, so we emit a rejection event so we can observe it.
        // Resolving the block index uses the same helper the reducer uses,
        // so the two code paths classify identically.
        let rejectionContext = resolveSetsOverrideRejection(
            itemID: itemID,
            overrides: hadOverrides ? overrides : nil
        )
        apply([.swap(
            itemID: itemID,
            toExerciseID: alt.exerciseID,
            overrides: hadOverrides ? overrides : nil
        )])
        emitSwapTelemetry(
            itemID: itemID,
            fromExerciseID: fromExerciseID,
            toExerciseID: alt.exerciseID,
            hadOverrides: hadOverrides
        )
        if let context = rejectionContext {
            emitSwapSetsOverrideRejected(context: context)
        }
    }

    // MARK: - Sets-override rejection

    /// Resolve whether a `sets`-override applied to `itemID` will be
    /// rejected by the reducer because the containing block is not
    /// set-major. Returns the payload fields needed for the telemetry
    /// event, or `nil` when no rejection will happen (no `sets` override,
    /// unknown item, or set-major block).
    ///
    /// Classification mirrors `SessionReducer+Handlers.applySwap`: the
    /// block's advancement policy comes from
    /// `state.structure.advancementByBlock[blockIndex]`, and only
    /// `.setMajor` permits a row-count rewrite.
    func resolveSetsOverrideRejection(
        itemID: UUID,
        overrides: AlternativeOverrides?
    ) -> SetsOverrideRejectionContext? {
        guard let overrides, overrides.sets != nil else { return nil }
        guard let flatIndex = state.items.firstIndex(where: { $0.itemID == itemID }) else {
            return nil
        }
        guard let position = SessionReducer.findBlockItemPosition(
            flatIndex: flatIndex,
            in: state.structure
        ) else {
            return nil
        }
        guard position.blockIndex < state.structure.advancementByBlock.count else {
            return nil
        }
        let advancement = state.structure.advancementByBlock[position.blockIndex]
        guard advancement != .setMajor else { return nil }
        return SetsOverrideRejectionContext(
            itemID: itemID,
            blockIndex: position.blockIndex,
            advancement: advancement
        )
    }

    /// Emit an `execution.swap_sets_override_rejected` event. Payload
    /// carries the offending `(item_id, block_index, advancement_mode)`
    /// so we can reconstruct the rejection in production. Fire-and-forget
    /// — the reducer has already applied the rest of the override.
    private func emitSwapSetsOverrideRejected(context: SetsOverrideRejectionContext) {
        let payload = #"""
        {"item_id":"\#(context.itemID.wireID)","block_index":\#(context.blockIndex),"advancement_mode":"\#(context.advancement.rawValue)"}
        """#
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.swap_sets_override_rejected",
            dataJSON: payload,
            workoutID: self.context.workout.id
        ))
    }
}

/// Captured by `resolveSetsOverrideRejection` when a `sets`-override on a
/// round-robin block will be dropped by the reducer. The telemetry emit
/// site reads these fields verbatim.
struct SetsOverrideRejectionContext: Sendable, Equatable {
    let itemID: UUID
    let blockIndex: Int
    let advancement: SessionState.BlockAdvancement
}
