// PrescriptionLineFormatter.swift
//
// Renders a `Prescription` as the one-line summary shown on the Today
// exercise row, matching the hi-fi reference ("4 × 5 @ 102.5 kg",
// "3 × 8 @ 80 kg", etc. — see docs/design/src/hifi.jsx:9-40).
//
// Only the common shapes are covered to sensible strings. Exotic shapes
// (cluster, setsDetail, warmup, amrapToken, empty) render a best-effort
// fallback that never crashes. The Today screen is a glance view — if a
// prescription is too complex to summarize in one line, we hand the user
// enough to recognise the exercise and defer the detail to the plan sheet.
//
// Numeric text always goes through `formatKilograms` so "100 kg" renders
// as "100 kg" (not "100.0 kg") and "102.5 kg" stays as "102.5 kg".
//
// Per docs/design/RULES.md § "RIR (Reps In Reserve)" the system is
// RIR-only — reps-in-reserve is expressed as "RIR n" when it surfaces.

import Foundation
import CoreDomain
import CorePrescription
import WorkoutCoreFoundation

/// Produce a one-line prescription summary for the Today row.
///
/// Delimits sets/reps with " × " (U+00D7, real multiplication sign) to
/// match the hi-fi prototype; load is suffixed with " @ <value> <unit>".
/// Unit defaults to `.lb` when a prescription omits `weight_unit`
/// (docs/prescription.md § "Units").
public func formatPrescriptionLine(_ prescription: Prescription) -> String {
    switch prescription {
    case .straightSets(let sets, let reps, let loadKg, let unit, _, _, _, _):
        return straightSetsLine(sets: sets, reps: reps, loadKg: loadKg, unit: unit)

    case .percentOf1RM(let sets, let reps, let percent, _):
        // e.g. "4 × 5 @ 85% 1RM"
        let pctText = formatPercent(percent)
        return "\(sets) × \(reps) @ \(pctText) 1RM"

    case .repRange(let sets, let repsMin, let repsMax, let loadKg, let unit, _, _):
        // e.g. "3 × 8–12 @ 60 kg" or "3 × 8–12" when bodyweight-ish
        let repsText = "\(repsMin)\u{2013}\(repsMax)"
        if let loadKg {
            return "\(sets) × \(repsText) @ \(loadText(loadKg, unit: unit))"
        }
        return "\(sets) × \(repsText)"

    case .bodyweight(let sets, let reps, _):
        // "3 × 10 BW"
        return "\(sets) × \(reps) BW"

    case .cluster(let sets, let reps, let loadKg, let unit, let subSets, _, _):
        // "4 × (3 × 5) @ 100 kg" — condensed cluster summary
        return "\(sets) × (\(subSets) × \(reps)) @ \(loadText(loadKg, unit: unit))"

    case .setsDetail(let details, _, _, _):
        // Fall back to the count of entries; the plan sheet shows the rest.
        let n = details.count
        return n == 1 ? "1 set" : "\(n) sets"

    case .amrapToken(let loadKg, let unit, _):
        if let loadKg {
            return "AMRAP @ \(loadText(loadKg, unit: unit))"
        }
        return "AMRAP"

    case .warmup(let sets, let reps, let loadKg, let unit):
        if let loadKg {
            return "warmup · \(sets) × \(reps) @ \(loadText(loadKg, unit: unit))"
        }
        return "warmup · \(sets) × \(reps)"

    case .empty:
        // The item's work lives on the block (continuous / intervals /
        // tabata / rest / custom). Nothing terse to say here.
        return ""
    }
}

// MARK: - Helpers

private func loadText(_ kg: Double, unit: WeightUnit) -> String {
    // swiftlint:disable:next force_unwrapping
    let loadUnit = LoadUnit(rawValue: unit.rawValue)!
    return "\(formatLoadNumber(kg)) \(loadUnit.rawValue)"
}

private func straightSetsLine(sets: Int?, reps: RepCount?, loadKg: Double?, unit: WeightUnit) -> String {
    let setsText = sets.map(String.init)
    let repsText: String? = reps.flatMap { rc in
        switch rc {
        case .count(let n): return String(n)
        case .amrap: return "AMRAP"
        }
    }
    let sxr: String? = {
        switch (setsText, repsText) {
        case let (s?, r?): return "\(s) × \(r)"
        case (let s?, nil): return s
        case (nil, let r?): return r
        case (nil, nil): return nil
        }
    }()

    let load: String? = loadKg.map { loadText($0, unit: unit) }

    switch (sxr, load) {
    case let (core?, load?): return "\(core) @ \(load)"
    case (let core?, nil): return core
    case (nil, let load?): return load
    case (nil, nil): return ""
    }
}

private func formatPercent(_ fraction: Double) -> String {
    // Prescriptions express `percent_1rm` as a fraction in 0.0...1.0
    // (see docs/prescription.md § "percent_1rm"). Render as an integer
    // percentage — decimal percentages are noise at a glance.
    let pct = Int((fraction * 100.0).rounded())
    return "\(pct)%"
}
