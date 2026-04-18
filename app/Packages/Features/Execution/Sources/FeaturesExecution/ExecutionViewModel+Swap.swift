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
    /// `{itemID, fromExerciseID, toExerciseID, hadOverrides}`.
    ///
    /// Unknown `alternativeID` or an itemID with no authored alternatives
    /// is a silent no-op; the long-press UI should not have opened the
    /// sheet in that case, but we guard defensively.
    public func swap(itemID: UUID, alternativeID: UUID) {
        let alts = context.alternatives(for: itemID)
        guard let alt = alts.first(where: { $0.id == alternativeID }) else {
            return
        }
        let overrides = AlternativeOverrides.parse(alt.parameterOverridesJSON)
        let hadOverrides = !overrides.isEmpty
        // Resolve the exercise id we're swapping FROM — honoring an earlier
        // swap if one happened this session. Falls back to the item's
        // authored exerciseID.
        let fromExerciseID: UUID? = state.items
            .first(where: { $0.itemID == itemID })?
            .performedExerciseID
            ?? findItem(id: itemID, in: context)?.exerciseID
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
    }
}
