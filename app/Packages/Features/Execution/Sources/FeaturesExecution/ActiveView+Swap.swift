// ActiveView+Swap.swift
//
// The long-press → SwapSheet plumbing, split out of `ActiveView.swift` so
// the parent struct body stays under SwiftLint's `type_body_length` cap.
// Everything here is file-internal and called from `ActiveView.body`.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import CoreDomain

extension ActiveView {

    /// View-builder for the active swap sheet. Called from
    /// `activeSheetContent(for:)` in `ActiveView+Sheets.swift`.
    @ViewBuilder
    var swapSheet: some View {
        if let swapContext = currentSwapContext() {
            SwapSheet(
                itemID: swapContext.itemID,
                currentExerciseName: swapContext.currentName,
                alternatives: swapContext.alternatives,
                exerciseName: { id in
                    viewModel.context.exercises[id]?.name ?? "(unknown exercise)"
                },
                lastPerformed: { id in viewModel.context.lastPerformed[id] },
                onPick: { altID in
                    activeSheet = nil
                    viewModel.swap(itemID: swapContext.itemID, alternativeID: altID)
                },
                onCancel: { activeSheet = nil }
            )
        } else {
            // Defensive: the cursor is out of range — render a minimal
            // dismiss affordance rather than an empty sheet.
            SwapSheet(
                itemID: UUID(),
                currentExerciseName: "",
                alternatives: [],
                exerciseName: { _ in "" },
                lastPerformed: { _ in nil },
                onPick: { _ in activeSheet = nil },
                onCancel: { activeSheet = nil }
            )
        }
    }

    struct SwapContext {
        let itemID: UUID
        let currentName: String
        let alternatives: [CoreDomain.ExerciseAlternative]
    }

    /// Resolve the current cursor's item + its alternatives for the
    /// swap sheet. Returns nil when the cursor is stale or out of range.
    func currentSwapContext() -> SwapContext? {
        let c = viewModel.state.cursor
        guard let item = viewModel.context.item(
            at: c.blockIndex,
            itemIndex: c.itemIndex
        ) else { return nil }
        let itemLog = viewModel.state.items.first(where: { $0.itemID == item.id })
        let currentName = viewModel.context.exerciseName(
            for: item,
            performedExerciseID: itemLog?.performedExerciseID
        )
        return SwapContext(
            itemID: item.id,
            currentName: currentName,
            alternatives: viewModel.context.alternatives(for: item.id)
        )
    }

    /// Trigger a medium impact haptic + present the swap sheet. Called
    /// from the long-press gesture in `ActiveView.body`. Haptic is
    /// UIKit-only; on macOS / watch previews the gesture still opens
    /// the sheet.
    func openSwapSheet() {
        #if canImport(UIKit) && !os(watchOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        activeSheet = .swap
    }
}
