// DSPill.swift
//
// Larger labeled pill for logged sets on the rest screen. Larger than `DSChip`,
// with a bigger value face and a small caption underneath (e.g. value "102.5"
// caption "KG" or value "5" caption "REPS"). Tappable variant for edit entry.
//
// Uses tokens: `DSColors.surfaceElevated` (fill), `DSColors.surfaceHigh`
// (pressed), `DSColors.accent` (editable highlight), `DSTypography.monoLarge`
// (value), `DSTypography.caption` (caption), `DSSpacing.sm..lg` (padding).

import SwiftUI

/// A labeled numeric pill. Larger sibling to `DSChip` — used where the number
/// is the focal element (the just-did row on the rest screen).
///
/// - Parameters:
///   - value: The numeric value displayed prominently (mono, tabular).
///   - caption: Optional caption below the value (uppercase, mono, small).
///   - isEditable: When `true`, hints tappability visually (accent stroke).
///   - onTap: Tap callback. Passing `nil` disables interaction regardless of
///     `isEditable`.
public struct DSPill: View {
    private let value: String
    private let caption: String?
    private let isEditable: Bool
    private let onTap: (() -> Void)?

    public init(
        value: String,
        caption: String? = nil,
        isEditable: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.value = value
        self.caption = caption
        self.isEditable = isEditable
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }, label: {
            VStack(spacing: DSSpacing.xs) {
                Text(value)
                    .font(DSTypography.monoLarge)
                    .monospacedDigit()
                    .foregroundStyle(isEditable ? DSColors.accentInk : DSColors.foreground)
                if let caption {
                    // Uses `DSTypography.subLabel` (12pt medium mono) —
                    // the prior 9pt was unreadable at arm's length in
                    // a gym (bug-021). Tracking is eased to `1.2` so
                    // the larger glyphs don't spread too wide.
                    Text(caption.uppercased())
                        .font(DSTypography.subLabel)
                        .tracking(1.2)
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.lg)
            .background(isEditable ? DSColors.accentMuted : DSColors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.pill, style: .continuous)
                    .strokeBorder(isEditable ? DSColors.accent : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.pill, style: .continuous))
        })
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(Text(caption.map { "\(value) \($0)" } ?? value))
    }
}

#Preview {
    HStack(spacing: DSSpacing.md) {
        DSPill(value: "102.5", caption: "kg", isEditable: true, onTap: {})
        DSPill(value: "5", caption: "reps", isEditable: true, onTap: {})
        DSPill(value: "2", caption: "rir")
    }
    .padding()
    .background(DSColors.background)
}
