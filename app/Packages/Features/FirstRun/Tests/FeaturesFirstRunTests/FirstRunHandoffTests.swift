// FirstRunHandoffTests.swift
//
// Pins the scope-boundary behaviour introduced when FirstRun stopped
// firing `/api/sync/pull` itself. The first pull — the one that
// populates the cache — is AppBootstrap's job; FirstRun only validates
// credentials via `/api/version`.
//
// Why the bug this forecloses mattered:
//   Before the fix, FirstRun ran a pull AND AppBootstrap ran a pull.
//   If FirstRun's pull succeeded but AppBootstrap's follow-up pull later
//   failed (non-401), the user would land on `.empty` despite having
//   valid creds — stranded with no way back to FirstRun to pick a
//   different server. Eliminating FirstRun's duplicate pull removes the
//   stranding hazard at the root.
//
// Pair with `AppBootstrapPullOwnershipTests` in the Shell test target:
// together they assert "FirstRun makes zero pull calls AND AppBootstrap
// makes exactly one."
//
// Split into its own file so `FirstRunViewModelTests`'s class body
// stays under SwiftLint's `type_body_length` cap.

import XCTest
import Foundation
import Sync
import Persistence
@testable import FeaturesFirstRun

@MainActor
final class FirstRunHandoffTests: XCTestCase {

    /// Pins that FirstRun produces exactly one network call per connect
    /// attempt — the `/api/version` handshake. Re-adding a pull to
    /// FirstRun would bump `callCount` to 2 and fail this assertion.
    func testFirstRunHandsOffToBootstrapWithoutSecondPull() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"server_version":"0.0.1"}"#.utf8)
        )))
        let vm = FirstRunViewModel(
            tokenStore: store,
            transportBuilder: { _ in transport },
            onComplete: {}
        )
        vm.url = "https://host.ts.net"
        vm.token = "tok"
        await vm.connect()
        XCTAssertEqual(vm.state, .complete)
        // The critical assertion: FirstRun fired one and only one HTTP
        // call (the version handshake). AppBootstrap owns the first pull.
        XCTAssertEqual(transport.callCount, 1,
                       "FirstRun must not duplicate AppBootstrap's first /api/sync/pull")
        XCTAssertEqual(transport.paths, ["/api/version"])
    }

    // MARK: - Pre-fill (change-server recovery route)

    /// When `.empty` routes back to FirstRun via "change server," the
    /// shell passes the previously-entered URL + token as `initialURL` /
    /// `initialToken` so Eric doesn't retype. The view binds these via
    /// `@Bindable` on the view model, so we verify the VM's publicly
    /// observable `url` / `token` are set at init time.
    func testPrefillPopulatesURLAndTokenAtInit() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        let vm = FirstRunViewModel(
            tokenStore: store,
            transportBuilder: { _ in transport },
            onComplete: {},
            initialURL: "https://old.ts.net",
            initialToken: "old-token"
        )
        XCTAssertEqual(vm.url, "https://old.ts.net")
        XCTAssertEqual(vm.token, "old-token")
        XCTAssertEqual(vm.state, .welcome)
    }

    /// End-to-end: pre-filled VM with edited fields runs through connect
    /// and lands on `.complete` with the edited values persisted. This
    /// is the "change server → edit token → reconnect" path from the
    /// shell's recovery route.
    func testPrefilledConnectReachesCompleteWithEditedValues() async {
        let store = FakeTokenStore()
        let transport = FakeHTTPTransport()
        transport.enqueue(.response(HTTPResponse(
            status: 200,
            body: Data(#"{"server_version":"0.0.1"}"#.utf8)
        )))
        let vm = FirstRunViewModel(
            tokenStore: store,
            transportBuilder: { _ in transport },
            onComplete: {},
            initialURL: "https://old.ts.net",
            initialToken: "old-token"
        )
        // User edits the token before retrying.
        vm.token = "new-token"
        await vm.connect()
        XCTAssertEqual(vm.state, .complete)
        XCTAssertEqual(store.saved?.token, "new-token")
        XCTAssertEqual(store.saved?.url.absoluteString, "https://old.ts.net")
    }
}
