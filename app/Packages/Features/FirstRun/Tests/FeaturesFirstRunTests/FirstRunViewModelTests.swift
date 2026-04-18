// FirstRunViewModelTests.swift
//
// Exercises the FirstRunViewModel state machine end-to-end with a fake
// TokenStore + FakeHTTPTransport. No URLSession round-trips, no SwiftData
// — the point is to prove the state transitions and side effects match
// the contract in `docs/sync.md` § "First-run UX".

import XCTest
import Foundation
import Sync
import Persistence
@testable import FeaturesFirstRun

@MainActor
final class FirstRunViewModelTests: XCTestCase {

    // MARK: - URL validation

    func testConnectWithInvalidURLYieldsInvalidURLFailure() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        let vm = makeViewModel(store: store, transport: transport)

        vm.url = "not a url"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .invalidURL))
        // No transport call was made — validation happens first.
        XCTAssertEqual(transport.callCount, 0)
        // Token was not saved.
        XCTAssertNil(store.saved)
    }

    func testConnectWithEmptyURLYieldsInvalidURLFailure() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        let vm = makeViewModel(store: store, transport: transport)

        vm.url = "   "
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .invalidURL))
        XCTAssertNil(store.saved)
    }

    // MARK: - Happy path

    func testConnectWith200PersistsAndCompletes() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        enqueueHappyPath(transport)
        let box = CounterBox()
        let vm = makeViewModel(store: store, transport: transport,
                               onComplete: { box.count += 1 })
        vm.url = "https://host.ts.net"
        vm.token = "valid-token"
        await vm.connect()
        XCTAssertEqual(vm.state, .complete)
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(store.saved?.token, "valid-token")
        XCTAssertEqual(store.saved?.url.absoluteString, "https://host.ts.net")
        XCTAssertEqual(transport.callCount, 2)
        XCTAssertEqual(transport.paths, ["/api/version", "/api/sync/pull"])
    }

    func testConnectTrimsWhitespaceOnToken() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        enqueueHappyPath(transport)
        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "  https://host.ts.net  "
        vm.token = "  spaced  "
        await vm.connect()
        XCTAssertEqual(vm.state, .complete)
        XCTAssertEqual(store.saved?.token, "spaced")
    }

    // MARK: - 401 on /api/version

    func testConnectWith401OnVersionFailsAndDoesNotSave() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()

        transport.enqueue(.response(HTTPResponse(status: 401, body: Data())))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "bad"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .tokenRejected))
        // Critically, TokenStore.save was never called — we don't want to
        // persist a token that produces 401 on every subsequent call.
        XCTAssertNil(store.saved)
        // Only one network call — we never hit /api/sync/pull.
        XCTAssertEqual(transport.callCount, 1)
    }

    // MARK: - 401 on /api/sync/pull

    func testConnectWith401OnPullFails() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()

        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"server_version":"0.0.1"}"#.utf8)
        )))
        transport.enqueue(.response(HTTPResponse(status: 401, body: Data())))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .tokenRejected))
        // Version succeeded, so the token did get saved. That matches the
        // spec's "first-sync crash recovery" note — the connection string
        // persists, the partial cache (which we never wrote) is cleared.
        XCTAssertNotNil(store.saved)
    }

    // MARK: - Transport throws

    func testConnectWithTransportThrowYieldsUnreachable() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        transport.enqueue(.throwError(.network("timeout")))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .unreachable))
        XCTAssertNil(store.saved)
    }

    // MARK: - Decode failure

    func testConnectWithDecodeFailureOnPullYieldsDecode() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()

        // Version is fine.
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"server_version":"0.0.1"}"#.utf8)
        )))
        // Pull responds with something that can't decode to the probe.
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data("not json".utf8)
        )))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .decode))
    }

    // MARK: - 5xx

    func testConnectWith500YieldsUnreachable() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        transport.enqueue(.response(HTTPResponse(
            status: 503,
            body: Data("service unavailable".utf8)
        )))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .unreachable))
        XCTAssertNil(store.saved)
    }

    // MARK: - Re-entrancy

    /// Double-tap regression: firing `connect()` twice concurrently must
    /// produce exactly one pipeline run. Without the re-entrancy guard
    /// the second call would reach `TokenStore.save` + `onComplete` a
    /// second time — duplicate Keychain writes, duplicate pull traffic.
    func testConcurrentConnectCallsRunOnlyOnce() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        for _ in 0..<2 { enqueueHappyPath(transport) }
        let completions = CounterBox()
        let vm = makeViewModel(store: store, transport: transport,
                               onComplete: { completions.count += 1 })
        vm.url = "https://host.ts.net"
        vm.token = "valid-token"
        async let first: Void = vm.connect()
        async let second: Void = vm.connect()
        _ = await (first, second)
        XCTAssertEqual(vm.state, .complete)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(transport.callCount, 2)
    }

    /// Bug-018 regression: rapid double-tap of the "connect" button must
    /// only run the version → persist → pull pipeline once. The scripted
    /// transport enqueues a SINGLE happy path; if the guard regressed and
    /// the second call fell through, the second `GET /api/version` would
    /// hit the empty script tail — call count would jump to 4, not 2.
    ///
    /// The user-visible fix is belt-and-braces: `connect()` short-circuits
    /// when `state ∈ {.connecting, .syncingFirstPull, .complete}` AND the
    /// view's connect button binds `.disabled(viewModel.isConnectInFlight)`
    /// so the UI can't dispatch a second call mid-flight. This test pins
    /// the VM-level guard; a ViewInspector-style test would pin the view.
    ///
    /// Distinct from `testConcurrentConnectCallsRunOnlyOnce` above: that
    /// test enqueues TWO happy paths and asserts the second is unused.
    /// This test enqueues ONE and asserts the guard never even consumes
    /// the second — tighter pin on the transport script contract.
    func testRapidDoubleTapConnectOnlyInvokesPipelineOnce() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        enqueueHappyPath(transport)   // ONE pipeline worth of responses
        let completions = CounterBox()
        let vm = makeViewModel(store: store, transport: transport,
                               onComplete: { completions.count += 1 })
        vm.url = "https://host.ts.net"
        vm.token = "valid-token"

        // Two concurrent calls: the first enters `.connecting` before any
        // suspension, the second sees that state and early-returns.
        async let first: Void = vm.connect()
        async let second: Void = vm.connect()
        _ = await (first, second)

        XCTAssertEqual(vm.state, .complete)
        XCTAssertEqual(store.saveCount, 1,
                       "rapid double-tap must save exactly once")
        XCTAssertEqual(completions.count, 1,
                       "onComplete must fire exactly once")
        XCTAssertEqual(transport.callCount, 2,
                       "exactly one version + one pull — no duplicate requests")
        XCTAssertEqual(transport.paths, ["/api/version", "/api/sync/pull"],
                       "paths pinned so a future change that re-orders or adds calls fails here")
    }

    // MARK: - Retry

    func testRetryAfterFailureCanSucceed() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()

        // First attempt: 401.
        transport.enqueue(.response(HTTPResponse(status: 401, body: Data())))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "bad"
        await vm.connect()
        XCTAssertEqual(vm.state, .failed(reason: .tokenRejected))

        // User fixes the token and retries.
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"server_version":"0.0.1"}"#.utf8)
        )))
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"server_time":"2026-04-17T19:04:22Z","workouts":[{}],"exercises":[{},{}],"user_parameters_latest":{},"last_performed":[]}"#.utf8)
        )))
        vm.token = "good"
        await vm.retry()

        XCTAssertEqual(vm.state, .complete)
        XCTAssertEqual(store.saved?.token, "good")
    }

    // MARK: - Helpers

    private func makeViewModel(
        store: FakeTokenStore,
        transport: FakeHTTPTransport,
        onComplete: @escaping @Sendable () -> Void = {}
    ) -> FirstRunViewModel {
        FirstRunViewModel(
            tokenStore: store,
            transportBuilder: { _ in transport },
            onComplete: onComplete
        )
    }
}

// File-scope helpers — kept out of the test class so it stays under
// SwiftLint's `type_body_length` cap.

private func enqueueHappyPath(_ transport: FakeHTTPTransport) {
    transport.enqueue(.response(HTTPResponse(
        status: 200,
        body: Data(#"{"server_version":"0.0.1"}"#.utf8)
    )))
    transport.enqueue(.response(HTTPResponse(
        status: 200,
        body: Data(#"{"server_time":"2026-04-17T19:04:22Z","workouts":[],"exercises":[],"user_parameters_latest":{},"last_performed":[]}"#.utf8)
    )))
}

/// Mutable counter used by the re-entrancy test.
private final class CounterBox: @unchecked Sendable {
    var count = 0
}
