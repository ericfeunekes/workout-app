// DTOMapping+Primitive.swift
//
// Mapping for primitive DTOs. This is intentionally the only app layer that
// imports WorkoutDBSchema; execution consumes CoreDomain primitives.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

extension DTOMapping {
    public static func mapPrimitiveWorkout(
        _ dto: WorkoutDBSchema.PrimitiveWorkout
    ) -> Result<CoreDomain.PrimitiveWorkout, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("PrimitiveWorkout.id is not a UUID: \(dto.id)"))
        }
        var blocks: [CoreDomain.PrimitiveBlock] = []
        for block in dto.primitiveBlocks {
            switch mapPrimitiveBlock(block) {
            case .success(let mapped): blocks.append(mapped)
            case .failure(let error): return .failure(error)
            }
        }
        return .success(CoreDomain.PrimitiveWorkout(id: id, name: dto.name, blocks: blocks))
    }

    private static func mapPrimitiveBlock(
        _ dto: WorkoutDBSchema.PrimitiveBlock
    ) -> Result<CoreDomain.PrimitiveBlock, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("PrimitiveBlock.id is not a UUID: \(dto.id)"))
        }
        var sets: [CoreDomain.PrimitiveSet] = []
        for set in dto.sets {
            switch mapPrimitiveSet(set) {
            case .success(let mapped): sets.append(mapped)
            case .failure(let error): return .failure(error)
            }
        }
        return .success(CoreDomain.PrimitiveBlock(
            id: id,
            title: dto.title,
            repeatCount: dto.repeatCount,
            workTargets: dto.workTarget.map(mapPrimitiveWorkTarget),
            sets: sets
        ))
    }

    private static func mapPrimitiveSet(
        _ dto: WorkoutDBSchema.PrimitiveSet
    ) -> Result<CoreDomain.PrimitiveSet, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("PrimitiveSet.id is not a UUID: \(dto.id)"))
        }
        var slots: [CoreDomain.PrimitiveSlot] = []
        for slot in dto.slots {
            switch mapPrimitiveSlot(slot) {
            case .success(let mapped): slots.append(mapped)
            case .failure(let error): return .failure(error)
            }
        }
        guard let timingMode = CoreDomain.PrimitiveTimingMode(rawValue: dto.timing.mode.rawValue),
              let traversal = CoreDomain.PrimitiveTraversal(rawValue: dto.traversal.rawValue)
        else {
            return .failure(.decode("PrimitiveSet has unknown timing or traversal"))
        }
        return .success(CoreDomain.PrimitiveSet(
            id: id,
            title: dto.title,
            timing: CoreDomain.PrimitiveTiming(
                mode: timingMode,
                intervalSec: dto.timing.intervalSec,
                rounds: dto.timing.rounds,
                capSec: dto.timing.capSec
            ),
            traversal: traversal,
            repeatCount: dto.repeatCount,
            workTargets: dto.workTarget.map(mapPrimitiveWorkTarget),
            slots: slots
        ))
    }

    private static func mapPrimitiveSlot(
        _ dto: WorkoutDBSchema.PrimitiveSlot
    ) -> Result<CoreDomain.PrimitiveSlot, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("PrimitiveSlot.id is not a UUID: \(dto.id)"))
        }
        guard let exerciseID = UUID(uuidString: dto.exerciseId) else {
            return .failure(.decode("PrimitiveSlot.exercise_id is not a UUID: \(dto.exerciseId)"))
        }
        return .success(CoreDomain.PrimitiveSlot(
            id: id,
            exerciseID: exerciseID,
            workTargets: dto.workTarget.map(mapPrimitiveWorkTarget),
            load: dto.load.flatMap(mapPrimitiveLoad),
            stimuli: dto.stimuli.compactMap(mapPrimitiveStimulus),
            postRestSec: dto.postRestSec,
            isWarmup: dto.isWarmup
        ))
    }

    public static func toDTO(_ log: CoreDomain.PrimitiveSetLog) -> WorkoutDBSchema.PrimitiveSetLog {
        WorkoutDBSchema.PrimitiveSetLog(
            id: log.id.wireID,
            role: WorkoutDBSchema.PrimitiveLogRole(rawValue: log.role.rawValue)!,
            slotId: log.slotID?.wireID,
            setId: log.setID?.wireID,
            blockId: log.blockID?.wireID,
            workoutId: log.workoutID?.wireID,
            plannedExerciseId: log.plannedExerciseID?.wireID,
            performedExerciseId: log.performedExerciseID?.wireID,
            setIndex: log.setIndex,
            setRepeatIndex: log.setRepeatIndex,
            blockRepeatIndex: log.blockRepeatIndex,
            reps: log.reps,
            weight: log.weight,
            weightUnit: log.weightUnit.map { WorkoutDBSchema.WeightUnit(rawValue: $0.rawValue)! },
            durationSec: log.durationSec,
            distanceM: log.distanceM,
            rounds: log.rounds,
            rir: log.rir,
            isWarmup: log.isWarmup,
            completedAt: log.completedAt
        )
    }

    public static func mapPrimitiveSetLog(
        _ dto: WorkoutDBSchema.PrimitiveSetLog
    ) -> Result<CoreDomain.PrimitiveSetLog, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("PrimitiveSetLog.id is not a UUID: \(dto.id)"))
        }
        guard let role = CoreDomain.PrimitiveLogRole(rawValue: dto.role.rawValue) else {
            return .failure(.decode("PrimitiveSetLog.role unknown: \(dto.role.rawValue)"))
        }
        let slotID: PrimitiveSlotID?
        switch parseOptionalUUID(dto.slotId, fieldName: "PrimitiveSetLog.slot_id") {
        case .success(let parsed): slotID = parsed
        case .failure(let error): return .failure(error)
        }
        let setID: PrimitiveSetID?
        switch parseOptionalUUID(dto.setId, fieldName: "PrimitiveSetLog.set_id") {
        case .success(let parsed): setID = parsed
        case .failure(let error): return .failure(error)
        }
        let blockID: BlockID?
        switch parseOptionalUUID(dto.blockId, fieldName: "PrimitiveSetLog.block_id") {
        case .success(let parsed): blockID = parsed
        case .failure(let error): return .failure(error)
        }
        let workoutID: WorkoutID?
        switch parseOptionalUUID(dto.workoutId, fieldName: "PrimitiveSetLog.workout_id") {
        case .success(let parsed): workoutID = parsed
        case .failure(let error): return .failure(error)
        }
        let plannedID: ExerciseID?
        switch parseOptionalUUID(
            dto.plannedExerciseId,
            fieldName: "PrimitiveSetLog.planned_exercise_id"
        ) {
        case .success(let parsed): plannedID = parsed
        case .failure(let error): return .failure(error)
        }
        let performedID: ExerciseID?
        switch parseOptionalUUID(
            dto.performedExerciseId,
            fieldName: "PrimitiveSetLog.performed_exercise_id"
        ) {
        case .success(let parsed): performedID = parsed
        case .failure(let error): return .failure(error)
        }
        let unit = dto.weightUnit.flatMap { CoreDomain.WeightUnit(rawValue: $0.rawValue) }
        return .success(CoreDomain.PrimitiveSetLog(
            id: id,
            role: role,
            slotID: slotID,
            setID: setID,
            blockID: blockID,
            workoutID: workoutID,
            plannedExerciseID: plannedID,
            performedExerciseID: performedID,
            setIndex: dto.setIndex,
            setRepeatIndex: dto.setRepeatIndex,
            blockRepeatIndex: dto.blockRepeatIndex,
            reps: dto.reps,
            weight: dto.weight,
            weightUnit: unit,
            durationSec: dto.durationSec,
            distanceM: dto.distanceM,
            rounds: dto.rounds,
            rir: dto.rir,
            isWarmup: dto.isWarmup,
            completedAt: dto.completedAt
        ))
    }

    private static func mapPrimitiveWorkTarget(
        _ dto: WorkoutDBSchema.PrimitiveWorkTarget
    ) -> CoreDomain.PrimitiveWorkTarget {
        CoreDomain.PrimitiveWorkTarget(
            metric: CoreDomain.PrimitiveMetric(rawValue: dto.metric.rawValue)!,
            valueForm: CoreDomain.PrimitiveValueForm(rawValue: dto.valueForm.rawValue)!,
            value: dto.value,
            role: CoreDomain.PrimitiveWorkRole(rawValue: dto.role.rawValue)!
        )
    }

    private static func mapPrimitiveLoad(
        _ dto: WorkoutDBSchema.PrimitiveLoad
    ) -> CoreDomain.PrimitiveLoad? {
        guard let unit = CoreDomain.PrimitiveLoadUnit(rawValue: dto.unit.rawValue),
              let unitType = CoreDomain.PrimitiveLoadUnitType(rawValue: dto.unitType.rawValue)
        else {
            return nil
        }
        return CoreDomain.PrimitiveLoad(value: dto.value, unit: unit, unitType: unitType)
    }

    private static func mapPrimitiveStimulus(
        _ dto: WorkoutDBSchema.PrimitiveStimulus
    ) -> CoreDomain.PrimitiveStimulus? {
        guard let type = CoreDomain.PrimitiveStimulusType(rawValue: dto.type.rawValue) else {
            return nil
        }
        return CoreDomain.PrimitiveStimulus(type: type, target: dto.target)
    }
}
