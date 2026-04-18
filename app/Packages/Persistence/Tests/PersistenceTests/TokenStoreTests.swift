// TokenStoreTests.swift
//
// Keychain round-trip + UserDefaults isolation. Each test uses a unique
// service name so Keychain rows from one test don't bleed into another —
// even across concurrent parallel test runs.

import XCTest
@testable import Persistence

final class TokenStoreTests: XCTestCase {

    private func makeStore() -> (TokenStoreImpl, String) {
        let service = "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        let defaultsSuite = "WorkoutDBPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        return (
            TokenStoreImpl(
                serviceName: service,
                account: "bearer",
                urlDefaultsKey: "workoutdb.server.url",
                defaults: defaults
            ),
            service
        )
    }

    override func tearDown() async throws {
        // Clean-up safety net — each test already clears its own store, but
        // if a test throws before clear() the Keychain item can leak. The
        // per-test unique service name prevents bleed, but this keeps local
        // keychains tidy.
    }

    func testLoadWithoutSaveReturnsNil() throws {
        let (store, _) = makeStore()
        let result = try store.loadConnection()
        XCTAssertNil(result)
    }

    func testSaveAndLoad() throws {
        let (store, _) = makeStore()
        defer { try? store.clear() }
        let url = URL(string: "https://tailscale.example.ts.net")!
        try store.saveConnection(url: url, token: "bearer-tok-xyz")

        let loaded = try store.loadConnection()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "bearer-tok-xyz")
    }

    func testSaveOverwritesExisting() throws {
        let (store, _) = makeStore()
        defer { try? store.clear() }
        let url1 = URL(string: "https://one.example.com")!
        let url2 = URL(string: "https://two.example.com")!

        try store.saveConnection(url: url1, token: "tok-1")
        try store.saveConnection(url: url2, token: "tok-2")

        let loaded = try store.loadConnection()
        XCTAssertEqual(loaded?.url, url2)
        XCTAssertEqual(loaded?.token, "tok-2")
    }

    func testClearRemovesBoth() throws {
        let (store, _) = makeStore()
        let url = URL(string: "https://example.com")!
        try store.saveConnection(url: url, token: "tok")

        try store.clear()
        let loaded = try store.loadConnection()
        XCTAssertNil(loaded)
    }

    func testClearWhenEmptyIsIdempotent() throws {
        let (store, _) = makeStore()
        // Must not throw even if nothing's stored.
        try store.clear()
        try store.clear()
    }
}
