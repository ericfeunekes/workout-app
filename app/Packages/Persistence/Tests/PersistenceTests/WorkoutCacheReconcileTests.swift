// WorkoutCacheReconcileTests.swift
//
// `save(_:)` reconciles the workout subtree (blocks → items →
// alternatives) against the incoming payload. Orphaned children are
// deleted so a Claude-side edit that removes an item or alternative
// doesn't leave stale rows in the local cache. SetLogs survive the
// reconcile because they're client-owned and indexed by UUID rather
// than by SwiftData relationship (the actor detaches the relationship
// before cascade-deleting the parent item — see
// `WorkoutCache+Reconcile.swift`).
//
// Scope: these tests pin the contract "pull replaces, doesn't accumulate"
// without overlapping the upsert / rollback tests in `WorkoutCacheTests`.
// Split across two test classes so each class stays under SwiftLint's
// `type_body_length` cap.

import XCTest
import SwiftData
import CoreDomain
import WorkoutCoreFoundation
@testable import Persistence

/// Shared factory helper — reused by the split test classes below.
enum ReconcileTestSupport {
    static func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }
}

final class WorkoutCacheReconcileDeletionTests: XCTestCase {

    func testReconcileDeletesOrphanedItems() async throws {
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache

        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let keepItemID = UUID()
        let keepItemID2 = UUID()
        let dropItemID = UUID()
        let item1 = Fixtures.sampleItem(id: keepItemID, blockID: block.id, position: 0)
        let item2 = Fixtures.sampleItem(id: keepItemID2, blockID: block.id, position: 1)
        let item3 = Fixtures.sampleItem(id: dropItemID, blockID: block.id, position: 2)

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [item1, item2, item3])
        )
        let before = try await cache.loadItems(blockID: block.id)
        XCTAssertEqual(before.count, 3)

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block], items: [item1, item2])
        )

        let after = try await cache.loadItems(blockID: block.id)
        XCTAssertEqual(after.count, 2)
        let remainingIDs = Set(after.map(\.id))
        XCTAssertTrue(remainingIDs.contains(keepItemID))
        XCTAssertTrue(remainingIDs.contains(keepItemID2))
        XCTAssertFalse(
            remainingIDs.contains(dropItemID),
            "Item removed from the re-pulled workout must be reconciled away"
        )
    }

    func testReconcileDeletesOrphanedAlternatives() async throws {
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache

        let workout = Fixtures.sampleWorkout()
        let block = Fixtures.sampleBlock(workoutID: workout.id)
        let item = Fixtures.sampleItem(blockID: block.id)
        let keepAltID = UUID()
        let dropAltID = UUID()
        let alt1 = Fixtures.sampleAlternative(id: keepAltID, workoutItemID: item.id)
        let alt2 = Fixtures.sampleAlternative(id: dropAltID, workoutItemID: item.id)

        try await cache.save(
            PulledDataset(
                workouts: [workout],
                blocks: [block],
                items: [item],
                alternatives: [alt1, alt2]
            )
        )
        let sanityAlts = try await cache.loadAlternatives(workoutItemID: item.id)
        XCTAssertEqual(sanityAlts.count, 2)

        try await cache.save(
            PulledDataset(
                workouts: [workout],
                blocks: [block],
                items: [item],
                alternatives: [alt1]
            )
        )

        let after = try await cache.loadAlternatives(workoutItemID: item.id)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].id, keepAltID)
        XCTAssertFalse(
            after.contains { $0.id == dropAltID },
            "Alternative removed from re-pulled workout must be reconciled away"
        )
    }

    func testReconcileDeletesOrphanedBlocks() async throws {
        let factory = try ReconcileTestSupport.makeFactory()
        let cache = factory.workoutCache

        let workout = Fixtures.sampleWorkout()
        let keepBlockID = UUID()
        let dropBlockID = UUID()
        let block1 = Fixtures.sampleBlock(id: keepBlockID, workoutID: workout.id, position: 0)
        let block2 = Fixtures.sampleBlock(id: dropBlockID, workoutID: workout.id, position: 1)
        let item1 = Fixtures.sampleItem(blockID: block1.id)
        let item2 = Fixtures.sampleItem(blockID: block2.id)

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block1, block2], items: [item1, item2])
        )
        let sanityBlocks = try await cache.loadBlocks(workoutID: workout.id)
        XCTAssertEqual(sanityBlocks.count, 2)

        try await cache.save(
            PulledDataset(workouts: [workout], blocks: [block1], items: [item1])
        )

        let remainingBlocks = try await cache.loadBlocks(workoutID: workout.id)
        XCTAssertEqual(remainingBlocks.count, 1)
        XCTAssertEqual(remainingBlocks[0].id, keepBlockID)
        let dropBlockItems = try await cache.loadItems(blockID: dropBlockID)
        XCTAssertTrue(
            dropBlockItems.isEmpty,
            "Items under a reconciled-away block must cascade-delete"
        )
    }
}

// Preservation-side reconcile tests (set-log survival, cross-workout
// isolation) live in `WorkoutCacheReconcilePreservationTests.swift`.
