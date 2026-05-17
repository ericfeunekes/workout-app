// AppSyncLocalStateReset.swift
//
// Local device-state reset helpers for app-sync recovery. SyncAPI owns
// transport; Persistence owns stores. Shell owns the policy that a server
// identity change or token-rejection recovery must invalidate cached server
// data and the sync cursor together.

import Foundation
import Persistence

@MainActor
public enum AppSyncLocalStateReset {

    public static func clearCachedServerData(
        persistence: PersistenceFactory
    ) async {
        try? await persistence.workoutCache.clear()
        await persistence.syncMetadataStore.clearLastSyncAt()
    }

    public static func clearConnectionAndCachedServerData(
        persistence: PersistenceFactory
    ) async {
        try? persistence.tokenStore.clear()
        await clearCachedServerData(persistence: persistence)
    }
}
