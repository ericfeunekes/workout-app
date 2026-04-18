// DTOMapping+Exercise.swift
//
// Exercise + ExerciseAlternative mapping. Split out of `DTOMapping.swift`
// so no single file in the mapping namespace exceeds SwiftLint's
// `type_body_length` cap.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

extension DTOMapping {

    // MARK: - Exercise

    public static func mapExercise(_ dto: WorkoutDBSchema.Exercise) -> Result<CoreDomain.Exercise, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("Exercise.id is not a UUID: \(dto.id)"))
        }
        let url = dto.demoUrl.flatMap { URL(string: $0) }
        return .success(CoreDomain.Exercise(
            id: id,
            name: dto.name,
            notes: dto.notes,
            demoURL: url,
            defaultPrescriptionJSON: dto.defaultPrescriptionJson,
            defaultAlternativesJSON: dto.defaultAlternativesJson
        ))
    }

    // MARK: - ExerciseAlternative

    public static func mapAlternative(
        _ dto: WorkoutDBSchema.ExerciseAlternative,
        workoutItemID: WorkoutItemID
    ) -> Result<CoreDomain.ExerciseAlternative, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("ExerciseAlternative.id is not a UUID: \(dto.id)"))
        }
        guard let exerciseID = UUID(uuidString: dto.exerciseId) else {
            return .failure(.decode("ExerciseAlternative.exercise_id is not a UUID: \(dto.exerciseId)"))
        }
        return .success(CoreDomain.ExerciseAlternative(
            id: id,
            workoutItemID: workoutItemID,
            exerciseID: exerciseID,
            reason: dto.reason,
            parameterOverridesJSON: dto.parameterOverridesJson
        ))
    }
}
