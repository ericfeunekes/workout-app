// Sync + version DTOs.

import Foundation

public struct WorkoutStatusUpdate: Codable, Sendable, Equatable {
    public let workoutId: String
    public let status: WorkoutStatus
    public let completedAt: Date?
    /// User-authored post-workout note. Carried on the terminal status
    /// push so the server becomes authoritative for the value — without
    /// this the next `sync/pull` would overwrite the freshly-typed note
    /// with the server's stale value. `nil` leaves the existing server-
    /// side notes alone; a non-nil value replaces them.
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case status
        case completedAt = "completed_at"
        case notes
    }

    public init(
        workoutId: String,
        status: WorkoutStatus,
        completedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.workoutId = workoutId
        self.status = status
        self.completedAt = completedAt
        self.notes = notes
    }
}

public struct WorkoutReset: Codable, Sendable, Equatable {
    public let workoutId: String

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
    }

    public init(workoutId: String) {
        self.workoutId = workoutId
    }
}

public struct SyncResultsPayload: Codable, Sendable, Equatable {
    public let primitiveSetLogs: [PrimitiveSetLog]
    public let statusUpdates: [WorkoutStatusUpdate]
    public let workoutResets: [WorkoutReset]

    enum CodingKeys: String, CodingKey {
        case primitiveSetLogs = "primitive_set_logs"
        case statusUpdates = "status_updates"
        case workoutResets = "workout_resets"
    }

    public init(
        primitiveSetLogs: [PrimitiveSetLog] = [],
        statusUpdates: [WorkoutStatusUpdate] = [],
        workoutResets: [WorkoutReset] = []
    ) {
        self.primitiveSetLogs = primitiveSetLogs
        self.statusUpdates = statusUpdates
        self.workoutResets = workoutResets
    }
}

public struct ExerciseLastPerformed: Codable, Sendable, Equatable {
    public let exerciseId: String
    public let lastSetLogs: [PrimitiveSetLog]

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case lastSetLogs = "last_set_logs"
    }

    public init(exerciseId: String, lastSetLogs: [PrimitiveSetLog]) {
        self.exerciseId = exerciseId
        self.lastSetLogs = lastSetLogs
    }
}

public struct SyncPullResponse: Codable, Sendable, Equatable {
    public let workouts: [Workout]
    public let exercises: [Exercise]
    public let userParameters: [UserParameter]
    public let lastPerformed: [ExerciseLastPerformed]
    public let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case workouts
        case exercises
        case userParameters = "user_parameters"
        case lastPerformed = "last_performed"
        case serverTime = "server_time"
    }

    public init(
        workouts: [Workout],
        exercises: [Exercise],
        userParameters: [UserParameter],
        lastPerformed: [ExerciseLastPerformed],
        serverTime: Date
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.userParameters = userParameters
        self.lastPerformed = lastPerformed
        self.serverTime = serverTime
    }
}

public struct VersionInfo: Codable, Sendable, Equatable {
    public let schemaVersion: String?
    public let appliedMigrations: [String]
    public let serverVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appliedMigrations = "applied_migrations"
        case serverVersion = "server_version"
    }

    public init(schemaVersion: String?, appliedMigrations: [String], serverVersion: String) {
        self.schemaVersion = schemaVersion
        self.appliedMigrations = appliedMigrations
        self.serverVersion = serverVersion
    }
}
