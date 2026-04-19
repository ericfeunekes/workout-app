// FirstRunViewModelTests.swift
//
// Exercises the FirstRunViewModel state machine end-to-end with a fake
// TokenStore + FakeHTTPTransport. No URLSession round-trips, no SwiftData
// — the point is to prove the state transitions and side effects match
// the contract in `docs/sync.md` § "First-run UX".
//
// Scope boundary: FirstRun only fires `GET /api/version`. The first
// `GET /api/sync/pull` is AppBootstrap's job (see the file header on
// `FirstRunViewModel.swift` for why). These tests therefore assert that
// the ONLY transport call during `connect()` is `/api/version` — no
// second pull-from-FirstRun path exists.

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
        // Only one call — FirstRun no longer fires `/api/sync/pull`. The
        // first pull lives in AppBootstrap; that's the whole point of the
        // scope-boundary comment in `FirstRunViewModel.swift`.
        XCTAssertEqual(transport.callCount, 1)
        XCTAssertEqual(transport.paths, ["/api/version"])
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
        XCTAssertEqual(transport.callCount, 1)
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

    // MARK: - Decode failure on /api/version

    /// Version endpoint returns a 200 with a body that doesn't match the
    /// expected VersionProbe shape. FirstRun flips to `.decode` — "this
    /// URL answered but it's not a workoutdb server." Previously this
    /// test covered the equivalent case on `/api/sync/pull`; now that the
    /// pull is gone, the only decode path left is the version probe.
    func testConnectWithDecodeFailureOnVersionYieldsDecode() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()

        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data("not json".utf8)
        )))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .decode))
        XCTAssertNil(store.saved)
    }

    /// qa-038 regression: a server that answers 200 on `/api/version`
    /// with valid JSON but the WRONG shape (no `server_version`,
    /// `applied_migrations`, or `schema_version`) must surface as
    /// `.decode`. Previously the probe had an all-optional shape so
    /// `{"hello":"world"}` decoded successfully and the user landed on
    /// a bootstrapped-but-empty app with no banner.
    ///
    /// Scenarios this catches:
    ///   • Reverse-proxy misconfig that points at a different app's
    ///     health endpoint.
    ///   • A prior-generation server that answered `/api/version` with
    ///     a different shape entirely.
    ///   • Any arbitrary JSON body at the target URL that happens to
    ///     200 and 401-gate the bearer.
    func testConnectRejectsWrongShapeServer() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()

        // Wrong-shape body: valid JSON, 200 OK, valid bearer — but no
        // WorkoutDB discriminator fields. Must decode-fail.
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"hello":"world"}"#.utf8)
        )))

        let vm = makeViewModel(store: store, transport: transport)
        vm.url = "https://host.ts.net"
        vm.token = "tok"

        await vm.connect()

        XCTAssertEqual(vm.state, .failed(reason: .decode))
        XCTAssertNil(store.saved,
                     "wrong-shape server must not persist a connection")
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
    /// second time — duplicate Keychain writes.
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
        XCTAssertEqual(transport.callCount, 1)
    }

    /// Bug-018 regression: rapid double-tap of the "connect" button must
    /// only run the version → persist pipeline once. The scripted
    /// transport enqueues a SINGLE happy path; if the guard regressed and
    /// the second call fell through, the second `GET /api/version` would
    /// hit the empty script tail — call count would jump to 2, not 1.
    ///
    /// The user-visible fix is belt-and-braces: `connect()` short-circuits
    /// when `state ∈ {.connecting, .complete}` AND the view's connect
    /// button binds `.disabled(viewModel.isConnectInFlight)` so the UI
    /// can't dispatch a second call mid-flight. This test pins the
    /// VM-level guard; a ViewInspector-style test would pin the view.
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
        XCTAssertEqual(transport.callCount, 1,
                       "exactly one /api/version — the first pull is AppBootstrap's job")
        XCTAssertEqual(transport.paths, ["/api/version"],
                       "paths pinned so a future change that re-adds the pull here fails")
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
        enqueueHappyPath(transport)
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

/// Queues exactly one successful `/api/version` response. FirstRun no
/// longer calls `/api/sync/pull`, so the happy-path script is a single
/// 200 now.
///
/// qa-038: the body must carry the full WorkoutDB handshake shape
/// (`schema_version` + `server_version` + `applied_migrations`) or the
/// strict decode in `VersionProbe` fails. `schema_version` is modeled
/// as `str | None` on the server so we keep it null here to exercise
/// that leniency — the key's presence, not its value, is load-bearing.
private func enqueueHappyPath(_ transport: FakeHTTPTransport) {
    transport.enqueue(.response(HTTPResponse(
        status: 200,
        body: Data(#"{"schema_version":null,"server_version":"0.0.1","applied_migrations":[]}"#.utf8)
    )))
}

/// Mutable counter used by the re-entrancy test.
private final class CounterBox: @unchecked Sendable {
    var count = 0
}
