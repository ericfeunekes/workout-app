// PrescriptionParser+TimingConfig.swift
//
// Timing-config parsers, split out of `PrescriptionParser.swift` so the
// parent struct stays under SwiftLint's `type_body_length` cap. Each parser
// is still a method on `PrescriptionParser` — the dispatcher in the parent
// file forwards to these by timing-mode string.

import Foundation

extension PrescriptionParser {

    // MARK: - Timing config dispatch

    public func parseTimingConfig(
        timingMode: String,
        configJSON: String
    ) -> Result<TimingConfig, ParseError> {
        switch parseRootObject(configJSON, shape: "timing_config:\(timingMode)") {
        case .failure(let e): return .failure(e)
        case .success(let obj):
            return parseTimingConfig(timingMode: timingMode, dictionary: obj)
        }
    }

    public func parseTimingConfig(
        timingMode: String,
        dictionary obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        switch timingMode {
        case "straight_sets": return parseStraightSetsConfig(obj)
        case "superset":      return parseSupersetConfig(obj)
        case "circuit":       return parseCircuitConfig(obj)
        case "emom":          return parseEmomConfig(obj)
        case "amrap":         return parseAmrapConfig(obj)
        case "for_time":      return parseForTimeConfig(obj)
        case "intervals":     return parseIntervalsConfig(obj)
        case "tabata":        return .success(.tabata)
        case "continuous":    return parseContinuousConfig(obj)
        case "accumulate":    return parseAccumulateConfig(obj)
        case "custom":        return parseCustomConfig(obj)
        case "rest":          return parseRestConfig(obj)
        default:              return .failure(.unknownTimingMode(timingMode))
        }
    }

    // MARK: - Simple per-mode config parsers

    func parseStraightSetsConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        // Both fields are independently optional. When only one is
        // authored, the missing field defaults to the present one (the
        // between-exercises rest should be AT LEAST the between-sets
        // rest, and a caller that authors only between-exercises rest
        // should not have a zero between-sets floor). When neither is
        // authored, both default to 0. This is the fix for bug-039:
        // `{"rest_between_sets_sec": 15}` previously failed the parse
        // and the driver's .failure branch returned 0, silently dropping
        // the authored rest.
        let rbsRaw: Double?
        switch readOptionalDouble(obj, "rest_between_sets_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): rbsRaw = v
        }
        let rbeRaw: Double?
        switch readOptionalDouble(obj, "rest_between_exercises_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): rbeRaw = v
        }
        let rbs = rbsRaw ?? rbeRaw ?? 0
        let rbe = rbeRaw ?? rbsRaw ?? 0
        return .success(.straightSets(
            restBetweenSetsSec: rbs,
            restBetweenExercisesSec: rbe
        ))
    }

    func parseSupersetConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let shape = "timingConfig.superset"
        let v: Double
        switch readRequiredDouble(obj, "rest_between_rounds_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let d): v = d
        }
        switch readRoundRobinLoggingMode(
            obj,
            defaultMode: .batchAtRoundRest
        ) {
        case .failure(let e): return .failure(e)
        case .success(let mode):
            return .success(.superset(
                restBetweenRoundsSec: v,
                loggingMode: mode
            ))
        }
    }

    func parseCircuitConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let shape = "timingConfig.circuit"
        let rbe: Double
        switch readRequiredDouble(obj, "rest_between_exercises_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): rbe = v
        }
        let rbr: Double
        switch readRequiredDouble(obj, "rest_between_rounds_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): rbr = v
        }
        switch readRoundRobinLoggingMode(
            obj,
            defaultMode: .stationByStation
        ) {
        case .failure(let e): return .failure(e)
        case .success(let mode):
            return .success(.circuit(
                restBetweenExercisesSec: rbe,
                restBetweenRoundsSec: rbr,
                loggingMode: mode
            ))
        }
    }

    func parseEmomConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let shape = "timingConfig.emom"
        let iv: Double
        switch readRequiredDouble(obj, "interval_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): iv = v
        }
        let tm: Int
        switch readRequiredInt(obj, "total_minutes", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): tm = v
        }
        return .success(.emom(intervalSec: iv, totalMinutes: tm))
    }

    func parseAmrapConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let shape = "timingConfig.amrap"
        let tc: Double
        switch readRequiredDouble(obj, "time_cap_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): tc = v
        }
        return .success(.amrap(timeCapSec: tc))
    }

    func parseForTimeConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let tc: Double?
        switch readOptionalDouble(obj, "time_cap_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): tc = v
        }
        return .success(.forTime(timeCapSec: tc))
    }

    func parseRestConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let shape = "timingConfig.rest"
        let d: Double
        switch readRequiredDouble(obj, "duration_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): d = v
        }
        return .success(.rest(durationSec: d))
    }

    func parseAccumulateConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let dur: Double?
        switch readOptionalDouble(obj, "target_duration_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): dur = v
        }
        let reps: Int?
        switch readOptionalInt(obj, "target_reps") {
        case .failure(let e): return .failure(e)
        case .success(let v): reps = v
        }
        let dist: Double?
        switch readOptionalDouble(obj, "target_distance_m") {
        case .failure(let e): return .failure(e)
        case .success(let v): dist = v
        }
        return .success(.accumulate(
            targetDurationSec: dur,
            targetReps: reps,
            targetDistanceM: dist
        ))
    }

    func readRoundRobinLoggingMode(
        _ obj: [String: Any],
        defaultMode: RoundRobinLoggingMode
    ) -> Result<RoundRobinLoggingMode, ParseError> {
        switch readOptionalString(obj, "logging_mode") {
        case .failure(let e):
            return .failure(e)
        case .success(.none):
            return .success(defaultMode)
        case .success(.some(let raw)):
            guard let mode = RoundRobinLoggingMode(rawValue: raw) else {
                return .failure(.wrongType(
                    key: "logging_mode",
                    expected: "\"station_by_station\" or \"batch_at_round_rest\""
                ))
            }
            return .success(mode)
        }
    }
}
