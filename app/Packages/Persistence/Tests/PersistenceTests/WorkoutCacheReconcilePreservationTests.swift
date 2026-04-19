// WorkoutCacheReconcilePreservationTests.swift
//
// Pinned invariants on the preservation side of the reconcile contract:
//
//   • `testReconciledSetLogsReachableViaLoadSetLogsByWorkoutID` —
//     when reconcile removes a WorkoutItem that already has logged
//     sets, the set_logs survive AND stay reachable through the
//     public `loadSetLogs(workoutID:)` API. R1.3 shipped the on-disk
//     survival; R1.4 (this fix-it) closes the leak where the rows
//     were invisible to the public query path because the block →
//     item walk lost them. The test fails pre-R1.4 and passes after.
//   • `testReconciledSetLogsReachableViaLoadSetLogsByExerciseID` —
//     same preservation invariant, via the by-exercise query (the
//     History trend view).
//   • `testReconcileLeavesOtherWorkoutsAlone` — reconcile scope is per-
//     incoming-workout; a pull that only mentions workout A must not
//     touch workout B's subtree.
//   • `testLoadOrphanedSetLogsReturnsTrulyOrphanedRows` — the recovery
//     surface for pre-V3 orphans whose parent item was reconciled
//     away before the R1.4 backfill could map them to a workoutID.
//   • `testLoadSetLogsByWorkoutIDReturnsBackfilledRowsAfterReconcile` —
//     the post-R1.4 happy path: even when an item is reconciled away
//     after the log was written, the denormalized `workoutID` column
//     keeps the row reachable via the normal history query.
//
// Deletion-side reconcile tests live in `WorkoutCacheReconcileTests.swift`.
// Split across two files to stay under SwiftLint's `single_test_class`
// and `type_body_length` caps.

import XCTest
import SwiftData
import CoreDomain
import WorkoutCoreFoundation
@testable import Persistence

final class WorkoutCacheReconcilePreservationTests: XCTestCase {

    func testReconciledSetLogsReachableViaLoadSetLogsByWorkoutID() async throws {
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache
        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let dropItem = Fixtures.sampleItem(blockID: block.id, position: 0)
        let keepItem = Fixtures.sampleItem(blockID: block.id, position: 1)

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [dropItem, keepItem])
        )
        let setLog = Fixtures.sampleSetLog(workoutItemID: dropItem.id, setIndex: 1)
        try await cache.saveSetLogs([setLog], workoutID: workout.id)

        // Re-pull the workout with dropItem gone. The item is cascade-
        // deleted; the set_log must NOT go with it (see
        // `detachSetLogs(fromItem:)` in WorkoutCache+Reconcile.swift).
        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [keepItem])
        )

        // R1.4 fix: the set_log must be reachable via the public
        // history API even after its parent item is gone. Pre-R1.4
        // the query walked blocks → items → logs and silently
        // dropped reconciled orphans; the fix denormalizes
        // `workoutID` onto SetLogModel so the query resolves
        // directly off the set_log row.
        let byWorkout = try await cache.loadSetLogs(workoutID: workout.id)
        XCTAssertEqual(
            byWorkout.count,
            1,
            "Reconciled-away SetLogs must remain reachable via loadSetLogs(workoutID:)."
        )
        XCTAssertEqual(byWorkout.first?.id, setLog.id)
        XCTAssertEqual(byWorkout.first?.workoutItemID, dropItem.id)
    }

    func testReconciledSetLogsReachableViaLoadSetLogsByExerciseID() async throws {
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache
        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let droppedExerciseID = UUID()
        let dropItem = Fixtures.sampleItem(
            blockID: block.id,
            exerciseID: droppedExerciseID,
            position: 0
        )

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [dropItem])
        )
        let setLog = Fixtures.sampleSetLog(workoutItemID: dropItem.id, setIndex: 1)
        try await cache.saveSetLogs([setLog], workoutID: workout.id)

        // Reconcile removes the item (no items in the incoming pull).
        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [])
        )

        // The set_log's `plannedExerciseID` was stamped at insert
        // time from the parent item's `exerciseID`, so the by-
        // exercise query still surfaces it even though the item
        // row is gone.
        let byExercise = try await cache.loadSetLogs(exerciseID: droppedExerciseID, limit: 10)
        XCTAssertEqual(
            byExercise.count,
            1,
            "Reconciled-away SetLogs must remain reachable via loadSetLogs(exerciseID:)."
        )
        XCTAssertEqual(byExercise.first?.id, setLog.id)
    }

    func testLoadOrphanedSetLogsReturnsTrulyOrphanedRows() async throws {
        // Model the pre-V3 orphan: a SetLog whose `workoutItemID` points
        // at a row that doesn't exist AND cannot be resolved via any
        // surviving workout. We insert directly through the container's
        // context because the public API (`saveSetLogs(_:workoutID:)`)
        // always stamps `workoutID` at insert time — the orphan state
        // is only produced by the V2→V3 backfill failing to find a
        // surviving parent item.
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache

        // Seed a surviving (non-orphan) log so we can verify the query
        // filters correctly, not just "returns everything".
        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let item = Fixtures.sampleItem(blockID: block.id)
        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [item])
        )
        let keepLog = Fixtures.sampleSetLog(workoutItemID: item.id, setIndex: 1)
        try await cache.saveSetLogs([keepLog], workoutID: workout.id)

        // Build a SetLogModel directly with `workoutID == nil` to
        // simulate the post-upgrade orphan state. Use a fresh
        // MainActor-bound context against the shared container.
        let orphanID = UUID()
        let missingItemID = UUID()
        try await MainActor.run {
            let context = ModelContext(factory.container)
            let orphan = SetLogModel(
                id: orphanID,
                workoutItemID: missingItemID,
                workoutID: nil,
                plannedExerciseID: nil,
                performedExerciseID: nil,
                setIndex: 1,
                reps: 5,
                weight: 70.0,
                weightUnitRaw: "kg",
                durationSec: nil,
                distanceM: nil,
                rir: 2,
                isWarmup: false,
                startedAt: Fixtures.baseDate,
                completedAt: Fixtures.baseDate.addingTimeInterval(45),
                hrAvgBpm: nil,
                hrMaxBpm: nil,
                cadenceAvgSpm: nil,
                motionSamplesRef: nil,
                notes: "pre-upgrade orphan"
            )
            context.insert(orphan)
            try context.save()
        }

        let orphans = try await cache.loadOrphanedSetLogs()
        XCTAssertEqual(
            orphans.count,
            1,
            "loadOrphanedSetLogs must return exactly the nil-workoutID rows"
        )
        XCTAssertEqual(orphans.first?.id, orphanID)
        XCTAssertEqual(orphans.first?.workoutItemID, missingItemID)

        // The non-orphan log stays out of the orphan bucket.
        let byWorkout = try await cache.loadSetLogs(workoutID: workout.id)
        XCTAssertEqual(byWorkout.count, 1)
        XCTAssertEqual(byWorkout.first?.id, keepLog.id)
    }

    func testLoadSetLogsByWorkoutIDReturnsBackfilledRowsAfterReconcile() async throws {
        // Post-R1.3 reconcile flow: delete the parent item, then query
        // by workoutID. The denormalized column (stamped at insert)
        // keeps the row reachable even though the block→item walk can't
        // find it. This pins that the fix-it's simpler approach — rely
        // on the denormalized column, don't filter on `workoutID != nil`
        // — actually works for the reconcile-after-R1.3 case.
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache

        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let dropItem = Fixtures.sampleItem(blockID: block.id, position: 0)
        let keepItem = Fixtures.sampleItem(blockID: block.id, position: 1)

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [dropItem, keepItem])
        )
        let logOnDrop = Fixtures.sampleSetLog(workoutItemID: dropItem.id, setIndex: 1)
        let logOnKeep = Fixtures.sampleSetLog(workoutItemID: keepItem.id, setIndex: 1)
        try await cache.saveSetLogs([logOnDrop, logOnKeep], workoutID: workout.id)

        // Reconcile dropItem away. Its SetLog survives (detach path) and
        // retains the denormalized workoutID set at insert time.
        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [keepItem])
        )

        let byWorkout = try await cache.loadSetLogs(workoutID: workout.id)
        XCTAssertEqual(
            byWorkout.count,
            2,
            "Both SetLogs (dropped-parent + surviving-parent) must return via workoutID predicate"
        )
        XCTAssertTrue(byWorkout.contains(where: { $0.id == logOnDrop.id }))
        XCTAssertTrue(byWorkout.contains(where: { $0.id == logOnKeep.id }))

        // Neither row should show up as orphaned — the denormalized
        // column kept them linked to their workout even though the
        // item cascade removed the parent row.
        let orphans = try await cache.loadOrphanedSetLogs()
        XCTAssertTrue(
            orphans.isEmpty,
            "Post-R1.3 reconciled logs keep workoutID stamped — not orphans"
        )
    }

    func testReconcileLeavesOtherWorkoutsAlone() async throws {
        // Reconcile scope is per-incoming-workout. Pulling workout A must
        // not touch workout B's subtree even if B is fully present in the
        // cache and absent from the pull.
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache

        let workoutA = Fixtures.sampleWorkout(name: "A")
        let blockA = Fixtures.sampleBlock(workoutID: workoutA.id)
        let itemA = Fixtures.sampleItem(blockID: blockA.id)
        let workoutB = Fixtures.sampleWorkout(name: "B")
        let blockB = Fixtures.sampleBlock(workoutID: workoutB.id)
        let itemB = Fixtures.sampleItem(blockID: blockB.id)

        try await cache.save(
            PulledDataset(
                workouts: [workoutA, workoutB],
                blocks: [blockA, blockB],
                items: [itemA, itemB]
            )
        )
        try await cache.save(
            PulledDataset(workouts: [workoutA], blocks: [blockA], items: [itemA])
        )

        let bBlocks = try await cache.loadBlocks(workoutID: workoutB.id)
        XCTAssertEqual(
            bBlocks.count,
            1,
            "Workout B's blocks must survive a pull that didn't mention B"
        )
        let bItems = try await cache.loadItems(blockID: blockB.id)
        XCTAssertEqual(
            bItems.count,
            1,
            "Workout B's items must survive a pull that didn't mention B"
        )
    }
}
