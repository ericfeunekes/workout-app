// SyncMetadataStore.swift
//
// Holds small key-value sync bookkeeping that doesn't warrant a SwiftData
// row: most importantly `lastSyncAt` — the `serverTime` returned by the
// previous pull, fed back in as `since` on the next pull per
// `docs/sync.md` § "Pull protocol".
//
// Why UserDefaults and not a SwiftData row:
//   • A single `Date?` does not need schema versioning.
//   • The value is not load-bearing if lost — a missing `lastSyncAt` just
//     triggers a full-cache pull next time, which is cheap on a home
//     server over Tailscale.
//   • Keeping it out of SwiftData avoids a new @Model class (and a new
//     migration stage) for one timestamp.
//
// Lives in Persistence (not Sync) because this is on-device state, and
// Sync is the "talks to the server" package. The AppBootstrap composition
// reads this store and passes `lastSyncAt` into `SyncAPI.pullLatest(...)`.

import Foundation

public protocol SyncMetadataStore: Sendable {
    /// Last known server time from a successful pull. `nil` when no pull
    /// has ever succeeded on this device (first-run, cache cleared, or
    /// reinstall).
    func getLastSyncAt() async -> Date?

    /// Record the `serverTime` from a successful pull.
    func setLastSyncAt(_ date: Date) async
}

/// UserDefaults-backed implementation. Thread-safety comes from
/// UserDefaults' own documented guarantees; actor isolation is not needed
/// for a single timestamp.
public struct SyncMetadataStoreImpl: SyncMetadataStore {
    private let key: String
    // UserDefaults is thread-safe per Apple's docs but not Sendable.
    // Mirrors the pattern used by `TokenStoreImpl`.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(
        key: String = "workoutdb.sync.last_sync_at",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    public func getLastSyncAt() async -> Date? {
        defaults.object(forKey: key) as? Date
    }

    public func setLastSyncAt(_ date: Date) async {
        defaults.set(date, forKey: key)
    }
}
