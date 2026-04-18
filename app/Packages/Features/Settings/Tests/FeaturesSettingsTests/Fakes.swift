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
