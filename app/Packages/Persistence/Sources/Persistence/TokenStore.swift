// TokenStore.swift
//
// Keychain-backed server connection. The URL and bearer token live as one
// payload because the app either has a usable connection or doesn't
// (first-run state). Keeping the whole pair in Keychain means it survives
// app reinstalls on the same device; `UserDefaults` is only a compatibility
// mirror for older installs and diagnostics.
//
// Keychain item shape:
//   • `kSecClass`              = `kSecClassGenericPassword`
//   • `kSecAttrService`        = configurable service name (default
//                                 `com.ericfeunekes.WorkoutDB.token`). Tests
//                                 override this to avoid bleed between runs.
//   • `kSecAttrAccount`        = `bearer`
//   • `kSecValueData`          = JSON `{version, url, token}` as UTF-8 bytes.
//
// Legacy shape: earlier builds stored only the raw bearer token in Keychain
// and `workoutdb.server.url` in UserDefaults. `loadConnection()` still reads
// that pair and rewrites it into the durable Keychain payload.

import Foundation
import Security

public protocol TokenStore: Sendable {
    func saveConnection(url: URL, token: String) throws
    func loadConnection() throws -> (url: URL, token: String)?
    func clear() throws
}

public struct TokenStoreImpl: TokenStore {
    private struct StoredConnection: Codable {
        var version: Int
        var url: String
        var token: String
    }

    private let serviceName: String
    private let account: String
    private let urlDefaultsKey: String
    // UserDefaults is documented as thread-safe by Apple but does not carry
    // a Sendable conformance. `nonisolated(unsafe)` reflects the runtime
    // reality — UserDefaults atomically reads/writes and tolerates calls
    // from any thread. See `TokenStoreImpl` init where the default is
    // `UserDefaults.standard`, the same instance every call site uses.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(
        serviceName: String = "com.ericfeunekes.WorkoutDB.token",
        account: String = "bearer",
        urlDefaultsKey: String = "workoutdb.server.url",
        defaults: UserDefaults = .standard
    ) {
        self.serviceName = serviceName
        self.account = account
        self.urlDefaultsKey = urlDefaultsKey
        self.defaults = defaults
    }

    public func saveConnection(url: URL, token: String) throws {
        defaults.set(url.absoluteString, forKey: urlDefaultsKey)
        try writeKeychain(connection: StoredConnection(
            version: 1,
            url: url.absoluteString,
            token: token
        ))
    }

    public func loadConnection() throws -> (url: URL, token: String)? {
        guard let data = try readKeychainData() else {
            return nil
        }

        if let stored = try? JSONDecoder().decode(StoredConnection.self, from: data),
           let url = URL(string: stored.url) {
            defaults.set(stored.url, forKey: urlDefaultsKey)
            return (url, stored.token)
        }

        guard let legacyToken = String(data: data, encoding: .utf8),
              let urlString = defaults.string(forKey: urlDefaultsKey),
              let url = URL(string: urlString) else {
            return nil
        }

        try writeKeychain(connection: StoredConnection(
            version: 1,
            url: url.absoluteString,
            token: legacyToken
        ))

        return (url, legacyToken)
    }

    public func clear() throws {
        defaults.removeObject(forKey: urlDefaultsKey)
        try deleteKeychain()
    }

    // MARK: - Keychain ops

    private func writeKeychain(connection: StoredConnection) throws {
        let data = try JSONEncoder().encode(connection)
        try writeKeychain(data: data)
    }

    private func writeKeychain(data: Data) throws {
        // Prefer update; fall back to add. Avoids leaving multiple items in
        // the login keychain with the same service/account pair.
        let query = keychainQuery()
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw PersistenceError.keychain(updateStatus)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw PersistenceError.keychain(addStatus)
        }
    }

    private func readKeychainData() throws -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw PersistenceError.keychain(status) }
        return result as? Data
    }

    private func deleteKeychain() throws {
        let status = SecItemDelete(keychainQuery() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw PersistenceError.keychain(status)
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
    }
}
