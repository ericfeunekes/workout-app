// DurationFormatting.swift
//
// Render durations for timers and rest countdowns. Matches the conventions in
// docs/design/ (mm:ss for under an hour, h:mm:ss for an hour or more).

import Foundation

/// Render a duration in seconds as "m:ss" or "h:mm:ss".
///
/// - Parameter seconds: Duration in seconds. Fractional seconds are truncated
///   toward zero (a 2.9 s duration renders as "0:02"). Negative inputs render
///   as "0:00" — the UI should never show a negative rest countdown, so this
///   clamps defensively.
///
/// Examples:
///   - 0     -> "0:00"
///   - 45    -> "0:45"
///   - 90    -> "1:30"
///   - 180   -> "3:00"
///   - 754   -> "12:34"
///   - 3661  -> "1:01:01"
public func formatDuration(seconds: Double) -> String {
    let clamped = max(0, Int(seconds))
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let secs = clamped % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

/// Convenience overload for integer-second inputs.
public func formatDuration(seconds: Int) -> String {
    formatDuration(seconds: Double(seconds))
}
