// NumPadSheet.swift
//
// Numeric entry sheet — a thin wrapper around `DSKeypad` plus a big
// numeric readout. Used for:
//   - initial reps entry on `log set` (in-flight pending value)
//   - past-set corrections (load or reps) from the rest screen's pills
//   - future: scoped edits with a "this set / remaining" toggle
//
// The scoped variant described in the brief as `ScopedNumPad` is not
// wired up in v0 — the rest screen's past-set edits don't need scope,
// and the active screen's longpress menu for scoped edits is a v1.1
// feature. The shape here is designed so adding scope is a new view
// mode, not a new view.

import SwiftUI
import DesignSystem

struct NumPadSheet: View {
    let title: String
    let unit: String?
    let initialValue: Double
    let step: Double
    let allowsDecimal: Bool
    let subtitle: String?
    let confirmTitle: String
    let onCommit: (Double) -> Void

    @State private var buffer: String = ""
    @State private var primed: Bool = false

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                readout
                nudgeRow
                DSKeypad(
                    onDigit: pressDigit,
                    onDelete: pressDelete,
                    onDecimal: allowsDecimal ? pressDecimal : nil
                )
                DSButton(
                    title: confirmTitle,
                    style: .primary,
                    action: commit
                )
            }
            .padding(DSSpacing.xl)
        }
        .onAppear(perform: primeBuffer)
        .presentationDetents([.fraction(0.7), .large])
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.sm) {
                Text(title)
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                if let unit {
                    Text("(\(unit))")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundDim)
            }
        }
    }

    private var readout: some View {
        Text(displayBuffer)
            .font(.system(size: 48, weight: .light, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(DSColors.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.lg)
    }

    private var nudgeRow: some View {
        HStack(spacing: DSSpacing.md) {
            DSButton(
                title: "− \(formattedStep)",
                style: .ghost,
                action: { nudge(-step) }
            )
            DSButton(
                title: "+ \(formattedStep)",
                style: .ghost,
                action: { nudge(step) }
            )
        }
    }

    // MARK: - Buffer

    private var displayBuffer: String {
        buffer.isEmpty ? "0" : buffer
    }

    private var formattedStep: String {
        if step.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(step))
        }
        return String(format: "%.1f", step)
    }

    private func primeBuffer() {
        guard !primed else { return }
        primed = true
        if initialValue.truncatingRemainder(dividingBy: 1) == 0 {
            buffer = String(Int(initialValue))
        } else {
            buffer = String(format: "%g", initialValue)
        }
    }

    private func pressDigit(_ digit: Int) {
        let d = String(digit)
        if buffer == "0" {
            buffer = d
        } else {
            buffer.append(d)
        }
    }

    private func pressDelete() {
        if buffer.isEmpty {
            return
        }
        buffer.removeLast()
        if buffer.isEmpty { buffer = "0" }
    }

    private func pressDecimal() {
        if buffer.contains(".") { return }
        if buffer.isEmpty { buffer = "0" }
        buffer.append(".")
    }

    private func nudge(_ delta: Double) {
        let current = Double(buffer) ?? initialValue
        let next = (current + delta).rounded(toPlaces: 2)
        if next.truncatingRemainder(dividingBy: 1) == 0 {
            buffer = String(Int(next))
        } else {
            buffer = String(format: "%g", next)
        }
    }

    private func commit() {
        let value = Double(buffer) ?? 0
        onCommit(value)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
