// Radius.swift
//
// Corner-radius scale. Primitives that use `RoundedRectangle(cornerRadius:)`
// should pull from `DSRadius` rather than hard-coded values so the visual
// language stays coherent across cards, buttons, pills, sheets, and the
// numeric keypad.
//
// Visual QA flagged the previous inconsistency (card=18, button=16, keypad
// key=14, pill=10) as a noticeable rhythm break — this token centralizes
// the choices.

import CoreGraphics

/// Corner-radius scale in points. Enum-as-namespace; access via
/// `DSRadius.card`, etc.
///
/// The scale is hand-tuned rather than mathematical — different component
/// sizes want different visual softness. A generic "small / medium / large"
/// would either make buttons too boxy (everyone uses 16) or cards too
/// fluffy (everyone uses 20). Picking names per component locks intent.
public enum DSRadius {
    /// `8pt` — smallest rounded element. Chip, badge, inline pill.
    public static let pill: CGFloat = 10

    /// `12pt` — keypad keys, sheet action buttons, compact controls.
    public static let control: CGFloat = 14

    /// `16pt` — primary buttons, action bars.
    public static let button: CGFloat = 16

    /// `16pt` — cards and containers. Matches buttons so card-on-card
    /// nesting feels coherent; previously 18 vs 16 created a subtle
    /// staircase effect that visual QA called out (bug-026).
    public static let card: CGFloat = 16

    /// `24pt` — sheet containers, full-screen modal cards.
    public static let sheet: CGFloat = 24
}
