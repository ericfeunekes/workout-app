// TokenStoreTests.swift
//
// Keychain round-trip + UserDefaults isolation. Each test uses a unique
// service name so Keychain rows from one test don't bleed into another —
// even across concurrent parallel test runs.

import XCTest
import Security
@testable import Persistence

final class TokenStoreTests: XCTestCase {

    private func makeStore() -> (TokenStoreImpl, String, String) {
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
            service,
            defaultsSuite
        )
    }

    private func makeStore(
        service: String,
        defaultsSuite: String
    ) -> TokenStoreImpl {
        TokenStoreImpl(
            serviceName: service,
            account: "bearer",
            urlDefaultsKey: "workoutdb.server.url",
            defaults: UserDefaults(suiteName: defaultsSuite) ?? .standard
        )
    }

    override func tearDown() async throws {
        // Clean-up safety net — each test already clears its own store, but
        // if a test throws before clear() the Keychain item can leak. The
        // per-test unique service name prevents bleed, but this keeps local
        // keychains tidy.
    }

    func testLoadWithoutSaveReturnsNil() throws {
        let (store, _, _) = makeStore()
        let result = try store.loadConnection()
        XCTAssertNil(result)
    }

    func testSaveAndLoad() throws {
        let (store, _, _) = makeStore()
        defer { try? store.clear() }
        let url = URL(string: "https://tailscale.example.ts.net")!
        try store.saveConnection(url: url, token: "bearer-tok-xyz")

        let loaded = try store.loadConnection()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "bearer-tok-xyz")
    }

    func testSaveOverwritesExisting() throws {
        let (store, _, _) = makeStore()
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
        let (store, service, _) = makeStore()
        defer { try? store.clear() }
        let url = URL(string: "http://100.106.10.41:8080")!
        try store.saveConnection(url: url, token: "durable-token")

        let reinstallStore = makeStore(
            service: service,
            defaultsSuite: "WorkoutDBPersistenceTests.reinstall.\(UUID().uuidString)"
        )
        let loaded = try reinstallStore.loadConnection()

        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "durable-token")
    }

    func testLegacyTokenAndDefaultsMigratesToDurablePayload() throws {
        let (store, service, defaultsSuite) = makeStore()
        defer { try? store.clear() }
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        let url = URL(string: "https://legacy.example.com")!
        defaults.set(url.absoluteString, forKey: "workoutdb.server.url")
        try writeLegacyToken(service: service, token: "legacy-token")

        let loaded = try store.loadConnection()
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "legacy-token")

        let reinstallStore = makeStore(
            service: service,
            defaultsSuite: "WorkoutDBPersistenceTests.legacy-reinstall.\(UUID().uuidString)"
        )
        let migrated = try reinstallStore.loadConnection()
        XCTAssertEqual(migrated?.url, url)
        XCTAssertEqual(migrated?.token, "legacy-token")
    }

    func testClearRemovesBoth() throws {
        let (store, _, _) = makeStore()
        let url = URL(string: "https://example.com")!
        try store.saveConnection(url: url, token: "tok")

        try store.clear()
        let loaded = try store.loadConnection()
        XCTAssertNil(loaded)
    }

    func testClearWhenEmptyIsIdempotent() throws {
        let (store, _, _) = makeStore()
        // Must not throw even if nothing's stored.
        try store.clear()
        try store.clear()
    }

    private func writeLegacyToken(service: String, token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "bearer",
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
