// PushFlusher.swift
//
// Drives the foreground push-retry cadence. Per `docs/sync.md` § "Cadence":
// every ~60s while the app is foregrounded, the push queue is flushed (one
// attempt per pending batch). No exponential backoff — single-user scale.
//
// Design (option (a) + event-kick hybrid, per the task brief):
//   * The flusher owns a detached `Task` that loops on `Task.sleep` at the
//     configured interval and calls `SyncAPI.flushPushQueue()`.
//   * On `.complete`, `ExecutionViewModel` dispatches an immediate flush via
//     the `PushFlushKick` hook so the terminal payload hits the server in
//     seconds rather than within the next minute.
//   * On `SyncError.tokenRejected`, the flusher stops itself — the app is
//     unauthenticated, repeat flushes would hammer the server for no gain.
//     The shell surface then notices (via `ConnectionManager.states()` or
//     the next explicit pull) and routes the user back to FirstRun.
//
// No Combine, no Timer.publish — a single `Task { while !Task.isCancelled {
// … } }` matches how the rest of the package talks to async APIs. The
// flusher is an `actor` only because stopping the task from outside should
// be safe across threads; the inside of the loop is single-threaded by
// construction.

import Foundation
import Sync
import WorkoutCoreFoundation

/// Periodic flusher for the push queue. Instantiate once from
/// `AppBootstrap`, call `start()` after bootstrap lands, call `stop()`
/// from the shell when the app backgrounds or the connection is wiped.
public actor PushFlusher {
    private let api: SyncAPI
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    public init(
        api: SyncAPI,
        interval: TimeInterval = 60
    ) {
        self.api = api
        self.interval = interval
    }

    /// Start the periodic flush loop. Idempotent — calling twice is a
    /// no-op; the existing task continues.
    public func start() {
        if task != nil { return }
        let api = self.api
        let interval = self.interval
        task = Task.detached { [weak self] in
            while !Task.isCancelled {
                // Sleep first so we don't fire an immediate flush on
                // start — bootstrap's own pull already did one and
                // there's no queued work yet. If a completion kick
                // arrives before the first tick it uses `flushNow()`
                // directly on the API; we don't short-circuit from
                // here.
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                do {
                    _ = try await api.flushPushQueue()
                } catch SyncError.tokenRejected {
                    // 401 — stop the loop; the shell reauth flow
                    // replaces us with a fresh flusher on next
                    // connect.
                    await self?.clearTask()
                    return
                } catch {
                    // Transient failure — loop continues. The queue
                    // item stays, attempts bump inside PushQueue
                    // itself, ConnectionManager flips to `.offline`.
                }
            }
        }
    }

    /// Immediate flush kick. Safe to call on any actor; returns after the
    /// single flush attempt completes. Used by `ExecutionViewModel.complete`
    /// via a `PushFlushKick` closure so the terminal payload drains
    /// quickly. Errors are swallowed — the caller never awaits this for
    /// correctness.
    public func flushNow() async {
        do {
            _ = try await api.flushPushQueue()
        } catch {
            // Same posture as the loop — transient errors stay in the
            // queue; a 401 parks the tick loop but callers of
            // `flushNow` don't need to react.
        }
    }

    /// Cancel the loop. Safe to call multiple times.
    public func stop() {
        task?.cancel()
        task = nil
    }

    private func clearTask() {
        task = nil
    }
}
