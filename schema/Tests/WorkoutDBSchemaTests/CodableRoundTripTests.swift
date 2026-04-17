// Round-trip tests — encode a known shape to JSON, decode it back, verify equality.
// Also includes tests that decode sample JSON from the server's real wire format to
// catch key-mapping bugs.

import Foundation
import Testing

@testable import WorkoutDBSchema

struct CodableRoundTripTests {

    let decoder = JSONDecoder.workoutDB()
    let encoder = JSONEncoder.workoutDB()

    @Test func exerciseRoundTrip() throws {
        let original = Exercise(id: "back-squat", name: "Back Squat", notes: "keep bar tight")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Exercise.self, from: data)
        #expect(decoded == original)
    }

    @Test func exerciseDecodesServerShape() throws {
        let json = """
            {"id":"back-squat","name":"Back Squat","notes":null,"demo_url":null}
            """
        let decoded = try decoder.decode(Exercise.self, from: Data(json.utf8))
        #expect(decoded.id == "back-squat")
        #expect(decoded.name == "Back Squat")
        #expect(decoded.notes == nil)
        #expect(decoded.demoUrl == nil)
    }

    @Test func timingModeEnumValues() {
        // Exhaustive list must match the server's enum + SQL CHECK constraint.
        let all = TimingMode.allCases.map(\.rawValue).sorted()
        let expected = [
            "amrap",
            "circuit",
            "continuous",
            "custom",
            "emom",
            "for_time",
            "intervals",
            "rest",
            "straight_sets",
            "superset",
            "tabata",
        ]
        #expect(all == expected)
    }

    @Test func workoutStatusEnumValues() {
        let all = WorkoutStatus.allCases.map(\.rawValue).sorted()
        #expect(all == ["active", "completed", "planned", "skipped"])
    }

    @Test func workoutSourceEnumValues() {
        #expect(WorkoutSource.allCases.map(\.rawValue).sorted() == ["claude", "manual"])
    }

    @Test func weightUnitEnumValues() {
        #expect(WeightUnit.allCases.map(\.rawValue).sorted() == ["kg", "lb"])
    }

    @Test func userParameterSourceEnumValues() {
        #expect(
            UserParameterSource.allCases.map(\.rawValue).sorted()
                == ["app_log", "claude", "manual"]
        )
    }

    @Test func nestedWorkoutRoundTrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1_744_000_000)  // 2025-04-07
        let workout = Workout(
            id: "w-1",
            userId: "u-1",
            name: "Tuesday Legs",
            scheduledDate: "2026-04-20",
            status: .planned,
            source: .claude,
            tagsJson: #"["hypertrophy_block_2"]"#,
            createdAt: createdAt,
            updatedAt: createdAt,
            blocks: [
                Block(
                    id: "b-1",
                    position: 0,
                    timingMode: .straightSets,
                    timingConfigJson: #"{"rest_between_sets_sec":180}"#,
                    workoutItems: [
                        WorkoutItem(
                            id: "i-1",
                            position: 0,
                            exerciseId: "back-squat",
                            prescriptionJson: #"{"sets":5,"reps":5,"load_kg":100}"#,
                            alternatives: [
                                ExerciseAlternative(
                                    id: "alt-1",
                                    exerciseId: "front-squat",
                                    reason: "bar taken"
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        let data = try encoder.encode(workout)
        let decoded = try decoder.decode(Workout.self, from: data)
        #expect(decoded == workout)
    }

    @Test func setLogRoundTripWithHR() throws {
        let log = SetLog(
            id: "s-1",
            workoutItemId: "i-1",
            setIndex: 1,
            reps: 5,
            weight: 100.0,
            weightUnit: .kg,
            rpe: 7.5,
            completedAt: Date(timeIntervalSince1970: 1_744_000_000),
            hrAvgBpm: 142,
            hrMaxBpm: 168,
            cadenceAvgSpm: 180
        )
        let data = try encoder.encode(log)
        let decoded = try decoder.decode(SetLog.self, from: data)
        #expect(decoded == log)
    }

    @Test func userParameterSourceSnakeCase() throws {
        let json = #"{"id":"1","user_id":"u","key":"k","value":"v","updated_at":"2026-04-17T00:00:00Z","source":"app_log"}"#
        let decoded = try decoder.decode(UserParameter.self, from: Data(json.utf8))
        #expect(decoded.source == .appLog)
    }

    @Test func versionInfoDecodes() throws {
        let json = """
            {"schema_version":"001_initial.sql","applied_migrations":["001_initial.sql"],"server_version":"0.0.1"}
            """
        let decoded = try decoder.decode(VersionInfo.self, from: Data(json.utf8))
        #expect(decoded.schemaVersion == "001_initial.sql")
        #expect(decoded.appliedMigrations == ["001_initial.sql"])
        #expect(decoded.serverVersion == "0.0.1")
    }

    @Test func syncPullResponseDecodes() throws {
        let json = """
            {
              "workouts": [],
              "exercises": [{"id":"e1","name":"Pullup","notes":null,"demo_url":null}],
              "user_parameters": [],
              "last_performed": [],
              "server_time": "2026-04-17T08:00:00Z"
            }
            """
        let decoded = try decoder.decode(SyncPullResponse.self, from: Data(json.utf8))
        #expect(decoded.exercises.count == 1)
        #expect(decoded.exercises[0].id == "e1")
        #expect(decoded.lastPerformed.isEmpty)
    }
}
