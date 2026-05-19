// DSButton.swift
//
// Primary / ghost / danger button. Mirrors `.btn`, `.btn.primary`, `.btn.ghost`
// in `docs/design/styles/hifi.css`. Tap scale-down matches the CSS `:active`.
//
// Uses tokens: `DSColors.accent` (primary fill), `DSColors.surfaceElevated`
// (default fill), `DSColors.foreground` (default label), `DSColors.border`
// (ghost stroke), `DSSpacing.xl` (padding), `DSAnimation.quick` (press scale).

import SwiftUI

/// A terse, imperative button. Matches the CSS `.btn` primitive.
///
/// Use `DSButton` for any tappable action — "Log set", "Start workout", "Save".
/// Lowercase imperative copy is expected per `docs/design/RULES.md` §
/// "Copywriting rules".
///
/// - Parameters:
///   - title: The button label. Keep it short and imperative.
///   - style: Visual weight. `.primary` for the dominant action on a screen,
///     `.ghost` for secondary actions, `.danger` for destructive.
///   - disabled: Disables taps and tones the fill down.
///   - action: Callback fired on tap.
public struct DSButton: View {
    public static let minimumHeight: CGFloat = 56

    public enum ButtonStyle {
        case primary
        case ghost
        case danger
    }

    private let title: String
    private let style: ButtonStyle
    private let disabled: Bool
    private let action: () -> Void

    public init(
        title: String,
        style: ButtonStyle = .primary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.xl)
                .padding(.horizontal, DSSpacing.xl + DSSpacing.sm)
                .frame(minHeight: Self.minimumHeight)
                .foregroundStyle(foreground)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.button, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: style == .ghost ? 1 : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .accessibilityLabel(Text(title))
    }

    private var background: Color {
        switch style {
        case .primary: return DSColors.accent
        case .ghost: return .clear
        case .danger: return DSColors.danger
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: return .white
        case .ghost: return DSColors.foregroundMuted
        case .danger: return .white
        }
    }

    private var strokeColor: Color {
        switch style {
        case .ghost: return DSColors.border
        default: return .clear
        }
    }
}

#Preview {
    VStack(spacing: DSSpacing.lg) {
        DSButton(title: "log set", style: .primary, action: {})
        DSButton(title: "skip", style: .ghost, action: {})
        DSButton(title: "reset local data", style: .danger, action: {})
        DSButton(title: "disabled", style: .primary, disabled: true, action: {})
    }
    .padding()
    .background(DSColors.background)
}
