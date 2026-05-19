// WorkoutCompletionRecord.swift
//
// Transport-neutral app-owned facts for a completed workout. Local History,
// REST push, and future replication surfaces should consume this value instead
// of each re-deriving completion from live SessionState.

import Foundation
import WorkoutCoreFoundation

/// Completed workout facts recorded by the app.
///
/// This type is deliberately free of REST, CloudKit, SwiftData, and retry
/// policy. It is the local authority for what the app says happened at
/// Save & Done time.
public struct WorkoutCompletionRecord: Sendable, Hashable {
    public var workout: Workout
    public var primitiveSetLogs: [PrimitiveSetLog]

    public init(
        workout: Workout,
        primitiveSetLogs: [PrimitiveSetLog] = []
    ) {
        precondition(workout.status == .completed, "WorkoutCompletionRecord requires completed status")
        precondition(workout.completedAt != nil, "WorkoutCompletionRecord requires completedAt")
        self.workout = workout
        self.primitiveSetLogs = primitiveSetLogs
    }

    public var workoutID: WorkoutID {
        workout.id
    }

    public var completedAt: Date? {
        workout.completedAt
    }

    public var notes: String? {
        workout.notes
    }
}
