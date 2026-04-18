// TelemetrySession.swift
//
// One UUID per app launch, captured once and reused by every emitter. When
// Eric reports a bug we filter the event_log by `session_id` to get the
// exact trail of one run.
//
// Static-let guarantees the first access generates the ID and every
// subsequent access sees the same value for the lifetime of the process.
// Features thread it through explicitly (via `Event(sessionID: ...)`) so
// the dependency is visible at the call site.

import Foundation

public enum TelemetrySession {
    /// The UUID for this app launch. Generated lazily on first access and
    /// stable for the life of the process.
    public static let id: UUID = UUID()
}
