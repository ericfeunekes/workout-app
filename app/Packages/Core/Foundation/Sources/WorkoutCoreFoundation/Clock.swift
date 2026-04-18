// Clock.swift
//
// Time injection for testability. Core code never reads `Date()` directly;
// instead it depends on a `Clock` so tests can freeze time with `FixedClock`.
//
// Not related to Swift Concurrency's `Clock` protocol — that lives in
// `_Concurrency` and deals with durations + sleeping. This is a narrow
// "what time is it right now?" abstraction.

import Foundation

/// A source of the current wall-clock time.
///
/// Core packages depend on this instead of `Date()` so behavior is
/// deterministic under test. Pass a `SystemClock` in production and a
/// `FixedClock` in tests.
public protocol Clock: Sendable {
    /// The current time as the clock sees it.
    var now: Date { get }
}

/// A `Clock` backed by the system wall clock (`Date()`).
public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }
}

/// A `Clock` that always returns a fixed instant.
///
/// Use in tests to pin "now" to a known value. The stored `now` is mutable so
/// a test can advance the clock by reassigning, but there is deliberately no
/// `advance(by:)` helper — callers should reassign explicitly so the new value
/// shows up in code review.
public struct FixedClock: Clock {
    public var now: Date

    public init(now: Date) {
        self.now = now
    }
}
