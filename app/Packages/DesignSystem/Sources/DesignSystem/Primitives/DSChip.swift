// DSChip.swift
//
// Small uppercase-mono pill for kicker labels like "LAST SESSION · FRI". Mirrors
// `.pill` in `docs/design/styles/hifi.css`. When a value is paired with a label
// (value only shown in mono numeric), renders them inline separated by a mid-dot.
//
// Uses tokens: `DSTypography.caption` (label + value), `DSColors.surfaceElevated`
// (default fill), `DSColors.accentMuted` / `DSColors.accentInk` (accent tone),
// `DSColors.foregroundDim` (muted tone).

import SwiftUI

/// Visual tone for a `DSChip`.
public enum ChipTone {
    /// Neutral fill on elevated surface.
    case `default`
    /// Accent-tinted (terracotta) fill for primary-indicator chips.
    case accent
    /// Lower-contrast variant — surface fill with dim foreground.
    case muted
}

/// A compact uppercase-mono chip. Value is optional — when present, it appears
/// after the label separated by a mid-dot (matching "LAST SESSION · FRI").
///
/// - Parameters:
///   - label: The label text; auto-uppercased at render time.
///   - value: Optional numeric or short-token suffix.
///   - tone: Visual tone.
public struct DSChip: View {
    private let label: String
    private let value: String?
    private let tone: ChipTone

    public init(label: String, value: String? = nil, tone: ChipTone = .default) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(label.uppercased())
                .font(DSTypography.caption)
                .tracking(0.5)
            if let value {
                Text("·")
                    .font(DSTypography.caption)
                    .opacity(0.6)
                Text(value)
                    .font(DSTypography.caption)
                    .tracking(0.5)
            }
        }
        .foregroundStyle(foreground)
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.lg - DSSpacing.xs)
        .background(fill)
        .overlay(
            Capsule().strokeBorder(strokeColor, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var fill: Color {
        switch tone {
        case .default: return DSColors.surfaceElevated
        case .accent: return DSColors.accentMuted
        case .muted: return DSColors.surface
        }
    }

    private var foreground: Color {
        switch tone {
        case .default: return DSColors.foregroundMuted
        case .accent: return DSColors.accentInk
        case .muted: return DSColors.foregroundDim
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .default: return DSColors.border
        case .accent: return DSColors.accent.opacity(0.3)
        case .muted: return DSColors.border
        }
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        DSChip(label: "last session", value: "fri")
        DSChip(label: "personal best", value: "102.5 kg", tone: .accent)
        DSChip(label: "offline", tone: .muted)
    }
    .padding()
    .background(DSColors.background)
}
