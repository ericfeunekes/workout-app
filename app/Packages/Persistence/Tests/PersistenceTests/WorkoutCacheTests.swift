// WorkoutCacheTests.swift
//
// Round-trip and upsert semantics for `WorkoutCacheImpl`. All tests use an
// in-memory ModelContainer so state does not leak between runs.

import XCTest
import SwiftData
import CoreDomain
import WorkoutCoreFoundation
@testable import Persistence

final class WorkoutCacheTests: XCTestCase {

    private func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    func testSaveAndLoadWorkoutRoundTrip() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let item = Fixtures.sampleItem(blockID: block.id)
        let alt = Fixtures.sampleAlternative(workoutItemID: item.id)
        let exercise = Fixtures.sampleExercise(id: item.exerciseID)
        let param = Fixtures.sampleUserParameter(userID: workout.userID)

        try await cache.save(
            PulledDataset(
                workouts: [workout],
                blocks: [block],
                items: [item],
                alternatives: [alt],
                exercises: [exercise],
                userParameters: [param]
            )
        )

        let loadedWorkouts = try await cache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(loadedWorkouts.count, 1)
        XCTAssertEqual(loadedWorkouts[0], workout)

        let loadedBlocks = try await cache.loadBlocks(workoutID: workout.id)
        XCTAssertEqual(loadedBlocks.count, 1)
        XCTAssertEqual(loadedBlocks[0], block)

        let loadedItems = try await cache.loadItems(blockID: block.id)
        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertEqual(loadedItems[0], item)

        let loadedAlternatives = try await cache.loadAlternatives(workoutItemID: item.id)
        XCTAssertEqual(loadedAlternatives.count, 1)
        XCTAssertEqual(loadedAlternatives[0], alt)

        let exercises = try await cache.loadExercises()
        XCTAssertEqual(exercises, [exercise])

        let latest = try await cache.loadUserParametersLatest()
        XCTAssertEqual(latest[param.key], param)
    }

    func testUpsertDoesNotDuplicate() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        let workout = Fixtures.sampleWorkout()
        try await cache.save(PulledDataset(workouts: [workout]))

        // Save the same UUID with a changed name. The row must update
        // in place — not insert a second row — so we still have exactly
        // one workout and the new name wins.
        var updated = workout
        updated.name = "Renamed"
        try await cache.save(PulledDataset(workouts: [updated]))

        let rows = try await cache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Renamed")
    }

    func testFilterWorkoutsByStatus() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        let planned = Fixtures.sampleWorkout(status: .planned)
        let completed = Fixtures.sampleWorkout(status: .completed)
        try await cache.save(PulledDataset(workouts: [planned, completed]))

        let plannedRows = try await cache.loadWorkouts(status: .planned, since: nil)
        XCTAssertEqual(plannedRows.count, 1)
        XCTAssertEqual(plannedRows[0].id, planned.id)

        let completedRows = try await cache.loadWorkouts(status: .completed, since: nil)
        XCTAssertEqual(completedRows.count, 1)
        XCTAssertEqual(completedRows[0].id, completed.id)
    }

    func testLatestUserParameterPerKey() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        let userID = UUID()
        let earlier = UserParameter(
            id: UUID(),
            userID: userID,
            key: "bodyweight_kg",
            value: "80.0",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .claude
        )
        let later = UserParameter(
            id: UUID(),
            userID: userID,
            key: "bodyweight_kg",
            value: "81.5",
            updatedAt: Date(timeIntervalSince1970: 1_700_100_000),
            source: .claude
        )
        try await cache.save(PulledDataset(userParameters: [earlier, later]))

        let latest = try await cache.loadUserParametersLatest()
        XCTAssertEqual(latest["bodyweight_kg"]?.value, "81.5")
    }

    /// Atomicity regression: `save(_:)` wraps its upsert loop in
    /// `ModelContext.transaction { ... }`. If any helper throws mid-loop
    /// the whole batch rolls back — nothing the failed run touched ends
    /// up on disk. Without the transaction wrap, a partial loop would
    /// leave the in-memory context dirty and the NEXT successful save()
    /// would flush that half-state.
    func testSaveRollsBackOnThrowMidLoop() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        // 1. Seed some known-good state so we can prove the rollback
        //    doesn't wipe rows that existed before the failed batch.
        let preExistingWorkout = Fixtures.sampleWorkout(name: "Original")
        try await cache.save(PulledDataset(workouts: [preExistingWorkout]))

        // 2. Attempt a transactional batch that performs valid upserts
        //    and then throws at the end of the block. Use the test hook
        //    on the concrete actor to reach into the same transaction
        //    path `save(_:)` uses.
        let failingWorkout = Fixtures.sampleWorkout(name: "Should Not Persist")
        let failingExercise = Fixtures.sampleExercise(name: "Should Not Persist")

        guard let impl = cache as? WorkoutCacheImpl else {
            XCTFail("WorkoutCacheImpl expected from the factory")
            return
        }

        do {
            try await impl.saveThenThrowForTests(
                PulledDataset(
                    workouts: [failingWorkout],
                    exercises: [failingExercise]
                )
            )
            XCTFail("saveThenThrowForTests should have thrown")
        } catch {
            // Expected — the test hook always throws after its upserts.
        }

        // 3. Assertions:
        //    - The pre-existing workout is still there (unchanged).
        //    - The failed batch's workout is NOT on disk.
        //    - The failed batch's exercise is NOT on disk.
        let workouts = try await cache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts[0].id, preExistingWorkout.id)
        XCTAssertEqual(workouts[0].name, "Original")

        let exercises = try await cache.loadExercises()
        XCTAssertTrue(
            exercises.isEmpty,
            "Exercise from rolled-back batch should not be on disk"
        )

        // 4. A subsequent *successful* save must not include any stray
        //    state from the failed batch (this is the specific hazard
        //    transaction-wrap protects against — a dirty context flushed
        //    by the next save()).
        let cleanWorkout = Fixtures.sampleWorkout(name: "Clean Batch")
        try await cache.save(PulledDataset(workouts: [cleanWorkout]))

        let finalWorkouts = try await cache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(finalWorkouts.count, 2)
        let names = Set(finalWorkouts.map { $0.name })
        XCTAssertEqual(names, Set(["Original", "Clean Batch"]))
        XCTAssertFalse(
            names.contains("Should Not Persist"),
            "Rolled-back batch must not leak into the next successful save"
        )
    }

    func testClearRemovesEverything() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        try await cache.save(
            PulledDataset(
                workouts: [Fixtures.sampleWorkout()],
                exercises: [Fixtures.sampleExercise()],
                userParameters: [Fixtures.sampleUserParameter()]
            )
        )

        try await cache.clear()

        let workouts = try await cache.loadWorkouts(status: nil, since: nil)
        let exercises = try await cache.loadExercises()
        let params = try await cache.loadUserParametersLatest()
        XCTAssertTrue(workouts.isEmpty)
        XCTAssertTrue(exercises.isEmpty)
        XCTAssertTrue(params.isEmpty)
    }
}
