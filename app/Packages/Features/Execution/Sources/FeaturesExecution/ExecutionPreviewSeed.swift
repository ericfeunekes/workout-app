// ExecutionPreviewSeed.swift
//
// DEBUG-only fixture that mirrors `TodayPreviewSeed.pushA(...)` but
// returns a `WorkoutContext` (the shape Execution consumes).
//
// Used by:
//   - SwiftUI `#Preview`s for ActiveView / RestView / CompleteView
//   - early runtime before a real loader lands
//
// Not shipped in Release builds (wrapped in `#if DEBUG`).

#if DEBUG

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public enum ExecutionPreviewSeed {
    public static func pushA() -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let now = Date()
        let catalog = ExerciseCatalog()
        return WorkoutContext(
            workout: makePushAWorkout(workoutID: workoutID, userID: userID, now: now),
            blocks: [makePushABlock(blockID: blockID, workoutID: workoutID)],
            itemsByBlock: [makePushAItems(blockID: blockID, catalog: catalog)],
            exercises: catalog.exercises,
            lastPerformed: catalog.lastPerformed
        )
    }

    /// Stable exercise IDs + invented "last performed" strings. Kept as a
    /// value type so the dictionaries stay tied to the same UUIDs.
    private struct ExerciseCatalog {
        let benchID = UUID()
        let rowID = UUID()
        let ohpID = UUID()
        let dipID = UUID()

        var exercises: [UUID: Exercise] {
            [
                benchID: Exercise(id: benchID, name: "Barbell Bench Press"),
                rowID: Exercise(id: rowID, name: "Barbell Row"),
                ohpID: Exercise(id: ohpID, name: "Overhead Press"),
                dipID: Exercise(id: dipID, name: "Weighted Dip"),
            ]
        }

        var lastPerformed: [UUID: String] {
            [
                benchID: "5×5 @ 100 kg · RIR 2",
                rowID: "3×8 @ 77.5 kg · RIR 1",
                ohpID: "3×6 @ 52.5 kg · RIR 2",
                dipID: "3×10 @ BW+12.5 · RIR 1",
            ]
        }
    }

    private static func makePushAWorkout(
        workoutID: UUID,
        userID: UUID,
        now: Date
    ) -> Workout {
        Workout(
            id: workoutID,
            userID: userID,
            name: "Push A",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
    }

    private static func makePushABlock(blockID: UUID, workoutID: UUID) -> Block {
        Block(
            id: blockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: "main",
            timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":180,"rest_between_exercises_sec":180}"#,
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
    }

    private static func makePushAItems(
        blockID: UUID,
        catalog: ExerciseCatalog
    ) -> [WorkoutItem] {
        [
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 0,
                exerciseID: catalog.benchID,
                prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5,"target_rir":2,"autoreg":{}}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 1,
                exerciseID: catalog.rowID,
                prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80,"target_rir":1,"autoreg":{}}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 2,
                exerciseID: catalog.ohpID,
                prescriptionJSON: #"{"sets":3,"reps":6,"load_kg":55,"target_rir":2,"autoreg":{}}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 3,
                exerciseID: catalog.dipID,
                prescriptionJSON: #"{"sets":3,"reps":10,"load_kg":15,"target_rir":1,"autoreg":{}}"#
            ),
        ]
    }
}

#endif
