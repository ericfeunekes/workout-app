// DSCard.swift
//
// Surface container with rounded corners and a hairline border. Mirrors `.card`
// in `docs/design/styles/hifi.css`. The container is a pure wrapper — it
// doesn't own content layout, rows, or dividers. Callers stack child views with
// their own spacing and use `DSDivider` between rows.
//
// Uses tokens: `DSColors.surface` (fill), `DSColors.border` (stroke),
// `DSSpacing.xl` (inner padding default).

import SwiftUI

/// A card surface — rounded rect with a 1pt border on the divider color.
///
/// - Parameters:
///   - padding: Inner padding. Defaults to `DSSpacing.xl` (16pt). Pass `.zero`
///     when child rows want to handle their own padding (e.g. a list card
///     where each row has per-side inset).
///   - content: The card contents.
public struct DSCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = DSSpacing.xl, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(DSColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .strokeBorder(DSColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
    }
}

/// A hairline horizontal divider. Use between rows inside a `DSCard`.
public struct DSDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(DSColors.divider)
            .frame(height: 1)
    }
}

#Preview {
    VStack(spacing: DSSpacing.lg) {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("today").font(DSTypography.title)
                Text("4 exercises · 45 min").font(DSTypography.caption)
            }
        }
        DSCard(padding: 0) {
            VStack(spacing: 0) {
                Text("row 1").font(DSTypography.body).padding()
                DSDivider()
                Text("row 2").font(DSTypography.body).padding()
            }
        }
    }
    .padding()
    .background(DSColors.background)
}
