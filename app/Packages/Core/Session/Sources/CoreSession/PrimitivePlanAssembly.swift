// PrimitivePlanAssembly.swift
//
// Shared bridge policy for building primitive execution plans from cached
// workouts. The full primitive-only cutover will make this the primary runtime
// path; while old timing-mode execution still exists, this keeps Today and
// Shell from applying different failure policies to the same derived plan.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public enum PrimitivePlanAssembly {
    public static func exerciseIDs(in primitiveWorkouts: [PrimitiveWorkout]) -> Set<ExerciseID> {
        primitiveWorkouts.reduce(into: Set<ExerciseID>()) { partial, workout in
            for block in workout.blocks {
                for set in block.sets {
                    partial.formUnion(set.slots.map(\.exerciseID))
                }
            }
        }
    }

    public static func exerciseIDs(in primitiveWorkout: PrimitiveWorkout?) -> Set<ExerciseID> {
        guard let primitiveWorkout else { return [] }
        return exerciseIDs(in: [primitiveWorkout])
    }

    public static func numericUserParameters(
        from userParameters: [String: UserParameter]
    ) -> [String: Double] {
        userParameters.reduce(into: [:]) { partial, entry in
            guard let value = Double(entry.value.value) else { return }
            partial[entry.key] = value
        }
    }

    public static func executionPlan(
        for primitiveWorkout: PrimitiveWorkout?,
        userParameters: [String: Double]
    ) throws -> ExecutionPlan? {
        guard let primitiveWorkout else { return nil }
        return try ExecutionPlan.validated(
            workout: primitiveWorkout,
            userParameters: userParameters
        )
    }
}
