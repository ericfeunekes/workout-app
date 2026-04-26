// WorkTarget.swift
//
// Unit-aware work target parsing for item prescriptions. This is the shared
// representation for "what counts as completing this station/set": reps,
// duration, or distance. Logs stay canonical (`reps`, `duration_sec`,
// `distance_m`); the target keeps the authored display unit so execution can
// say "200 ft carry" instead of leaking the canonical "60.96 m".

import Foundation

public struct WorkTarget: Equatable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case reps
        case duration
        case distance
    }

    public enum Unit: String, Sendable, Hashable {
        case reps
        case seconds = "sec"
        case minutes = "min"
        case metres = "m"
        case kilometres = "km"
        case feet = "ft"
        case yards = "yd"
        case miles = "mi"
    }

    public let kind: Kind
    public let value: Double
    public let unit: Unit

    public init(kind: Kind, value: Double, unit: Unit) {
        self.kind = kind
        self.value = value
        self.unit = unit
    }

    public static func reps(_ count: Int) -> WorkTarget {
        WorkTarget(kind: .reps, value: Double(count), unit: .reps)
    }

    public var canonicalReps: Int? {
        guard kind == .reps else { return nil }
        return Int(value.rounded())
    }

    public var canonicalDurationSec: Double? {
        guard kind == .duration else { return nil }
        switch unit {
        case .seconds:
            return value
        case .minutes:
            return value * 60
        case .reps, .metres, .kilometres, .feet, .yards, .miles:
            return nil
        }
    }

    public var canonicalDistanceM: Double? {
        guard kind == .distance else { return nil }
        switch unit {
        case .metres:
            return value
        case .kilometres:
            return value * 1_000
        case .feet:
            return value * 0.3048
        case .yards:
            return value * 0.9144
        case .miles:
            return value * 1_609.344
        case .reps, .seconds, .minutes:
            return nil
        }
    }

    public var isDetectableByClock: Bool {
        kind == .duration
    }
}

extension PrescriptionParser {
    public func parseWorkTarget(prescriptionJSON: String) -> WorkTarget? {
        guard let obj = parseLooseObject(prescriptionJSON) else { return nil }
        return parseWorkTarget(dictionary: obj)
    }

    public func parseWorkTarget(dictionary obj: [String: Any]) -> WorkTarget? {
        if let target = obj["target"] as? [String: Any],
           let parsed = parseStructuredWorkTarget(target) {
            return parsed
        }

        if let reps = intValue(obj["reps"]) {
            return .reps(reps)
        }

        if let duration = doubleValue(obj["duration"]),
           let unit = durationUnit(from: obj["duration_unit"]) {
            return WorkTarget(kind: .duration, value: duration, unit: unit)
        }
        if let seconds = doubleValue(obj["duration_sec"]) {
            return WorkTarget(kind: .duration, value: seconds, unit: .seconds)
        }

        if let distance = doubleValue(obj["distance"]),
           let unit = distanceUnit(from: obj["distance_unit"]) {
            return WorkTarget(kind: .distance, value: distance, unit: unit)
        }
        if let metres = doubleValue(obj["distance_m"]) {
            return WorkTarget(kind: .distance, value: metres, unit: .metres)
        }

        return nil
    }

    private func parseStructuredWorkTarget(_ obj: [String: Any]) -> WorkTarget? {
        guard let rawKind = obj["kind"] as? String,
              let kind = WorkTarget.Kind(rawValue: rawKind),
              let value = doubleValue(obj["value"]) else {
            return nil
        }
        let unit = (obj["unit"] as? String).flatMap(WorkTarget.Unit.init(rawValue:))
            ?? defaultUnit(for: kind)
        guard unitAllowed(unit, for: kind) else { return nil }
        return WorkTarget(kind: kind, value: value, unit: unit)
    }

    private func unitAllowed(_ unit: WorkTarget.Unit, for kind: WorkTarget.Kind) -> Bool {
        switch kind {
        case .reps:
            return unit == .reps
        case .duration:
            return unit == .seconds || unit == .minutes
        case .distance:
            return unit == .metres
                || unit == .kilometres
                || unit == .feet
                || unit == .yards
                || unit == .miles
        }
    }

    private func defaultUnit(for kind: WorkTarget.Kind) -> WorkTarget.Unit {
        switch kind {
        case .reps: return .reps
        case .duration: return .seconds
        case .distance: return .metres
        }
    }

    private func durationUnit(from value: Any?) -> WorkTarget.Unit? {
        guard let raw = value as? String else { return .seconds }
        switch raw {
        case "sec", "second", "seconds", "s":
            return .seconds
        case "min", "minute", "minutes", "m":
            return .minutes
        default:
            return nil
        }
    }

    private func distanceUnit(from value: Any?) -> WorkTarget.Unit? {
        guard let raw = value as? String else { return .metres }
        switch raw {
        case "m", "metre", "metres", "meter", "meters":
            return .metres
        case "km", "kilometre", "kilometres", "kilometer", "kilometers":
            return .kilometres
        case "ft", "foot", "feet":
            return .feet
        case "yd", "yard", "yards":
            return .yards
        case "mi", "mile", "miles":
            return .miles
        default:
            return nil
        }
    }

    private func parseLooseObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let v as Double:
            return v
        case let v as Int:
            return Double(v)
        case let v as NSNumber:
            return v.doubleValue
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let v as Int:
            return v
        case let v as NSNumber where CFNumberIsFloatType(v) == false:
            return v.intValue
        default:
            return nil
        }
    }
}
