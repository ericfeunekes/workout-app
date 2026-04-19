// PushQueueStoreTests.swift
//
// Covers the `PushQueueStore` contract against the SwiftData-backed impl:
// enqueue → peek → remove, update semantics, isEmpty, idempotent enqueue,
// payload round-trip for both `setLogs` and `statusUpdate`.

import XCTest
import SwiftData
import CoreDomain
import CoreTelemetry
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

    /// Regression for the telemetry-isolation fix: `peek(max:)` must
    /// return `setLogs` / `statusUpdate` / `userParameter` BEFORE
    /// `events`, regardless of the chronological enqueue order. Without
    /// the priority weighting, a verbose-mode telemetry burst enqueued
    /// before a fresh set log would push the log behind the tail.
    func testPeekSortsByPriorityThenFIFO() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        // Two old telemetry events, then a fresh set log that was
        // enqueued chronologically *later*. If we sorted by enqueuedAt
        // only, the set log would land last. Priority weighting must
        // pull it to position zero.
        let oldTelemetry = PushItem(
            id: UUID(),
            payload: .events([CoreTelemetry.Event(
                sessionID: UUID(), kind: "state", name: "old.1"
            )]),
            enqueuedAt: Date(timeIntervalSince1970: 1_000),
            attempts: 0
        )
        let olderTelemetry = PushItem(
            id: UUID(),
            payload: .events([CoreTelemetry.Event(
                sessionID: UUID(), kind: "state", name: "old.2"
            )]),
            enqueuedAt: Date(timeIntervalSince1970: 1_500),
            attempts: 0
        )
        let freshSetLog = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog()]),
            enqueuedAt: Date(timeIntervalSince1970: 2_000),
            attempts: 0
        )
        try await store.enqueue(oldTelemetry)
        try await store.enqueue(olderTelemetry)
        try await store.enqueue(freshSetLog)

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 3)
        XCTAssertEqual(peeked[0].id, freshSetLog.id, "results drain first")
        // Within priority 1 the FIFO order must hold — older event first.
        XCTAssertEqual(peeked[1].id, oldTelemetry.id)
        XCTAssertEqual(peeked[2].id, olderTelemetry.id)
    }

    /// Regression for "no logical dedup; two pushes of the same set_log
    /// just queue up twice". `PushQueue.enqueueSetLogs` now drops any
    /// existing queued row carrying the same SetLog.id before inserting
    /// the fresh one — so an edit-before-flush collapses to one row with
    /// the latest payload, instead of a stale-then-fresh sequence that
    /// transiently overwrites the corrected server-side bytes.
    func testPushQueueReplaceInPlaceForSameSetLogId() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore
        let queue = PushQueue(
            store: store,
            transport: EmptyTransport()
        )

        // First push: 5 reps @ 100 kg.
        let setLogID = UUID()
        let first = CoreDomain.SetLog(
            id: setLogID,
            workoutItemID: UUID(),
            performedExerciseID: nil,
            setIndex: 3,
            reps: 5,
            weight: 100,
            weightUnit: .kg,
            rir: 2,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await queue.enqueueSetLogs([first])

        // User corrects — same id, bumped reps/load.
        let corrected = CoreDomain.SetLog(
            id: setLogID,  // SAME id
            workoutItemID: first.workoutItemID,
            performedExerciseID: nil,
            setIndex: 3,
            reps: 8,
            weight: 102.5,
            weightUnit: .kg,
            rir: 1,
            completedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
        try await queue.enqueueSetLogs([corrected])

        let all = try await store.peek(max: 10)
        XCTAssertEqual(all.count, 1, "dedup collapses to a single row")
        if case .setLogs(let logs) = all[0].payload {
            XCTAssertEqual(logs.count, 1)
            XCTAssertEqual(logs[0].id, setLogID)
            XCTAssertEqual(logs[0].reps, 8, "latest payload wins")
            XCTAssertEqual(logs[0].weight, 102.5)
            XCTAssertEqual(logs[0].rir, 1)
        } else {
            XCTFail("expected setLogs payload")
        }
    }

    /// Regression for "unknown envelope kind stalls the whole queue". A
    /// forward-versioned row (written by a newer build; downgrade left it
    /// behind) or a corrupted blob used to throw from `peek`, which
    /// bubbled out of `PushQueue.flush` and halted the drain. The peek is
    /// now tolerant — unknown envelopes are silently skipped and the
    /// valid rows ship unaffected.
    func testPushQueuePeekSkipsUnknownEnvelope() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        // Seed three rows: valid-before, UNKNOWN, valid-after. The store's
        // tolerant peek must return the two valid rows and drop the bad
        // middle one.
        let before = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 1)]),
            enqueuedAt: Date(timeIntervalSince1970: 1_000),
            attempts: 0
        )
        let after = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 2)]),
            enqueuedAt: Date(timeIntervalSince1970: 3_000),
            attempts: 0
        )
        try await store.enqueue(before)
        try await store.enqueue(after)

        // Forge the bad row straight into the container so the PushQueue
        // payload coding can't reject it on enqueue. Represents the
        // "forward-versioned row written by a newer build" class of drift.
        let badRow = PushItemModel(
            id: UUID(),
            enqueuedAt: Date(timeIntervalSince1970: 2_000),
            attempts: 0,
            payloadJSON: Data(#"{"kind":"futureCaseWeDoNotKnow","extra":42}"#.utf8)
        )
        let bootstrapContext = ModelContext(factory.container)
        bootstrapContext.insert(badRow)
        try bootstrapContext.save()

        // Peek must return only the two decodable rows — the bad row is
        // silently skipped, not thrown.
        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 2, "unknown envelope row must be skipped, not stall peek")
        XCTAssertEqual(peeked[0].id, before.id, "first valid row lands in position 0")
        XCTAssertEqual(peeked[1].id, after.id, "second valid row lands in position 1")

        // The bad row stays in the table — a future build that knows how
        // to decode it can pick it up. `isEmpty` still reflects the raw
        // row count (peek is tolerant, not destructive).
        let emptyAfter = try await store.isEmpty()
        XCTAssertFalse(emptyAfter)
    }

    /// Regression for "tolerant peek leaves poison rows on disk forever".
    /// The peek path silently skips an undecodable envelope so one bad row
    /// doesn't stall the queue — but the skipped row stays in the table
    /// and `isEmpty()` / flush's `remaining` never see zero again. Prune
    /// is the scheduled sweep that actually deletes those rows. This test
    /// seeds 2 valid + 1 forward-versioned row, runs prune, and asserts
    /// only the valid rows remain.
    func testPushQueuePruneUndecodableRowsRemovesPoisonRows() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let valid1 = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 1)]),
            enqueuedAt: Date(timeIntervalSince1970: 1_000),
            attempts: 0
        )
        let valid2 = PushItem(
            id: UUID(),
            payload: .setLogs([Fixtures.sampleSetLog(setIndex: 2)]),
            enqueuedAt: Date(timeIntervalSince1970: 3_000),
            attempts: 0
        )
        try await store.enqueue(valid1)
        try await store.enqueue(valid2)

        // Forge the bad row directly — same technique as the peek-tolerance
        // regression test above. Represents a forward-versioned envelope
        // written by a newer build and left behind after a downgrade.
        let badRow = PushItemModel(
            id: UUID(),
            enqueuedAt: Date(timeIntervalSince1970: 2_000),
            attempts: 0,
            payloadJSON: Data(#"{"kind":"futureCaseWeDoNotKnow","extra":42}"#.utf8)
        )
        let bootstrapContext = ModelContext(factory.container)
        bootstrapContext.insert(badRow)
        try bootstrapContext.save()

        // Cast back to the concrete impl — the prune hook is deliberately
        // NOT on the `PushQueueStore` protocol (persistence-hygiene concern,
        // not a Sync vocabulary word). Same cast the factory's
        // `prepareTelemetry` does internally.
        let impl = try XCTUnwrap(store as? PushQueueStoreImpl)
        let removed = try await impl.pruneUndecodableRows()
        XCTAssertEqual(removed, 1, "exactly one poison row removed")

        // After prune, only the two valid rows survive.
        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 2)
        XCTAssertEqual(Set(peeked.map(\.id)), Set([valid1.id, valid2.id]))

        // A second prune is a clean no-op — nothing left to reject.
        let removedSecond = try await impl.pruneUndecodableRows()
        XCTAssertEqual(removedSecond, 0)
    }

    // MARK: - Stubs

    /// Non-issuing transport — the replace-in-place test never calls
    /// `flush` so no HTTP call is expected, but `PushQueue.init` requires
    /// an `HTTPTransport`.
    private struct EmptyTransport: HTTPTransport {
        func get(
            path: String,
            query: [(String, String)],
            bearerToken: String
        ) async throws -> HTTPResponse {
            XCTFail("unexpected GET \(path)")
            return HTTPResponse(status: 599, body: Data())
        }

        func post(
            path: String,
            body: Data,
            bearerToken: String
        ) async throws -> HTTPResponse {
            XCTFail("unexpected POST \(path)")
            return HTTPResponse(status: 599, body: Data())
        }
    }

    func testStatusUpdatePayloadRoundTrip() async throws {
        let factory = try makeFactory()
        let store = factory.pushQueueStore

        let workoutID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let item = PushItem(
            id: UUID(),
            payload: .statusUpdate(
                workoutID: workoutID,
                status: .completed,
                completedAt: completedAt,
                notes: "leg day PR!"
            ),
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            attempts: 0
        )
        try await store.enqueue(item)

        let peeked = try await store.peek(max: 10)
        XCTAssertEqual(peeked.count, 1)
        if case .statusUpdate(let wid, let status, let ca, let notes) = peeked[0].payload {
            XCTAssertEqual(wid, workoutID)
            XCTAssertEqual(status, .completed)
            XCTAssertEqual(ca, completedAt)
            XCTAssertEqual(notes, "leg day PR!")
        } else {
            XCTFail("expected statusUpdate payload")
        }
    }
}
