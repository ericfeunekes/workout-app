// Event.swift
//
// Pure value type for a structured telemetry event. Mirrors the wire shape
// (`WorkoutDBSchema.TelemetryEvent`) but uses domain types — `UUID`, `Date`
// — so the rest of the app never has to reason about string-typed IDs.
//
// Conversion to/from the wire DTO lives in `Persistence` / `Sync` — this
// module stays pure and has no Codable, networking, or SwiftData imports.

import Foundation

/// One structured telemetry event. Emitted from the app's view models,
/// persisted locally, then lazily pushed to the server.
///
/// `kind` partitions the event space for filtering ("interaction",
/// "network", "state", "timer", "error"). `name` is the specific event
/// (e.g. "today.start_tap", "execution.log_set", "network.pull_latest").
/// `dataJson` is a freeform string payload — the server never cracks it,
/// so new event shapes don't require schema changes.
public struct Event: Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let sessionID: UUID
    public let kind: String
    public let name: String
    public let dataJSON: String?
    public let workoutID: UUID?
    public let setLogID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionID: UUID,
        kind: String,
        name: String,
        dataJSON: String? = nil,
        workoutID: UUID? = nil,
        setLogID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.kind = kind
        self.name = name
        self.dataJSON = dataJSON
        self.workoutID = workoutID
        self.setLogID = setLogID
    }
}
