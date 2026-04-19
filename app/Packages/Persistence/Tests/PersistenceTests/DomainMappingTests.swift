// DomainMappingTests.swift
//
// Each entity's domain → @Model → domain round-trip must preserve every
// field. If a new field is added to the domain type, the compiler forces
// us to update the mapping; this test catches the case where a field round-
// trips through a `nil`-defaulted initializer instead.

import XCTest
import CoreDomain
@testable import Persistence

final class DomainMappingTests: XCTestCase {

    func testWorkoutRoundTrip() {
        let w = Fixtures.sampleWorkout()
        let model = WorkoutModel.from(w)
        XCTAssertEqual(model.toDomain(), w)
    }

    func testBlockRoundTrip() {
        let b = Fixtures.sampleBlock()
        let model = BlockModel.from(b)
        XCTAssertEqual(model.toDomain(), b)
    }

    func testWorkoutItemRoundTrip() {
        let i = Fixtures.sampleItem()
        let model = WorkoutItemModel.from(i)
        XCTAssertEqual(model.toDomain(), i)
    }

    func testExerciseRoundTrip() {
        let e = Fixtures.sampleExercise()
        let model = ExerciseModel.from(e)
        XCTAssertEqual(model.toDomain(), e)
    }

    func testExerciseAlternativeRoundTrip() {
        let a = Fixtures.sampleAlternative()
        let model = ExerciseAlternativeModel.from(a)
        XCTAssertEqual(model.toDomain(), a)
    }

    func testSetLogRoundTrip() {
        let s = Fixtures.sampleSetLog()
        // `workoutID` / `plannedExerciseID` are local-only denormalized
        // columns on `SetLogModel` — they round-trip inside Persistence
        // but don't appear on the domain `SetLog`. Pass nil here so the
        // test exercises the ingestion path a pre-R1.4 row would hit
        // (see `SchemaMigrationTests.testV2toV3UpgradeBackfills...` for
        // the post-backfill path).
        let model = SetLogModel.from(s, workoutID: nil, plannedExerciseID: nil)
        XCTAssertEqual(model.toDomain(), s)
    }

    func testUserParameterRoundTrip() {
        let p = Fixtures.sampleUserParameter()
        let model = UserParameterModel.from(p)
        XCTAssertEqual(model.toDomain(), p)
    }

    func testAppUserRoundTrip() {
        let u = Fixtures.sampleAppUser()
        let model = AppUserModel.from(u)
        XCTAssertEqual(model.toDomain(), u)
    }
}
