// TimingConfig.swift
//
// Typed representation of `block.timing_config_json` per timing mode. Each
// case corresponds to a row in docs/prescription.md § "Per-timing-mode
// prescription shapes". Unknown (extra) keys in the source JSON are ignored
// per the doc's "Timing config is strict. The app reads only the keys
// documented per mode. Extraneous keys in `timing_config_json` are
// ignored — no error, but Claude should avoid littering."
//
// Units:
// * `*_sec` fields are Double seconds (accept JSON int or double).
// * distances are Double metres.
// * pace is Double seconds per km.

import Foundation

public enum TimingConfig: Equatable, Sendable, Hashable {
    /// `{ "rest_between_sets_sec": n, "rest_between_exercises_sec": n }`
    case straightSets(
        restBetweenSetsSec: Double,
        restBetweenExercisesSec: Double
    )

    /// `{ "rest_between_rounds_sec": n, "logging_mode": "..."? }`
    case superset(
        restBetweenRoundsSec: Double,
        loggingMode: RoundRobinLoggingMode
    )

    /// `{ "rest_between_exercises_sec": n, "rest_between_rounds_sec": n,
    ///    "logging_mode": "..."? }`
    case circuit(
        restBetweenExercisesSec: Double,
        restBetweenRoundsSec: Double,
        loggingMode: RoundRobinLoggingMode
    )

    /// `{ "interval_sec": n, "total_minutes": n }`
    case emom(
        intervalSec: Double,
        totalMinutes: Int
    )

    /// `{ "time_cap_sec": n }`
    case amrap(
        timeCapSec: Double
    )

    /// `{ "time_cap_sec": n? }` — cap is optional.
    case forTime(
        timeCapSec: Double?
    )

    /// Intervals has two authoring variants — time-based or distance-based.
    /// Both may carry `target_pace_sec_per_km`.
    case intervals(
        workSec: Double?,
        restSec: Double?,
        workDistanceM: Double?,
        restDistanceM: Double?,
        intervalCount: Int,
        targetPaceSecPerKm: Double?
    )

    /// `{}` — 20/10/8 is the definition.
    case tabata

    /// `{ "target_duration_sec": n?, "target_distance_m": n?,
    ///    "target_pace_sec_per_km": n?, "target_hr_zone": n? }`
    case continuous(
        targetDurationSec: Double?,
        targetDistanceM: Double?,
        targetPaceSecPerKm: Double?,
        targetHrZone: Int?
    )

    /// `{ "target_duration_sec": n?, "target_reps": n?,
    ///    "target_distance_m": n? }`
    case accumulate(
        targetDurationSec: Double?,
        targetReps: Int?,
        targetDistanceM: Double?
    )

    /// `{ "segments": [ { type, duration_sec, label, target_hr_zone? }, ... ] }`
    case custom(
        segments: [CustomSegment]
    )

    /// `{ "duration_sec": n }` — a standalone rest block.
    case rest(
        durationSec: Double
    )
}

public enum RoundRobinLoggingMode: String, Equatable, Sendable, Hashable {
    case stationByStation = "station_by_station"
    case batchAtRoundRest = "batch_at_round_rest"
}

public struct CustomSegment: Equatable, Sendable, Hashable {
    public enum SegmentType: String, Sendable, Hashable {
        case work
        case rest
    }

    public let type: SegmentType
    public let durationSec: Double
    public let label: String?
    public let targetHrZone: Int?

    public init(
        type: SegmentType,
        durationSec: Double,
        label: String? = nil,
        targetHrZone: Int? = nil
    ) {
        self.type = type
        self.durationSec = durationSec
        self.label = label
        self.targetHrZone = targetHrZone
    }
}
