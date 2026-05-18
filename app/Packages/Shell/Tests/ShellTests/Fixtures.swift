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

    /// A fully-assembled planned workout with its blocks, items, and
    /// exercises — the shape needed to prime `WorkoutCache` for the
    /// post-save-VM-rebuild regression test. One block, one item, one
    /// set so a single `logSet` drives the workout to completion.
    struct PlannedWorkout {
        let workout: Workout
        let blocks: [Block]
        let items: [WorkoutItem]
        let exercises: [Exercise]
    }

    /// Two planned workouts scheduled on adjacent days, with non-
    /// overlapping IDs so the cache can hold both. Workout A is
    /// scheduled earlier (one day before B) so
    /// `TodayLoader.pickClosest(to: A.scheduledDate, ...)` selects it
    /// first. After A is completed, a reload at the same `now` picks B
    /// (the only remaining `.planned` row).
    static func twoPlannedWorkouts() -> (PlannedWorkout, PlannedWorkout) {
        let userID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let day = TimeInterval(24 * 60 * 60)
        let now = ISO8601DateFormatter().date(from: "2026-04-17T08:00:00Z")!
        let workoutA = singletonWorkout(
            name: "Workout A",
            userID: userID,
            scheduledAt: now,
            createdAt: now,
            ids: .init(
                workout: UUID(uuidString: "a0000000-0000-0000-0000-000000000000")!,
                block: UUID(uuidString: "a1000000-0000-0000-0000-000000000000")!,
                item: UUID(uuidString: "a2000000-0000-0000-0000-000000000000")!,
                exercise: UUID(uuidString: "a3000000-0000-0000-0000-000000000000")!
            )
        )
        let workoutB = singletonWorkout(
            name: "Workout B",
            userID: userID,
            scheduledAt: now.addingTimeInterval(day),
            createdAt: now,
            ids: .init(
                workout: UUID(uuidString: "b0000000-0000-0000-0000-000000000000")!,
                block: UUID(uuidString: "b1000000-0000-0000-0000-000000000000")!,
                item: UUID(uuidString: "b2000000-0000-0000-0000-000000000000")!,
                exercise: UUID(uuidString: "b3000000-0000-0000-0000-000000000000")!
            )
        )
        return (workoutA, workoutB)
    }

    private struct SingletonIDs {
        let workout: UUID
        let block: UUID
        let item: UUID
        let exercise: UUID
    }

    /// Build a minimal 1-block / 1-item / 1-set planned workout. A
    /// single `logSet(reps:rir:)` drives it from `.active` straight to
    /// `.complete` because `timing_config_json` is `{}` → zero rest.
    private static func singletonWorkout(
        name: String,
        userID: UUID,
        scheduledAt: Date,
        createdAt: Date,
        ids: SingletonIDs
    ) -> PlannedWorkout {
        let workout = Workout(
            id: ids.workout,
            userID: userID,
            name: name,
            scheduledDate: scheduledAt,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil,
            tagsJSON: nil
        )
        let block = Block(
            id: ids.block,
            workoutID: ids.workout,
            parentBlockID: nil,
            position: 0,
            name: nil,
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let item = WorkoutItem(
            id: ids.item,
            blockID: ids.block,
            position: 0,
            exerciseID: ids.exercise,
            prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":100}"#
        )
        let exercise = Exercise(id: ids.exercise, name: "Barbell Squat")
        return PlannedWorkout(
            workout: workout,
            blocks: [block],
            items: [item],
            exercises: [exercise]
        )
    }

    /// Canned "Push A" fixture — one workout, one block, two items
    /// (bench + row). Returned both as a JSON payload (what the
    /// transport hands back) and as CoreDomain values (what the cache
    /// would hold after a successful pull → save).
    static func sampleWorkoutPayload(
        includeLastPerformed: Bool = false
    ) -> WorkoutPayload {
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

        // `last_performed` section. Empty by default to keep existing
        // tests unchanged; the qa-001/qa-020 regression test passes
        // `includeLastPerformed: true` so the server response carries
        // one snapshot per exercise the workout references.
        let lastPerformedJSON: String
        if includeLastPerformed {
            lastPerformedJSON = """
            [
              {
                "exercise_id": "\(benchID.uuidString.lowercased())",
                "last_set_logs": [
                  {
                    "id": "aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
                    "role": "slot",
                    "slot_id": "aaaaaaaa-aaaa-4aaa-8aaa-000000000002",
                    "set_id": null,
                    "block_id": null,
                    "workout_id": "\(workoutID.uuidString.lowercased())",
                    "planned_exercise_id": "\(benchID.uuidString.lowercased())",
                    "performed_exercise_id": null,
                    "set_index": 1,
                    "set_repeat_index": 0,
                    "block_repeat_index": 0,
                    "reps": 5,
                    "weight": 100.0,
                    "weight_unit": "kg",
                    "duration_sec": null,
                    "distance_m": null,
                    "rounds": null,
                    "rir": 2,
                    "is_warmup": false,
                    "completed_at": "2026-04-10T07:15:00Z"
                  }
                ]
              },
              {
                "exercise_id": "\(rowID.uuidString.lowercased())",
                "last_set_logs": [
                  {
                    "id": "bbbbbbbb-bbbb-4bbb-8bbb-000000000001",
                    "role": "slot",
                    "slot_id": "bbbbbbbb-bbbb-4bbb-8bbb-000000000002",
                    "set_id": null,
                    "block_id": null,
                    "workout_id": "\(workoutID.uuidString.lowercased())",
                    "planned_exercise_id": "\(rowID.uuidString.lowercased())",
                    "performed_exercise_id": null,
                    "set_index": 1,
                    "set_repeat_index": 0,
                    "block_repeat_index": 0,
                    "reps": 8,
                    "weight": 77.5,
                    "weight_unit": "kg",
                    "duration_sec": null,
                    "distance_m": null,
                    "rounds": null,
                    "rir": 1,
                    "is_warmup": false,
                    "completed_at": "2026-04-10T07:25:00Z"
                  },
                  {
                    "id": "bbbbbbbb-bbbb-4bbb-8bbb-000000000003",
                    "role": "slot",
                    "slot_id": "bbbbbbbb-bbbb-4bbb-8bbb-000000000002",
                    "set_id": null,
                    "block_id": null,
                    "workout_id": "\(workoutID.uuidString.lowercased())",
                    "planned_exercise_id": "\(rowID.uuidString.lowercased())",
                    "performed_exercise_id": null,
                    "set_index": 2,
                    "set_repeat_index": 1,
                    "block_repeat_index": 0,
                    "reps": 8,
                    "weight": 77.5,
                    "weight_unit": "kg",
                    "duration_sec": null,
                    "distance_m": null,
                    "rounds": null,
                    "rir": 1,
                    "is_warmup": false,
                    "completed_at": "2026-04-10T07:27:00Z"
                  },
                  {
                    "id": "bbbbbbbb-bbbb-4bbb-8bbb-000000000004",
                    "role": "slot",
                    "slot_id": "bbbbbbbb-bbbb-4bbb-8bbb-000000000002",
                    "set_id": null,
                    "block_id": null,
                    "workout_id": "\(workoutID.uuidString.lowercased())",
                    "planned_exercise_id": "\(rowID.uuidString.lowercased())",
                    "performed_exercise_id": null,
                    "set_index": 3,
                    "set_repeat_index": 2,
                    "block_repeat_index": 0,
                    "reps": 8,
                    "weight": 77.5,
                    "weight_unit": "kg",
                    "duration_sec": null,
                    "distance_m": null,
                    "rounds": null,
                    "rir": 1,
                    "is_warmup": false,
                    "completed_at": "2026-04-10T07:29:00Z"
                  }
                ]
              }
            ]
            """
        } else {
            lastPerformedJSON = "[]"
        }

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
              "primitive_blocks": [
                {
                  "id": "\(blockID.uuidString.lowercased())",
                  "title": null,
                  "repeat": 1,
                  "work_target": [],
                  "sets": [
                    {
                      "id": "\(item1ID.uuidString.lowercased())",
                      "title": null,
                      "timing": {"mode": "set_bounded", "interval_sec": null, "rounds": null, "cap_sec": null},
                      "traversal": "sequential",
                      "repeat": 4,
                      "work_target": [],
                      "slots": [
                        {
                          "id": "\(item1ID.uuidString.lowercased())",
                          "exercise_id": "\(benchID.uuidString.lowercased())",
                          "work_target": [{"metric": "reps", "value_form": "single", "value": 5, "role": "completion"}],
                          "load": {"value": 102.5, "unit": "kg", "unit_type": "absolute"},
                          "stimuli": [],
                          "post_rest_sec": 0,
                          "is_warmup": false
                        }
                      ]
                    },
                    {
                      "id": "\(item2ID.uuidString.lowercased())",
                      "title": null,
                      "timing": {"mode": "set_bounded", "interval_sec": null, "rounds": null, "cap_sec": null},
                      "traversal": "sequential",
                      "repeat": 3,
                      "work_target": [],
                      "slots": [
                        {
                          "id": "\(item2ID.uuidString.lowercased())",
                          "exercise_id": "\(rowID.uuidString.lowercased())",
                          "work_target": [{"metric": "reps", "value_form": "single", "value": 8, "role": "completion"}],
                          "load": {"value": 80, "unit": "kg", "unit_type": "absolute"},
                          "stimuli": [],
                          "post_rest_sec": 0,
                          "is_warmup": false
                        }
                      ]
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
          "last_performed": \(lastPerformedJSON),
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
