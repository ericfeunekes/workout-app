// PrimitiveSeedResolution.swift
//
// Seed-time primitive resolution for executable session plans. This belongs in
// Core/Session because Today, Execution, previews, persistence, and future
// Watch/History consumers all need the same load-resolution contract before
// feature-specific presentation starts.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public extension ExecutionPlan {
    static func validated(
        workout: PrimitiveWorkout,
        userParameters: [String: Double]
    ) throws -> ExecutionPlan {
        try validated(workout: workout) { slot in
            PrimitiveSeedResolution.resolve(
                load: slot.load,
                exerciseID: slot.exerciseID,
                userParameters: userParameters
            )
        }
    }

    func setResultLog(
        blockIndex: Int,
        setIndexInBlock: Int,
        blockRepeatIndex: Int,
        setRepeatIndex: Int,
        reps: Int? = nil,
        rounds: Int?,
        durationSec: Double?,
        distanceM: Double? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit? = nil,
        completedAt: Date
    ) -> PrimitiveSetLog {
        blocks[blockIndex].sets[setIndexInBlock].setResultLog(
            workoutID: workoutID,
            blockRepeatIndex: blockRepeatIndex,
            setRepeatIndex: setRepeatIndex,
            reps: reps,
            rounds: rounds,
            durationSec: durationSec,
            distanceM: distanceM,
            weight: weight,
            weightUnit: weightUnit,
            completedAt: completedAt
        )
    }

    func blockResultLog(
        blockIndex: Int,
        blockRepeatIndex: Int,
        durationSec: Double?,
        completedAt: Date
    ) -> PrimitiveSetLog {
        blocks[blockIndex].blockResultLog(
            workoutID: workoutID,
            blockRepeatIndex: blockRepeatIndex,
            durationSec: durationSec,
            completedAt: completedAt
        )
    }
}

enum PrimitiveSeedResolution {
    static func resolve(
        load: PrimitiveLoad?,
        exerciseID: ExerciseID,
        userParameters: [String: Double]
    ) -> ResolvedPrimitiveLoad? {
        guard let load else { return nil }
        switch (load.unit, load.unitType) {
        case (.oneRepMax, .relative):
            let key = "one_rep_max_\(exerciseID.uuidString.lowercased())_kg"
            guard let base = userParameters[key], let value = load.value else {
                return ResolvedPrimitiveLoad(loadKg: nil, loadUnit: nil, loadDisplayValue: load.value)
            }
            let resolved = base * value
            return ResolvedPrimitiveLoad(loadKg: resolved, loadUnit: .kg, loadDisplayValue: resolved)
        case (.bodyweight, .relative):
            guard let base = userParameters["bodyweight_kg"], let value = load.value else {
                return ResolvedPrimitiveLoad(loadKg: nil, loadUnit: nil, loadDisplayValue: load.value)
            }
            let resolved = base * value
            return ResolvedPrimitiveLoad(loadKg: resolved, loadUnit: .kg, loadDisplayValue: resolved)
        default:
            return nil
        }
    }
}
