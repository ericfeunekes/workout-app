// Telemetry DTOs — wire types for structured event logging.
//
// Design choices:
//   • Snake_case JSON mapped to camelCase Swift via CodingKeys (same as
//     Entities.swift).
//   • `dataJson` is a permissive free-form JSON string so new event shapes
//     don't require schema changes. The server never cracks it.
//   • Dates are Date values (ISO-8601 via JSONDecoder/Encoder strategies).
//   • IDs are strings (UUIDs on the wire) — matches the rest of the schema.
//
// See docs/specs/v2-architecture.md for the "dumb app, smart conversation"
// invariant this serves: when Eric reports a bug, the event trail is on the
// server and Claude can reason about what happened without needing the
// device.

import Foundation

public struct TelemetryEvent: Codable, Sendable, Equatable {
    public let id: String
    public let timestamp: Date
    public let sessionId: String
    public let kind: String
    public let name: String
    public let dataJson: String?
    public let workoutId: String?
    public let setLogId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case sessionId = "session_id"
        case kind
        case name
        case dataJson = "data_json"
        case workoutId = "workout_id"
        case setLogId = "set_log_id"
    }

    public init(
        id: String,
        timestamp: Date,
        sessionId: String,
        kind: String,
        name: String,
        dataJson: String? = nil,
        workoutId: String? = nil,
        setLogId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.kind = kind
        self.name = name
        self.dataJson = dataJson
        self.workoutId = workoutId
        self.setLogId = setLogId
    }
}

public struct TelemetryEventsPayload: Codable, Sendable, Equatable {
    public let events: [TelemetryEvent]

    public init(events: [TelemetryEvent]) {
        self.events = events
    }
}
