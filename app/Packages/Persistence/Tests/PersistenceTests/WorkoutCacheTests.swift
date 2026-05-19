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

    func testPrimitiveWorkoutRoundTripsThroughCache() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000031")!
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive AMRAP",
            blocks: [
                PrimitiveBlock(
                    id: UUID(uuidString: "20000000-0000-4000-8000-000000000031")!,
                    sets: [
                        PrimitiveSet(
                            id: UUID(uuidString: "30000000-0000-4000-8000-000000000031")!,
                            timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                            traversal: .amrap,
                            workTargets: [
                                PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                            ],
                            slots: [
                                PrimitiveSlot(
                                    id: UUID(uuidString: "40000000-0000-4000-8000-000000000031")!,
                                    exerciseID: UUID(uuidString: "50000000-0000-4000-8000-000000000031")!,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .reps,
                                            valueForm: .single,
                                            value: 10,
                                            role: .completion
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )

        try await cache.save(PulledDataset(primitiveWorkouts: [primitive]))

        let loaded = try await cache.loadPrimitiveWorkouts()
        XCTAssertEqual(loaded, [primitive])
    }

    func testPrimitiveWorkoutActivityIntentSurvivesOnDiskReopen() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("primitive-activity-intent-\(UUID().uuidString).store")
        let tokenService = "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000231")!
        let oldPayload = PrimitiveWorkout(
            id: workoutID,
            name: "Old payload",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000231")!, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "30000000-0000-4000-8000-000000000231")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        slots: []
                    ),
                ]),
            ]
        )
        var newPayload = oldPayload
        newPayload.name = "New payload"
        newPayload.activityIntent = ActivityIntent(
            activityDomain: .mixedModal,
            preservationPolicy: .preserveStructure
        )

        do {
            let factory = try PersistenceFactory.makeOnDisk(
                storeURL: storeURL,
                tokenServiceName: tokenService
            )
            try await factory.workoutCache.save(PulledDataset(primitiveWorkouts: [oldPayload]))
        }
        do {
            let reopened = try PersistenceFactory.makeOnDisk(
                storeURL: storeURL,
                tokenServiceName: tokenService
            )
            let loaded = try await reopened.workoutCache.loadPrimitiveWorkouts()
            XCTAssertEqual(loaded, [oldPayload])
            XCTAssertNil(loaded[0].activityIntent)
            try await reopened.workoutCache.save(PulledDataset(primitiveWorkouts: [newPayload]))
        }
        do {
            let reopened = try PersistenceFactory.makeOnDisk(
                storeURL: storeURL,
                tokenServiceName: tokenService
            )
            let loaded = try await reopened.workoutCache.loadPrimitiveWorkouts()
            XCTAssertEqual(loaded, [newPayload])
            XCTAssertEqual(loaded[0].activityIntent?.activityDomain, .mixedModal)
            XCTAssertEqual(loaded[0].activityIntent?.environment, .unspecified)
            XCTAssertEqual(loaded[0].activityIntent?.preservationPolicy, .preserveStructure)
        }
    }

    func testPrimitiveWorkoutUpsertReplacesPayload() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000032")!
        let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000032")!
        let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000032")!
        let first = PrimitiveWorkout(
            id: workoutID,
            name: "Before",
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(id: setID, timing: PrimitiveTiming(mode: .setBounded), slots: []),
                ]),
            ]
        )
        var updated = first
        updated.name = "After"
        updated.blocks[0].sets[0].repeatCount = 3

        try await cache.save(PulledDataset(primitiveWorkouts: [first]))
        try await cache.save(PulledDataset(primitiveWorkouts: [updated]))

        let loaded = try await cache.loadPrimitiveWorkouts()
        XCTAssertEqual(loaded, [updated])
    }

    func testPrimitiveWorkoutTombstoneDeletesCachedPayload() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000034")!
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: "Before",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000034")!, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "30000000-0000-4000-8000-000000000034")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        slots: []
                    ),
                ]),
            ]
        )

        try await cache.save(PulledDataset(primitiveWorkouts: [primitive]))
        try await cache.savePrimitiveSetLogs([
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000034")!,
                role: .blockResult,
                blockID: UUID(uuidString: "20000000-0000-4000-8000-000000000034")!,
                workoutID: workoutID,
                setIndex: 0,
                completedAt: Fixtures.baseDate
            ),
        ], workoutID: workoutID)
        try await cache.save(PulledDataset(primitiveWorkoutIDsToDelete: [workoutID]))

        let loaded = try await cache.loadPrimitiveWorkouts()
        XCTAssertTrue(loaded.isEmpty)
        let logs = try await cache.loadPrimitiveSetLogs(workoutID: workoutID)
        XCTAssertTrue(logs.isEmpty)
    }

    func testPrimitiveSetLogsRoundTripThroughCache() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000033")!
        let completedAt = Fixtures.baseDate.addingTimeInterval(900)
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive Logged",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000034")!, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "30000000-0000-4000-8000-000000000034")!,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        slots: []
                    ),
                ]),
            ]
        )
        let log = PrimitiveSetLog(
            id: UUID(uuidString: "60000000-0000-4000-8000-000000000033")!,
            role: .setResult,
            setID: UUID(uuidString: "30000000-0000-4000-8000-000000000033")!,
            blockID: UUID(uuidString: "20000000-0000-4000-8000-000000000033")!,
            workoutID: nil,
            setIndex: 0,
            reps: 4,
            durationSec: 300,
            rounds: 7,
            skipped: true,
            side: .left,
            notes: "scaled after warmup",
            completedAt: completedAt
        )

        try await cache.save(PulledDataset(primitiveWorkouts: [primitive]))
        try await cache.savePrimitiveSetLogs([log], workoutID: workoutID)

        let loaded = try await cache.loadPrimitiveSetLogs(workoutID: workoutID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].workoutID, workoutID)
        XCTAssertEqual(loaded[0].role, .setResult)
        XCTAssertEqual(loaded[0].setIndex, 0)
        XCTAssertEqual(loaded[0].reps, 4)
        XCTAssertEqual(loaded[0].rounds, 7)
        XCTAssertEqual(loaded[0].durationSec, 300)
        XCTAssertTrue(loaded[0].skipped)
        XCTAssertEqual(loaded[0].side, .left)
        XCTAssertEqual(loaded[0].notes, "scaled after warmup")
    }

    func testPrimitiveSetLogsRoundTripSlotSetAndBlockResultFields() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000133")!
        let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000133")!
        let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000133")!
        let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000133")!
        let plannedExerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000133")!
        let performedExerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000134")!
        let completedAt = Fixtures.baseDate.addingTimeInterval(1_200)
        let logs = [
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000133")!,
                role: .slot,
                slotID: slotID,
                setID: setID,
                blockID: blockID,
                workoutID: nil,
                plannedExerciseID: plannedExerciseID,
                performedExerciseID: performedExerciseID,
                setIndex: 0,
                setRepeatIndex: 1,
                blockRepeatIndex: 2,
                reps: 12,
                weight: 24,
                weightUnit: .kg,
                durationSec: 42,
                distanceM: 15,
                rir: 1,
                hrAvgBpm: 150,
                hrMaxBpm: 172,
                isWarmup: true,
                skipped: false,
                side: .right,
                notes: "changed side",
                completedAt: completedAt
            ),
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000134")!,
                role: .setResult,
                setID: setID,
                blockID: blockID,
                workoutID: workoutID,
                setIndex: 0,
                setRepeatIndex: 0,
                blockRepeatIndex: 0,
                reps: 7,
                durationSec: 300,
                distanceM: 1_000,
                rounds: 3,
                notes: "set score",
                completedAt: completedAt.addingTimeInterval(1)
            ),
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000135")!,
                role: .blockResult,
                blockID: blockID,
                workoutID: workoutID,
                setIndex: 0,
                durationSec: 900,
                notes: "block score",
                completedAt: completedAt.addingTimeInterval(2)
            ),
        ]

        try await cache.savePrimitiveSetLogs(logs, workoutID: workoutID)

        let loaded = try await cache.loadPrimitiveSetLogs(workoutID: workoutID)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(Set(loaded.map(\.role)), Set([.slot, .setResult, .blockResult]))
        XCTAssertTrue(loaded.allSatisfy { $0.workoutID == workoutID })

        let slot = try XCTUnwrap(loaded.first { $0.role == .slot })
        XCTAssertEqual(slot.slotID, slotID)
        XCTAssertEqual(slot.setID, setID)
        XCTAssertEqual(slot.blockID, blockID)
        XCTAssertEqual(slot.plannedExerciseID, plannedExerciseID)
        XCTAssertEqual(slot.performedExerciseID, performedExerciseID)
        XCTAssertEqual(slot.setRepeatIndex, 1)
        XCTAssertEqual(slot.blockRepeatIndex, 2)
        XCTAssertEqual(slot.reps, 12)
        XCTAssertEqual(slot.weight, 24)
        XCTAssertEqual(slot.weightUnit, .kg)
        XCTAssertEqual(slot.durationSec, 42)
        XCTAssertEqual(slot.distanceM, 15)
        XCTAssertEqual(slot.rir, 1)
        XCTAssertEqual(slot.hrAvgBpm, 150)
        XCTAssertEqual(slot.hrMaxBpm, 172)
        XCTAssertTrue(slot.isWarmup)
        XCTAssertFalse(slot.skipped)
        XCTAssertEqual(slot.side, .right)
        XCTAssertEqual(slot.notes, "changed side")

        let setResult = try XCTUnwrap(loaded.first { $0.role == .setResult })
        XCTAssertEqual(setResult.rounds, 3)
        XCTAssertEqual(setResult.distanceM, 1_000)
        XCTAssertEqual(setResult.notes, "set score")
        let blockResult = try XCTUnwrap(loaded.first { $0.role == .blockResult })
        XCTAssertEqual(blockResult.durationSec, 900)
        XCTAssertEqual(blockResult.notes, "block score")
    }

    func testPrimitiveSetLogsExerciseQueryReturnsRawRowsForConsumerSemantics() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000233")!
        let plannedExerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000233")!
        let performedExerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000234")!
        let completedAt = Fixtures.baseDate.addingTimeInterval(1_400)
        let logs = [
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000233")!,
                role: .slot,
                slotID: UUID(uuidString: "40000000-0000-4000-8000-000000000233")!,
                workoutID: workoutID,
                plannedExerciseID: plannedExerciseID,
                performedExerciseID: performedExerciseID,
                setIndex: 0,
                reps: 5,
                weight: 100,
                weightUnit: .kg,
                completedAt: completedAt
            ),
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000234")!,
                role: .slot,
                slotID: UUID(uuidString: "40000000-0000-4000-8000-000000000234")!,
                workoutID: workoutID,
                plannedExerciseID: plannedExerciseID,
                setIndex: 0,
                reps: 6,
                completedAt: completedAt.addingTimeInterval(-60)
            ),
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000235")!,
                role: .setResult,
                workoutID: workoutID,
                plannedExerciseID: performedExerciseID,
                setIndex: 0,
                rounds: 3,
                completedAt: completedAt.addingTimeInterval(60)
            ),
            PrimitiveSetLog(
                id: UUID(uuidString: "60000000-0000-4000-8000-000000000236")!,
                role: .slot,
                slotID: UUID(uuidString: "40000000-0000-4000-8000-000000000236")!,
                workoutID: workoutID,
                plannedExerciseID: performedExerciseID,
                setIndex: 0,
                skipped: true,
                completedAt: completedAt.addingTimeInterval(120)
            ),
        ]

        try await cache.savePrimitiveSetLogs(logs, workoutID: workoutID)

        let performedRows = try await cache.loadPrimitiveSetLogs(
            exerciseID: performedExerciseID,
            limit: 10
        )
        XCTAssertEqual(performedRows.map(\.id), [logs[3].id, logs[2].id, logs[0].id])
        XCTAssertEqual(performedRows.map(\.role), [.slot, .setResult, .slot])
        XCTAssertEqual(performedRows.map(\.skipped), [true, false, false])

        let plannedRows = try await cache.loadPrimitiveSetLogs(
            exerciseID: plannedExerciseID,
            limit: 10
        )
        XCTAssertEqual(plannedRows.map(\.id), [logs[1].id])
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

    func testResetWorkoutDeletesLogsAndReturnsWorkoutToPlanned() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        var workout = Fixtures.sampleWorkout(status: .completed)
        workout.completedAt = Fixtures.baseDate.addingTimeInterval(3_600)
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let item = Fixtures.sampleItem(blockID: block.id)
        let exercise = Fixtures.sampleExercise(id: item.exerciseID)
        let log = Fixtures.sampleSetLog(workoutItemID: item.id)

        try await cache.save(PulledDataset(
            workouts: [workout],
            blocks: [block],
            items: [item],
            exercises: [exercise]
        ))
        try await cache.saveSetLogs([log], workoutID: workout.id)

        let logsBeforeReset = try await cache.loadSetLogs(workoutID: workout.id)
        XCTAssertEqual(logsBeforeReset.count, 1)

        try await cache.resetWorkout(workoutID: workout.id)

        let logsAfterReset = try await cache.loadSetLogs(workoutID: workout.id)
        XCTAssertTrue(logsAfterReset.isEmpty)
        let completedAfterReset = try await cache.loadCompletedWorkouts(limit: 10, offset: 0)
        XCTAssertTrue(completedAfterReset.isEmpty)
        let planned = try await cache.loadWorkouts(status: .planned, since: nil)
        XCTAssertEqual(planned.map(\.id), [workout.id])
        XCTAssertNil(planned[0].completedAt)
    }

    func testLoadSetLogsUsesPerformedExerciseIdentityForSwaps() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        let plannedExerciseID = UUID()
        let performedExerciseID = UUID()
        var workout = Fixtures.sampleWorkout(status: .completed)
        workout.completedAt = Fixtures.baseDate.addingTimeInterval(3_600)
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let item = Fixtures.sampleItem(
            blockID: block.id,
            exerciseID: plannedExerciseID
        )
        let log = SetLog(
            id: UUID(),
            workoutItemID: item.id,
            performedExerciseID: performedExerciseID,
            setIndex: 1,
            reps: 10,
            weight: 70,
            weightUnit: .lb,
            rir: 2,
            isWarmup: false,
            skipped: false,
            startedAt: nil,
            completedAt: Fixtures.baseDate.addingTimeInterval(60),
            notes: nil
        )

        try await cache.save(PulledDataset(
            workouts: [workout],
            blocks: [block],
            items: [item],
            exercises: [
                Fixtures.sampleExercise(id: plannedExerciseID, name: "Bench Press"),
                Fixtures.sampleExercise(id: performedExerciseID, name: "DB Bench Press"),
            ]
        ))
        try await cache.saveSetLogs([log], workoutID: workout.id)

        let plannedRows = try await cache.loadSetLogs(exerciseID: plannedExerciseID, limit: 10)
        let performedRows = try await cache.loadSetLogs(exerciseID: performedExerciseID, limit: 10)

        XCTAssertTrue(
            plannedRows.isEmpty,
            "swapped-away planned exercise must not keep the performed row in by-exercise history"
        )
        XCTAssertEqual(performedRows.map(\.id), [log.id])
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

    // Reconcile tests (orphaned-child deletion, set-log preservation) live
    // in `WorkoutCacheReconcileTests.swift`.

    /// Perf regression guard for perf-004. The old `save(_:)` issued one
    /// `modelContext.fetch` per incoming row (and another per parent
    /// attachment), turning a 50-workout pull into thousands of SQL
    /// queries — the first-launch bootstrap hot path. The new shape
    /// batches one IN-predicate fetch per entity class, so the total
    /// number of fetches is bounded by entity count, not row count.
    ///
    /// Asserts the fetch count scales with O(entity classes), not
    /// O(rows). The exact upper bound matches the pull-path fetch
    /// sites in `WorkoutCache+Preload.swift` (six entity classes) plus
    /// any `detachSetLogs` fetches triggered by reconcile (none in
    /// this dataset — all items are kept). The bound is chosen to
    /// fail loudly if an upsert helper starts re-introducing a per-row
    /// fetch.
    func testSavePreloadsExistingRowsOnce() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        // Build a modest-but-not-trivial dataset: 10 workouts, each with
        // 2 blocks, 3 items per block, 1 alternative per item, plus a
        // catalog of 20 exercises and 5 user_parameters. This hits every
        // upsert helper multiple times, so a per-row fetch would be
        // obvious in the count.
        var workouts: [Workout] = []
        var blocks: [Block] = []
        var items: [WorkoutItem] = []
        var alts: [ExerciseAlternative] = []
        for _ in 0..<10 {
            let workout = Fixtures.sampleWorkout()
            workouts.append(workout)
            for blockIndex in 0..<2 {
                let block = Fixtures.sampleBlock(
                    workoutID: workout.id,
                    position: blockIndex
                )
                blocks.append(block)
                for itemIndex in 0..<3 {
                    let item = Fixtures.sampleItem(
                        blockID: block.id,
                        position: itemIndex
                    )
                    items.append(item)
                    alts.append(Fixtures.sampleAlternative(workoutItemID: item.id))
                }
            }
        }
        let exercises = (0..<20).map { _ in Fixtures.sampleExercise() }
        let params = (0..<5).map { _ in Fixtures.sampleUserParameter() }

        let dataset = PulledDataset(
            workouts: workouts,
            blocks: blocks,
            items: items,
            alternatives: alts,
            exercises: exercises,
            userParameters: params
        )

        guard let impl = cache as? WorkoutCacheImpl else {
            XCTFail("WorkoutCacheImpl expected from the factory")
            return
        }

        // First save: cold cache, no existing rows. One fetch per
        // entity class that has incoming data — six total.
        await impl.resetFetchCallCount()
        try await cache.save(dataset)
        let coldFetches = await impl.fetchCallCount
        XCTAssertLessThanOrEqual(
            coldFetches,
            6,
            """
            Cold-cache save should issue at most six fetches (one per
            entity class in PullPreload). Observed \(coldFetches) —
            this indicates an upsert / reconcile helper has re-introduced
            a per-row fetch.
            """
        )

        // Second save: every row is now in the store, so reconcile has
        // the full subtree to walk. The bound is still entity-class-
        // scoped, not row-scoped.
        await impl.resetFetchCallCount()
        try await cache.save(dataset)
        let warmFetches = await impl.fetchCallCount
        XCTAssertLessThanOrEqual(
            warmFetches,
            6,
            """
            Warm-cache save should still issue at most six fetches; \
            the preload covers both upsert matching and reconcile's \
            per-workout walk. Observed \(warmFetches).
            """
        )

        // Round-trip sanity so the perf bound isn't trivially met by
        // skipping work. Every row must still be on disk.
        let loadedWorkouts = try await cache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(loadedWorkouts.count, 10)
        let loadedExercises = try await cache.loadExercises()
        XCTAssertEqual(loadedExercises.count, 20)
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
