// Fakes.swift
//
// In-memory doubles for the three store protocols the SettingsViewModel
// depends on. Kept local to this test target — sibling Features do the
// same rather than trying to share a single `TestSupport` product.

import Foundation
import Persistence
@testable import FeaturesSettings

/// In-memory TokenStore. Records the last save, returns whatever was
/// saved on load, clears state on clear. No Keychain, no UserDefaults.
final class FakeTokenStore: @unchecked Sendable, TokenStore {
    var saved: (url: URL, token: String)?
    /// Flips to `true` if a test wants `loadConnection` to throw.
    var shouldThrowOnLoad = false
    /// How many times `clear()` was invoked.
    private(set) var clearCount = 0

    init(initial: (url: URL, token: String)? = nil) {
        self.saved = initial
    }

    func saveConnection(url: URL, token: String) throws {
        saved = (url, token)
    }

    func loadConnection() throws -> (url: URL, token: String)? {
        if shouldThrowOnLoad {
            throw NSError(domain: "FakeTokenStore", code: 1)
        }
        return saved
    }

    func clear() throws {
        clearCount += 1
        saved = nil
    }
}

/// In-memory autoreg defaults store. Starts with factory defaults; tests
/// can seed it with a different value to verify the viewModel reads
/// through.
final class FakeAutoregStore: @unchecked Sendable, AutoregDefaultsStore {
    var current: AutoregDefaults
    private(set) var resetCount = 0

    init(current: AutoregDefaults = AutoregDefaults()) {
        self.current = current
    }

    func load() -> AutoregDefaults { current }

    func resetToDefaults() {
        resetCount += 1
        current = AutoregDefaults()
    }
}

/// In-memory units preference store.
final class FakeUnitsStore: @unchecked Sendable, UnitsPreferenceStore {
    var current: UnitsPreference
    private(set) var saveCount = 0

    init(current: UnitsPreference = .kg) {
        self.current = current
    }

    func load() -> UnitsPreference { current }

    func save(_ units: UnitsPreference) {
        saveCount += 1
        current = units
    }
}

/// In-memory sync metadata store. Holds a single `lastSyncAt` value so
/// tests can pin what the "last synced" row renders without touching
/// UserDefaults.
final class FakeSyncMetadataStore: @unchecked Sendable, SyncMetadataStore {
    var lastSyncAt: Date?
    private(set) var setCount = 0

    init(lastSyncAt: Date? = nil) {
        self.lastSyncAt = lastSyncAt
    }

    func getLastSyncAt() async -> Date? { lastSyncAt }

    func setLastSyncAt(_ date: Date) async {
        setCount += 1
        lastSyncAt = date
    }

    func clearLastSyncAt() async {
        lastSyncAt = nil
    }
}

final class FakeHealthArchiveExportStateStore: @unchecked Sendable, HealthArchiveExportStateStore {
    var snapshot: HealthArchiveExportSnapshot
    var setScopeDelayNanoseconds: UInt64 = 0
    private(set) var loadedNamespaces: [String?] = []
    private(set) var setScopeCallCount = 0

    init(snapshot: HealthArchiveExportSnapshot = HealthArchiveExportSnapshot()) {
        self.snapshot = snapshot
    }

    func loadSnapshot(serverNamespace: String?) async -> HealthArchiveExportSnapshot {
        loadedNamespaces.append(serverNamespace)
        return HealthArchiveExportSnapshot(
            scope: snapshot.scope,
            serverNamespace: serverNamespace ?? snapshot.serverNamespace,
            requestSetKey: snapshot.requestSetKey,
            descriptorFingerprint: snapshot.descriptorFingerprint,
            acknowledgedCursor: snapshot.acknowledgedCursor,
            status: snapshot.status,
            lastFetchAt: snapshot.lastFetchAt,
            lastUploadAt: snapshot.lastUploadAt,
            lastRecordCount: snapshot.lastRecordCount,
            lastTombstoneCount: snapshot.lastTombstoneCount,
            lastFailureClass: snapshot.lastFailureClass,
            automaticEnabled: snapshot.automaticEnabled,
            nextAttemptAt: snapshot.nextAttemptAt,
            lastAttemptAt: snapshot.lastAttemptAt
        )
    }

    func saveSnapshot(_ snapshot: HealthArchiveExportSnapshot) async {
        self.snapshot = snapshot
    }

    func setScope(_ scope: HealthArchiveExportScope) async {
        setScopeCallCount += 1
        if setScopeDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: setScopeDelayNanoseconds)
        }
        snapshot = HealthArchiveExportSnapshot(
            scope: scope,
            automaticEnabled: snapshot.automaticEnabled,
            nextAttemptAt: snapshot.nextAttemptAt
        )
    }

    func setAutomaticEnabled(_ enabled: Bool) async {
        snapshot = HealthArchiveExportSnapshot(
            scope: snapshot.scope,
            automaticEnabled: enabled,
            nextAttemptAt: snapshot.nextAttemptAt
        )
    }

    func clear() async {
        snapshot = HealthArchiveExportSnapshot()
    }
}
