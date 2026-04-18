// PushQueueStoreTests.swift
//
// Covers the `PushQueueStore` contract against the SwiftData-backed impl:
// enqueue → peek → remove, update semantics, isEmpty, idempotent enqueue,
// payload round-trip for both `setLogs` and `statusUpdate`.

import XCTest
import CoreDomain
import Sync
@testable import Persistence

final class PushQueueStoreTests: XCTestCase {

    private func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    func testEnqueuePeekRemove() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let log = Fixtures.sampleSetLog()
        let item = PushItem(
            id: UUID(),
            payload: .setLogs([log]),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            attempts: 0
        )
        try await store.enqueue(item)

        let isEmptyBefore = try await store.isEmpty()
        XCTAssertFalse(isEmptyBefore)

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 1)
        XCTAssertEqual(peeked[0].id, item.id)

        if case .setLogs(let logs) = peeked[0].payload {
            XCTAssertEqual(logs.count, 1)
            XCTAssertEqual(logs[0], log)
        } else {
            XCTFail("expected setLogs payload")
        }

        try await store.remove(ids: [item.id])
        let isEmptyAfter = try await store.isEmpty()
        XCTAssertTrue(isEmptyAfter)
    }

    func testPeekIsFIFOByEnqueuedAt() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let a = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 1)]),
            enqueuedAt: Date(timeIntervalSince1970: 2_000),
            attempts: 0
        )
        let b = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 2)]),
            enqueuedAt: Date(timeIntervalSince1970: 1_000),
            attempts: 0
        )
        try await store.enqueue(a)
        try await store.enqueue(b)

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 2)
        XCTAssertEqual(peeked[0].id, b.id, "older enqueuedAt comes first")
        XCTAssertEqual(peeked[1].id, a.id)
    }

    func testEnqueueSameIDReplaces() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let id = UUID()
        let first = PushItem(
            id: id,
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 1)]),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            attempts: 0
        )
        let second = PushItem(
            id: id,
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 9)]),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_500),
            attempts: 3
        )
        try await store.enqueue(first)
        try await store.enqueue(second)

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 1)
        XCTAssertEqual(peeked[0].attempts, 3)
        if case .setLogs(let logs) = peeked[0].payload {
            XCTAssertEqual(logs[0].setIndex, 9)
        } else {
            XCTFail("expected setLogs payload")
        }
    }

    func testUpdateBumpsAttempts() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let item = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog()]),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            attempts: 0
        )
        try await store.enqueue(item)
        try await store.update(item.incrementingAttempts())

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 1)
        XCTAssertEqual(peeked[0].attempts, 1)
    }

    func testUpdateUnknownIDIsNoOp() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let ghost = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog()]),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            attempts: 5
        )
        // Must not throw.
        try await store.update(ghost)
        let empty = try await store.isEmpty()
        XCTAssertTrue(empty)
    }

    func testStatusUpdatePayloadRoundTrip() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let workoutID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let item = PushItem(
            id: UUID(),
            payload: .statusUpdate(workoutID: workoutID, status: .completed, completedAt: completedAt),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            attempts: 0
        )
        try await store.enqueue(item)

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 1)
        if case .statusUpdate(let wid, let status, let ca) = peeked[0].payload {
            XCTAssertEqual(wid, workoutID)
            XCTAssertEqual(status, .completed)
            XCTAssertEqual(ca, completedAt)
        } else {
            XCTFail("expected statusUpdate payload")
        }
    }
}
