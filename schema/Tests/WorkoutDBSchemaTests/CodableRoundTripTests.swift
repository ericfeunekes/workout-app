// Round-trip tests — encode a known shape to JSON, decode it back, verify equality.
// Also includes tests that decode sample JSON from the server's real wire format to
// catch key-mapping bugs.

import Foundation
import Testing

@testable import WorkoutDBSchema

// Canonical test UUIDs. Per `docs/specs/v2-architecture.md` § "Data model",
// every id is a UUID; these stable literals keep diffs readable.
private let kExerciseBackSquat = "e0000001-0000-4000-8000-000000000001"
private let kExerciseFrontSquat = "e0000002-0000-4000-8000-000000000002"
private let kWorkoutID = "11111111-1111-1111-1111-111111111111"
private let kUserID = "22222222-2222-2222-2222-222222222222"
private let kBlockID = "33333333-3333-3333-3333-333333333333"
private let kWorkoutItemID = "44444444-4444-4444-4444-444444444444"
private let kAlternativeID = "55555555-5555-5555-5555-555555555555"
private let kUserParameterID = "66666666-6666-6666-6666-666666666666"
private let kSetLogID = "77777777-7777-7777-7777-777777777777"

struct CodableRoundTripTests {

    let decoder = JSONDecoder.workoutDB()
    let encoder = JSONEncoder.workoutDB()

    @Test func exerciseRoundTrip() throws {
        let original = Exercise(id: kExerciseBackSquat, name: "Back Squat", notes: "keep bar tight")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Exercise.self, from: data)
        #expect(decoded == original)
    }

    @Test func exerciseRoundTripWithSmartDefaults() throws {
        let original = Exercise(
            id: kExerciseBackSquat,
            name: "Back Squat",
            defaultPrescriptionJson: #"{"target_rir":2}"#,
            defaultAlternativesJson: #"[{"exercise_id":"\#(kExerciseFrontSquat)","reason":"bar taken","parameter_overrides_json":null}]"#
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Exercise.self, from: data)
        #expect(decoded == original)
        #expect(decoded.defaultPrescriptionJson?.contains("target_rir") == true)
        #expect(decoded.defaultAlternativesJson?.contains("bar taken") == true)
    }

    @Test func workoutItemRoundTripWithPrescriptionRaw() throws {
        // Round-trip the `prescription_json_raw` field — the smart-defaults
        // snapshot column the server populates when the client sent a sparse
        // prescription.
        let item = WorkoutItem(
            id: kWorkoutItemID,
            position: 0,
            exerciseId: kExerciseBackSquat,
            prescriptionJson: #"{"load_kg":102.5,"reps":5,"sets":4,"target_rir":2}"#,
            prescriptionJsonRaw: #"{"sets":4,"reps":5,"load_kg":102.5}"#
        )
        let data = try encoder.encode(item)
        let decoded = try decoder.decode(WorkoutItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.prescriptionJsonRaw?.contains("102.5") == true)
    }

    @Test func exerciseDecodesServerShape() throws {
        let json = """
            {"id":"\(kExerciseBackSquat)","name":"Back Squat","notes":null,"demo_url":null}
            """
        let decoded = try decoder.decode(Exercise.self, from: Data(json.utf8))
        #expect(decoded.id == kExerciseBackSquat)
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

    @Test func setLogSideEnumValues() {
        #expect(SetLogSide.allCases.map(\.rawValue).sorted() == ["bilateral", "left", "right"])
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
            id: kWorkoutID,
            userId: kUserID,
            name: "Tuesday Legs",
            scheduledDate: "2026-04-20",
            status: .planned,
            source: .claude,
            tagsJson: #"["hypertrophy_block_2"]"#,
            createdAt: createdAt,
            updatedAt: createdAt,
            blocks: [
                Block(
                    id: kBlockID,
                    position: 0,
                    timingMode: .straightSets,
                    timingConfigJson: #"{"rest_between_sets_sec":180}"#,
                    intent: "Keep the main lift crisp",
                    workoutItems: [
                        WorkoutItem(
                            id: kWorkoutItemID,
                            position: 0,
                            exerciseId: kExerciseBackSquat,
                            prescriptionJson: #"{"sets":5,"reps":5,"load_kg":100}"#,
                            alternatives: [
                                ExerciseAlternative(
                                    id: kAlternativeID,
                                    exerciseId: kExerciseFrontSquat,
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
            id: kSetLogID,
            workoutItemId: kWorkoutItemID,
            setIndex: 1,
            reps: 5,
            weight: 100.0,
            weightUnit: .kg,
            rir: 2,
            skipped: true,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 1_744_000_000),
            hrAvgBpm: 142,
            hrMaxBpm: 168,
            cadenceAvgSpm: 180
        )
        let data = try encoder.encode(log)
        let decoded = try decoder.decode(SetLog.self, from: data)
        #expect(decoded == log)
        #expect(decoded.skipped == true)
        #expect(decoded.side == .left)
    }

    @Test func userParameterSourceSnakeCase() throws {
        let json = #"{"id":"\#(kUserParameterID)","user_id":"\#(kUserID)","key":"k","value":"v","updated_at":"2026-04-17T00:00:00Z","source":"app_log"}"#
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

    @Test func telemetryEventRoundTrip() throws {
        let ts = Date(timeIntervalSince1970: 1_744_000_000)
        let event = TelemetryEvent(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            timestamp: ts,
            sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            kind: "interaction",
            name: "today.start_tap",
            dataJson: #"{"tab":"today"}"#,
            workoutId: kWorkoutID,
            setLogId: nil
        )
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(TelemetryEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test func telemetryEventsPayloadRoundTrip() throws {
        let ts = Date(timeIntervalSince1970: 1_744_000_000)
        let payload = TelemetryEventsPayload(events: [
            TelemetryEvent(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                timestamp: ts,
                sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                kind: "network",
                name: "network.request",
                dataJson: nil
            )
        ])
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(TelemetryEventsPayload.self, from: data)
        #expect(decoded == payload)
        #expect(decoded.events.count == 1)
    }

    @Test func telemetryEventDecodesSnakeCase() throws {
        let json = #"""
            {
              "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
              "timestamp":"2026-04-18T14:32:15Z",
              "session_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
              "kind":"state",
              "name":"execution.session_mutation",
              "data_json":null,
              "workout_id":null,
              "set_log_id":null
            }
            """#
        let decoded = try decoder.decode(TelemetryEvent.self, from: Data(json.utf8))
        #expect(decoded.sessionId == "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        #expect(decoded.dataJson == nil)
    }

    @Test func syncPullResponseDecodes() throws {
        let json = """
            {
              "workouts": [],
              "exercises": [{"id":"\(kExerciseBackSquat)","name":"Pullup","notes":null,"demo_url":null}],
              "user_parameters": [],
              "last_performed": [],
              "server_time": "2026-04-17T08:00:00Z"
            }
            """
        let decoded = try decoder.decode(SyncPullResponse.self, from: Data(json.utf8))
        #expect(decoded.exercises.count == 1)
        #expect(decoded.exercises[0].id == kExerciseBackSquat)
        #expect(decoded.lastPerformed.isEmpty)
    }
}
