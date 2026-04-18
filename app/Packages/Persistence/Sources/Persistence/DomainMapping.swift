// DomainMapping.swift
//
// Pure translation between `CoreDomain` value types and `@Model` reference
// types. The domain types are the currency used by Features/Sync — anything
// leaving Persistence is a domain value; anything entering is too.
//
// Convention: `toDomain()` reads a model and returns the value;
// `fromDomain(_:)` (or an initializer) produces a fresh model. Mutating an
// existing model in place is done by `apply(_ domain:)` for upsert.
//
// Enums map through their `rawValue`. If a persisted row ever holds a
// rawValue that doesn't round-trip (e.g. a SwiftData migration left it in a
// mid-state), we prefer a sensible default over a crash — logged set_logs
// are too valuable to lose to an enum case we don't recognize.

import Foundation
import CoreDomain

extension WorkoutModel {
    public func toDomain() -> Workout {
        Workout(
            id: id,
            userID: userID,
            name: name,
            scheduledDate: scheduledDate,
            status: WorkoutStatus(rawValue: statusRaw) ?? .planned,
            source: WorkoutSource(rawValue: sourceRaw) ?? .claude,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            tagsJSON: tagsJSON
        )
    }

    public static func from(_ w: Workout) -> WorkoutModel {
        WorkoutModel(
            id: w.id,
            userID: w.userID,
            name: w.name,
            scheduledDate: w.scheduledDate,
            statusRaw: w.status.rawValue,
            sourceRaw: w.source.rawValue,
            notes: w.notes,
            createdAt: w.createdAt,
            updatedAt: w.updatedAt,
            completedAt: w.completedAt,
            tagsJSON: w.tagsJSON
        )
    }

    public func apply(_ w: Workout) {
        userID = w.userID
        name = w.name
        scheduledDate = w.scheduledDate
        statusRaw = w.status.rawValue
        sourceRaw = w.source.rawValue
        notes = w.notes
        createdAt = w.createdAt
        updatedAt = w.updatedAt
        completedAt = w.completedAt
        tagsJSON = w.tagsJSON
    }
}

extension BlockModel {
    public func toDomain() -> Block {
        Block(
            id: id,
            workoutID: workoutID,
            parentBlockID: parentBlockID,
            position: position,
            name: name,
            timingMode: TimingMode(rawValue: timingModeRaw) ?? .straightSets,
            timingConfigJSON: timingConfigJSON,
            rounds: rounds,
            roundsRepSchemeJSON: roundsRepSchemeJSON,
            notes: notes
        )
    }

    public static func from(_ b: Block) -> BlockModel {
        BlockModel(
            id: b.id,
            workoutID: b.workoutID,
            parentBlockID: b.parentBlockID,
            position: b.position,
            name: b.name,
            timingModeRaw: b.timingMode.rawValue,
            timingConfigJSON: b.timingConfigJSON,
            rounds: b.rounds,
            roundsRepSchemeJSON: b.roundsRepSchemeJSON,
            notes: b.notes
        )
    }

    public func apply(_ b: Block) {
        workoutID = b.workoutID
        parentBlockID = b.parentBlockID
        position = b.position
        name = b.name
        timingModeRaw = b.timingMode.rawValue
        timingConfigJSON = b.timingConfigJSON
        rounds = b.rounds
        roundsRepSchemeJSON = b.roundsRepSchemeJSON
        notes = b.notes
    }
}

extension WorkoutItemModel {
    public func toDomain() -> WorkoutItem {
        WorkoutItem(
            id: id,
            blockID: blockID,
            position: position,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON,
            prescriptionJSONRaw: prescriptionJSONRaw
        )
    }

    public static func from(_ i: WorkoutItem) -> WorkoutItemModel {
        WorkoutItemModel(
            id: i.id,
            blockID: i.blockID,
            position: i.position,
            exerciseID: i.exerciseID,
            prescriptionJSON: i.prescriptionJSON,
            prescriptionJSONRaw: i.prescriptionJSONRaw
        )
    }

    public func apply(_ i: WorkoutItem) {
        blockID = i.blockID
        position = i.position
        exerciseID = i.exerciseID
        prescriptionJSON = i.prescriptionJSON
        prescriptionJSONRaw = i.prescriptionJSONRaw
    }
}

extension ExerciseModel {
    public func toDomain() -> Exercise {
        Exercise(
            id: id,
            name: name,
            notes: notes,
            demoURL: demoURLString.flatMap { URL(string: $0) },
            defaultPrescriptionJSON: defaultPrescriptionJSON,
            defaultAlternativesJSON: defaultAlternativesJSON
        )
    }

    public static func from(_ e: Exercise) -> ExerciseModel {
        ExerciseModel(
            id: e.id,
            name: e.name,
            notes: e.notes,
            demoURLString: e.demoURL?.absoluteString,
            defaultPrescriptionJSON: e.defaultPrescriptionJSON,
            defaultAlternativesJSON: e.defaultAlternativesJSON
        )
    }

    public func apply(_ e: Exercise) {
        name = e.name
        notes = e.notes
        demoURLString = e.demoURL?.absoluteString
        defaultPrescriptionJSON = e.defaultPrescriptionJSON
        defaultAlternativesJSON = e.defaultAlternativesJSON
    }
}

extension ExerciseAlternativeModel {
    public func toDomain() -> ExerciseAlternative {
        ExerciseAlternative(
            id: id,
            workoutItemID: workoutItemID,
            exerciseID: exerciseID,
            reason: reason,
            parameterOverridesJSON: parameterOverridesJSON
        )
    }

    public static func from(_ a: ExerciseAlternative) -> ExerciseAlternativeModel {
        ExerciseAlternativeModel(
            id: a.id,
            workoutItemID: a.workoutItemID,
            exerciseID: a.exerciseID,
            reason: a.reason,
            parameterOverridesJSON: a.parameterOverridesJSON
        )
    }

    public func apply(_ a: ExerciseAlternative) {
        workoutItemID = a.workoutItemID
        exerciseID = a.exerciseID
        reason = a.reason
        parameterOverridesJSON = a.parameterOverridesJSON
    }
}

extension SetLogModel {
    public func toDomain() -> SetLog {
        SetLog(
            id: id,
            workoutItemID: workoutItemID,
            performedExerciseID: performedExerciseID,
            setIndex: setIndex,
            reps: reps,
            weight: weight,
            weightUnit: weightUnitRaw.flatMap { WeightUnit(rawValue: $0) },
            durationSec: durationSec,
            distanceM: distanceM,
            rir: rir,
            isWarmup: isWarmup,
            startedAt: startedAt,
            completedAt: completedAt,
            hrAvgBpm: hrAvgBpm,
            hrMaxBpm: hrMaxBpm,
            cadenceAvgSpm: cadenceAvgSpm,
            motionSamplesRef: motionSamplesRef,
            notes: notes
        )
    }

    public static func from(_ s: SetLog) -> SetLogModel {
        SetLogModel(
            id: s.id,
            workoutItemID: s.workoutItemID,
            performedExerciseID: s.performedExerciseID,
            setIndex: s.setIndex,
            reps: s.reps,
            weight: s.weight,
            weightUnitRaw: s.weightUnit?.rawValue,
            durationSec: s.durationSec,
            distanceM: s.distanceM,
            rir: s.rir,
            isWarmup: s.isWarmup,
            startedAt: s.startedAt,
            completedAt: s.completedAt,
            hrAvgBpm: s.hrAvgBpm,
            hrMaxBpm: s.hrMaxBpm,
            cadenceAvgSpm: s.cadenceAvgSpm,
            motionSamplesRef: s.motionSamplesRef,
            notes: s.notes
        )
    }

    public func apply(_ s: SetLog) {
        workoutItemID = s.workoutItemID
        performedExerciseID = s.performedExerciseID
        setIndex = s.setIndex
        reps = s.reps
        weight = s.weight
        weightUnitRaw = s.weightUnit?.rawValue
        durationSec = s.durationSec
        distanceM = s.distanceM
        rir = s.rir
        isWarmup = s.isWarmup
        startedAt = s.startedAt
        completedAt = s.completedAt
        hrAvgBpm = s.hrAvgBpm
        hrMaxBpm = s.hrMaxBpm
        cadenceAvgSpm = s.cadenceAvgSpm
        motionSamplesRef = s.motionSamplesRef
        notes = s.notes
    }
}

extension UserParameterModel {
    public func toDomain() -> UserParameter {
        UserParameter(
            id: id,
            userID: userID,
            key: key,
            value: value,
            updatedAt: updatedAt,
            source: UserParameterSource(rawValue: sourceRaw) ?? .claude
        )
    }

    public static func from(_ p: UserParameter) -> UserParameterModel {
        UserParameterModel(
            id: p.id,
            userID: p.userID,
            key: p.key,
            value: p.value,
            updatedAt: p.updatedAt,
            sourceRaw: p.source.rawValue
        )
    }

    public func apply(_ p: UserParameter) {
        userID = p.userID
        key = p.key
        value = p.value
        updatedAt = p.updatedAt
        sourceRaw = p.source.rawValue
    }
}

extension AppUserModel {
    public func toDomain() -> AppUser {
        AppUser(id: id, name: name, createdAt: createdAt)
    }

    public static func from(_ u: AppUser) -> AppUserModel {
        AppUserModel(id: u.id, name: u.name, createdAt: u.createdAt)
    }

    public func apply(_ u: AppUser) {
        name = u.name
        createdAt = u.createdAt
    }
}
