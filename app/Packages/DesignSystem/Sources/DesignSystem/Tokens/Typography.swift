// Typography.swift
//
// Type ramp. Rule (from docs/design/RULES.md § "Copywriting rules"):
//   - Monospace (IBM Plex Mono) for anything numeric.
//   - Sans (Inter / SF) for labels and body copy.
//   - Display (SF Pro Display) for large titles.
//
// TODO: Bundle "IBM Plex Mono" and "Inter" as package resources once the font
// files are approved for redistribution. Until then, `Font.custom(...)` falls
// back to the system default silently (iOS behavior), so we explicitly compose
// `.system(...)` variants with `.monospaced()` / `.rounded()` design hints so
// the package compiles and looks sensible in previews without the assets.

import SwiftUI

/// Named type ramp for WorkoutDB.
///
/// Enum-as-namespace. Access via `DSTypography.display`, etc. Each token is a
/// `SwiftUI.Font` — use with `.font(DSTypography.body)`.
///
/// Ramp (sizes chosen from `docs/design/styles/hifi.css`, adjusted for
/// gym-arm's-length legibility per bug-021 / bug-022 visual QA):
///   - `display` (32pt, bold, sans) — large-title headings ("Today", "Complete").
///   - `title` (20pt, semibold, sans) — section titles, sheet titles.
///   - `subtitle` (14pt, semibold, sans) — meta rows that need to read at
///     arm's length (set counter, rest duration on Active).
///   - `body` (15pt, regular, sans) — default body copy.
///   - `caption` (11pt, regular, mono, uppercase intent) — purely decorative
///     kickers where legibility isn't load-bearing.
///   - `subLabel` (12pt, medium, mono) — mandatory-legibility sub-labels
///     under numeric values (KG / REPS / RIR on the just-logged pills).
///   - `mono` (14pt, regular, mono) — ledger cells, numeric values inline.
///   - `monoLarge` (22pt, medium, mono, tabular) — rest timer, chunky numerics.
///
/// The 11pt `caption` was consciously kept (kickers that sit beside
/// uppercase body text, where micro-size matches the visual rhythm), but
/// every call site that needs a user to act on the value now moves to
/// `subtitle` (for mixed-case sub-headers) or `subLabel` (for uppercase
/// numeric captions).
public enum DSTypography {
    /// Large display — `32pt` semibold/bold sans. For screen titles.
    public static let display = Font.system(size: 32, weight: .bold, design: .default)

    /// Screen / sheet title — `20pt` semibold sans.
    public static let title = Font.system(size: 20, weight: .semibold, design: .default)

    /// Meta / sub-header — `14pt` semibold sans. Sits between `caption` and
    /// `body` on the ramp. Use for meta-rows where the user has to *read
    /// and act on* the content at arm's length (set counter on Active,
    /// "BETWEEN BLOCKS" label on Rest). Introduced per bug-022 — `caption`
    /// at 11pt is fine for decorative kickers but too small for the "Set 1
    /// of 4 · Rest 0:15" line under the exercise name.
    public static let subtitle = Font.system(size: 14, weight: .semibold, design: .default)

    /// Default body copy — `15pt` regular sans.
    public static let body = Font.system(size: 15, weight: .regular, design: .default)

    /// Caption / kicker — `11pt` regular mono. Pair with `.textCase(.uppercase)`
    /// and a tracked letter-spacing on the rendering site (SwiftUI's
    /// `.tracking(1.5)`). Use for purely decorative kickers; anything the
    /// user has to read quickly belongs on `subtitle` or `subLabel`.
    public static let caption = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// Numeric sub-label — `12pt` medium mono. The small uppercase caption
    /// that sits under a larger numeric value (e.g. "KG" under "102.5",
    /// "REPS" under "5"). Introduced per bug-021 — the prior 9pt mono was
    /// unreadable at gym arm's length. Pair with `.textCase(.uppercase)`
    /// and `.tracking(1.2)` on the rendering site.
    public static let subLabel = Font.system(size: 12, weight: .medium, design: .monospaced)

    /// Numeric inline text — `14pt` regular mono. For ledger cells, editable
    /// values, plan sheet numbers.
    public static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// Hero numeric — `22pt` medium mono. Pair with `.monospacedDigit()` on the
    /// rendering site to force tabular figures.
    public static let monoLarge = Font.system(size: 22, weight: .medium, design: .monospaced)
}
