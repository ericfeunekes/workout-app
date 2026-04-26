// ExecutionViewModel+Autoreg.swift
//
// Autoreg-undo reversal lives here so the main class body stays under
// SwiftLint's `type_body_length` cap. `acceptAutoreg` is a one-liner
// that remains on the class for symmetry with `logSet` — `undoAutoreg`
// is the long reversal reducer that rebuilds prescribed loads from the
// seed and accepts the `.manual` tag as a side-effect of reusing
// `editPendingSet` (see the doc below for the rationale).

import Foundation
import CoreAutoreg
import CoreDomain
import CoreSession

extension ExecutionViewModel {

    /// Run the revert side of `undoAutoreg`. Returns nil when the proposal
    /// or its anchoring itemLog/item can't be resolved — caller drops the
    /// proposal and short-circuits.
    ///
    /// To revert, we apply an inverse proposal: any non-done set whose
    /// `adjust` matches the proposal's direction gets its prescribed
    /// load restored from the seeded plan. We pile those restores onto
    /// a mutations batch, append a `.holdAutoreg` so subsequent logs
    /// don't re-propose, and hand the batch to `apply(_:)`.
    ///
    /// Note: `editPendingSet` marks the set as `.manual` as a side-effect.
    /// We want the revert to look pristine so autoreg could re-trigger
    /// later if the hold were ever lifted — but the hold flag makes this
    /// moot within the session. The cleaner path would be a dedicated
    /// reducer mutation that restores `.adjust = nil`; v0 accepts the
    /// `.manual` tag as a known cosmetic side-effect.
    func runAutoregUndo() {
        guard let proposal = currentProposal,
              let itemID = currentProposalItemID else { return }
        emitAutoreg("execution.autoreg_undo")

        guard let itemLog = state.items.first(where: { $0.itemID == itemID }),
              let item = findItem(id: itemID, in: context) else {
            currentProposal = nil
            currentProposalItemID = nil
            return
        }

        let originals = SessionSeeder.seedSets(for: item)
        let proposalDirection: SetPlan.Adjust = proposal.direction == .up ? .up : .down
        var revertMutations: [SessionMutation] = []
        for set in itemLog.sets where !set.done && set.adjust == proposalDirection {
            if let original = originals.first(where: { $0.setIndex == set.setIndex }) {
                revertMutations.append(.editPendingSet(
                    itemID: itemID,
                    setIndex: set.setIndex,
                    loadKg: original.loadKg,
                    reps: nil,
                    rir: nil,
                    startedAt: nil
                ))
            }
        }
        revertMutations.append(.holdAutoreg(itemID: itemID))
        apply(revertMutations)

        currentProposal = nil
        currentProposalItemID = nil
    }
}
