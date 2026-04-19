// PercentOf1RMResolverQa045Tests.swift
//
// qa-045 — `percent_1rm` prescriptions must resolve to a concrete
// `loadKg` at seed time when `user_parameters.1rm_<slug>_kg` is
// populated. Before the fix, `percent_1rm` rows landed with `loadKg
// = nil`, so the Active hero rendered "BW" even though Today's
// formatter correctly showed "3 × 5 @ 60% 1RM".
//
// These tests pin the happy-path resolver plus the nil-fallback when
// the key is missing (the spec's documented fallback per
// `docs/prescription.md` § "Percentage-based load").

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class PercentOf1RMResolverQa045Tests: XCTestCase {

    func testPercentOneRmResolvesAgainstUserParameters() {
        // Back Squat, `{sets:3, reps:5, percent_1rm:0.6}`, with a
        // populated `1rm_back_squat_kg = 160`. Resolver must set
        // loadKg = 96.0 on every pending row and unit = .kg.
        let exerciseID = UUID()
        let context = makeContext(
            exerciseID: exerciseID,
            exerciseName: "Back Squat",
            prescriptionJSON: #"{"sets":3,"reps":5,"percent_1rm":0.6}"#,
            userParameters: ["1rm_back_squat_kg": 160.0]
        )

        let state = SessionSeeder.seed(context: context)

        let itemLog = state.items.first
        XCTAssertNotNil(itemLog)
        XCTAssertEqual(itemLog?.sets.count, 3)
        let loads = itemLog?.sets.map(\.loadKg) ?? []
        XCTAssertEqual(loads, [96.0, 96.0, 96.0])
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.unit == .kg } ?? false,
            "resolved percent_1rm rows carry unit = .kg (the parameter's scale)"
        )
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.reps == 5 } ?? false,
            "reps are preserved from the prescription"
        )
    }

    func testPercentOneRmFallsBackToNilWhenNoParameter() {
        // Same prescription, no `1rm_back_squat_kg` in the user_parameters
        // map. Resolver must leave loadKg = nil — the Active hero then
        // renders "BW" and the numpad opens blank.
        let exerciseID = UUID()
        let context = makeContext(
            exerciseID: exerciseID,
            exerciseName: "Back Squat",
            prescriptionJSON: #"{"sets":3,"reps":5,"percent_1rm":0.6}"#,
            userParameters: [:]
        )

        let state = SessionSeeder.seed(context: context)

        let itemLog = state.items.first
        XCTAssertEqual(itemLog?.sets.count, 3)
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.loadKg == nil } ?? false,
            "missing 1RM key falls back to nil (BW) per spec"
        )
    }

    func testOneRMKeyDerivesSlugFromExerciseName() {
        // Pin the key convention against a few canonical names so a
        // future rename doesn't silently diverge from the server's
        // `1rm_<slug>_kg` shape.
        XCTAssertEqual(
            SessionSeeder.oneRMKey(forExerciseName: "Back Squat"),
            "1rm_back_squat_kg"
        )
        XCTAssertEqual(
            SessionSeeder.oneRMKey(forExerciseName: "Close-Grip Bench Press"),
            "1rm_close_grip_bench_press_kg"
        )
        XCTAssertEqual(
            SessionSeeder.oneRMKey(forExerciseName: "  Deadlift  "),
            "1rm_deadlift_kg"
        )
    }

    // MARK: - Fixture

    private func makeContext(
        exerciseID: UUID,
        exerciseName: String,
        prescriptionJSON: String,
        userParameters: [String: Double]
    ) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "qa-045",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: exerciseName)],
            userParameters: userParameters
        )
    }
}
