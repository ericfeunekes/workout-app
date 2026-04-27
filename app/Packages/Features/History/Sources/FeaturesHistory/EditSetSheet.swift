// EditSetSheet.swift
//
// Corrective-edit sheet for the History session-detail surface. Closes
// bug-015 — the stub at `HistorySessionDetailView.swift:89` that used
// to flash a highlight and do nothing.
//
// Shape parity with the shared SetEditSheet contract:
//   - reps/load/duration/distance use the same keypad
//   - skipped, notes, and RIR are explicit controls
//   - inline "save" commit key on the keypad (one-thumb flow)
//   - every field is optional: committing without touching a field means
//     "preserve the existing value" — HistoryViewModel.editPastSet
//     applies only the overrides the user actually changed.
//
// Reserved side semantics: `set_log.side` still round-trips through the
// History surface because the caller passes the current value in, but
// this sheet does not author it. D1's unilateral model is exercise-item
// based, not "toggle side on a generic set row."
//
// Weight-unit correctness: the loaded `SetLog.weightUnit` (`.kg` / `.lb`)
// is threaded through. The LOAD field's label flips between "LOAD KG" /
// "LOAD LB" based on that unit, and the commit returns a `LoadCommit`
// that carries both the numeric value AND the unit — so the caller
// preserves whatever the user typed in the source unit. The sheet never
// performs unit conversion; conversion belongs at the display boundary
// (none today — v0 is kg-only in practice), not at the edit path.
//
// RIR clear: the picker row supports tap-to-clear (tapping the selected
// value toggles it off) AND explicit "CLEAR" chip at the end. The commit
// path distinguishes "user didn't touch RIR" (preserve existing) from
// "user explicitly cleared" (set nil) via an internal `rirTouched`
// flag — see `commit()`. The shared `SetEditIntent.rir` enum carries
// the distinction to `HistoryViewModel.editPastSet`.
//
// Reps cap: the numpad handler clamps the reps buffer at 999. Typing
// a fourth digit is rejected silently — the buffer stops at "999" and
// the next digit tap is a no-op. Covers mistaken-entry (typing the
// load value into the reps field) without breaking legitimate entries
// below 1000. Matches the gym-realistic max (AMRAP sets on low-load
// machines occasionally hit triple digits; no one logs 1000+ reps).
//
// Why a dedicated sheet instead of reusing LogSetSheet:
//   - LogSetSheet lives in FeaturesExecution; FeaturesHistory does not
//     (and should not) depend on Execution. Duplicating ~200 lines here
//     is cheaper than the boundary break.
//   - Edits don't propose autoreg and don't need the "log set N / M"
//     counter — simpler surface than the live-log flow.
//   - The sheet locally blocks the invalid skipped→performed transition
//     where reps/load/duration/distance would all remain nil. That keeps
//     the user in the sheet with a visible error instead of dismissing
//     into a no-op save path.
//
// State lives in `EditSetSheetModel` so the commit contract is unit-
// testable without ViewInspector. The view holds it as @State; tests
// instantiate it directly and drive `pressDigit` / `pressRir` /
// `commit` to inspect what the model emits.

import SwiftUI
import CoreDomain
import DesignSystem

// MARK: - Model

@Observable
@MainActor
public final class EditSetSheetModel {

    /// Hard cap on the reps buffer. 999 comfortably above any realistic
    /// set (no one logs four-digit reps) and protects against mistaken
    /// entries where the user typed a load value into the reps field.
    public static let maxReps: Int = 999

    /// Set index being edited (for the header readout). 1-based to match
    /// the runtime pipeline (SessionSeeder cursor starts at 1).
    public let setIndex: Int
    /// Prefill values. nil means "no value recorded" — the sheet renders
    /// a muted placeholder but commits keep the existing nil if the
    /// user doesn't edit that field.
    public let initialReps: Int?
    public let initialRir: Int?
    public let initialLoad: Double?
    public let initialDurationSec: Double?
    public let initialDistanceM: Double?
    public let initialSkipped: Bool
    /// Current stored side. Threaded through unchanged so History edits
    /// preserve the row's round-tripped value, but the sheet does not
    /// expose side as an editable control.
    public let initialSide: SetLogSide
    public let initialNotes: String?
    /// Unit the loaded SetLog was recorded in. Defaults to `.kg` when
    /// the SetLog has `weightUnit == nil` (older rows before the field
    /// was populated). The sheet renders / commits in this unit verbatim.
    public let weightUnit: WeightUnit

    /// Invoked when the user taps the inline "save" button. Carries
    /// only the fields the user actually changed — unchanged fields pass
    /// as nil/`.preserve` so `HistoryViewModel.editPastSet` preserves the
    /// existing value instead of overwriting with the prefill.
    public let onCommit: (_ intent: SetEditIntent) -> Void

    /// reps buffer. `""` = user hasn't touched it; commit returns nil
    /// for reps so the existing value is preserved.
    public private(set) var repsBuffer: String = ""
    /// load buffer. Same convention as reps.
    public private(set) var loadBuffer: String = ""
    public private(set) var durationBuffer: String = ""
    public private(set) var distanceBuffer: String = ""
    public private(set) var notesText: String = ""
    public private(set) var notesTouched: Bool = false
    public private(set) var skippedValue: Bool
    public private(set) var skippedTouched: Bool = false
    public private(set) var validationMessage: String?
    /// Which field the on-screen keypad drives.
    public private(set) var activeField: Field = .reps
    /// Picked RIR. nil = user didn't touch the row OR explicitly cleared;
    /// disambiguated by `rirTouched`.
    public private(set) var pickedRir: Int?
    /// True once the user has explicitly tapped a RIR button or the
    /// clear affordance — once set, the commit writes `.set(value)` /
    /// `.clear` rather than `.preserve`. Lets a user zero out a stale
    /// RIR without ambiguity.
    public private(set) var rirTouched: Bool = false

    public enum Field: Sendable, Equatable {
        case reps
        case load
        case duration
        case distance
    }

    public init(
        setIndex: Int,
        initialReps: Int?,
        initialRir: Int?,
        initialLoad: Double?,
        initialDurationSec: Double?,
        initialDistanceM: Double?,
        initialSkipped: Bool,
        initialSide: SetLogSide,
        initialNotes: String?,
        weightUnit: WeightUnit,
        onCommit: @escaping (SetEditIntent) -> Void
    ) {
        self.setIndex = setIndex
        self.initialReps = initialReps
        self.initialRir = initialRir
        self.initialLoad = initialLoad
        self.initialDurationSec = initialDurationSec
        self.initialDistanceM = initialDistanceM
        self.initialSkipped = initialSkipped
        self.initialSide = initialSide
        self.initialNotes = initialNotes
        self.weightUnit = weightUnit
        self.onCommit = onCommit
        self.notesText = initialNotes ?? ""
        self.skippedValue = initialSkipped
        self.pickedRir = initialRir
    }

    /// ALL-CAPS label for the load tile: "LOAD KG" when the SetLog was
    /// recorded in kg, "LOAD LB" in lb. Threaded through so the sheet
    /// never misrepresents what unit the user's about to save in.
    public var loadLabel: String {
        switch weightUnit {
        case .kg: return "LOAD KG"
        case .lb: return "LOAD LB"
        }
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
        if let l = initialLoad {
            // Strip trailing ".0" so "100.0" renders as "100" —
            // SessionDetailViewModel.formatSetRow uses the same idiom
            // via `formatLoad`.
            let whole = l.rounded() == l
            return whole ? String(Int(l)) : String(l)
        }
        return "—"
    }

    public var durationDisplay: String {
        if !durationBuffer.isEmpty { return durationBuffer }
        if let value = initialDurationSec {
            return formatNumber(value)
        }
        return "—"
    }

    public var distanceDisplay: String {
        if !distanceBuffer.isEmpty { return distanceBuffer }
        if let value = initialDistanceM {
            return formatNumber(value)
        }
        return "—"
    }

    public var skippedLabel: String {
        skippedValue ? "SKIPPED" : "PERFORMED"
    }

    public func selectField(_ field: Field) {
        clearValidationMessage()
        activeField = field
    }

    public func pressDigit(_ digit: Int) {
        clearValidationMessage()
        switch activeField {
        case .reps:
            appendRepsDigit(digit)
        case .load:
            appendDigitTo(&loadBuffer, digit: digit, allowsDecimal: true)
        case .duration:
            appendDigitTo(&durationBuffer, digit: digit, allowsDecimal: true)
        case .distance:
            appendDigitTo(&distanceBuffer, digit: digit, allowsDecimal: true)
        }
    }

    public func pressDecimal() {
        clearValidationMessage()
        switch activeField {
        case .reps:
            return
        case .load:
            appendDecimal(to: &loadBuffer)
        case .duration:
            appendDecimal(to: &durationBuffer)
        case .distance:
            appendDecimal(to: &distanceBuffer)
        }
    }

    public func pressDelete() {
        clearValidationMessage()
        switch activeField {
        case .reps: pressDeleteOn(&repsBuffer)
        case .load: pressDeleteOn(&loadBuffer)
        case .duration: pressDeleteOn(&durationBuffer)
        case .distance: pressDeleteOn(&distanceBuffer)
        }
    }

    public func pressRir(_ value: Int) {
        clearValidationMessage()
        rirTouched = true
        if pickedRir == value {
            pickedRir = nil
        } else {
            pickedRir = value
        }
    }

    /// Explicit clear of the RIR selection — lets a user who tapped into
    /// the sheet via a row that already had a RIR set explicitly zero it
    /// out. Distinct from "tap the selected chip twice" (which also
    /// clears via `pressRir`) because it always clears regardless of
    /// current state. Commits as `.clear` downstream.
    public func clearRir() {
        clearValidationMessage()
        rirTouched = true
        pickedRir = nil
    }

    public func setSkipped(_ skipped: Bool) {
        clearValidationMessage()
        skippedTouched = true
        skippedValue = skipped
    }

    public func setNotes(_ notes: String) {
        clearValidationMessage()
        notesTouched = true
        notesText = notes
    }

    public func commit() {
        guard validateCommit() else { return }
        let contract = DesignSystem.SetEditSheetModel(
            availableFields: [
                .load, .reps, .rir, .distance, .duration,
                .skipped, .notes,
            ]
        )
        if let reps = parsedReps() {
            contract.setReps(reps)
        }
        if let load = parsedLoad() {
            contract.setLoad(load.value, unit: load.unit.rawValue)
        }
        if let duration = parsedDuration() {
            contract.setDuration(seconds: duration)
        }
        if let distance = parsedDistance() {
            contract.setDistance(distance, unit: "m")
        }
        if rirTouched {
            if let picked = pickedRir {
                contract.setRIR(picked)
            } else {
                contract.clearRIR()
            }
        }
        if skippedTouched {
            contract.setSkipped(skippedValue)
        }
        if notesTouched {
            contract.setNotes(notesText)
        }
        onCommit(contract.commit())
    }

    // MARK: - Private

    /// Parse the reps buffer; clamped to `[0, maxReps]` as an extra
    /// defensive check for any caller that bypassed `appendRepsDigit`
    /// (paste, programmatic tests). `appendRepsDigit` already enforces
    /// the cap at input time so real users can't reach the branch.
    private func parsedReps() -> Int? {
        guard let value = Int(repsBuffer) else { return nil }
        return min(max(0, value), Self.maxReps)
    }

    private func parsedLoad() -> (value: Double, unit: WeightUnit)? {
        guard let value = Double(loadBuffer) else { return nil }
        return (value, weightUnit)
    }

    private func parsedDuration() -> Double? {
        guard let value = Double(durationBuffer) else { return nil }
        return max(0, value)
    }

    private func parsedDistance() -> Double? {
        guard let value = Double(distanceBuffer) else { return nil }
        return max(0, value)
    }

    private func validateCommit() -> Bool {
        guard !(initialSkipped && skippedTouched && skippedValue == false && resultingMetricsAreAllNil) else {
            validationMessage = "add at least one metric before marking performed"
            return false
        }
        validationMessage = nil
        return true
    }

    private var resultingMetricsAreAllNil: Bool {
        resultingReps == nil &&
        resultingLoad == nil &&
        resultingDuration == nil &&
        resultingDistance == nil
    }

    private var resultingReps: Int? {
        parsedReps() ?? initialReps
    }

    private var resultingLoad: Double? {
        parsedLoad()?.value ?? initialLoad
    }

    private var resultingDuration: Double? {
        parsedDuration() ?? initialDurationSec
    }

    private var resultingDistance: Double? {
        parsedDistance() ?? initialDistanceM
    }

    /// Append a digit to the reps buffer, rejecting the input when the
    /// resulting number would exceed `maxReps`. Matches the numpad
    /// behavior users expect on a capped field: the buffer simply stops
    /// growing at the cap rather than showing a 4-digit value and then
    /// clamping on commit (which would visually mislead).
    private func appendRepsDigit(_ digit: Int) {
        let trial: String
        if repsBuffer.isEmpty || repsBuffer == "0" {
            trial = String(digit)
        } else {
            trial = repsBuffer + String(digit)
        }
        guard let parsed = Int(trial), parsed <= Self.maxReps else {
            // Reject silently — the buffer stays at its prior value.
            return
        }
        repsBuffer = trial
    }

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

    private func appendDecimal(to buffer: inout String) {
        if buffer.contains(".") { return }
        if buffer.isEmpty { buffer = "0" }
        buffer.append(".")
    }

    private func pressDeleteOn(_ buffer: inout String) {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
    }

    private func clearValidationMessage() {
        validationMessage = nil
    }

    private func formatNumber(_ value: Double) -> String {
        let whole = value.rounded() == value
        return whole ? String(Int(value)) : String(value)
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
        initialLoad: Double?,
        initialDurationSec: Double?,
        initialDistanceM: Double?,
        initialSkipped: Bool,
        initialSide: SetLogSide,
        initialNotes: String?,
        weightUnit: WeightUnit,
        onCommit: @escaping (SetEditIntent) -> Void
    ) {
        _model = State(initialValue: EditSetSheetModel(
            setIndex: setIndex,
            initialReps: initialReps,
            initialRir: initialRir,
            initialLoad: initialLoad,
            initialDurationSec: initialDurationSec,
            initialDistanceM: initialDistanceM,
            initialSkipped: initialSkipped,
            initialSide: initialSide,
            initialNotes: initialNotes,
            weightUnit: weightUnit,
            onCommit: onCommit
        ))
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                fieldRow
                cardioFieldRow
                statusRow
                validationRow
                notesField
                rirRow
                DSKeypad(
                    onDigit: { model.pressDigit($0) },
                    onDelete: { model.pressDelete() },
                    onDecimal: model.activeField == .reps ? nil : { model.pressDecimal() },
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

    @ViewBuilder
    private var validationRow: some View {
        if let message = model.validationMessage {
            Text(message)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.warn)
        }
    }

    private var fieldRow: some View {
        HStack(spacing: DSSpacing.md) {
            fieldTile(title: "REPS", display: model.repsDisplay, field: .reps)
            fieldTile(title: model.loadLabel, display: model.loadDisplay, field: .load)
        }
    }

    private var cardioFieldRow: some View {
        HStack(spacing: DSSpacing.md) {
            fieldTile(title: "DURATION S", display: model.durationDisplay, field: .duration)
            fieldTile(title: "DISTANCE M", display: model.distanceDisplay, field: .distance)
        }
    }

    private var statusRow: some View {
        HStack(spacing: DSSpacing.sm) {
            statusButton(title: "PERFORMED", skipped: false)
            statusButton(title: "SKIPPED", skipped: true)
        }
    }

    private func statusButton(title: String, skipped: Bool) -> some View {
        let selected = model.skippedValue == skipped
        return Button(action: { model.setSkipped(skipped) }, label: {
            Text(title)
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(selected ? DSColors.accentInk : DSColors.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.sm)
                .background(selected ? DSColors.accentMuted : DSColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                        .strokeBorder(selected ? DSColors.accent : DSColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        })
        .buttonStyle(.plain)
    }

    private var notesField: some View {
        TextField(
            "NOTE",
            text: Binding(
                get: { model.notesText },
                set: { model.setNotes($0) }
            ),
            axis: .vertical
        )
        .font(DSTypography.body)
        .foregroundStyle(DSColors.foreground)
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(DSColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
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
                Button(action: { model.clearRir() }, label: {
                    rirClearButton()
                })
                .buttonStyle(.plain)
                .accessibilityIdentifier("editset.rir.clear")
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

    /// Trailing affordance on the RIR row to explicitly clear the value —
    /// distinct from tapping the selected chip twice. Users who arrive
    /// at the sheet with a RIR already set and want to zero it out now
    /// have an unambiguous control.
    private func rirClearButton() -> some View {
        VStack(spacing: 2) {
            Text("×")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DSColors.foreground)
            Text("clear")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(DSColors.foregroundDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(DSColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
    }
}
