// AuthRecoveryStore.swift
//
// Tiny durable marker for token-rejected recovery. Credentials stay in
// TokenStore so FirstRun can prefill them, but launch must know not to
// immediately retry a connection that already returned 401.

import Foundation

public protocol AuthRecoveryStore: Sendable {
    func isTokenRejected() -> Bool
    func markTokenRejected()
    func clearTokenRejected()
}

public struct AuthRecoveryStoreImpl: AuthRecoveryStore {
    private let key: String
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(
        key: String = "workoutdb.auth.token_rejected",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    public func isTokenRejected() -> Bool {
        defaults.bool(forKey: key)
    }

    public func markTokenRejected() {
        defaults.set(true, forKey: key)
    }

    public func clearTokenRejected() {
        defaults.removeObject(forKey: key)
    }
}
