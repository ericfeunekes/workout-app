// Fixtures.swift
//
// Test fixtures for AppBootstrapTests. Builds a SyncPullResponse-shaped
// JSON payload representing a single "Push A" workout with two items.
// Also exposes the equivalent CoreDomain values so cache-priming paths
// (offline fallback test) can seed the cache directly without decoding.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

enum Fixtures {

    struct WorkoutPayload {
        let json: Data
        let serverTime: Date
        let scheduledDate: Date
        let domainWorkout: Workout
        let domainBlocks: [Block]
        let domainItems: [WorkoutItem]
        let domainExercises: [Exercise]
    }

    /// Canned "Push A" fixture — one workout, one block, two items
    /// (bench + row). Returned both as a JSON payload (what the
    /// transport hands back) and as CoreDomain values (what the cache
    /// would hold after a successful pull → save).
    static func sampleWorkoutPayload() -> WorkoutPayload {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let workoutID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let blockID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let item1ID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let item2ID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let benchID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let rowID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

        // Use a fixed timestamp so "scheduled today" matches the
        // injected clock exactly. The wire format for `scheduled_date`
        // is `YYYY-MM-DD`; the wire format for timestamps is ISO-8601.
        let serverTime = ISO8601DateFormatter().date(from: "2026-04-17T08:00:00Z")!
        let scheduledDateFormatter = DateFormatter()
        scheduledDateFormatter.calendar = Calendar(identifier: .gregorian)
        scheduledDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        scheduledDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        scheduledDateFormatter.dateFormat = "yyyy-MM-dd"
        let scheduledDate = scheduledDateFormatter.date(from: "2026-04-17")!

        let createdAtString = "2026-04-17T07:00:00Z"
        let createdAt = ISO8601DateFormatter().date(from: createdAtString)!

        let json = """
        {
          "workouts": [
            {
              "id": "\(workoutID.uuidString.lowercased())",
              "user_id": "\(userID.uuidString.lowercased())",
              "name": "Push A",
              "scheduled_date": "2026-04-17",
              "status": "planned",
              "source": "claude",
              "notes": null,
              "tags_json": null,
              "created_at": "\(createdAtString)",
              "updated_at": "\(createdAtString)",
              "completed_at": null,
              "blocks": [
                {
                  "id": "\(blockID.uuidString.lowercased())",
                  "position": 0,
                  "parent_block_id": null,
                  "name": null,
                  "timing_mode": "straight_sets",
                  "timing_config_json": "{}",
                  "rounds": null,
                  "rounds_rep_scheme_json": null,
                  "notes": null,
                  "workout_items": [
                    {
                      "id": "\(item1ID.uuidString.lowercased())",
                      "position": 0,
                      "exercise_id": "\(benchID.uuidString.lowercased())",
                      "prescription_json": "{\\"sets\\":4,\\"reps\\":5,\\"load_kg\\":102.5}",
                      "alternatives": []
                    },
                    {
                      "id": "\(item2ID.uuidString.lowercased())",
                      "position": 1,
                      "exercise_id": "\(rowID.uuidString.lowercased())",
                      "prescription_json": "{\\"sets\\":3,\\"reps\\":8,\\"load_kg\\":80}",
                      "alternatives": []
                    }
                  ]
                }
              ]
            }
          ],
          "exercises": [
            {
              "id": "\(benchID.uuidString.lowercased())",
              "name": "Barbell Bench Press",
              "notes": null,
              "demo_url": null
            },
            {
              "id": "\(rowID.uuidString.lowercased())",
              "name": "Barbell Row",
              "notes": null,
              "demo_url": null
            }
          ],
          "user_parameters": [],
          "last_performed": [],
          "server_time": "2026-04-17T08:00:00Z"
        }
        """.data(using: .utf8)!

        // Parallel Domain values for the cache-seed test path.
        let domainWorkout = Workout(
            id: workoutID,
            userID: userID,
            name: "Push A",
            scheduledDate: scheduledDate,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil,
            tagsJSON: nil
        )
        let domainBlocks = [
            Block(
                id: blockID,
                workoutID: workoutID,
                parentBlockID: nil,
                position: 0,
                name: nil,
                timingMode: .straightSets,
                timingConfigJSON: "{}",
                rounds: nil,
                roundsRepSchemeJSON: nil,
                notes: nil
            )
        ]
        let domainItems = [
            WorkoutItem(
                id: item1ID,
                blockID: blockID,
                position: 0,
                exerciseID: benchID,
                prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#
            ),
            WorkoutItem(
                id: item2ID,
                blockID: blockID,
                position: 1,
                exerciseID: rowID,
                prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80}"#
            ),
        ]
        let domainExercises = [
            Exercise(id: benchID, name: "Barbell Bench Press"),
            Exercise(id: rowID, name: "Barbell Row"),
        ]

        return WorkoutPayload(
            json: json,
            serverTime: serverTime,
            scheduledDate: scheduledDate,
            domainWorkout: domainWorkout,
            domainBlocks: domainBlocks,
            domainItems: domainItems,
            domainExercises: domainExercises
        )
    }
}
