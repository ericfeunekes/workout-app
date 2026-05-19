// Canonical fixture decoding tests.
//
// These JSON files under schema/fixtures/ are the cross-stack truth-set —
// both Swift and Python decode them successfully. If a fixture stops decoding
// here or in the Python contract tests, the wire format drifted.

import Foundation
import Testing

@testable import WorkoutDBSchema

struct FixtureDecodingTests {

    static var fixtureRoot: URL {
        // Tests run from schema/.build/..., so walk up to the package dir.
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "schema" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("fixtures")
    }

    let decoder = JSONDecoder.workoutDB()

    @Test func workoutCreateFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("workout_create.json")
        let data = try Data(contentsOf: url)
        let workout = try decoder.decode(Workout.self, from: data)
        #expect(workout.name == "Tuesday Legs")
        #expect(workout.status == .planned)
        #expect(workout.activityIntent?.activityDomain == .traditionalStrength)
        #expect(workout.activityIntent?.environment == .unspecified)
        #expect(workout.activityIntent?.preservationPolicy == .preserveStructure)
        #expect(workout.primitiveBlocks.count == 1)
        #expect(workout.primitiveBlocks[0].sets.count == 1)
        #expect(workout.primitiveBlocks[0].sets[0].timing.mode == .setBounded)
        #expect(workout.tagsJson == "[\"hypertrophy_block_2\", \"week_3\"]")
    }

    @Test func workoutDecodeRejectsInvalidPrimitiveBlocks() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "name": "Mixed primitive",
          "scheduled_date": "2026-04-20",
          "status": "planned",
          "source": "claude",
          "notes": null,
          "tags_json": null,
          "created_at": "2026-04-17T08:00:00Z",
          "updated_at": "2026-04-17T08:00:00Z",
          "completed_at": null,
          "primitive_blocks": [
            {
              "id": "33333333-3333-4333-8333-333333333333",
              "title": "Main",
              "repeat": 1,
              "work_target": [],
              "sets": [
                {
                  "id": "44444444-4444-4444-8444-444444444444",
                  "timing": { "mode": "set_bounded" },
                  "traversal": "sequential",
                  "repeat": 1,
                  "work_target": [],
                  "slots": [
                    {
                      "id": "55555555-5555-4555-8555-555555555555",
                      "exercise_id": "e0000001-0000-4000-8000-000000000001",
                      "work_target": [],
                      "load": null,
                      "stimuli": [],
                      "post_rest_sec": 0,
                      "is_warmup": false
                    }
                  ]
                }
              ]
            },
            {
              "id": "99999999-9999-4999-8999-999999999999",
              "sets": [
                { "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "timing": { "mode": "future_mode" }, "slots": [] }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(Workout.self, from: json)
        }
    }

    @Test func syncPullResponseFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("sync_pull_response.json")
        let data = try Data(contentsOf: url)
        let response = try decoder.decode(SyncPullResponse.self, from: data)
        #expect(response.exercises.count == 1)
        #expect(response.exercises[0].id == "e0000001-0000-4000-8000-000000000001")
        #expect(response.userParameters.count == 1)
        #expect(response.userParameters[0].source == .claude)
        #expect(response.lastPerformed.count == 1)
        let first = response.lastPerformed[0]
        #expect(first.exerciseId == "e0000001-0000-4000-8000-000000000001")
        #expect(first.lastSetLogs.first?.role == .slot)
        #expect(first.lastSetLogs.first?.weight == 100.0)
        #expect(first.lastSetLogs.first?.rir == 2)
    }

    @Test func exerciseWithDefaultsFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("exercise_with_defaults.json")
        let data = try Data(contentsOf: url)
        let exercise = try decoder.decode(Exercise.self, from: data)
        #expect(exercise.id == "e0000001-0000-4000-8000-000000000001")
        #expect(exercise.defaultPrescriptionJson?.contains("target_rir") == true)
        #expect(exercise.defaultPrescriptionJson?.contains("autoreg") == true)
        #expect(exercise.defaultAlternativesJson?.contains("bar taken") == true)
    }

    @Test func telemetryEventFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("telemetry_event.json")
        let data = try Data(contentsOf: url)
        let event = try decoder.decode(TelemetryEvent.self, from: data)
        #expect(event.id == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        #expect(event.sessionId == "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        #expect(event.kind == "interaction")
        #expect(event.name == "today.start_tap")
        #expect(event.dataJson == "{\"tab\":\"today\"}")
        #expect(event.workoutId == "11111111-1111-1111-1111-111111111111")
        #expect(event.setLogId == nil)
    }

    @Test func primitiveStrengthFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("primitive_strength_workout.json")
        let data = try Data(contentsOf: url)
        let workout = try decoder.decode(PrimitiveWorkout.self, from: data)
        #expect(workout.name == "Primitive strength")
        #expect(workout.primitiveBlocks[0].sets[0].timing.mode == .setBounded)
        #expect(workout.primitiveBlocks[0].sets[0].repeatCount == 3)
        #expect(workout.primitiveBlocks[0].sets[0].slots[0].load?.unit == .kg)
        #expect(workout.primitiveBlocks[0].sets[0].slots[0].stimuli[0].type == .rir)
    }

    @Test func primitiveAmrapFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("primitive_amrap_workout.json")
        let data = try Data(contentsOf: url)
        let workout = try decoder.decode(PrimitiveWorkout.self, from: data)
        let set = workout.primitiveBlocks[0].sets[0]
        #expect(set.timing.mode == .capBounded)
        #expect(set.traversal == .amrap)
        #expect(set.workTarget[0].metric == .rounds)
        #expect(set.slots.count == 2)
    }
}
