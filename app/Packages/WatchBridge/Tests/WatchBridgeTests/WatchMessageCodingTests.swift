// WatchMessageCodingTests.swift
//
// JSON round-trip every WatchMessage variant. These cases guard against a
// decoder that silently tolerates unknown tags, and against future cases
// being added without Codable coverage.

import XCTest
@testable import WatchBridge

final class WatchMessageCodingTests: XCTestCase {

    private func roundTrip(_ original: WatchMessage, file: StaticString = #file, line: UInt = #line) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WatchMessage.self, from: data)
        XCTAssertEqual(decoded, original, file: file, line: line)
    }

    // MARK: - iPhone → Watch

    func testPushActiveBlockRoundTrip() throws {
        let payload = ActiveBlockPayload(
            workoutItemID: UUID(),
            exerciseName: "Back Squat",
            prescription: "5 reps @ 102.5 kg",
            setNumber: 2,
            setCount: 5,
            targetRir: 2
        )
        try roundTrip(.pushActiveBlock(payload))
    }

    func testPushActiveBlockRoundTripNilTargetRir() throws {
        // targetRir can be nil (e.g. warmup set) — make sure the optional
        // survives the round trip without turning into `.some(0)`.
        let payload = ActiveBlockPayload(
            workoutItemID: UUID(),
            exerciseName: "Front Squat",
            prescription: "Warmup",
            setNumber: 1,
            setCount: 3,
            targetRir: nil
        )
        try roundTrip(.pushActiveBlock(payload))
    }

    func testPushRestTimerRoundTrip() throws {
        // Round-trip a timestamp rounded to whole seconds. ISO-8601 without
        // fractional seconds is the common subset both sides agree on;
        // using an arbitrary interval risks sub-millisecond loss.
        let endsAt = Date(timeIntervalSince1970: 1_765_000_000)
        try roundTrip(.pushRestTimer(endsAt: endsAt))
    }

    func testPushWorkoutCompleteRoundTrip() throws {
        try roundTrip(.pushWorkoutComplete)
    }

    // MARK: - Watch → iPhone

    func testSetStartedRoundTrip() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let at = Date(timeIntervalSince1970: 1_765_000_050)
        try roundTrip(.setStarted(workoutItemID: id, setIndex: 1, at: at))
    }

    func testSetEndedRoundTrip() throws {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let at = Date(timeIntervalSince1970: 1_765_000_100)
        try roundTrip(.setEnded(
            workoutItemID: id,
            setIndex: 3,
            at: at,
            bpmAvg: 142,
            bpmMax: 168
        ))
    }

    func testSetEndedWithoutHRRoundTrip() throws {
        // Watch without HR access still logs the set; bpm fields arrive nil.
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let at = Date(timeIntervalSince1970: 1_765_000_200)
        try roundTrip(.setEnded(
            workoutItemID: id,
            setIndex: 4,
            at: at,
            bpmAvg: nil,
            bpmMax: nil
        ))
    }

    func testQuickLogRoundTrip() throws {
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        try roundTrip(.quickLog(workoutItemID: id, setIndex: 2, reps: 8, rir: 2))
    }

    func testQuickLogWithoutRIRRoundTrip() throws {
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        try roundTrip(.quickLog(workoutItemID: id, setIndex: 1, reps: 5, rir: nil))
    }

    // MARK: - ActiveBlockPayload on its own

    func testActiveBlockPayloadRoundTrip() throws {
        // Exercising the payload directly (not via the WatchMessage wrapper)
        // locks in the on-wire key names — useful if a future iteration
        // grows a second consumer.
        let original = ActiveBlockPayload(
            workoutItemID: UUID(),
            exerciseName: "Romanian Deadlift",
            prescription: "8 reps @ 80 kg",
            setNumber: 3,
            setCount: 4,
            targetRir: 1
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ActiveBlockPayload.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testUnknownTagFailsCleanly() throws {
        // Sanity — an unknown discriminator is a decode error, not silent
        // coercion to a default case.
        let bogus = Data(#"{"type":"notAThing","payload":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(WatchMessage.self, from: bogus))
    }
}
