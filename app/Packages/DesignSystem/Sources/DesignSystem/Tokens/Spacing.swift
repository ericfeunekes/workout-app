// Spacing.swift
//
// 4-point spacing scale. All primitive padding and gaps should pull from here
// rather than hard-coded CGFloat literals; the scale keeps visual rhythm
// consistent and makes a future "compact" pass a one-line change.

import CoreGraphics

/// Spacing scale in points. Enum-as-namespace; access via `DSSpacing.md`, etc.
///
/// The scale doubles roughly every step (2, 4, 8, 12, 16, 24, 40). Matches the
/// spacing rhythm in `docs/design/styles/hifi.css` (6px / 8px / 12px / 16px /
/// 20px / 24px / 32px — we quantize to 4pt multiples with a 2pt `xs` fine tier
/// for tight grouping).
public enum DSSpacing {
    /// `2pt` — tightest grouping (letter-spacing compensation, pip gutters).
    public static let xs: CGFloat = 2

    /// `4pt` — inline label-to-value, baseline-offset adjustments.
    public static let sm: CGFloat = 4

    /// `8pt` — default gap between adjacent elements in a row.
    public static let md: CGFloat = 8

    /// `12pt` — card inner padding, row padding inline.
    public static let lg: CGFloat = 12

    /// `16pt` — card outer margin, screen-edge padding.
    public static let xl: CGFloat = 16

    /// `24pt` — section spacing.
    public static let xxl: CGFloat = 24

    /// `40pt` — large hero spacing (rest hero, completion card).
    public static let xxxl: CGFloat = 40
}
