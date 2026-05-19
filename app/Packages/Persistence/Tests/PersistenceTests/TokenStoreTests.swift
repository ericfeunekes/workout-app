// TokenStoreTests.swift
//
// TokenStore payload, migration, and UserDefaults mirror behavior. These tests
// use an in-memory Keychain client so pre-QA proves TokenStore logic without
// depending on a macOS SwiftPM Keychain environment.

import XCTest
@testable import Persistence

final class TokenStoreTests: XCTestCase {

    private func makeStore() -> (TokenStoreImpl, InMemoryTokenStoreKeychainClient, String, String) {
        let service = "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        let defaultsSuite = "WorkoutDBPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        let keychain = InMemoryTokenStoreKeychainClient()
        return (
            TokenStoreImpl(
                serviceName: service,
                account: "bearer",
                urlDefaultsKey: "workoutdb.server.url",
                defaults: defaults,
                keychainClient: keychain
            ),
            keychain,
            service,
            defaultsSuite
        )
    }

    private func makeStore(
        service: String,
        defaultsSuite: String,
        keychain: InMemoryTokenStoreKeychainClient
    ) -> TokenStoreImpl {
        TokenStoreImpl(
            serviceName: service,
            account: "bearer",
            urlDefaultsKey: "workoutdb.server.url",
            defaults: UserDefaults(suiteName: defaultsSuite) ?? .standard,
            keychainClient: keychain
        )
    }

    override func tearDown() async throws {
        // Clean-up safety net — each test already clears its own store, but
        // if a test throws before clear() the Keychain item can leak. The
        // per-test unique service name prevents bleed, but this keeps local
        // keychains tidy.
    }

    func testLoadWithoutSaveReturnsNil() throws {
        let (store, _, _, _) = makeStore()
        let result = try store.loadConnection()
        XCTAssertNil(result)
    }

    func testSaveAndLoad() throws {
        let (store, _, _, _) = makeStore()
        defer { try? store.clear() }
        let url = URL(string: "https://tailscale.example.ts.net")!
        try store.saveConnection(url: url, token: "bearer-tok-xyz")

        let loaded = try store.loadConnection()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "bearer-tok-xyz")
    }

    func testSaveOverwritesExisting() throws {
        let (store, _, _, _) = makeStore()
        defer { try? store.clear() }
        let url1 = URL(string: "https://one.example.com")!
        let url2 = URL(string: "https://two.example.com")!

        try store.saveConnection(url: url1, token: "tok-1")
        try store.saveConnection(url: url2, token: "tok-2")

        let loaded = try store.loadConnection()
        XCTAssertEqual(loaded?.url, url2)
        XCTAssertEqual(loaded?.token, "tok-2")
    }

    func testSaveAndLoadSurvivesDefaultsLoss() throws {
        let (store, keychain, service, _) = makeStore()
        defer { try? store.clear() }
        let url = URL(string: "http://100.106.10.41:8080")!
        try store.saveConnection(url: url, token: "durable-token")

        let reinstallStore = makeStore(
            service: service,
            defaultsSuite: "WorkoutDBPersistenceTests.reinstall.\(UUID().uuidString)",
            keychain: keychain
        )
        let loaded = try reinstallStore.loadConnection()

        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "durable-token")
    }

    func testLegacyTokenAndDefaultsMigratesToDurablePayload() throws {
        let (store, keychain, service, defaultsSuite) = makeStore()
        defer { try? store.clear() }
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        let url = URL(string: "https://legacy.example.com")!
        defaults.set(url.absoluteString, forKey: "workoutdb.server.url")
        try keychain.write(data: Data("legacy-token".utf8), serviceName: service, account: "bearer")

        let loaded = try store.loadConnection()
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "legacy-token")

        let reinstallStore = makeStore(
            service: service,
            defaultsSuite: "WorkoutDBPersistenceTests.legacy-reinstall.\(UUID().uuidString)",
            keychain: keychain
        )
        let migrated = try reinstallStore.loadConnection()
        XCTAssertEqual(migrated?.url, url)
        XCTAssertEqual(migrated?.token, "legacy-token")
    }

    func testClearRemovesBoth() throws {
        let (store, _, _, _) = makeStore()
        let url = URL(string: "https://example.com")!
        try store.saveConnection(url: url, token: "tok")

        try store.clear()
        let loaded = try store.loadConnection()
        XCTAssertNil(loaded)
    }

    func testClearWhenEmptyIsIdempotent() throws {
        let (store, _, _, _) = makeStore()
        // Must not throw even if nothing's stored.
        try store.clear()
        try store.clear()
    }
}

final class InMemoryTokenStoreKeychainClient: TokenStoreKeychainClient, @unchecked Sendable {
    private var storage: [Key: Data] = [:]

    func write(data: Data, serviceName: String, account: String) throws {
        storage[Key(serviceName: serviceName, account: account)] = data
    }

    func read(serviceName: String, account: String) throws -> Data? {
        storage[Key(serviceName: serviceName, account: account)]
    }

    func delete(serviceName: String, account: String) throws {
        storage.removeValue(forKey: Key(serviceName: serviceName, account: account))
    }

    private struct Key: Hashable {
        var serviceName: String
        var account: String
    }
}
