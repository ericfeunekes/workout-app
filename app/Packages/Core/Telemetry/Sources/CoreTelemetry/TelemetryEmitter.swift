// TelemetryEmitter.swift
//
// The injection protocol. Features take a `TelemetryEmitter` via init and
// call `emit(_:)` at key points — a set logged, a network request fired,
// an auth rejection. Production uses the Persistence-backed emitter;
// tests and previews use `NoopTelemetryEmitter`.
//
// Fire-and-forget by design: `emit(_:)` is non-throwing and returns
// immediately. The implementation is expected to enqueue the event onto
// its own actor / queue — callers must never block on telemetry.

import Foundation

/// Accept a structured event. Implementations MUST return immediately and
/// do the actual persistence off the caller's thread. `Sendable` because
/// emitters are threaded through `@MainActor` view models and also
/// through actor-bound Sync code.
public protocol TelemetryEmitter: Sendable {
    func emit(_ event: Event)
}

/// No-op emitter — the default for tests and previews. Exists so Feature
/// init signatures can offer a default parameter rather than making every
/// test construct a real emitter.
public struct NoopTelemetryEmitter: TelemetryEmitter {
    public init() {}

    public func emit(_ event: Event) {
        // Deliberately empty.
        _ = event
    }
}
