// LastPerformedStore.swift
//
// On-device cache for the pre-formatted "LAST · …" summary strings the
// server piggybacks on `GET /api/sync/pull` (see `docs/sync.md` §
// "Pull protocol" and ADR-2026-04-17-ux-scope § 3). One `[UUID: String]`
// map keyed by exerciseID — the value is exactly what Today's "LAST TIME"
// chip and SwapSheet's "LAST · …" row render, pre-formatted by the Shell
// composition layer so the UI stays a dumb display path.
//
// Why UserDefaults and not a SwiftData row (mirrors `SyncMetadataStore`):
//   • No schema versioning for a display-only string map.
//   • Not load-bearing if lost — a missing snapshot just hides the chip
//     until the next pull repopulates it. The actual set_log history
//     lives on the server + in the cache's SetLogModel rows; this is a
//     memoised render of the latest row per exercise.
//   • Avoids a new @Model class + migration stage just to surface a
//     handful of display strings.
//
// Shape: JSON-encoded `{ "<uuid-string>": "<summary>", ... }`. Serialized
// as one blob — the whole map is rewritten on every pull (it's at most
// a few dozen entries, one per exercise the user touches) so partial
// updates don't matter. Decode failures surface as an empty map — the
// chip hides rather than crashing the launch path.
//
// Lives in Persistence (not Sync) for the same reason as
// `SyncMetadataStore`: this is on-device state, and Sync is the "talks
// to the server" package. The Shell composition reads this store into
// `TodayContext.lastPerformed` / `WorkoutContext.lastPerformed`.

import Foundation

public protocol LastPerformedStore: Sendable {
    /// The currently-cached per-exercise "LAST · …" summary map. Empty
    /// when no pull has ever succeeded on this device, when the store
    /// has been cleared, or when the previous write landed malformed
    /// JSON (the loader defensively degrades to empty rather than
    /// crashing — losing a display chip is better than losing a launch).
    func load() async -> [UUID: String]

    /// Replace the cached map with `entries`. Writes the full JSON blob;
    /// prior entries not in `entries` are dropped (the server sends the
    /// complete snapshot on every pull, so the write is authoritative).
    func save(_ entries: [UUID: String]) async
}

/// UserDefaults-backed implementation. Thread-safety comes from
/// UserDefaults' own documented guarantees; actor isolation is not needed
/// for a single blob. Matches the pattern used by `SyncMetadataStoreImpl`
/// and `TokenStoreImpl`.
public struct LastPerformedStoreImpl: LastPerformedStore {
    private let key: String
    // UserDefaults is thread-safe per Apple's docs but not Sendable.
    // Mirrors the pattern used by `SyncMetadataStoreImpl`.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(
        key: String = "workoutdb.sync.last_performed",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    public func load() async -> [UUID: String] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        guard let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            // Malformed blob (older shape, truncated write, etc.) — degrade
            // to empty so the UI simply hides the chip until the next pull
            // rewrites the map.
            return [:]
        }
        var out: [UUID: String] = [:]
        out.reserveCapacity(raw.count)
        for (key, value) in raw {
            guard let uuid = UUID(uuidString: key) else { continue }
            out[uuid] = value
        }
        return out
    }

    public func save(_ entries: [UUID: String]) async {
        var raw: [String: String] = [:]
        raw.reserveCapacity(entries.count)
        for (uuid, value) in entries {
            raw[uuid.uuidString] = value
        }
        guard let data = try? JSONEncoder().encode(raw) else {
            // Encoding a `[String: String]` shouldn't fail under any
            // realistic input, but swallowing the error is consistent
            // with the rest of the metadata-store path: display-only
            // state never blocks the caller.
            return
        }
        defaults.set(data, forKey: key)
    }
}
