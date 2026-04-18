// ConnectionManager.swift
//
// Owns the `ConnectionState` signal. Separate from `PullService` and
// `PushQueue` per HS-1 — each of those feeds events in, the manager
// transitions, and the current state is broadcast to observers via an
// `AsyncStream`.
//
// Structured concurrency, no Combine. The UI layer (iOS 17 `@Observable`)
// can bridge an `AsyncStream` into view state trivially; avoiding Combine
// keeps the package watchOS-friendly and lets us drop iOS 16 support
// assumptions without worrying about the Combine deprecation surface.

import Foundation

/// Signals an outcome that drives a state transition. Emitted by `PullService`
/// and `PushQueue`; consumed by `ConnectionManager.observe(_:)`.
public enum ConnectionEvent: Sendable {
    case syncStarted
    case pullSucceeded(at: Date)
    case pushSucceeded(at: Date)
    case networkFailed
    case serverUnreachable
    case tokenRejected
    /// A successful token rotation or reconfiguration — the UI collected a
    /// new token and the manager should allow requests again.
    case reauthorized
}

/// Single source of truth for `ConnectionState`. Thread-safe via `actor`
/// isolation. `state` is read synchronously via the snapshot property; the
/// `AsyncStream` emits on every transition for observers.
public actor ConnectionManager {
    private var currentState: ConnectionState
    private var continuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    public init(initial: ConnectionState = .offline) {
        self.currentState = initial
    }

    /// The most recent state. Safe to read concurrently — actor isolation
    /// serializes access.
    public var state: ConnectionState { currentState }

    /// A stream of every state value including the current one (immediately
    /// yielded on subscribe). Multiple subscribers each get their own stream;
    /// all receive the same values.
    public func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            let id = UUID()
            self.register(id: id, continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unregister(id: id) }
            }
        }
    }

    /// Whether requests should be attempted. `false` while `.tokenRejected`
    /// — consumers use this to short-circuit pulls and to pause the push
    /// queue. See `docs/sync.md` § "Auth posture" — 401 is not retried
    /// silently.
    public var allowsRequests: Bool {
        if case .tokenRejected = currentState { return false }
        return true
    }

    /// Feed an event in; the manager computes the next state and publishes
    /// it. Idempotent on no-op transitions (e.g. repeated `.networkFailed`
    /// while already offline does not re-emit).
    public func observe(_ event: ConnectionEvent) {
        let next: ConnectionState
        switch event {
        case .syncStarted:
            // Never leave `.tokenRejected` without an explicit reauthorized
            // event — starting a sync doesn't clear the 401 condition.
            if case .tokenRejected = currentState { return }
            next = .syncing
        case .pullSucceeded(let at), .pushSucceeded(let at):
            next = .online(lastSyncAt: at)
        case .networkFailed:
            if case .tokenRejected = currentState { return }
            next = .offline
        case .serverUnreachable:
            if case .tokenRejected = currentState { return }
            next = .serverUnreachable
        case .tokenRejected:
            next = .tokenRejected
        case .reauthorized:
            next = .offline
        }
        setState(next)
    }

    /// Reset to a known state. Used on first-run and on server change.
    public func reset(to state: ConnectionState) {
        setState(state)
    }

    // MARK: - Private

    private func setState(_ next: ConnectionState) {
        if next == currentState { return }
        currentState = next
        for cont in continuations.values {
            cont.yield(next)
        }
    }

    private func register(
        id: UUID,
        continuation: AsyncStream<ConnectionState>.Continuation
    ) {
        continuations[id] = continuation
        continuation.yield(currentState)
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
