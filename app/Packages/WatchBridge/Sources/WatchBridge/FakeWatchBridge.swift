// FakeWatchBridge.swift
//
// In-memory `WatchBridge` for Features tests. Sending enqueues the message
// into the outbound log; calling `deliver(_:)` from the test pushes a
// message into every active `messages()` stream as if the peer had sent it.
//
// Not Codable-gated — the fake skips JSON encoding so tests stay fast and
// focused on call flow. The WatchMessage JSON round-trip is covered
// separately in WatchMessageCodingTests.

import Foundation
import os

/// All mutable state lives in here, behind `OSAllocatedUnfairLock`. We
/// avoid `actor` so `messages()` can register a continuation synchronously
/// and the test can `deliver(_:)` on the next line without a scheduler
/// race. We avoid `NSLock` because it's not safe to acquire from an async
/// context under Swift 6 strict concurrency — `OSAllocatedUnfairLock`
/// exposes `withLock` which is.
private struct FakeState {
    var sent: [WatchMessage] = []
    var continuations: [UUID: AsyncStream<WatchMessage>.Continuation] = [:]
    var reachable: Bool
    var isPaired: Bool
    var isWatchAppInstalled: Bool
}

public final class FakeWatchBridge: WatchBridge {

    private let state: OSAllocatedUnfairLock<FakeState>

    public init(
        isReachable: Bool = true,
        isPaired: Bool = true,
        isWatchAppInstalled: Bool = true
    ) {
        self.state = OSAllocatedUnfairLock(
            initialState: FakeState(
                reachable: isReachable,
                isPaired: isPaired,
                isWatchAppInstalled: isWatchAppInstalled
            )
        )
    }

    // MARK: - WatchBridge conformance

    public var isReachable: Bool {
        get async { state.withLock { $0.reachable } }
    }

    public func deviceSnapshot() async -> WatchDeviceSnapshot {
        state.withLock {
            WatchDeviceSnapshot(
                isSupported: true,
                isPaired: $0.isPaired,
                isWatchAppInstalled: $0.isWatchAppInstalled,
                isReachable: $0.reachable
            )
        }
    }

    public func send(_ message: WatchMessage) async throws {
        state.withLock { $0.sent.append(message) }
    }

    public func messages() -> AsyncStream<WatchMessage> {
        AsyncStream<WatchMessage> { continuation in
            let id = UUID()

            // Register synchronously — no Task hop — so the caller can
            // `deliver` on the next line and know this stream will see it.
            self.state.withLock { $0.continuations[id] = continuation }

            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    // MARK: - Test-facing API

    /// Outbound log — everything `send(_:)` received, in order.
    public func sentMessages() -> [WatchMessage] {
        state.withLock { $0.sent }
    }

    /// Inject a message as if the peer sent it. Every active `messages()`
    /// stream receives it.
    public func deliver(_ message: WatchMessage) {
        // Snapshot continuations under the lock; yield outside the lock
        // so consumer-side reactions don't deadlock if they happen to
        // re-enter the bridge.
        let snapshot = state.withLock { Array($0.continuations.values) }
        for continuation in snapshot {
            continuation.yield(message)
        }
    }

    /// Flip reachability for tests that exercise fallback paths.
    public func setReachable(_ reachable: Bool) {
        state.withLock { $0.reachable = reachable }
    }

    public func setDeviceState(
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool
    ) {
        state.withLock {
            $0.isPaired = isPaired
            $0.isWatchAppInstalled = isWatchAppInstalled
            $0.reachable = isReachable
        }
    }

    /// Finish every open `messages()` stream. Useful when a test needs to
    /// drain and assert after a bounded batch.
    public func finish() {
        // Drain under the lock; call `finish()` outside the lock so the
        // continuation's `onTermination` handler can re-enter safely.
        let snapshot = state.withLock { state -> [AsyncStream<WatchMessage>.Continuation] in
            let all = Array(state.continuations.values)
            state.continuations.removeAll()
            return all
        }
        for continuation in snapshot {
            continuation.finish()
        }
    }
}
