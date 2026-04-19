// PushBackoff.swift
//
// Backoff + dead-letter policy for the push queue retry loop.
//
// Before this file existed, `PushFlusher` slept for a fixed 60s between
// flushes and `PushQueue` retried forever on every non-2xx. That's fine
// for transient 5xx / network drops — the server comes back and the queue
// drains. But for a persistent 4xx (e.g. 422 validation), the same item
// re-pushes every 60s forever, filling logs and blocking the head of the
// queue. See `docs/features/push-queue.md` § "Retry cadence".
//
// The contract:
//   1. `nextDelay(forAttempts:)` yields `[10s, 30s, 60s, 120s, 300s]` for
//      attempts 0..4, then plateaus at 300s. A fresh enqueue resets the
//      caller's consecutive-failure counter to 0.
//   2. `deadLetterThreshold` is the attempt count at which a `PushQueue`
//      seeing a persistent 4xx (non-401) drops the item and emits a
//      `execution.push_item_dead_lettered` telemetry event. 401 still
//      routes to `tokenRejected` — persistent 4xx here means the server
//      keeps rejecting the body as invalid, and no amount of retries will
//      fix that without a code change.
//
// This file is data + pure functions; no Foundation networking, no actor
// state. `PushQueue` (for per-item dead-letter counting) and `PushFlusher`
// (for loop cadence) both call in.

import Foundation

public enum PushBackoff {

    /// Backoff schedule in seconds. Index `i` is the delay to wait *after*
    /// the i-th consecutive failure (0-indexed). After the table is
    /// exhausted the delay plateaus at the last entry.
    ///
    /// Single-user / single-device: we cap at 5 minutes so a recovered
    /// server doesn't wait arbitrarily long before the next attempt.
    public static let schedule: [TimeInterval] = [10, 30, 60, 120, 300]

    /// Number of consecutive persistent-4xx (non-401) failures after which
    /// `PushQueue` dead-letters the head item. Chosen small enough that a
    /// genuine stuck row can't block the queue for long, and large enough
    /// that a single bad request from a transient condition (clock skew,
    /// in-flight schema deploy) gets retries before we drop it.
    public static let deadLetterThreshold: Int = 5

    /// Delay to wait before the next attempt given the number of
    /// consecutive failures so far. `attempts=0` is the *first* retry
    /// window — use this right after the first failed flush.
    public static func nextDelay(forAttempts attempts: Int) -> TimeInterval {
        let clamped = max(0, attempts)
        if clamped >= schedule.count {
            // swiftlint:disable:next force_unwrapping
            return schedule.last!
        }
        return schedule[clamped]
    }
}
