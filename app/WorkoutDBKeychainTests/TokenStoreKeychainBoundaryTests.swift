import XCTest
import Security
import Persistence

final class TokenStoreKeychainBoundaryTests: XCTestCase {
    private let account = "bearer"

    func testRealTokenStoreRoundTripsAndClearsConnection() throws {
        let service = serviceName()
        let defaults = defaultsSuite()
        let store = TokenStoreImpl(
            serviceName: service,
            account: account,
            urlDefaultsKey: "workoutdb.server.url",
            defaults: defaults
        )
        defer { try? store.clear() }

        let url = try XCTUnwrap(URL(string: "https://keychain-boundary.example.test"))
        try store.saveConnection(url: url, token: "boundary-token")

        let loaded = try store.loadConnection()
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "boundary-token")

        try store.clear()
        XCTAssertNil(try store.loadConnection())
    }

    func testRealTokenStoreMigratesLegacyTokenAndDefaultsPair() throws {
        let service = serviceName()
        let defaults = defaultsSuite()
        let store = TokenStoreImpl(
            serviceName: service,
            account: account,
            urlDefaultsKey: "workoutdb.server.url",
            defaults: defaults
        )
        defer { try? store.clear() }

        let url = try XCTUnwrap(URL(string: "https://legacy-keychain.example.test"))
        defaults.set(url.absoluteString, forKey: "workoutdb.server.url")
        try writeLegacyToken(service: service, token: "legacy-boundary-token")

        let loaded = try store.loadConnection()
        XCTAssertEqual(loaded?.url, url)
        XCTAssertEqual(loaded?.token, "legacy-boundary-token")

        let reinstallStore = TokenStoreImpl(
            serviceName: service,
            account: account,
            urlDefaultsKey: "workoutdb.server.url",
            defaults: defaultsSuite()
        )
        let migrated = try reinstallStore.loadConnection()
        XCTAssertEqual(migrated?.url, url)
        XCTAssertEqual(migrated?.token, "legacy-boundary-token")
    }

    private func serviceName() -> String {
        "com.ericfeunekes.WorkoutDB.token.boundary.\(UUID().uuidString)"
    }

    private func defaultsSuite() -> UserDefaults {
        UserDefaults(suiteName: "WorkoutDBTokenStoreBoundaryTests.\(UUID().uuidString)") ?? .standard
    }

    private func writeLegacyToken(service: String, token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = Data(token.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
