// PrescriptionParser+IntervalConfigs.swift
//
// Larger per-mode timing-config parsers — intervals, continuous, and
// custom — split out of the parent extension so no single function exceeds
// SwiftLint's `function_body_length` cap. Each parser here pulls optional
// pace/distance fields and composes them into a `TimingConfig`.

import Foundation

extension PrescriptionParser {

    func parseIntervalsConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        switch readIntervalsDistances(obj) {
        case .failure(let e): return .failure(e)
        case .success(let dist):
            switch readIntervalsCountAndPace(obj) {
            case .failure(let e): return .failure(e)
            case .success(let meta):
                return .success(.intervals(
                    workSec: dist.workSec,
                    restSec: dist.restSec,
                    workDistanceM: dist.workDist,
                    restDistanceM: dist.restDist,
                    intervalCount: meta.count,
                    targetPaceSecPerKm: meta.pace
                ))
            }
        }
    }

    private struct IntervalsDistances {
        let workSec: Double?
        let restSec: Double?
        let workDist: Double?
        let restDist: Double?
    }

    private struct IntervalsMeta {
        let count: Int
        let pace: Double?
    }

    private func readIntervalsDistances(
        _ obj: [String: Any]
    ) -> Result<IntervalsDistances, ParseError> {
        let workSec: Double?
        switch readOptionalDouble(obj, "work_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): workSec = v
        }
        let restSec: Double?
        switch readOptionalDouble(obj, "rest_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): restSec = v
        }
        let workDist: Double?
        switch readOptionalDouble(obj, "work_distance_m") {
        case .failure(let e): return .failure(e)
        case .success(let v): workDist = v
        }
        let restDist: Double?
        switch readOptionalDouble(obj, "rest_distance_m") {
        case .failure(let e): return .failure(e)
        case .success(let v): restDist = v
        }
        return .success(IntervalsDistances(
            workSec: workSec,
            restSec: restSec,
            workDist: workDist,
            restDist: restDist
        ))
    }

    private func readIntervalsCountAndPace(
        _ obj: [String: Any]
    ) -> Result<IntervalsMeta, ParseError> {
        let shape = "timingConfig.intervals"
        let count: Int
        switch readRequiredInt(obj, "interval_count", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): count = v
        }
        let pace: Double?
        switch readOptionalDouble(obj, "target_pace_sec_per_km") {
        case .failure(let e): return .failure(e)
        case .success(let v): pace = v
        }
        return .success(IntervalsMeta(count: count, pace: pace))
    }

    func parseContinuousConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let dur: Double?
        switch readOptionalDouble(obj, "target_duration_sec") {
        case .failure(let e): return .failure(e)
        case .success(let v): dur = v
        }
        let dist: Double?
        switch readOptionalDouble(obj, "target_distance_m") {
        case .failure(let e): return .failure(e)
        case .success(let v): dist = v
        }
        let pace: Double?
        switch readOptionalDouble(obj, "target_pace_sec_per_km") {
        case .failure(let e): return .failure(e)
        case .success(let v): pace = v
        }
        let zone: Int?
        switch readOptionalInt(obj, "target_hr_zone") {
        case .failure(let e): return .failure(e)
        case .success(let v): zone = v
        }
        return .success(.continuous(
            targetDurationSec: dur,
            targetDistanceM: dist,
            targetPaceSecPerKm: pace,
            targetHrZone: zone
        ))
    }

    func parseCustomConfig(
        _ obj: [String: Any]
    ) -> Result<TimingConfig, ParseError> {
        let shape = "timingConfig.custom"
        let arr: [Any]
        switch readOptionalArray(obj, "segments") {
        case .failure(let e): return .failure(e)
        case .success(.none): return .failure(.missingKey("segments", inShape: shape))
        case .success(.some(let a)): arr = a
        }
        var segments: [CustomSegment] = []
        segments.reserveCapacity(arr.count)
        for (i, raw) in arr.enumerated() {
            guard let el = raw as? [String: Any] else {
                return .failure(.wrongType(key: "segments[\(i)]", expected: "object"))
            }
            switch parseCustomSegment(el, index: i) {
            case .failure(let e): return .failure(e)
            case .success(let seg): segments.append(seg)
            }
        }
        return .success(.custom(segments: segments))
    }

    private func parseCustomSegment(
        _ obj: [String: Any],
        index: Int
    ) -> Result<CustomSegment, ParseError> {
        let segShape = "customSegment[\(index)]"
        let typeStr: String
        switch readOptionalString(obj, "type") {
        case .failure(let e): return .failure(e)
        case .success(.none):
            return .failure(.missingKey("type", inShape: segShape))
        case .success(.some(let s)): typeStr = s
        }
        guard let type = CustomSegment.SegmentType(rawValue: typeStr) else {
            return .failure(.wrongType(key: "type", expected: "\"work\" or \"rest\""))
        }
        let dur: Double
        switch readRequiredDouble(obj, "duration_sec", shape: segShape) {
        case .failure(let e): return .failure(e)
        case .success(let v): dur = v
        }
        let label: String?
        switch readOptionalString(obj, "label") {
        case .failure(let e): return .failure(e)
        case .success(let v): label = v
        }
        let zone: Int?
        switch readOptionalInt(obj, "target_hr_zone") {
        case .failure(let e): return .failure(e)
        case .success(let v): zone = v
        }
        return .success(CustomSegment(
            type: type,
            durationSec: dur,
            label: label,
            targetHrZone: zone
        ))
    }
}
