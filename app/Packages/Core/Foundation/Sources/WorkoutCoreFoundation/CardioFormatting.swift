// CardioFormatting.swift
//
// Render cardio-shaped summaries for the execution ledger + history views.
// Cardio logs carry `duration_sec`, `distance_m`, and a derived pace;
// the strength "N×R @ load" template doesn't map cleanly — pre-fix the
// ledger rendered cardio items as "1×0 @ BW" which is both wrong and
// illegible (qa-043). This helper picks a compact cardio shape from the
// fields that are present.
//
// Shape rules (first-match wins):
//   * duration + distance → "MM:SS · 400 m" or with a derived pace
//     ("5:30 / km") when both fields make pace meaningful (distance ≥
//     50 m so a 400 m rep doesn't surface a meaningless pace).
//   * duration only       → "MM:SS" (or "H:MM:SS" for longer efforts).
//   * distance only       → "400 m" / "5 km".
//   * neither             → "no data".
//
// Pure function — no dependency on SetPlan or any Domain type, so
// `Core/Foundation` stays leaf-level (per `docs/architecture/swift-
// packages.md`). Callers in `FeaturesExecution` pull the three fields
// off a `SetPlan` and pass them in.

import Foundation

/// Render a cardio summary from the fields a single cardio log row
/// carries. `durationSec` is the elapsed work time; `distanceM` is
/// optional distance coverage; `count` (default 1) is how many
/// repetitions of the effort were logged — when > 1 the summary
/// prefixes "N × …" (e.g. "6 × 400 m").
///
/// - Parameters:
///   - durationSec: Seconds elapsed, or nil when the log has no duration.
///   - distanceM: Metres covered, or nil when the log has no distance.
///   - count: Number of reps that share the same (duration, distance)
///     shape. Pass > 1 for interval aggregates; defaults to 1 for a
///     single continuous effort.
/// - Returns: Display string, always non-empty. Never "BW" / "0 kg".
public func formatCardioSummary(
    durationSec: Double?,
    distanceM: Double?,
    count: Int = 1
) -> String {
    let prefix = count > 1 ? "\(count) × " : ""

    if let durationSec, durationSec > 0,
       let distanceM, distanceM > 0 {
        let distance = formatCardioDistance(distanceM)
        let duration = formatDuration(seconds: durationSec)
        if count > 1 {
            // Interval aggregate — distance is the authored work amount
            // per rep; pace is the useful secondary cue.
            if let pace = formatCardioPace(
                durationSec: durationSec,
                distanceM: distanceM
            ) {
                return "\(count) × \(distance) at \(pace)"
            }
            return "\(count) × \(distance)"
        }
        if let pace = formatCardioPace(
            durationSec: durationSec,
            distanceM: distanceM
        ) {
            return "\(duration) at \(pace)"
        }
        return "\(duration) · \(distance)"
    }

    if let durationSec, durationSec > 0 {
        return "\(prefix)\(formatDuration(seconds: durationSec))"
    }

    if let distanceM, distanceM > 0 {
        return "\(prefix)\(formatCardioDistance(distanceM))"
    }

    return "no data"
}

/// Render a cardio distance in metres for the ledger / active view:
/// ≥ 1000 m renders as "N km" (integer km) or "N.N km" (one decimal);
/// below that renders as "N m" (integer) or "N.N m" (one decimal).
/// Exposed so other cardio surfaces (future history view, charts) can
/// share the same formatting.
public func formatCardioDistance(_ metres: Double) -> String {
    if metres >= 1000 {
        let km = metres / 1000.0
        if km.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(km)) km"
        }
        return String(format: "%.1f km", km)
    }
    if metres.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(metres)) m"
    }
    return String(format: "%.1f m", metres)
}

/// Derive a pace ("m:ss / km") from a duration + distance pair.
/// Returns nil when either input is non-positive or the derived pace
/// would round to 0 — a single short sprint (e.g. 5 s / 50 m) still
/// yields a usable pace, but a 400 m rep at 90 s yields a meaningful
/// 3:45 / km. We gate on `distanceM >= 50` so absurd inputs don't
/// produce sub-second paces.
public func formatCardioPace(
    durationSec: Double,
    distanceM: Double
) -> String? {
    guard durationSec > 0, distanceM >= 50 else { return nil }
    let secPerKm = durationSec / (distanceM / 1000.0)
    let total = Int(secPerKm.rounded())
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d / km", m, s)
}
