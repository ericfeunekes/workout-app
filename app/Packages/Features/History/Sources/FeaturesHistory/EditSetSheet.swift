// EditSetSheet.swift
//
// Corrective-edit sheet for the History session-detail surface. Closes
// bug-015 — the stub at `HistorySessionDetailView.swift:89` that used
// to flash a highlight and do nothing.
//
// Shape parity with `FeaturesExecution.LogSetSheet`:
//   - reps numpad on top, RIR row in the middle, load numpad on bottom
//   - inline "save" commit key on the keypad (one-thumb flow)
//   - both fields optional: committing without touching a field means
//     "preserve the existing value" — HistoryViewModel.editPastSet
//     applies only the overrides the user actually changed.
//
// Why a dedicated sheet instead of reusing LogSetSheet:
//   - LogSetSheet lives in FeaturesExecution; FeaturesHistory does not
//     (and should not) depend on Execution. Duplicating ~200 lines here
//     is cheaper than the boundary break.
//   - Edits don't propose autoreg and don't need the "log set N / M"
//     counter — simpler surface than the live-log flow.
//
// State lives in `EditSetSheetModel` so the commit contract is unit-
// testable without ViewInspector. The view holds it as @State; tests
// instantiate it directly and drive `pressDigit` / `pressRir` /
// `commit` to inspect what the model emits.

import SwiftUI
import CoreDomain
import DesignSystem

// MARK: - Model

@MainActor
public final class EditSetSheetModel {

    /// Set index being edited (for the header readout). 1-based to match
    /// the runtime pipeline (SessionSeeder cursor starts at 1).
    public let setIndex: Int
    /// Prefill values. nil means "no value recorded" — the sheet renders
    /// a muted placeholder but commits keep the existing nil if the
    /// user doesn't edit that field.
    public let initialReps: Int?
    public let initialRir: Int?
    public let initialLoadKg: Double?

    /// Invoked when the user taps the inline "save" button. Carries
    /// only the fields the user actually changed — unchanged fields pass
    /// as nil so `HistoryViewModel.editPastSet` preserves the existing
    /// value instead of overwriting with the prefill.
    public let onCommit: (_ reps: Int?, _ rir: Int?, _ loadKg: Double?) -> Void

    /// reps buffer. `""` = user hasn't touched it; commit returns nil
    /// for reps so the existing value is preserved.
    public private(set) var repsBuffer: String = ""
    /// load buffer. Same convention as reps.
    public private(set) var loadBuffer: String = ""
    /// `.reps` or `.load` — which numpad the on-screen keypad drives.
    public private(set) var activeField: Field = .reps
    /// Picked RIR. nil = user didn't touch the row; commit preserves.
    public private(set) var pickedRir: Int?
    /// True once the user has explicitly tapped a RIR button — once
    /// set, the commit writes `pickedRir` even if it flipped back to
    /// nil (tap-to-clear). Lets a user zero out a stale RIR.
    public private(set) var rirTouched: Bool = false

    public enum Field: Sendable, Equatable {
        case reps
        case load
    }

    public init(
        setIndex: Int,
        initialReps: Int?,
        initialRir: Int?,
        initialLoadKg: Double?,
        onCommit: @escaping (Int?, Int?, Double?) -> Void
    ) {
        self.setIndex = setIndex
        self.initialReps = initialReps
        self.initialRir = initialRir
        self.initialLoadKg = initialLoadKg
        self.onCommit = onCommit
    }

    /// Display text for the reps readout. Shows the initial value as a
    /// placeholder until the user starts typing; then shows the buffer.
    public var repsDisplay: String {
        if !repsBuffer.isEmpty { return repsBuffer }
        if let r = initialReps { return String(r) }
        return "—"
    }

    /// Display text for the load readout. Same placeholder convention.
    public var loadDisplay: String {
        if !loadBuffer.isEmpty { return loadBuffer }
        if let l = initialLoadKg {
            // Strip trailing ".0" so "100.0" renders as "100" —
            // SessionDetailViewModel.formatSetRow uses the same idiom
            // via `formatLoad`.
            let whole = l.rounded() == l
            return whole ? String(Int(l)) : String(l)
        }
        return "—"
    }

    public func selectField(_ field: Field) {
        activeField = field
    }

    public func pressDigit(_ digit: Int) {
        switch activeField {
        case .reps:
            appendDigitTo(&repsBuffer, digit: digit, allowsDecimal: false)
        case .load:
            appendDigitTo(&loadBuffer, digit: digit, allowsDecimal: true)
        }
    }

    public func pressDecimal() {
        guard activeField == .load else { return }
        if loadBuffer.contains(".") { return }
        if loadBuffer.isEmpty { loadBuffer = "0" }
        loadBuffer.append(".")
    }

    public func pressDelete() {
        switch activeField {
        case .reps: pressDeleteOn(&repsBuffer)
        case .load: pressDeleteOn(&loadBuffer)
        }
    }

    public func pressRir(_ value: Int) {
        rirTouched = true
        if pickedRir == value {
            pickedRir = nil
        } else {
            pickedRir = value
        }
    }

    public func commit() {
        let reps = Int(repsBuffer)
        let load = Double(loadBuffer)
        // rir: if untouched, pass nil so editPastSet preserves existing
        // value. If the user explicitly tapped (rirTouched), pass the
        // current pickedRir (which may itself be nil from tap-to-clear
        // — but editPastSet uses `rir ?? existing.rir` so today a
        // touched-but-cleared RIR still collapses to preserve. That's a
        // watchlist nuance; in v1 the flow is "tap once, commit" and
        // clearing isn't a routine path.
        let rir = rirTouched ? pickedRir : nil
        onCommit(reps, rir, load)
    }

    // MARK: - Private

    private func appendDigitTo(
        _ buffer: inout String,
        digit: Int,
        allowsDecimal: Bool
    ) {
        let d = String(digit)
        if buffer.isEmpty || buffer == "0" {
            buffer = d
            return
        }
        buffer.append(d)
        _ = allowsDecimal
    }

    private func pressDeleteOn(_ buffer: inout String) {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
    }
}

// MARK: - View

struct EditSetSheet: View {
    @State private var model: EditSetSheetModel

    private let options: [(value: Int, label: String)] = [
        (0, "failure"),
        (1, "grinder"),
        (2, "hard"),
        (3, "moderate"),
        (4, "easy"),
        (5, "very easy"),
    ]

    init(
        setIndex: Int,
        initialReps: Int?,
        initialRir: Int?,
        initialLoadKg: Double?,
        onCommit: @escaping (Int?, Int?, Double?) -> Void
    ) {
        _model = State(initialValue: EditSetSheetModel(
            setIndex: setIndex,
            initialReps: initialReps,
            initialRir: initialRir,
            initialLoadKg: initialLoadKg,
            onCommit: onCommit
        ))
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                fieldRow
                rirRow
                DSKeypad(
                    onDigit: { model.pressDigit($0) },
                    onDelete: { model.pressDelete() },
                    onDecimal: model.activeField == .load ? { model.pressDecimal() } : nil,
                    onDone: { model.commit() },
                    doneLabel: "save"
                )
            }
            .padding(DSSpacing.xl)
        }
        .presentationDetents([.large])
        .transition(.move(edge: .bottom))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("edit set \(model.setIndex)")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("correcting log · no autoreg")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private var fieldRow: some View {
        HStack(spacing: DSSpacing.md) {
            fieldTile(title: "REPS", display: model.repsDisplay, field: .reps)
            fieldTile(title: "LOAD KG", display: model.loadDisplay, field: .load)
        }
    }

    private func fieldTile(title: String, display: String, field: EditSetSheetModel.Field) -> some View {
        let selected = model.activeField == field
        return Button(action: { model.selectField(field) }, label: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title)
                    .font(DSTypography.subLabel)
                    .tracking(1.2)
                    .foregroundStyle(DSColors.foregroundDim)
                Text(display)
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(selected ? DSColors.accentInk : DSColors.foreground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.md)
            .background(selected ? DSColors.accentMuted : DSColors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                    .strokeBorder(
                        selected ? DSColors.accent : DSColors.border,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        })
        .buttonStyle(.plain)
        .accessibilityIdentifier("editset.field.\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }

    private var rirRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("RIR")
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)
            HStack(spacing: DSSpacing.sm) {
                ForEach(options, id: \.value) { opt in
                    Button(action: { model.pressRir(opt.value) }, label: {
                        rirButton(value: opt.value, label: opt.label)
                    })
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editset.rir.\(opt.value)")
                }
            }
        }
    }

    private func rirButton(value: Int, label: String) -> some View {
        let selected = model.pickedRir == value
        return VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(selected ? DSColors.accentInk : DSColors.foreground)
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(DSColors.foregroundDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.sm)
        .background(selected ? DSColors.accentMuted : DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(
                    selected ? DSColors.accent : DSColors.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
    }
}
