// DSKeypad.swift
//
// Numeric keypad for load/reps entry. Mirrors `.keypad` / `.key` in
// `docs/design/styles/hifi.css` — 3-column grid, tall keys, mono font.
// Decimal key is optional (hidden for reps entry, shown for load).
//
// The keypad emits taps via callbacks; state lives with the caller (sheet that
// owns the in-progress number buffer). No business logic here.
//
// Uses tokens: `DSColors.surfaceElevated` (key fill), `DSColors.surfaceHigh`
// (pressed), `DSColors.border` (stroke), `DSTypography.monoLarge` (digit),
// `DSSpacing.md` (gutter), `DSAnimation.quick` (press).

import SwiftUI

/// A 3-column numeric keypad. 3×4 by default (digits, decimal/0/delete);
/// 3×5 when `onDone` is provided (adds a full-width "done" row at the
/// bottom so the user can confirm without reaching for a separate button
/// at the screen's base — one-handed thumb ergonomics).
///
/// - Parameters:
///   - onDigit: Fired with `0...9` when a digit key is tapped.
///   - onDelete: Fired when the delete (backspace) key is tapped.
///   - onDecimal: If non-nil, a decimal-point key is rendered in the bottom-left
///     slot and fires this on tap. Pass `nil` for integer-only entry (reps).
///   - onDone: If non-nil, a full-width "done" row is rendered under the
///     keypad and fires this on tap. The caller owns the label so the action
///     can be context-specific ("log", "save", "set").
///   - doneLabel: Text displayed on the full-width done row. Ignored when
///     `onDone` is nil. Defaults to "done".
public struct DSKeypad: View {
    private let onDigit: (Int) -> Void
    private let onDelete: () -> Void
    private let onDecimal: (() -> Void)?
    private let onDone: (() -> Void)?
    private let doneLabel: String

    public init(
        onDigit: @escaping (Int) -> Void,
        onDelete: @escaping () -> Void,
        onDecimal: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        doneLabel: String = "done"
    ) {
        self.onDigit = onDigit
        self.onDelete = onDelete
        self.onDecimal = onDecimal
        self.onDone = onDone
        self.doneLabel = doneLabel
    }

    public var body: some View {
        VStack(spacing: DSSpacing.md) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: 3),
                spacing: DSSpacing.md
            ) {
                ForEach(1...9, id: \.self) { digit in
                    digitKey(digit)
                }
                decimalOrSpacer()
                digitKey(0)
                deleteKey()
            }
            if let onDone {
                doneRow(onDone: onDone)
            }
        }
    }

    private func doneRow(onDone: @escaping () -> Void) -> some View {
        Button(action: onDone, label: {
            Text(doneLabel)
                .font(DSTypography.body)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(DSColors.accentInk)
                .background(DSColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        })
        .buttonStyle(.plain)
        .accessibilityLabel(Text(doneLabel))
    }

    private func digitKey(_ digit: Int) -> some View {
        Button(action: { onDigit(digit) }, label: {
            Text("\(digit)")
                .font(DSTypography.monoLarge)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.6, contentMode: .fit)
                .foregroundStyle(DSColors.foreground)
                .background(DSColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                        .strokeBorder(DSColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        })
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(digit)"))
    }

    @ViewBuilder
    private func decimalOrSpacer() -> some View {
        if let onDecimal {
            Button(action: onDecimal) {
                Text(".")
                    .font(DSTypography.monoLarge)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.6, contentMode: .fit)
                    .foregroundStyle(DSColors.foreground)
                    .background(DSColors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                            .strokeBorder(DSColors.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("decimal point"))
        } else {
            Color.clear.aspectRatio(1.6, contentMode: .fit)
        }
    }

    private func deleteKey() -> some View {
        Button(action: onDelete) {
            Image(systemName: "delete.left")
                .font(.system(size: 18, weight: .regular))
                .frame(maxWidth: .infinity)
                .aspectRatio(1.6, contentMode: .fit)
                .foregroundStyle(DSColors.foreground)
                .background(DSColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                        .strokeBorder(DSColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("delete"))
    }
}

#Preview("no done row") {
    VStack {
        DSKeypad(
            onDigit: { _ in },
            onDelete: {},
            onDecimal: {}
        )
        .padding()
    }
    .background(DSColors.background)
}

#Preview("inline done row") {
    VStack {
        DSKeypad(
            onDigit: { _ in },
            onDelete: {},
            onDecimal: {},
            onDone: {},
            doneLabel: "log"
        )
        .padding()
    }
    .background(DSColors.background)
}
