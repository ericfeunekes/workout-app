// Sync + version DTOs.

import Foundation

public struct WorkoutStatusUpdate: Codable, Sendable, Equatable {
    public let workoutId: String
    public let status: WorkoutStatus
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case status
        case completedAt = "completed_at"
    }

    public init(workoutId: String, status: WorkoutStatus, completedAt: Date? = nil) {
        self.workoutId = workoutId
        self.status = status
        self.completedAt = completedAt
    }
}

public struct SyncResultsPayload: Codable, Sendable, Equatable {
    public let setLogs: [SetLog]
    public let statusUpdates: [WorkoutStatusUpdate]

    enum CodingKeys: String, CodingKey {
        case setLogs = "set_logs"
        case statusUpdates = "status_updates"
    }

    public init(setLogs: [SetLog] = [], statusUpdates: [WorkoutStatusUpdate] = []) {
        self.setLogs = setLogs
        self.statusUpdates = statusUpdates
    }
}

public struct ExerciseLastPerformed: Codable, Sendable, Equatable {
    public let exerciseId: String
    public let lastSetLogs: [SetLog]
    public let prescriptionJson: String?

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case lastSetLogs = "last_set_logs"
        case prescriptionJson = "prescription_json"
    }

    public init(exerciseId: String, lastSetLogs: [SetLog], prescriptionJson: String? = nil) {
        self.exerciseId = exerciseId
        self.lastSetLogs = lastSetLogs
        self.prescriptionJson = prescriptionJson
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
