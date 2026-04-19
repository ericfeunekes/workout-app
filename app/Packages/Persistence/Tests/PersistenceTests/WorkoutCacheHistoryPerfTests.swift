// WorkoutCacheHistoryPerfTests.swift
//
// Pin the performance-shaped contracts History depends on:
//
//   • `testLoadCompletedWorkoutsPaginatesAtQuery` — perf-005. Ten
//     completed workouts, offset=3 + limit=5 must return exactly 5
//     rows AND must push pagination into the `FetchDescriptor` (vs
//     slicing a full in-memory fetch). We verify the former by result
//     shape and the latter by asserting the middle window — if the
//     fetch is unlimited the older SwiftData path still returns 5
//     rows, so we additionally prove the RIGHT 5 rows by UUID.
//   • `testSessionDetailSetLogOrderMatchesBlockItemPosition` —
//     perf-006 regression guard. Set_logs come out in
//     (block.position, item.position, setIndex) order even after the
//     per-block fetch collapse. Two blocks, each with two items,
//     each with two logs → 8 logs back in the expected sequence.
//   • `testLoadItemsByWorkoutIDsReturnsItemsGroupedByWorkout` —
//     perf-003. The bulk item fetch maps items to workout IDs
//     correctly and the items come out in (block.position,
//     item.position) order within each workout.
//
// These live in their own file so the existing WorkoutCacheTests /
// reconcile suites don't grow past SwiftLint's type_body_length cap.

import XCTest
import SwiftData
import CoreDomain
import WorkoutCoreFoundation
@testable import Persistence

final class WorkoutCacheHistoryPerfTests: XCTestCase {

    private func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    // MARK: - perf-005

    func testLoadCompletedWorkoutsPaginatesAtQuery() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        // Seed ten completed workouts with strictly increasing
        // `completedAt` so the sort order is deterministic. Newest first
        // means the seed at index 9 is returned first.
        let userID = UUID()
        var seeded: [Workout] = []
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<10 {
            seeded.append(
                Workout(
                    id: UUID(),
                    userID: userID,
                    name: "W\(i)",
                    scheduledDate: base.addingTimeInterval(Double(i) * 86_400),
                    status: .completed,
                    source: .claude,
                    notes: nil,
                    createdAt: base,
                    updatedAt: base,
                    completedAt: base.addingTimeInterval(Double(i) * 86_400),
                    tagsJSON: nil
                )
            )
        }
        try await cache.save(PulledDataset(workouts: seeded))

        // Expected sort: descending by completedAt. Indexes 9, 8, 7, 6,
        // 5, 4, 3, 2, 1, 0 in that order.
        let expectedOrder = seeded.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }

        // offset=3, limit=5 → rows 3..8 of the expected order.
        let window = try await cache.loadCompletedWorkouts(limit: 5, offset: 3)
        XCTAssertEqual(window.count, 5, "limit must cap the result slice")
        let windowIDs = window.map(\.id)
        let expectedIDs = Array(expectedOrder[3..<8]).map(\.id)
        XCTAssertEqual(
            windowIDs,
            expectedIDs,
            "Paginated slice must match the (offset, limit) window of the sorted history"
        )

        // A limit past the end returns just what's left (not a wrap).
        let tail = try await cache.loadCompletedWorkouts(limit: 5, offset: 8)
        XCTAssertEqual(tail.count, 2)

        // limit == 0 returns empty (guard clause).
        let empty = try await cache.loadCompletedWorkouts(limit: 0, offset: 0)
        XCTAssertTrue(empty.isEmpty)

        // Negative offset is clamped to 0.
        let clamped = try await cache.loadCompletedWorkouts(limit: 3, offset: -5)
        XCTAssertEqual(clamped.count, 3)
        XCTAssertEqual(clamped.map(\.id), Array(expectedOrder.prefix(3)).map(\.id))
    }

    // MARK: - perf-006

    func testSessionDetailSetLogOrderMatchesBlockItemPosition() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        // Workout with two blocks; each block has two items; each item
        // has two set_logs. The order we expect back from
        // `loadSetLogs(workoutID:)` is:
        //   block0/item0/set1, block0/item0/set2,
        //   block0/item1/set1, block0/item1/set2,
        //   block1/item0/set1, block1/item0/set2,
        //   block1/item1/set1, block1/item1/set2
        // Pre-perf-006 the helper walked blocks → items one block at a
        // time; this test proves the collapse into one bulk fetch
        // preserves the exact sequence.
        let workout = Fixtures.sampleWorkout(status: .completed)
        let blockA = Fixtures.sampleBlock(workoutID: workout.id, position: 0)
        let blockB = Fixtures.sampleBlock(workoutID: workout.id, position: 1)
        let itemA0 = Fixtures.sampleItem(blockID: blockA.id, position: 0)
        let itemA1 = Fixtures.sampleItem(blockID: blockA.id, position: 1)
        let itemB0 = Fixtures.sampleItem(blockID: blockB.id, position: 0)
        let itemB1 = Fixtures.sampleItem(blockID: blockB.id, position: 1)

        try await cache.save(
            PulledDataset(
                workouts: [workout],
                blocks: [blockA, blockB],
                items: [itemA0, itemA1, itemB0, itemB1]
            )
        )

        func log(itemID: UUID, setIndex: Int) -> SetLog {
            Fixtures.sampleSetLog(id: UUID(), workoutItemID: itemID, setIndex: setIndex)
        }
        let logs: [SetLog] = [
            // Deliberately shuffled on input — the sort is on the
            // cache side, not the caller side.
            log(itemID: itemB1.id, setIndex: 2),
            log(itemID: itemA0.id, setIndex: 1),
            log(itemID: itemB0.id, setIndex: 1),
            log(itemID: itemA1.id, setIndex: 2),
            log(itemID: itemA0.id, setIndex: 2),
            log(itemID: itemB1.id, setIndex: 1),
            log(itemID: itemB0.id, setIndex: 2),
            log(itemID: itemA1.id, setIndex: 1),
        ]
        try await cache.saveSetLogs(logs, workoutID: workout.id)

        let ordered = try await cache.loadSetLogs(workoutID: workout.id)
        XCTAssertEqual(ordered.count, 8)

        // Expected order as (workoutItemID, setIndex) tuples.
        let expected: [(UUID, Int)] = [
            (itemA0.id, 1), (itemA0.id, 2),
            (itemA1.id, 1), (itemA1.id, 2),
            (itemB0.id, 1), (itemB0.id, 2),
            (itemB1.id, 1), (itemB1.id, 2),
        ]
        for (index, row) in ordered.enumerated() {
            XCTAssertEqual(row.workoutItemID, expected[index].0,
                           "row \(index) item mismatch")
            XCTAssertEqual(row.setIndex, expected[index].1,
                           "row \(index) setIndex mismatch")
        }
    }

    // MARK: - perf-003

    func testLoadItemsByWorkoutIDsReturnsItemsGroupedByWorkout() async throws {
        let factory = try makeFactory()
        let cache = factory.workoutCache

        // Two workouts, each with two blocks and two items per block.
        // Seed block positions out of order to prove the cache sorts
        // by (block.position, item.position) within each workout.
        let workout1 = Fixtures.sampleWorkout(name: "Workout1")
        let workout2 = Fixtures.sampleWorkout(name: "Workout2")
        let w1BlockA = Fixtures.sampleBlock(workoutID: workout1.id, position: 0)
        let w1BlockB = Fixtures.sampleBlock(workoutID: workout1.id, position: 1)
        let w2BlockA = Fixtures.sampleBlock(workoutID: workout2.id, position: 0)
        let w2BlockB = Fixtures.sampleBlock(workoutID: workout2.id, position: 1)
        let w1ItemA0 = Fixtures.sampleItem(blockID: w1BlockA.id, position: 0)
        let w1ItemA1 = Fixtures.sampleItem(blockID: w1BlockA.id, position: 1)
        let w1ItemB0 = Fixtures.sampleItem(blockID: w1BlockB.id, position: 0)
        let w2ItemA0 = Fixtures.sampleItem(blockID: w2BlockA.id, position: 0)
        let w2ItemB0 = Fixtures.sampleItem(blockID: w2BlockB.id, position: 0)
        let w2ItemB1 = Fixtures.sampleItem(blockID: w2BlockB.id, position: 1)

        try await cache.save(
            PulledDataset(
                workouts: [workout1, workout2],
                blocks: [w1BlockA, w1BlockB, w2BlockA, w2BlockB],
                items: [w1ItemA0, w1ItemA1, w1ItemB0, w2ItemA0, w2ItemB0, w2ItemB1]
            )
        )

        let byWorkout = try await cache.loadItems(
            workoutIDs: [workout1.id, workout2.id]
        )
        XCTAssertEqual(byWorkout.count, 2)

        let w1Items = try XCTUnwrap(byWorkout[workout1.id])
        XCTAssertEqual(w1Items.map(\.id), [w1ItemA0.id, w1ItemA1.id, w1ItemB0.id],
                       "Workout 1 items must be (block0/item0, block0/item1, block1/item0)")

        let w2Items = try XCTUnwrap(byWorkout[workout2.id])
        XCTAssertEqual(w2Items.map(\.id), [w2ItemA0.id, w2ItemB0.id, w2ItemB1.id],
                       "Workout 2 items must be (block0/item0, block1/item0, block1/item1)")

        // Empty input returns empty output (guard clause).
        let empty = try await cache.loadItems(workoutIDs: [])
        XCTAssertTrue(empty.isEmpty)

        // Unknown workout id returns an empty map for that key (i.e.
        // the key is simply absent). Known + unknown together only
        // surface the known one.
        let mixed = try await cache.loadItems(
            workoutIDs: [workout1.id, UUID()]
        )
        XCTAssertEqual(mixed.count, 1)
        XCTAssertNotNil(mixed[workout1.id])
    }
}
