// ExerciseAlternative.swift
//
// See docs/specs/v2-architecture.md § "Data model · exercise_alternative".

import Foundation
import WorkoutCoreFoundation

/// A pre-computed swap option attached to a specific `WorkoutItem` within a
/// specific workout. Claude decides these; the app just renders and lets the
/// user pick one.
///
/// `parameterOverridesJSON` stays opaque — when present, it describes how the
/// alternative's prescription differs from the original (different sets/reps
/// /load). Parsers live in `Core/Prescription`.
public struct ExerciseAlternative: Sendable, Hashable {
    public var id: ExerciseAlternativeID
    public var workoutItemID: WorkoutItemID
    public var exerciseID: ExerciseID
    public var reason: String
    public var parameterOverridesJSON: String?

    public init(
        id: ExerciseAlternativeID,
        workoutItemID: WorkoutItemID,
        exerciseID: ExerciseID,
        reason: String,
        parameterOverridesJSON: String? = nil
    ) {
        self.id = id
        self.workoutItemID = workoutItemID
        self.exerciseID = exerciseID
        self.reason = reason
        self.parameterOverridesJSON = parameterOverridesJSON
    }
}
