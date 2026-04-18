// Colors.swift
//
// Dark-mode-only color tokens. Eric confirmed the app is dark-only (gym lighting
// justifies it). No light palette, no system-controlled appearance toggle.
//
// Hex values approximate the CSS tokens in `docs/design/styles/hifi.css`. The
// `oklch(...)` accent/warn/ok swatches are converted to nearest sRGB; the rest
// are direct hex translations. If the reference CSS moves, resync these.

import SwiftUI

/// Dark-mode color tokens for WorkoutDB.
///
/// Enum-as-namespace pattern: `DSColors` cannot be instantiated. Access members
/// via `DSColors.background`. Every token is a `SwiftUI.Color` so it can be
/// used as a fill, stroke, or `foregroundStyle` directly.
///
/// Grouping mirrors the CSS custom-property cascade:
///   - backgrounds: `background`, `surface`, `surfaceElevated`, `surfaceHigh`
///   - text: `foreground`, `foregroundMuted`, `foregroundDim`, `foregroundFaint`
///   - accent (terracotta): `accent`, `accentMuted`, `accentInk`
///   - structure: `divider`, `border`
///   - status: `warn`, `success`, `danger`
public enum DSColors {
    // MARK: - Backgrounds

    /// Base app background — warm near-black. Hex: `#0f0e0c`.
    /// CSS: `--bg`.
    public static let background = Color(red: 0x0F / 255.0, green: 0x0E / 255.0, blue: 0x0C / 255.0)

    /// Primary surface (cards, nav bar, keypad). Hex: `#1a1815`. CSS: `--surface`.
    public static let surface = Color(red: 0x1A / 255.0, green: 0x18 / 255.0, blue: 0x15 / 255.0)

    /// Elevated surface (editable cells, scope buttons). Hex: `#24211c`.
    /// CSS: `--surface-2`.
    public static let surfaceElevated = Color(red: 0x24 / 255.0, green: 0x21 / 255.0, blue: 0x1C / 255.0)

    /// Highest surface tier (pressed keypad key, progress-pip background).
    /// Hex: `#2e2a24`. CSS: `--surface-3`.
    public static let surfaceHigh = Color(red: 0x2E / 255.0, green: 0x2A / 255.0, blue: 0x24 / 255.0)

    // MARK: - Foreground (text and iconography)

    /// Primary text (display headings, body). Hex: `#f5f1e8`. CSS: `--ink`.
    public static let foreground = Color(red: 0xF5 / 255.0, green: 0xF1 / 255.0, blue: 0xE8 / 255.0)

    /// Secondary text (labels, subtitles). Hex: `#c2bcae`. CSS: `--ink-2`.
    public static let foregroundMuted = Color(red: 0xC2 / 255.0, green: 0xBC / 255.0, blue: 0xAE / 255.0)

    /// Kicker / uppercase caption tier. Hex: `#8a8478`. CSS: `--ink-3`.
    public static let foregroundDim = Color(red: 0x8A / 255.0, green: 0x84 / 255.0, blue: 0x78 / 255.0)

    /// Lowest-contrast text (pending / disabled, chevrons). Hex: `#524e44`.
    /// CSS: `--ink-4`.
    public static let foregroundFaint = Color(red: 0x52 / 255.0, green: 0x4E / 255.0, blue: 0x44 / 255.0)

    // MARK: - Accent (terracotta)

    /// Primary accent — terracotta. Hex approx `#d28766`. CSS: `--accent`
    /// `oklch(0.72 0.14 35)`.
    public static let accent = Color(red: 0xD2 / 255.0, green: 0x87 / 255.0, blue: 0x66 / 255.0)

    /// Muted accent background (accent pill, active editable cell).
    /// Hex approx `#4d342a`. CSS: `--accent-soft` `oklch(0.32 0.06 35)`.
    public static let accentMuted = Color(red: 0x4D / 255.0, green: 0x34 / 255.0, blue: 0x2A / 255.0)

    /// Accent-tinted text (rest hero, accent pill text). Hex approx `#e8a896`.
    /// CSS: `--accent-ink` `oklch(0.82 0.1 35)`.
    public static let accentInk = Color(red: 0xE8 / 255.0, green: 0xA8 / 255.0, blue: 0x96 / 255.0)

    // MARK: - Structure

    /// Hairline stroke between cells. Hex: `#36322b`. CSS: `--stroke`.
    public static let divider = Color(red: 0x36 / 255.0, green: 0x32 / 255.0, blue: 0x2B / 255.0)

    /// Border around containers — same as `divider` in the reference CSS;
    /// exposed as a distinct token so we can diverge if containers need it.
    public static let border = Color(red: 0x36 / 255.0, green: 0x32 / 255.0, blue: 0x2B / 255.0)

    // MARK: - Status

    /// Warn / undershoot amber. Hex approx `#d6a23a`. CSS: `--warn`
    /// `oklch(0.72 0.15 75)`.
    public static let warn = Color(red: 0xD6 / 255.0, green: 0xA2 / 255.0, blue: 0x3A / 255.0)

    /// Success / overshoot sage. Hex approx `#6bb896`. CSS: `--ok`
    /// `oklch(0.72 0.12 150)`.
    public static let success = Color(red: 0x6B / 255.0, green: 0xB8 / 255.0, blue: 0x96 / 255.0)

    /// Destructive action (delete, reset). Same channel as `accent` for now —
    /// we don't have a distinct "danger" swatch in the reference CSS.
    /// Hex approx `#d27266`.
    public static let danger = Color(red: 0xD2 / 255.0, green: 0x72 / 255.0, blue: 0x66 / 255.0)
}
