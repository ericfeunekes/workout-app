// FakeWatchBridgeTests.swift
//
// Exercise send → sentMessages() and deliver(_:) → messages() for every
// WatchMessage variant. This is what Features tests will lean on, so the
// channel has to be order-preserving and loss-free.

import XCTest
@testable import WatchBridge

final class FakeWatchBridgeTests: XCTestCase {

    // MARK: - Send side

    func testSendRecordsMessages() async throws {
        let bridge = FakeWatchBridge()
        let id = UUID()
        let at = Date(timeIntervalSince1970: 1_765_000_000)

        try await bridge.send(.pushWorkoutComplete)
        try await bridge.send(.pushRestTimer(endsAt: at))
        try await bridge.send(
            .setStarted(workoutItemID: id, setIndex: 1, at: at)
        )

        let sent = bridge.sentMessages()
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0], .pushWorkoutComplete)
        XCTAssertEqual(sent[1], .pushRestTimer(endsAt: at))
        XCTAssertEqual(
            sent[2],
            .setStarted(workoutItemID: id, setIndex: 1, at: at)
        )
    }

    func testReachabilityFlag() async throws {
        let bridge = FakeWatchBridge(isReachable: false)
        var reachable = await bridge.isReachable
        XCTAssertFalse(reachable)

        bridge.setReachable(true)
        reachable = await bridge.isReachable
        XCTAssertTrue(reachable)
    }

    // MARK: - Receive side — every variant lands in the stream

    func testRoundTripsEveryVariant() async throws {
        let bridge = FakeWatchBridge()
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let at = Date(timeIntervalSince1970: 1_765_000_000)

        let fixtures: [WatchMessage] = [
            .pushActiveBlock(ActiveBlockPayload(
                exerciseName: "Bench",
                prescription: "5 reps @ 80 kg",
                setNumber: 1,
                setCount: 5,
                targetRir: 2
            )),
            .pushRestTimer(endsAt: at),
            .pushWorkoutComplete,
            .setStarted(workoutItemID: id, setIndex: 1, at: at),
            .setEnded(
                workoutItemID: id,
                setIndex: 1,
                at: at,
                bpmAvg: 150,
                bpmMax: 170
            ),
            .quickLog(workoutItemID: id, setIndex: 2, reps: 5, rir: 2),
        ]

        let stream = bridge.messages()
        var iterator = stream.makeAsyncIterator()

        // Registration is synchronous (FakeWatchBridge uses a lock, not an
        // actor hop) so `deliver` is guaranteed to see this subscription.
        for expected in fixtures {
            bridge.deliver(expected)
            let received = await iterator.next()
            XCTAssertEqual(received, expected)
        }
    }

    func testMultipleSubscribersEachReceive() async throws {
        // `messages()` is expected to be multicast — both the active-screen
        // subscriber and a logger can listen at once. Prove it.
        let bridge = FakeWatchBridge()
        let streamA = bridge.messages()
        let streamB = bridge.messages()
        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()

        bridge.deliver(.pushWorkoutComplete)

        let a = await iteratorA.next()
        let b = await iteratorB.next()
        XCTAssertEqual(a, .pushWorkoutComplete)
        XCTAssertEqual(b, .pushWorkoutComplete)
    }

    func testFinishTerminatesStreams() async throws {
        let bridge = FakeWatchBridge()
        let stream = bridge.messages()
        var iterator = stream.makeAsyncIterator()

        bridge.deliver(.pushWorkoutComplete)
        _ = await iterator.next()

        bridge.finish()
        let terminal = await iterator.next()
        XCTAssertNil(terminal, "finish() should terminate the stream")
    }
}
