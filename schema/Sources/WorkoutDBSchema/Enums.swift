// Enums shared across entities.
//
// Mirrors the server's Literal types (api/schemas.py) and SQL CHECK constraints
// (db/migrations/001_initial.sql). Contract tests in tests/contract/ enforce that
// this list matches the server's.

import Foundation

public enum TimingMode: String, Codable, Sendable, CaseIterable {
    case straightSets = "straight_sets"
    case superset
    case circuit
    case emom
    case amrap
    case forTime = "for_time"
    case intervals
    case tabata
    case continuous
    case accumulate
    case custom
    case rest
}

public enum WorkoutStatus: String, Codable, Sendable, CaseIterable {
    case planned
    case active
    case completed
    case skipped
}

public enum WorkoutSource: String, Codable, Sendable, CaseIterable {
    case claude
    case manual
}

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kg
    case lb
}

public enum SetLogSide: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case bilateral
}

public enum UserParameterSource: String, Codable, Sendable, CaseIterable {
    case claude
    case appLog = "app_log"
    case manual
}
