// DTOMapping+SetLog.swift
//
// SetLog wire <-> Domain mapping. Decode (pull) is fallible on UUID and
// enum raw values; encode (push) is total because the Domain value has
// already validated those.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

extension DTOMapping {

    // MARK: - SetLog decode

    public static func mapSetLog(_ dto: WorkoutDBSchema.SetLog) -> Result<CoreDomain.SetLog, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("SetLog.id is not a UUID: \(dto.id)"))
        }
        guard let workoutItemID = UUID(uuidString: dto.workoutItemId) else {
            return .failure(.decode("SetLog.workout_item_id is not a UUID: \(dto.workoutItemId)"))
        }
        let performedID: ExerciseID?
        switch parseOptionalUUID(dto.performedExerciseId, fieldName: "SetLog.performed_exercise_id") {
        case .success(let parsed): performedID = parsed
        case .failure(let err): return .failure(err)
        }
        let unit: CoreDomain.WeightUnit?
        if let rawUnit = dto.weightUnit {
            guard let parsed = CoreDomain.WeightUnit(rawValue: rawUnit.rawValue) else {
                return .failure(.decode("SetLog.weight_unit unknown: \(rawUnit.rawValue)"))
            }
            unit = parsed
        } else {
            unit = nil
        }
        return .success(CoreDomain.SetLog(
            id: id,
            workoutItemID: workoutItemID,
            performedExerciseID: performedID,
            setIndex: dto.setIndex,
            reps: dto.reps,
            weight: dto.weight,
            weightUnit: unit,
            durationSec: dto.durationSec,
            distanceM: dto.distanceM,
            rir: dto.rir,
            isWarmup: dto.isWarmup,
            skipped: dto.skipped,
            side: CoreDomain.SetLogSide(rawValue: dto.side.rawValue) ?? .bilateral,
            startedAt: dto.startedAt,
            completedAt: dto.completedAt,
            hrAvgBpm: dto.hrAvgBpm,
            hrMaxBpm: dto.hrMaxBpm,
            cadenceAvgSpm: dto.cadenceAvgSpm,
            motionSamplesRef: dto.motionSamplesRef,
            notes: dto.notes
        ))
    }

    // MARK: - SetLog encode (push)

    /// Map a Domain `SetLog` back onto the wire DTO for push. Inverse of
    /// `mapSetLog`. No failure path — UUIDs are already validated.
    public static func toDTO(_ log: CoreDomain.SetLog) -> WorkoutDBSchema.SetLog {
        // `CoreDomain.WeightUnit` and `WorkoutDBSchema.WeightUnit` have the
        // same string-backed cases by construction (contract test
        // `test_swift_schema_parity.py` enforces parity). The force-unwrap
        // is therefore safe — if it ever fired it would mean the schemas
        // drifted and the contract test would have caught it first.
        // swiftlint:disable:next force_unwrapping
        let wireUnit = log.weightUnit.map { WorkoutDBSchema.WeightUnit(rawValue: $0.rawValue)! }
        return WorkoutDBSchema.SetLog(
            id: log.id.wireID,
            workoutItemId: log.workoutItemID.wireID,
            performedExerciseId: log.performedExerciseID?.wireID,
            setIndex: log.setIndex,
            reps: log.reps,
            weight: log.weight,
            weightUnit: wireUnit,
            durationSec: log.durationSec,
            distanceM: log.distanceM,
            rir: log.rir,
            isWarmup: log.isWarmup,
            skipped: log.skipped,
            side: WorkoutDBSchema.SetLogSide(rawValue: log.side.rawValue) ?? .bilateral,
            startedAt: log.startedAt,
            completedAt: log.completedAt,
            hrAvgBpm: log.hrAvgBpm,
            hrMaxBpm: log.hrMaxBpm,
            cadenceAvgSpm: log.cadenceAvgSpm,
            motionSamplesRef: log.motionSamplesRef,
            notes: log.notes
        )
    }
}
