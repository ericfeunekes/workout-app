// LoadFormatting.swift
//
// Render load values for display. The app stores `set_log.weight` in the unit
// the user entered (see `weight_unit`), and display surfaces render in that
// same unit — no conversion at the display boundary. These helpers keep
// formatting consistent so "100 kg" doesn't show up as "100.0 kg" in one place
// and "100 kg" in another.

import Foundation

/// Unit suffix for a rendered load. Mirror of the Domain `WeightUnit` raw
/// values ("kg" / "lb") — kept here because `Core/Foundation` has no
/// dependencies (see `docs/architecture/swift-packages.md`) and the formatter
/// has to work without importing Domain.
///
/// Contract test in `Tests/WorkoutCoreFoundationTests/main.swift` pins
/// `rawValue` equality against the expected strings; Domain's `WeightUnit`
/// has the same raw values, so callers can bridge with `LoadUnit(rawValue:
/// weightUnit.rawValue)` and `fatalError` on a miss (they already know the
/// two enums are in lockstep via contract test coverage at that layer).
public enum LoadUnit: String, Sendable, CaseIterable, Hashable {
    case kg
    case lb
}

/// Render a load for display in its recorded unit.
///
/// - Parameters:
///   - weight: The numeric load in `unit`'s scale. `nil` means bodyweight.
///   - unit: The unit the value is in. Rendered as the suffix verbatim.
///   - bodyweightAdded: When `weight` is non-nil, `true` renders "BW + 20 kg"
///     (weighted dips, weighted chin-ups). `false` renders a plain "20 kg".
/// - Returns: A display string.
///
/// Integer-valued loads drop the trailing `.0` ("100 kg", not "100.0 kg").
/// Non-integer loads render with up to two decimal places and no trailing
/// zeros ("102.5 kg", "101.25 kg", "2.5 kg"). Two-decimal support is for
/// equipment with 1.25 kg fractional plates — autoreg-computed values like
/// `101.25` used to render as `"101.2 kg"` under the old `%.1f` format.
/// Negative inputs are passed through as-is — callers validate.
///
/// Zero handling: `weight: 0` is treated as a literal numeric value, not as
/// bodyweight. `formatLoad(weight: nil, ...)` is "BW"; `formatLoad(weight: 0,
/// unit: .kg)` is "0 kg"; `formatLoad(weight: 0, unit: .kg, bodyweightAdded:
/// true)` is "BW + 0 kg". The convention: `nil` means "no external load" and
/// is semantically distinct from "zero added". Callers that want a pure
/// bodyweight chin-up to render as "BW" should pass `nil`, not `0`.
public func formatLoad(
    weight: Double?,
    unit: LoadUnit,
    bodyweightAdded: Bool = false
) -> String {
    guard let weight else {
        return "BW"
    }
    let number = formatLoadNumber(weight)
    if bodyweightAdded {
        return "BW + \(number) \(unit.rawValue)"
    }
    return "\(number) \(unit.rawValue)"
}

/// Kilogram-only overload preserved for the existing execution-time callers
/// (ActiveView hero load, rest banner, circuit ledger, EMOM / AMRAP / etc.
/// drivers). V0 prescriptions are authored in kg, so those sites stay kg-only
/// until a lb prescription path exists. History rendering MUST use the
/// unit-aware `formatLoad(weight:unit:)` — call sites were bug-prone when
/// only a kg variant existed.
public func formatLoad(kg: Double?, bodyweightAdded: Bool = false) -> String {
    formatLoad(weight: kg, unit: .kg, bodyweightAdded: bodyweightAdded)
}

/// Format a numeric load as a compact number string: "100", "102.5",
/// "101.25", "2.5".
///
/// Exposed so places that embed the number in a longer template (e.g. an
/// autoreg proposal banner) can reuse the same precision rules without
/// reconstructing them.
///
/// Precision: integer-valued loads drop the trailing `.0` ("100", not
/// "100.0"). Non-integer loads render with up to two decimal places and
/// trailing zeros trimmed — "101.25" stays "101.25", "102.50" becomes
/// "102.5", "2.5" stays "2.5". Values beyond two decimal places are
/// rounded to two (the gym-equipment granularity ceiling — no plate is
/// 0.005 kg); this keeps the display compact when floating-point
/// arithmetic produces `100.25000000000003`-style artifacts.
public func formatLoadNumber(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        // Exact integer value; render without decimals.
        return String(Int(value))
    }
    // Two-decimal max, then strip trailing zeros (and the `.` if everything
    // after it was stripped). Using `%g` would collapse trailing zeros but
    // also switches to scientific notation past six significant digits,
    // which is not what we want for load values; hand-rolling the trim is
    // clearer and avoids the surprise.
    var formatted = String(format: "%.2f", value)
    while formatted.hasSuffix("0") {
        formatted.removeLast()
    }
    if formatted.hasSuffix(".") {
        formatted.removeLast()
    }
    return formatted
}

/// Back-compat alias for `formatLoadNumber`. The kilogram-specific name was
/// misleading once lb rows landed — the function is unit-agnostic (it just
/// formats a Double). Kept so existing callers (`SessionDetailViewModel`'s
/// bodyweight readout, EditSetSheet's load buffer) don't churn in the same
/// slice as the unit-aware rendering fix.
public func formatKilograms(_ kg: Double) -> String {
    formatLoadNumber(kg)
}
