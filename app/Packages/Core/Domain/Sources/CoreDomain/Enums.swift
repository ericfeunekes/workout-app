// Enums.swift
//
// Domain enums — the Swift side of the server's string-valued enums and SQL
// CHECK constraints. These intentionally duplicate the cases in
// `schema/Sources/WorkoutDBSchema/Enums.swift` because Domain does not import
// `schema` (DTOs live at the wire boundary). Contract tests keep the two
// lists aligned at build time.
//
// Raw values are snake_case to match the wire / DB storage. Swift case names
// are lower camelCase.

import Foundation

/// How a block is timed — drives the app's timer UI.
///
/// Keep in lockstep with:
///   - `server/workoutdb_server/api/schemas.py` (`TimingMode` Literal)
///   - `server/db/migrations/001_initial.sql` (CHECK constraint)
///   - `docs/specs/v2-architecture.md` § "Timing modes"
///   - `schema/Sources/WorkoutDBSchema/Enums.swift`
public enum TimingMode: String, Sendable, CaseIterable, Hashable {
    case straightSets = "straight_sets"
    case superset
    case circuit
    case emom
    case amrap
    case forTime = "for_time"
    case intervals
    case tabata
    case continuous
    case custom
    case rest
}

/// Lifecycle state of a workout.
public enum WorkoutStatus: String, Sendable, CaseIterable, Hashable {
    case planned
    case active
    case completed
    case skipped
}

/// Unit the user logged a set in. The app stores `weight` in the unit the user
/// typed; conversion for display happens at the UI layer using helpers in
/// `WorkoutCoreFoundation`.
public enum WeightUnit: String, Sendable, CaseIterable, Hashable {
    case kg
    case lb
}

/// Who authored a workout row.
///
/// Scoped to workouts only — the spec (`docs/specs/v2-architecture.md`
/// § "Data model · workout") restricts `workout.source` to `{claude, manual}`.
/// `claude` means pushed from a conversation; `manual` means created in the
/// app. `app_log` is not valid for workouts — it belongs to
/// `UserParameterSource`. Keeping a separate type per entity prevents
/// callers from accidentally assigning `.appLog` to a workout.
public enum WorkoutSource: String, Sendable, CaseIterable, Hashable {
    case claude
    case manual
}

/// Who authored a `user_parameter` row.
///
/// Per `docs/specs/v2-architecture.md` § "Data model · user_parameters",
/// valid sources are `{claude, app_log, manual}`. `claude` is pushed from a
/// conversation; `app_log` is the app writing itself (e.g. `bodyweight_kg`
/// captured on completion); `manual` is a direct edit.
public enum UserParameterSource: String, Sendable, CaseIterable, Hashable {
    case claude
    case appLog = "app_log"
    case manual
}
