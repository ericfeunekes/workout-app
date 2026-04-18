// DTOMapping.swift
//
// Pure mapping functions between `WorkoutDBSchema` DTOs (wire shape) and
// `CoreDomain` values (domain shape). This is the only place `WorkoutDBSchema`
// is referenced from code that touches Domain — FF-11 requires it. Keep these
// private-to-package unless a consumer genuinely needs them; the `SyncAPI`
// facade returns Domain types.
//
// Design notes:
//   • Every mapping returns `Result<T, SyncError>`. Strict UUID parsing — any
//     non-UUID ID is a `.decode` error. `docs/specs/v2-architecture.md` is
//     explicit that IDs are UUIDs; silently coercing a non-UUID would
//     corrupt downstream joins.
//   • `Exercise.demoUrl: String?` upgrades to `URL?` at this boundary per the
//     doc comment on `CoreDomain.Exercise.demoURL`.
//   • `scheduled_date` on the wire is a `String?` (ISO-8601 date, no time).
//     Domain uses `Date?` — we parse through `DateFormatter` with the "y-M-d"
//     pattern.
//
// File layout: the enum is namespace-only here. Each entity's mapping lives
// in its own `DTOMapping+<Entity>.swift` file so no single file grows past
// the SwiftLint `type_body_length` cap. Shared helpers (`parseDateOnly`,
// `parseOptionalUUID`) live at the bottom of this file.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

public enum DTOMapping {

    // MARK: - Shared helpers

    /// Parse an ISO-8601 *date* (no time portion) into a `Date` at UTC
    /// midnight. The server sends `scheduled_date` as `"YYYY-MM-DD"`.
    static func parseDateOnly(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    /// Parse an optional UUID string. Returns `.success(nil)` when the input
    /// is nil, `.success(uuid)` for a valid UUID string, and `.failure` with
    /// a `SyncError.decode` when the string is present but malformed.
    static func parseOptionalUUID(
        _ raw: String?,
        fieldName: String
    ) -> Result<UUID?, SyncError> {
        guard let raw else { return .success(nil) }
        guard let parsed = UUID(uuidString: raw) else {
            return .failure(.decode("\(fieldName) is not a UUID: \(raw)"))
        }
        return .success(parsed)
    }
}

/// The flattened shape returned by `mapWorkout`. The wire type nests
/// `workout_items` inside `blocks` inside `workouts`; Domain persists them as
/// four separate tables, so the mapping returns four parallel lists.
public struct MappedWorkout: Sendable, Equatable {
    public let workout: CoreDomain.Workout
    public let blocks: [CoreDomain.Block]
    public let items: [CoreDomain.WorkoutItem]
    public let alternatives: [CoreDomain.ExerciseAlternative]

    public init(
        workout: CoreDomain.Workout,
        blocks: [CoreDomain.Block],
        items: [CoreDomain.WorkoutItem],
        alternatives: [CoreDomain.ExerciseAlternative]
    ) {
        self.workout = workout
        self.blocks = blocks
        self.items = items
        self.alternatives = alternatives
    }
}
