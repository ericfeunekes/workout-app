// PrimitiveSessionSeeder.swift
//
// Thin feature-owned adapter for the primitive runtime contract. The canonical
// executable state is CoreSession.ExecutionPlan; this layer only names the
// execution feature's seed entrypoint.

import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

public enum PrimitiveSessionSeedError: Error, Equatable {
    case illegalRuntimeCell(setID: PrimitiveSetID)
    case invalidTiming(setID: PrimitiveSetID)
}

public enum PrimitiveSessionSeeder {
    public static func seed(workout: PrimitiveWorkout) throws -> ExecutionPlan {
        try validate(workout)
        return ExecutionPlan(workout: workout)
    }

    public static func seed(
        workout: PrimitiveWorkout,
        userParameters: [String: Double]
    ) throws -> ExecutionPlan {
        try validate(workout)
        return ExecutionPlan(workout: workout) { slot in
            resolve(load: slot.load, exerciseID: slot.exerciseID, userParameters: userParameters)
        }
    }

    public static func setResultLog(
        plan: ExecutionPlan,
        blockIndex: Int,
        setIndexInBlock: Int,
        blockRepeatIndex: Int,
        setRepeatIndex: Int,
        reps: Int? = nil,
        rounds: Int?,
        durationSec: Double?,
        completedAt: Date
    ) -> PrimitiveSetLog {
        plan.blocks[blockIndex].sets[setIndexInBlock].setResultLog(
            workoutID: plan.workoutID,
            blockRepeatIndex: blockRepeatIndex,
            setRepeatIndex: setRepeatIndex,
            reps: reps,
            rounds: rounds,
            durationSec: durationSec,
            completedAt: completedAt
        )
    }

    public static func blockResultLog(
        plan: ExecutionPlan,
        blockIndex: Int,
        blockRepeatIndex: Int,
        durationSec: Double?,
        completedAt: Date
    ) -> PrimitiveSetLog {
        plan.blocks[blockIndex].blockResultLog(
            workoutID: plan.workoutID,
            blockRepeatIndex: blockRepeatIndex,
            durationSec: durationSec,
            completedAt: completedAt
        )
    }

    private static func validate(_ workout: PrimitiveWorkout) throws {
        for block in workout.blocks {
            for set in block.sets {
                if set.traversal == .amrap && (set.timing.mode == .setBounded || set.timing.mode == .targetBounded) {
                    throw PrimitiveSessionSeedError.illegalRuntimeCell(setID: set.id)
                }
                if set.timing.mode == .timeBounded,
                   (set.timing.intervalSec == nil || set.timing.rounds == nil) {
                    throw PrimitiveSessionSeedError.invalidTiming(setID: set.id)
                }
                if set.timing.mode == .capBounded, set.timing.capSec == nil {
                    throw PrimitiveSessionSeedError.invalidTiming(setID: set.id)
                }
                if set.timing.mode == .capBounded,
                   set.traversal == .amrap,
                   !hasRoundsObservation(set.workTargets) {
                    throw PrimitiveSessionSeedError.invalidTiming(setID: set.id)
                }
                if set.timing.mode == .capBounded,
                   set.traversal != .amrap,
                   !set.slots.isEmpty,
                   !hasDurationObservation(set.workTargets) {
                    throw PrimitiveSessionSeedError.invalidTiming(setID: set.id)
                }
            }
        }
    }

    private static func hasRoundsObservation(_ targets: [PrimitiveWorkTarget]) -> Bool {
        targets.contains { $0.metric == .rounds && $0.role == .observation }
    }

    private static func hasDurationObservation(_ targets: [PrimitiveWorkTarget]) -> Bool {
        targets.contains { $0.metric == .duration && $0.role == .observation }
    }

    private static func resolve(
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
