// RestView+Sheets.swift
//
// Sheet rendering for `RestView`, split out of `RestView.swift` so the main
// struct stays under SwiftLint's `type_body_length` cap. Each sheet reads
// the just-logged `SetPlan` and dispatches an `editPastSet` mutation on
// commit.

import SwiftUI
import CoreAutoreg
import CoreSession
import DesignSystem
import WorkoutCoreFoundation

extension RestView {

    @ViewBuilder
    func sheetContent(for sheet: RestSheet) -> some View {
        if let set = viewModel.lastLoggedSet,
           let item = currentItem() {
            switch sheet {
            case .load: loadSheet(set: set, item: item)
            case .reps: repsSheet(set: set, item: item)
            case .rir: rirSheet(set: set, item: item)
            }
        }
    }

    func loadSheet(set: SetPlan, item: RestViewItem) -> some View {
        // R2.10 unit-thread: numpad suffix follows the SetPlan's unit
        // so the user sees "102.5 LB" when editing a pound-prescribed
        // set, not a hardcoded "kg". Loadless rows (`SetPlan.loadKg ==
        // nil`) seed the numpad at 0 — the user was on a BW lift and
        // is now adding a numeric load via corrective edit.
        NumPadSheet(
            title: "load",
            unit: set.unit.rawValue,
            initialValue: set.loadKg ?? 0,
            step: 2.5,
            allowsDecimal: true,
            subtitle: "correcting log · no autoreg",
            confirmTitle: "save",
            onCommit: { v in
                activeSheet = nil
                viewModel.editPastSet(
                    itemID: item.id,
                    setIndex: set.setIndex,
                    loadKg: v,
                    reps: nil,
                    rir: nil
                )
            }
        )
    }

    func repsSheet(set: SetPlan, item: RestViewItem) -> some View {
        NumPadSheet(
            title: "reps",
            unit: nil,
            initialValue: Double(set.reps),
            step: 1,
            allowsDecimal: false,
            subtitle: "correcting log · no autoreg",
            confirmTitle: "save",
            onCommit: { v in
                activeSheet = nil
                viewModel.editPastSet(
                    itemID: item.id,
                    setIndex: set.setIndex,
                    loadKg: nil,
                    reps: Int(v),
                    rir: nil
                )
            }
        )
    }

    func rirSheet(set: SetPlan, item: RestViewItem) -> some View {
        RirSheet(
            initialValue: set.rir,
            onPick: { rir in
                activeSheet = nil
                viewModel.editPastSet(
                    itemID: item.id,
                    setIndex: set.setIndex,
                    loadKg: nil,
                    reps: nil,
                    rir: rir
                )
            },
            onSkip: { activeSheet = nil }
        )
    }

    func currentItem() -> RestViewItem? {
        let c = viewModel.state.cursor
        return viewModel.context.item(
            at: c.blockIndex,
            itemIndex: c.itemIndex
        ).map { RestViewItem(id: $0.id) }
    }
}

/// Minimal item identity wrapper — the rest view only needs the id to call
/// `editPastSet`.
struct RestViewItem {
    let id: UUID
}
