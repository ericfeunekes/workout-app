// TodayPreviewSeed.swift
//
// Hard-coded "Push A" fixture matching the hi-fi reference
// (docs/design/src/hifi.jsx:9-40). Used by:
//   - SwiftUI `#Preview`s in `TodayView`
//   - the initial app launch until the real pull service lands
//
// DEBUG-only. Not shipped in Release builds — the app shell must switch
// to a real `TodayLoader` path before Release. Compiled-out via
// `#if DEBUG` at the file level, which means the Release build simply
// doesn't have this seed; any accidental Release reference would be a
// compile error, caught well before an archive.

#if DEBUG

import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

public enum TodayPreviewSeed {

    /// Build the Push A context. `withLastSession = true` includes a
    /// "last session" chip value; `false` omits it for the alt preview.
    ///
    /// The "last session" summary string below is invented — the hi-fi
    /// reference shows "Fri · Push A · RIR 1.5 avg · body 82.1 kg" but
    /// the design spec does not mandate exact phrasing. We use "FRI ·
    /// Push A · RIR 1.6 avg" (uppercase weekday to match the ALL-CAPS
    /// chip pattern; drop bodyweight from the chip to keep it short).
    public static func pushA(withLastSession: Bool) -> TodayContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let now = Date()
        let catalog = ExerciseCatalog()
        let workout = makePushAWorkout(workoutID: workoutID, userID: userID, now: now)
        let block = makePushABlock(blockID: blockID, workoutID: workoutID)
        return TodayContext(
            workout: workout,
            blocks: [block],
            items: makePushAItems(blockID: blockID, catalog: catalog),
            exercises: catalog.exercises,
            lastPerformed: catalog.lastPerformed,
            lastSessionSummary: withLastSession ? "FRI · Push A · RIR 1.6 avg" : nil,
            programTags: ["week 3", "push day"],
            sessionStateBinding: nil
        )
    }

    /// The four Push A exercises plus their invented "last performed"
    /// summary strings. Kept as a value type so the stable UUIDs and the
    /// dictionaries are constructed together and handed into `pushA`.
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
            notes: "heavy upper — bench focus",
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: #"["week_3","push_day"]"#
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
                prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5,"target_rir":2}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 1,
                exerciseID: catalog.rowID,
                prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80,"target_rir":1}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 2,
                exerciseID: catalog.ohpID,
                prescriptionJSON: #"{"sets":3,"reps":6,"load_kg":55,"target_rir":2}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 3,
                exerciseID: catalog.dipID,
                prescriptionJSON: #"{"sets":3,"reps":10,"load_kg":15,"target_rir":1}"#
            ),
        ]
    }
}

#endif
