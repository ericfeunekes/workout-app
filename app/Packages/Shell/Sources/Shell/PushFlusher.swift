// PushFlusher.swift
//
// Drives the foreground push-retry cadence. Per `docs/sync.md` § "Cadence"
// plus the 2026-04-18 P2 polish: the loop sleeps on a backoff schedule
// driven by the count of consecutive failures, not a fixed 60s tick.
//
// Design (option (a) + event-kick hybrid, per the task brief):
//   * The flusher owns a detached `Task` that loops on `Task.sleep` at a
//     `PushBackoff`-driven interval and calls `SyncAPI.flushPushQueue()`.
//   * On `.complete`, `ExecutionViewModel` dispatches an immediate flush via
//     the `PushFlushKick` hook so the terminal payload hits the server in
//     seconds rather than within the next minute. The kick also resets the
//     consecutive-failure counter so a fresh log doesn't inherit the
//     previous burst's penalty.
//   * On `SyncError.tokenRejected`, the flusher stops itself and notifies
//     Shell's app-sync owner. Auth recovery is an app-level concern; the
//     flusher only reports the terminal outcome.
//
// Cadence table lives in `PushBackoff.schedule` so `PushQueue`'s dead-
// letter policy and this loop agree on what "an attempt" means. The
// flusher's counter is queue-wide (simpler than per-item); `PushQueue`
// owns the per-item 4xx dead-letter budget.
//
// No Combine, no Timer.publish — a single `Task { while !Task.isCancelled {
// … } }` matches how the rest of the package talks to async APIs. The
// flusher is an `actor` only because stopping the task from outside should
// be safe across threads; the inside of the loop is single-threaded by
// construction.

import Foundation
import Sync
import WorkoutCoreFoundation

public enum PushFlushOutcome: Sendable, Equatable {
    case completed
    case tokenRejected
}

/// Periodic flusher for the push queue. Instantiate once from
/// `AppBootstrap`, call `start()` after bootstrap lands, call `stop()`
/// from the shell when the app backgrounds or the connection is wiped.
public actor PushFlusher {
    private let api: SyncAPI
    private let onTokenRejected: (@Sendable () async -> Void)?
    /// Baseline delay used only when the backoff schedule's first slot
    /// is overridden (tests pass a tiny interval so the loop advances
    /// quickly). Production uses `PushBackoff.schedule` directly.
    private let baseInterval: TimeInterval?
    private var task: Task<Void, Never>?
    /// Count of consecutive flush attempts that did not produce a clean
    /// result. A "clean" result is one where the push queue reported
    /// `pushed > 0` with no network / token failure, or the queue was
    /// empty (nothing to do — not a failure). Reset by `flushNow()` so a
    /// user-driven kick (e.g. completing a workout) gets the fastest
    /// possible next attempt.
    private var consecutiveFailures: Int = 0

    public init(
        api: SyncAPI,
        interval: TimeInterval? = nil,
        onTokenRejected: (@Sendable () async -> Void)? = nil
    ) {
        self.api = api
        self.baseInterval = interval
        self.onTokenRejected = onTokenRejected
    }

    /// Start the periodic flush loop. Idempotent — calling twice is a
    /// no-op; the existing task continues.
    public func start() {
        if task != nil { return }
        task = Task.detached { [weak self] in
            while !Task.isCancelled {
                // Sleep first so we don't fire an immediate flush on
                // start — bootstrap's own pull already did one and
                // there's no queued work yet. If a completion kick
                // arrives before the first tick it uses `flushNow()`
                // directly; we don't short-circuit from here.
                let nanos = await self?.nextSleepNanos() ?? UInt64(60 * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let keepGoing = await self?.tick() ?? false
                if !keepGoing { return }
            }
        }
    }

    /// Run one flush attempt and fold the outcome into the backoff
    /// counter. Returns `false` when the loop should exit (401 / token
    /// rejection). Public-in-module for the loop body.
    func tick() async -> Bool {
        do {
            let result = try await api.flushPushQueue()
            if result.tokenRejected {
                await handleTokenRejected(notify: true)
                return false
            }
            if result.networkFailed {
                consecutiveFailures += 1
            } else {
                // Includes the "nothing to push" case — that is not a
                // failure. The queue is simply drained.
                consecutiveFailures = 0
            }
            return true
        } catch SyncError.tokenRejected {
            // 401 — stop the loop; the shell reauth flow replaces us
            // with a fresh flusher on next connect.
            await handleTokenRejected(notify: true)
            return false
        } catch {
            // Transient failure — loop continues on a longer sleep.
            // ConnectionManager has already flipped to `.offline` inside
            // `SyncAPI`.
            consecutiveFailures += 1
            return true
        }
    }

    /// Compute the next sleep in nanoseconds based on
    /// `consecutiveFailures`. Internal-in-module so tests can probe it.
    func nextSleepNanos() -> UInt64 {
        let seconds: TimeInterval
        if consecutiveFailures == 0, let base = baseInterval {
            // Honour the caller-specified tick interval while the queue
            // is healthy — production leaves this nil and falls through
            // to the schedule's first slot (10s).
            seconds = base
        } else {
            seconds = PushBackoff.nextDelay(forAttempts: consecutiveFailures)
        }
        return UInt64(seconds * 1_000_000_000)
    }

    /// Immediate flush kick. Safe to call on any actor; returns after the
    /// single flush attempt completes. Used by `ExecutionViewModel.complete`
    /// via a `PushFlushKick` closure so the terminal payload drains
    /// quickly. Errors are swallowed — the caller never awaits this for
    /// correctness. Also resets the consecutive-failure counter: a fresh
    /// user-driven enqueue deserves a fast next retry.
    @discardableResult
    public func flushNow() async -> PushFlushOutcome {
        consecutiveFailures = 0
        do {
            let result = try await api.flushPushQueue()
            if result.tokenRejected {
                await handleTokenRejected(notify: false)
                return .tokenRejected
            }
            // A kick that itself fails should not sit on zero — the
            // background loop needs the right delay before its next tick.
            if result.networkFailed {
                consecutiveFailures = 1
            }
            return .completed
        } catch SyncError.tokenRejected {
            await handleTokenRejected(notify: false)
            return .tokenRejected
        } catch {
            // Same posture as the loop — transient errors stay in the
            // queue. Auth failures are handled above because Shell must
            // route them through the same recovery path as pull 401s.
            return .completed
        }
    }

    /// Cancel the loop. Safe to call multiple times.
    public func stop() {
        task?.cancel()
        task = nil
    }

    private func handleTokenRejected(notify: Bool) async {
        task?.cancel()
        task = nil
        if notify {
            await onTokenRejected?()
        }
    }
}
