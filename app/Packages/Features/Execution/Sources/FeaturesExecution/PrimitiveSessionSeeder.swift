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
    case unsupportedRelativeLoad(slotID: PrimitiveSlotID)
    case illegalRuntimeCell(setID: PrimitiveSetID)
}

public enum PrimitiveSessionSeeder {
    public static func seed(workout: PrimitiveWorkout) throws -> ExecutionPlan {
        try validate(workout)
        return ExecutionPlan(workout: workout)
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
                if block.repeatCount != 1 && hasAggregateObservation(set) {
                    throw PrimitiveSessionSeedError.illegalRuntimeCell(setID: set.id)
                }
                if set.repeatCount != 1 && hasAggregateObservation(set) {
                    throw PrimitiveSessionSeedError.illegalRuntimeCell(setID: set.id)
                }
                for slot in set.slots {
                    guard let load = slot.load else { continue }
                    if load.unitType != .absolute || (load.unit != .kg && load.unit != .lb) {
                        throw PrimitiveSessionSeedError.unsupportedRelativeLoad(slotID: slot.id)
                    }
                }
            }
            if block.repeatCount != 1,
               hasDurationObservation(block.workTargets),
               let firstSet = block.sets.first {
                throw PrimitiveSessionSeedError.illegalRuntimeCell(setID: firstSet.id)
            }
            let aggregateSetCount = block.sets.filter(hasAggregateObservation).count
            if aggregateSetCount > 1, let firstSet = block.sets.first {
                throw PrimitiveSessionSeedError.illegalRuntimeCell(setID: firstSet.id)
            }
        }
    }

    private static func hasAggregateObservation(_ set: PrimitiveSet) -> Bool {
        hasRoundsObservation(set.workTargets) || hasDurationObservation(set.workTargets)
    }

    private static func hasRoundsObservation(_ targets: [PrimitiveWorkTarget]) -> Bool {
        targets.contains { $0.metric == .rounds && $0.role == .observation }
    }

    private static func hasDurationObservation(_ targets: [PrimitiveWorkTarget]) -> Bool {
        targets.contains { $0.metric == .duration && $0.role == .observation }
    }
}
