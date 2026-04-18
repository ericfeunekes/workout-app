// TokenStore.swift
//
// Keychain-backed bearer token + UserDefaults-backed server URL. The pair
// lives together because the app either has a usable connection (URL +
// token) or doesn't (first-run state). Splitting them would leak the
// intermediate "URL but no token" state into every call site.
//
// Keychain item shape:
//   • `kSecClass`              = `kSecClassGenericPassword`
//   • `kSecAttrService`        = configurable service name (default
//                                 `com.ericfeunekes.WorkoutDB.token`). Tests
//                                 override this to avoid bleed between runs.
//   • `kSecAttrAccount`        = `bearer`
//   • `kSecValueData`          = the bearer token as UTF-8 bytes.
//
// UserDefaults key: `workoutdb.server.url` (absolute string form). Kept in
// UserDefaults rather than Keychain because the URL is not a secret — only
// the paired token is sensitive, and Tailscale already gates network-layer
// access to the server.

import Foundation
import Security

public protocol TokenStore: Sendable {
    func saveConnection(url: URL, token: String) throws
    func loadConnection() throws -> (url: URL, token: String)?
    func clear() throws
}

public struct TokenStoreImpl: TokenStore {
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
        try writeKeychain(token: token)
    }

    public func loadConnection() throws -> (url: URL, token: String)? {
        guard let urlString = defaults.string(forKey: urlDefaultsKey),
              let url = URL(string: urlString) else {
            return nil
        }
        guard let token = try readKeychain() else {
            return nil
        }
        return (url, token)
    }

    public func clear() throws {
        defaults.removeObject(forKey: urlDefaultsKey)
        try deleteKeychain()
    }

    // MARK: - Keychain ops

    private func writeKeychain(token: String) throws {
        let data = Data(token.utf8)
        // Prefer update; fall back to add. Avoids leaving multiple items in
        // the login keychain with the same service/account pair.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
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
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw PersistenceError.keychain(addStatus)
        }
    }

    private func readKeychain() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw PersistenceError.keychain(status) }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    private func deleteKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw PersistenceError.keychain(status)
    }
}
