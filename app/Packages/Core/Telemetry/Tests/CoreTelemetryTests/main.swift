// main.swift — entry point for `swift run CoreTelemetryTests`.
//
// Covers:
//   1. Event init + equality — the value type's shape.
//   2. NoopTelemetryEmitter is genuinely a no-op (call doesn't crash).
//   3. TelemetrySession.id is stable across accesses.

import Foundation
import CoreTelemetry

runCase("Event carries all fields through init") {
    let id = UUID()
    let session = UUID()
    let ts = Date(timeIntervalSince1970: 1_744_000_000)
    let workoutID = UUID()
    let setLogID = UUID()

    let event = Event(
        id: id,
        timestamp: ts,
        sessionID: session,
        kind: "interaction",
        name: "today.start_tap",
        dataJSON: #"{"tab":"today"}"#,
        workoutID: workoutID,
        setLogID: setLogID
    )

    try expectEqual(event.id, id)
    try expectEqual(event.timestamp, ts)
    try expectEqual(event.sessionID, session)
    try expectEqual(event.kind, "interaction")
    try expectEqual(event.name, "today.start_tap")
    try expectEqual(event.dataJSON, #"{"tab":"today"}"#)
    try expectEqual(event.workoutID, workoutID)
    try expectEqual(event.setLogID, setLogID)
}

runCase("Event equality compares all fields") {
    let a = Event(sessionID: UUID(), kind: "state", name: "x")
    let b = Event(id: a.id, timestamp: a.timestamp, sessionID: a.sessionID, kind: a.kind, name: a.name)
    try expect(a == b, "same values should compare equal")

    let differentKind = Event(
        id: a.id, timestamp: a.timestamp, sessionID: a.sessionID, kind: "other", name: a.name
    )
    try expect(a != differentKind, "different kind should compare non-equal")
}

runCase("NoopTelemetryEmitter accepts events without crashing") {
    let emitter: TelemetryEmitter = NoopTelemetryEmitter()
    emitter.emit(Event(sessionID: TelemetrySession.id, kind: "interaction", name: "noop.smoke"))
    // Nothing to assert — the point is it doesn't throw or crash.
    try expect(true)
}

runCase("TelemetrySession.id is stable across accesses") {
    let first = TelemetrySession.id
    let second = TelemetrySession.id
    try expectEqual(first, second, "session id should be process-stable")
}

reportAndExit()
