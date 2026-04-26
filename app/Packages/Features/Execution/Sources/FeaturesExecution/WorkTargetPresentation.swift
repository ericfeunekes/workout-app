// WorkTargetPresentation.swift
//
// Execution-facing formatting and routing helpers for unit-aware work
// targets. Keep display-unit decisions here; reducers and push code keep
// canonical reps / seconds / metres.

import Foundation
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

func displayText(for target: WorkTarget) -> String {
    switch target.kind {
    case .reps:
        return "\(Int(target.value.rounded()))"
    case .duration:
        return "\(formatTargetNumber(target.value)) \(target.unit.rawValue)"
    case .distance:
        return "\(formatTargetNumber(target.value)) \(target.unit.rawValue)"
    }
}

func displayText(for set: SetPlan) -> String {
    if let target = set.workTarget {
        return displayText(for: target)
    }
    return "\(set.reps)"
}

func activeKind(for set: SetPlan) -> ActiveContent.Kind {
    guard let target = set.workTarget else { return .strength }
    switch target.kind {
    case .reps:
        return .strength
    case .duration, .distance:
        return .cardio
    }
}

func canonicalDurationForLog(set: SetPlan, elapsed: TimeInterval?) -> Double? {
    if let elapsed, set.workTarget?.kind == .duration {
        return elapsed
    }
    return set.durationSec ?? set.workTarget?.canonicalDurationSec
}

func canonicalDistanceForLog(set: SetPlan) -> Double? {
    set.distanceM ?? set.workTarget?.canonicalDistanceM
}

func loadDisplayForTarget(set: SetPlan) -> String {
    formatLoad(weight: set.loadKg, unit: LoadUnit(setPlanUnit: set.unit))
}

private func formatTargetNumber(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    var formatted = String(format: "%.2f", value)
    while formatted.hasSuffix("0") {
        formatted.removeLast()
    }
    if formatted.hasSuffix(".") {
        formatted.removeLast()
    }
    return formatted
}
