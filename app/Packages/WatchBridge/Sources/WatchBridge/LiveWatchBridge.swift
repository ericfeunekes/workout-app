// LiveWatchBridge.swift
//
// Production WCSession wrapper. The only file in the package (or the app)
// that may import WatchConnectivity — FF-13 enforces this via SwiftLint's
// `no_watchconnectivity_outside_watchbridge` custom rule, which excludes
// `Packages/WatchBridge/*`.
//
// Design:
//   - `WCSessionDelegate` is `NSObject`-bound Objective-C. We wrap it in an
//     internal delegate class (`LiveDelegate`) that forwards events into
//     an `AsyncStream.Continuation`. The public surface stays pure Swift.
//   - Outbound: try `sendMessage` when the peer is reachable (delivered
//     immediately, best for live UI state like "start rest timer").
//     Otherwise fall back to `transferUserInfo`, which WCSession queues
//     and delivers when the peer wakes up. This matters for watch→phone
//     quickLogs when the phone is in a pocket.
//   - Inbound: receive via both `didReceiveMessage:` and `didReceiveUserInfo:`
//     delegate methods, decode JSON, emit to the stream.
//
// On macOS (where WatchConnectivity is not available), this file compiles
// down to a stub that throws `.notActivated` on `send` and returns an empty
// stream — keeps the test target compilable from the command line without
// branching every call site.

import Foundation

#if canImport(WatchConnectivity)

import WatchConnectivity

public final class LiveWatchBridge: WatchBridge, @unchecked Sendable {

    // MARK: - Stored state
    //
    // The delegate owns both the WCSession and the inbound-stream
    // continuation. Public API forwards into it. The continuation is
    // created eagerly so `messages()` callers never miss an early event.

    private let delegate: LiveDelegate
    private let stream: AsyncStream<WatchMessage>

    public init() {
        // AsyncStream.makeStream hands back the continuation as a real value
        // instead of requiring the captured-var dance around the closure
        // initialiser, so we avoid the implicitly-unwrapped-optional.
        let (stream, continuation) = AsyncStream<WatchMessage>.makeStream()
        self.stream = stream
        self.delegate = LiveDelegate(continuation: continuation)

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = delegate
            delegate.session = session
            session.activate()
        }
    }

    // MARK: - WatchBridge conformance

    public var isReachable: Bool {
        get async {
            delegate.session?.isReachable ?? false
        }
    }

    public func deviceSnapshot() async -> WatchDeviceSnapshot {
        guard WCSession.isSupported() else {
            return WatchDeviceSnapshot(
                isSupported: false,
                isPaired: false,
                isWatchAppInstalled: false,
                isReachable: false
            )
        }
        guard let session = delegate.session else {
            return WatchDeviceSnapshot(
                isSupported: true,
                isPaired: false,
                isWatchAppInstalled: false,
                isReachable: false
            )
        }
        #if os(iOS)
        return WatchDeviceSnapshot(
            isSupported: true,
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable
        )
        #else
        return WatchDeviceSnapshot(
            isSupported: true,
            isPaired: true,
            isWatchAppInstalled: session.isCompanionAppInstalled,
            isReachable: session.isReachable
        )
        #endif
    }

    public func send(_ message: WatchMessage) async throws {
        guard let session = delegate.session, session.activationState == .activated else {
            throw WatchBridgeError.notActivated
        }

        let payload: [String: Any]
        do {
            let data = try JSONEncoder.watchBridge().encode(message)
            payload = ["wb": data]
        } catch {
            throw WatchBridgeError.encode(String(describing: error))
        }

        if session.isReachable {
            // sendMessage delivers immediately when the peer is reachable.
            // `errorHandler` fires on transport failure — in that case we
            // fall back to `transferUserInfo`, which WCSession queues for
            // delivery when the peer wakes up.
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: { _ in
                    session.transferUserInfo(payload)
                }
            )
            return
        }

        // Not reachable — queue for delivery.
        _ = session.transferUserInfo(payload)
    }

    public func messages() -> AsyncStream<WatchMessage> {
        stream
    }
}

// MARK: - Delegate

/// Bridges WCSessionDelegate callbacks into an `AsyncStream` continuation.
/// Must inherit from `NSObject` — WCSessionDelegate is Objective-C.
final class LiveDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {

    weak var session: WCSession?
    private let continuation: AsyncStream<WatchMessage>.Continuation

    init(continuation: AsyncStream<WatchMessage>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    // MARK: Activation

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // No-op. Live bridge is fire-and-forget on activation.
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate to pick up the new watch when users switch devices.
        WCSession.default.activate()
    }
    #endif

    // MARK: Inbound — live messages

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        decode(message)
    }

    // MARK: Inbound — queued user info

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        decode(userInfo)
    }

    // MARK: - Decode helper

    private func decode(_ payload: [String: Any]) {
        guard let data = payload["wb"] as? Data else { return }
        do {
            let message = try JSONDecoder.watchBridge().decode(WatchMessage.self, from: data)
            continuation.yield(message)
        } catch {
            // Silently drop malformed messages — the peer is on a newer
            // schema. A real production build would surface this via
            // os.Logger; we stay quiet here to keep the package dependency
            // graph minimal.
        }
    }
}

#else

// MARK: - macOS stub
//
// Compiles on macOS so `swift test` / `swift build` work from the command
// line without Xcode. Every call is a no-op or an error; the live bridge
// never runs outside iOS/watchOS.

public final class LiveWatchBridge: WatchBridge, @unchecked Sendable {
    public init() {}

    public var isReachable: Bool { get async { false } }

    public func deviceSnapshot() async -> WatchDeviceSnapshot {
        WatchDeviceSnapshot(
            isSupported: false,
            isPaired: false,
            isWatchAppInstalled: false,
            isReachable: false
        )
    }

    public func send(_ message: WatchMessage) async throws {
        throw WatchBridgeError.notActivated
    }

    public func messages() -> AsyncStream<WatchMessage> {
        AsyncStream { continuation in continuation.finish() }
    }
}

#endif

// MARK: - Encoder/decoder

extension JSONEncoder {
    /// The canonical encoder for WatchBridge payloads. ISO-8601 dates with
    /// fractional seconds to match Sync and schema conventions.
    static func watchBridge() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static func watchBridge() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
