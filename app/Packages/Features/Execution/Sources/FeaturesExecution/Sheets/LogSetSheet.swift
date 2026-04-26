// LogSetSheet.swift
//
// Row-based strength logger. The default view is compact: load, reps, and
// RIR are shown as editable cells, with the keypad appearing only for the
// selected numeric field. This keeps supersets/circuits from feeling like a
// fighter-jet dashboard while still letting the user correct load at log time.

import SwiftUI
import DesignSystem
import WorkoutCoreFoundation

// MARK: - Model

@Observable
@MainActor
public final class LogSetSheetModel {

    public enum Field: Equatable, Sendable {
        case load
        case reps
    }

    public let initialLoad: Double?
    public let loadUnit: String?
    public let initialReps: Int
    public let onCommit: (Double?, Int, Int?) -> Void

    public private(set) var selectedField: Field?
    public private(set) var loadBuffer: String
    public private(set) var repsBuffer: String
    public private(set) var pickedRir: Int?
    public private(set) var primed: Bool = false
    private var replaceOnNextInput: Field?

    public init(
        initialLoad: Double?,
        loadUnit: String?,
        initialReps: Int,
        onCommit: @escaping (Double?, Int, Int?) -> Void
    ) {
        self.initialLoad = initialLoad
        self.loadUnit = loadUnit
        self.initialReps = initialReps
        self.onCommit = onCommit
        self.selectedField = nil
        self.loadBuffer = ""
        self.repsBuffer = ""
    }

    public func prime() {
        guard !primed else { return }
        primed = true
        loadBuffer = initialLoad.map(formatLoadNumber) ?? ""
        repsBuffer = String(initialReps)
    }

    public func select(_ field: Field) {
        guard field != .load || initialLoad != nil else { return }
        if selectedField == field {
            selectedField = nil
            replaceOnNextInput = nil
        } else {
            selectedField = field
            replaceOnNextInput = field
        }
    }

    public func pressDigit(_ digit: Int) {
        replaceSelectedBufferIfNeeded()
        mutateSelectedBuffer { buffer in
            let d = String(digit)
            if buffer == "0" {
                buffer = d
            } else {
                buffer.append(d)
            }
        }
    }

    public func pressDecimal() {
        guard selectedField == .load else { return }
        replaceSelectedBufferIfNeeded()
        mutateSelectedBuffer { buffer in
            if !buffer.contains(".") {
                buffer.append(buffer.isEmpty ? "0." : ".")
            }
        }
    }

    public func pressDelete() {
        replaceOnNextInput = nil
        mutateSelectedBuffer { buffer in
            guard !buffer.isEmpty else { return }
            buffer.removeLast()
            if buffer.isEmpty { buffer = "0" }
        }
    }

    public func pressRir(_ value: Int) {
        pickedRir = pickedRir == value ? nil : value
    }

    public func commit() {
        let load = initialLoad == nil
            ? nil
            : Double(loadBuffer) ?? initialLoad
        let reps = Int(repsBuffer) ?? initialReps
        onCommit(load, reps, pickedRir)
    }

    public var loadDisplay: String {
        guard initialLoad != nil else { return "BW" }
        let value = loadBuffer.isEmpty ? "0" : loadBuffer
        return [value, loadUnit].compactMap(\.self).joined(separator: " ")
    }

    public var repsDisplay: String {
        repsBuffer.isEmpty ? "0" : repsBuffer
    }

    public var showsKeypad: Bool {
        selectedField != nil
    }

    public var keypadAllowsDecimal: Bool {
        selectedField == .load
    }

    private func mutateSelectedBuffer(_ body: (inout String) -> Void) {
        switch selectedField {
        case .load:
            guard initialLoad != nil else { return }
            body(&loadBuffer)
        case .reps:
            body(&repsBuffer)
        case nil:
            return
        }
    }

    private func replaceSelectedBufferIfNeeded() {
        guard replaceOnNextInput == selectedField else { return }
        replaceOnNextInput = nil
        switch selectedField {
        case .load:
            loadBuffer = ""
        case .reps:
            repsBuffer = ""
        case nil:
            return
        }
    }
}

// MARK: - View

struct LogSetSheet: View {
    @State private var model: LogSetSheetModel
    private let title: String

    private let options: [(value: Int, label: String)] = [
        (0, "failure"),
        (1, "grinder"),
        (2, "hard"),
        (3, "moderate"),
        (4, "easy"),
        (5, "very easy"),
    ]

    init(
        title: String = "log set",
        initialLoad: Double?,
        loadUnit: String?,
        initialReps: Int,
        onCommit: @escaping (Double?, Int, Int?) -> Void
    ) {
        self.title = title
        _model = State(initialValue: LogSetSheetModel(
            initialLoad: initialLoad,
            loadUnit: loadUnit,
            initialReps: initialReps,
            onCommit: onCommit
        ))
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                fields
                rirRow
                if model.showsKeypad {
                    keypad
                } else {
                    DSButton(
                        title: "log",
                        style: .primary,
                        action: { model.commit() }
                    )
                }
            }
            .padding(DSSpacing.xl)
        }
        .onAppear { model.prime() }
        .presentationDetents([.large])
        .transition(.move(edge: .bottom))
        .animation(.easeInOut(duration: 0.25), value: model.selectedField)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("tap a row to edit · rir optional")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private var fields: some View {
        HStack(spacing: DSSpacing.sm) {
            if model.initialLoad != nil {
                fieldCell(
                    label: "load",
                    value: model.loadDisplay,
                    isSelected: model.selectedField == .load,
                    action: { model.select(.load) }
                )
                .accessibilityIdentifier("logset.load_row")
            }
            fieldCell(
                label: "reps",
                value: model.repsDisplay,
                isSelected: model.selectedField == .reps,
                action: { model.select(.reps) }
            )
            .accessibilityIdentifier("logset.reps_row")
        }
    }

    private func fieldCell(
        label: String,
        value: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.xs) {
                    Text(label.uppercased())
                        .font(DSTypography.subLabel)
                        .tracking(1.2)
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(isSelected ? DSColors.accentInk : DSColors.foregroundDim)
                Text(value)
                    .font(DSTypography.monoLarge)
                    .foregroundStyle(isSelected ? DSColors.accentInk : DSColors.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.md)
            .background(isSelected ? DSColors.accentMuted : DSColors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? DSColors.accent : DSColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityValue(isSelected ? "editing" : "")
        .accessibilityHint("Tap to edit \(label)")
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
                    .accessibilityLabel("RIR \(opt.value) \(opt.label)")
                    .accessibilityValue(model.pickedRir == opt.value ? "selected" : "")
                    .accessibilityIdentifier("logset.rir.\(opt.value)")
                }
            }
        }
    }

    private func rirButton(value: Int, label: String) -> some View {
        let selected = model.pickedRir == value
        return VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(selected ? DSColors.accentInk : DSColors.foreground)
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(DSColors.foregroundDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.md)
        .background(selected ? DSColors.accentMuted : DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(selected ? DSColors.accent : DSColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
    }

    private var keypad: some View {
        DSKeypad(
            onDigit: { model.pressDigit($0) },
            onDelete: { model.pressDelete() },
            onDecimal: model.keypadAllowsDecimal ? { model.pressDecimal() } : nil,
            onDone: { model.commit() },
            doneLabel: "log"
        )
    }
}
