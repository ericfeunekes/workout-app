// Fakes.swift
//
// Test doubles for `TokenStore` and `HTTPTransport` that stay local to the
// FirstRun test target — Persistence's internal `FakeTokenStore` isn't
// exposed, and Sync's `FakeTransport` lives in an executable test target
// we can't depend on from another package.

import Foundation
import Sync
import Persistence

/// In-memory TokenStore. Records the last save, returns whatever was
/// saved on load, clears state on clear. No Keychain, no UserDefaults.
final class FakeTokenStore: @unchecked Sendable, TokenStore {
    /// Last `(url, token)` pair passed to `saveConnection`. `nil` when no
    /// save has occurred.
    var saved: (url: URL, token: String)?
    /// Total number of `saveConnection` calls. The re-entrancy test uses
    /// this to assert that concurrent `connect()` calls produce exactly
    /// one save, not two.
    var saveCount: Int = 0
    /// Swap to `true` if a test needs to simulate a Keychain write that
    /// blows up. None of the shipping tests exercise this path yet.
    var shouldThrowOnSave = false

    func saveConnection(url: URL, token: String) throws {
        if shouldThrowOnSave {
            throw NSError(domain: "FakeTokenStore", code: 1)
        }
        saved = (url, token)
        saveCount += 1
    }

    func loadConnection() throws -> (url: URL, token: String)? {
        saved
    }

    func clear() throws {
        saved = nil
    }
}

/// Scripted HTTPTransport. FIFO queue of outcomes; unscripted calls fall
/// through to a generic 200 empty-body response so a test that forgets to
/// enqueue won't hang.
final class FakeHTTPTransport: @unchecked Sendable, HTTPTransport {
    /// Outcomes the transport will return in order.
    enum Outcome {
        case response(HTTPResponse)
        case throwError(SyncError)
    }

    private var script: [Outcome] = []
    private(set) var paths: [String] = []
    var callCount: Int { paths.count }

    func enqueue(_ outcome: Outcome) {
        script.append(outcome)
    }

    func get(
        path: String,
        query: [(String, String)],
        bearerToken: String
    ) async throws -> HTTPResponse {
        paths.append(path)
        return try resolve()
    }

    func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse {
        paths.append(path)
        return try resolve()
    }

    private func resolve() throws -> HTTPResponse {
        guard !script.isEmpty else {
            return HTTPResponse(status: 200, body: Data())
        }
        switch script.removeFirst() {
        case .response(let r): return r
        case .throwError(let e): throw e
        }
    }
}
