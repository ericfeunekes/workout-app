// Fixtures.swift
//
// Shared factories for test data. Each helper accepts overrides so a test
// can pin the one field it cares about without restating everything.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

enum Fixtures {
    static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func sampleWorkout(
        id: UUID = UUID(),
        userID: UUID = UUID(),
        name: String = "Test Workout",
        status: WorkoutStatus = .planned
    ) -> Workout {
        Workout(
            id: id,
            userID: userID,
            name: name,
            scheduledDate: baseDate,
            status: status,
            source: .claude,
            notes: "sample notes",
            createdAt: baseDate,
            updatedAt: baseDate,
            completedAt: nil,
            tagsJSON: "[\"block_1\"]"
        )
    }

    static func sampleBlock(
        id: UUID = UUID(),
        workoutID: UUID = UUID(),
        position: Int = 0
    ) -> Block {
        Block(
            id: id,
            workoutID: workoutID,
            parentBlockID: nil,
            position: position,
            name: "Main",
            timingMode: .straightSets,
            timingConfigJSON: "{\"rest_between_sets_sec\":120}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil,
            intent: "Controlled strength work"
        )
    }

    static func sampleItem(
        id: UUID = UUID(),
        blockID: UUID = UUID(),
        exerciseID: UUID = UUID(),
        position: Int = 0
    ) -> WorkoutItem {
        WorkoutItem(
            id: id,
            blockID: blockID,
            position: position,
            exerciseID: exerciseID,
            prescriptionJSON: "{\"sets\":5,\"reps\":5,\"target_rir\":2}",
            prescriptionJSONRaw: "{\"sets\":5,\"reps\":5}"
        )
    }

    static func sampleAlternative(
        id: UUID = UUID(),
        workoutItemID: UUID = UUID(),
        exerciseID: UUID = UUID()
    ) -> ExerciseAlternative {
        ExerciseAlternative(
            id: id,
            workoutItemID: workoutItemID,
            exerciseID: exerciseID,
            reason: "knee-friendly",
            parameterOverridesJSON: "{\"reps\":8}"
        )
    }

    static func sampleExercise(
        id: UUID = UUID(),
        name: String = "Back Squat"
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            notes: "bar in the high-bar position",
            demoURL: URL(string: "https://example.com/backsquat"),
            defaultPrescriptionJSON: "{\"target_rir\":2}",
            defaultAlternativesJSON: "[{\"exercise_id\":\"00000000-0000-0000-0000-000000000001\",\"reason\":\"bar taken\"}]"
        )
    }

    /// Build a domain `SetLog` fixture. The local-only denormalized
    /// fields (`workoutID`, `plannedExerciseID` on `SetLogModel`) are
    /// stamped by the cache at insert time, so they don't belong on
    /// the domain fixture — callers pass them through `saveSetLogs`'s
    /// `workoutID` parameter instead.
    static func sampleSetLog(
        id: UUID = UUID(),
        workoutItemID: UUID = UUID(),
        setIndex: Int = 1
    ) -> SetLog {
        SetLog(
            id: id,
            workoutItemID: workoutItemID,
            performedExerciseID: nil,
            setIndex: setIndex,
            reps: 5,
            weight: 100.0,
            weightUnit: .kg,
            durationSec: nil,
            distanceM: nil,
            rir: 2,
            isWarmup: false,
            skipped: true,
            side: .right,
            startedAt: baseDate,
            completedAt: baseDate.addingTimeInterval(60),
            hrAvgBpm: 140,
            hrMaxBpm: 160,
            cadenceAvgSpm: nil,
            motionSamplesRef: nil,
            notes: nil
        )
    }

    static func samplePrimitiveSetLog(
        id: UUID = UUID(),
        role: PrimitiveLogRole = .slot,
        workoutID: UUID = UUID(),
        slotID: UUID = UUID(),
        setID: UUID = UUID(),
        blockID: UUID = UUID(),
        plannedExerciseID: UUID = UUID(),
        setIndex: Int = 1
    ) -> PrimitiveSetLog {
        PrimitiveSetLog(
            id: id,
            role: role,
            slotID: slotID,
            setID: setID,
            blockID: blockID,
            workoutID: workoutID,
            plannedExerciseID: plannedExerciseID,
            performedExerciseID: nil,
            setIndex: setIndex,
            reps: 5,
            weight: 100.0,
            weightUnit: .kg,
            rir: 2,
            completedAt: baseDate.addingTimeInterval(TimeInterval(setIndex))
        )
    }

    static func sampleUserParameter(
        id: UUID = UUID(),
        userID: UUID = UUID(),
        key: String = "bodyweight_kg",
        value: String = "81.5"
    ) -> UserParameter {
        UserParameter(
            id: id,
            userID: userID,
            key: key,
            value: value,
            updatedAt: baseDate,
            source: .claude
        )
    }

    static func sampleAppUser(
        id: UUID = UUID()
    ) -> AppUser {
        AppUser(id: id, name: "Eric", createdAt: baseDate)
    }
}
