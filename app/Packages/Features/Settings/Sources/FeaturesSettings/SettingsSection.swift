// SettingsSection.swift
//
// Data-driven section / row model for the Settings screen. Adding a row is
// appending a struct value to an array — the view iterates the array and
// picks the right DS primitive per `SettingsRow` case.
//
// Why this shape: HS-4 ("settings mega-view") calls out the failure mode of
// a giant `VStack` that grows every time a knob is added. Keeping the UI a
// pure function of `[SettingsSection]` lets the viewModel own all logic
// (which row has which default, which destructive confirm to wire) and
// keeps `SettingsView` a dumb renderer.
//
// Equality: `SettingsRow` carries trailing closures (`onPick`, `onTap`).
// Swift cannot synthesize `Equatable` for closures, so we mark the type
// `@unchecked Sendable` and define identity via the row's `id` — tests and
// snapshot comparisons should assert on `id` ordering + the public value
// fields, not on closure equality.

import Foundation

/// One grouped block in the Settings list — e.g. "SERVER" with its four
/// rows underneath.
public struct SettingsSection: Identifiable, Sendable {
    /// Stable id for SwiftUI `ForEach`. Section ids are lowercase kebab
    /// ("server", "device", "autoreg-defaults", "data") so they're safe to
    /// diff on reorder.
    public let id: String
    /// ALL CAPS kicker rendered above the section (e.g. "SERVER"). One of
    /// two copy exceptions in this screen — per `docs/design/RULES.md` §
    /// "Copywriting rules", monospace labels are ALL CAPS while the rest
    /// of the app is lowercase imperative.
    public let title: String
    /// Rows in top-to-bottom order.
    public let rows: [SettingsRow]

    public init(id: String, title: String, rows: [SettingsRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// One renderable row. The view picks a primitive per case; the viewModel
/// owns the closures so the view never reaches into persistence or sync.
///
/// Equality / diffing note: identity is the row `id`. The value fields
/// (`label`, `value`, `selected`) are comparable; the closures are not.
/// See `equalsIgnoringCallbacks(_:)` for a test-friendly comparison.
public enum SettingsRow: Identifiable, Sendable {
    /// Read-only `label · value` row (e.g. "synced · 4 min ago").
    case info(id: String, label: String, value: String)
    /// Segmented picker (e.g. units kg / lb).
    case picker(
        id: String,
        label: String,
        options: [String],
        selected: String,
        onPick: @MainActor @Sendable (String) -> Void
    )
    /// Binary setting row.
    case toggle(
        id: String,
        label: String,
        isOn: Bool,
        onToggle: @MainActor @Sendable (Bool) -> Void
    )
    /// Tappable action row. `destructive` toggles the accent color per the
    /// design reference — e.g. "change server" and "reset local data".
    case action(
        id: String,
        label: String,
        destructive: Bool,
        onTap: @MainActor @Sendable () -> Void
    )

    public var id: String {
        switch self {
        case .info(let id, _, _),
             .picker(let id, _, _, _, _),
             .toggle(let id, _, _, _),
             .action(let id, _, _, _):
            return id
        }
    }

    /// Human label (what the row reads as). Pulled out so tests can assert
    /// on it without switching over the case.
    public var label: String {
        switch self {
        case .info(_, let label, _),
             .picker(_, let label, _, _, _),
             .toggle(_, let label, _, _),
             .action(_, let label, _, _):
            return label
        }
    }

    /// Compare two rows on their value fields, ignoring the attached
    /// closures. Useful for assertions over the viewModel's state.
    public func equalsIgnoringCallbacks(_ other: SettingsRow) -> Bool {
        switch (self, other) {
        case (.info(let a, let la, let va), .info(let b, let lb, let vb)):
            return a == b && la == lb && va == vb
        case (.picker(let a, let la, let o1, let s1, _),
              .picker(let b, let lb, let o2, let s2, _)):
            return a == b && la == lb && o1 == o2 && s1 == s2
        case (.toggle(let a, let la, let on1, _),
              .toggle(let b, let lb, let on2, _)):
            return a == b && la == lb && on1 == on2
        case (.action(let a, let la, let d1, _),
              .action(let b, let lb, let d2, _)):
            return a == b && la == lb && d1 == d2
        default:
            return false
        }
    }
}
