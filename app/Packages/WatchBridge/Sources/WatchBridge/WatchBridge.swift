// WatchBridge.swift
//
// The pure-Swift boundary that everyone outside this package sees. Feature
// code and the watch app take a `WatchBridge` protocol in their init and
// never touch WatchConnectivity themselves — FF-13 enforces this via
// SwiftLint (`no_watchconnectivity_outside_watchbridge`).

import Foundation

public struct WatchDeviceSnapshot: Sendable, Hashable, Codable {
    public var isSupported: Bool
    public var isPaired: Bool
    public var isWatchAppInstalled: Bool
    public var isReachable: Bool

    public init(
        isSupported: Bool,
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool
    ) {
        self.isSupported = isSupported
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        self.isReachable = isReachable
    }

    public var displayValue: String {
        guard isSupported else { return "watch unavailable" }
        guard isPaired else { return "no watch paired" }
        guard isWatchAppInstalled else { return "paired, app not installed" }
        return isReachable ? "paired, reachable" : "paired, not reachable"
    }
}

/// Transport-agnostic IPC surface between the iPhone and the Watch.
///
/// Both peers implement the same protocol; direction is encoded by the
/// `WatchMessage` variant. `messages()` yields every inbound message for the
/// lifetime of the bridge.
public protocol WatchBridge: Sendable {
    /// True when the session can send an immediate `sendMessage` — the peer
    /// is paired, installed, and reachable. Callers treat `false` as a cue
    /// to fall back to the queued `transferUserInfo` path, which the live
    /// bridge already handles internally. This is surfaced mainly for UI
    /// affordances (e.g. a "watch connected" indicator).
    var isReachable: Bool { get async }

    /// Current device pairing/install/reachability state. `isReachable` alone
    /// is not pairing state: a paired watch is often unreachable while asleep,
    /// off-wrist, or while the companion app is not foregrounded.
    func deviceSnapshot() async -> WatchDeviceSnapshot

    /// Send a message to the peer. Throws `WatchBridgeError` if the session
    /// is not activated or the payload cannot be encoded. Transient
    /// reachability issues are not surfaced as errors — the implementation
    /// transparently queues them.
    func send(_ message: WatchMessage) async throws

    /// Inbound stream. One call = one multicast-capable stream for the
    /// bridge's lifetime. Messages yielded in arrival order.
    func messages() -> AsyncStream<WatchMessage>
}

public enum WatchBridgeError: Error, Equatable {
    /// The underlying WCSession never activated (or the platform does not
    /// support WatchConnectivity at all — e.g. macOS).
    case notActivated
    /// The peer is not reachable *and* the queued path could not accept the
    /// message. In practice this is rare; most unreachable cases are handled
    /// by falling through to `transferUserInfo`.
    case unreachable
    /// JSON encoding failed. Carries a human-readable reason.
    case encode(String)
}
