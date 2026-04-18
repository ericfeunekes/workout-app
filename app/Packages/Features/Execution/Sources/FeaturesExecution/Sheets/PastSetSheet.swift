// PastSetSheet.swift
//
// Dispatcher view for past-set edits. Given a field (`.load`, `.reps`,
// `.rir`) and whether the set is already logged, picks between
// `NumPadSheet` and `RirSheet` with the right subtitle copy.
//
// Today the only caller is the Rest screen's editable pills — and the
// Rest view handles the dispatch inline. This type exists to satisfy
// the Execution spec and so future callers (completion ledger taps,
// history review drill-down) have a single entry point.

import SwiftUI
import DesignSystem

public enum PastSetField: String, Sendable {
    case load
    case reps
    case rir
}

public enum PastSetMode: Sendable {
    /// Set is already logged — edit is corrective, never autoreg.
    case correctingLog
    /// Set is still pending — edit is a plan adjustment scoped to this set.
    case editingPlan
}

public struct PastSetSheet: View {
    let field: PastSetField
    let mode: PastSetMode
    let setIndex: Int
    let initialLoad: Double
    let initialReps: Int
    let initialRir: Int?
    let onCommit: (_ load: Double?, _ reps: Int?, _ rir: Int?) -> Void
    let onDismiss: () -> Void

    public init(
        field: PastSetField,
        mode: PastSetMode,
        setIndex: Int,
        initialLoad: Double,
        initialReps: Int,
        initialRir: Int?,
        onCommit: @escaping (_ load: Double?, _ reps: Int?, _ rir: Int?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.field = field
        self.mode = mode
        self.setIndex = setIndex
        self.initialLoad = initialLoad
        self.initialReps = initialReps
        self.initialRir = initialRir
        self.onCommit = onCommit
        self.onDismiss = onDismiss
    }

    public var body: some View {
        switch field {
        case .load:
            NumPadSheet(
                title: "set \(setIndex) — load",
                unit: "kg",
                initialValue: initialLoad,
                step: 2.5,
                allowsDecimal: true,
                subtitle: subtitle,
                confirmTitle: "save",
                onCommit: { v in onCommit(v, nil, nil) }
            )
        case .reps:
            NumPadSheet(
                title: "set \(setIndex) — reps",
                unit: nil,
                initialValue: Double(initialReps),
                step: 1,
                allowsDecimal: false,
                subtitle: subtitle,
                confirmTitle: "save",
                onCommit: { v in onCommit(nil, Int(v), nil) }
            )
        case .rir:
            RirSheet(
                initialValue: initialRir,
                onPick: { rir in onCommit(nil, nil, rir) },
                onSkip: onDismiss
            )
        }
    }

    private var subtitle: String {
        switch mode {
        case .correctingLog: return "correcting log · no autoreg"
        case .editingPlan:   return "editing plan · this set"
        }
    }
}
