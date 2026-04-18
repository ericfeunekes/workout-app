// LoadFormatting.swift
//
// Render load values for display. The app stores load in kilograms on
// `set_log.weight` (with a `weight_unit` field for what the user entered), but
// the UI usually shows kilograms. These helpers keep formatting consistent so
// "100 kg" doesn't show up as "100.0 kg" in one place and "100 kg" in another.

import Foundation

/// Render a load for display.
///
/// - Parameters:
///   - kg: The load in kilograms. `nil` means bodyweight.
///   - bodyweightAdded: When `kg` is non-nil, `true` renders the load as
///     "BW + 20 kg" (weighted dips, weighted chin-ups). `false` renders a
///     plain "20 kg".
/// - Returns: A display string.
///
/// Integer-valued loads drop the trailing `.0` ("100 kg", not "100.0 kg").
/// Non-integer loads render with up to one decimal place ("102.5 kg",
/// "2.5 kg"). Negative inputs are passed through as-is — callers validate.
///
/// Zero handling: `kg: 0` is treated as a literal numeric value, not as
/// bodyweight. `formatLoad(kg: nil)` is "BW"; `formatLoad(kg: 0)` is "0 kg";
/// `formatLoad(kg: 0, bodyweightAdded: true)` is "BW + 0 kg". The convention
/// here: `nil` means "no external load, bodyweight only" and is semantically
/// distinct from "zero kilograms added". Callers that want a bodyweight-only
/// chin-up to render as "BW" should pass `nil`, not `0`.
public func formatLoad(kg: Double?, bodyweightAdded: Bool = false) -> String {
    guard let kg else {
        return "BW"
    }
    let number = formatKilograms(kg)
    if bodyweightAdded {
        return "BW + \(number) kg"
    }
    return "\(number) kg"
}

/// Format a kilogram value as a compact number string: "100", "102.5", "2.5".
///
/// Exposed so places that embed the number in a longer template (e.g. an
/// autoreg proposal banner) can reuse the same precision rules without
/// reconstructing them.
public func formatKilograms(_ kg: Double) -> String {
    if kg.truncatingRemainder(dividingBy: 1) == 0 {
        // Exact integer value; render without decimals.
        return String(Int(kg))
    }
    // One decimal place, no trailing zero beyond that.
    return String(format: "%.1f", kg)
}
