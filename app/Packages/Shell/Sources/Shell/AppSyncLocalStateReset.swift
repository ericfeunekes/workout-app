// AppSyncLocalStateReset.swift
//
// Local device-state reset helpers for app-sync recovery. SyncAPI owns
// transport; Persistence owns stores. Shell owns the policy that a server
// identity change or explicit local reset must destructively recreate
// server-owned local state. Token rejection pauses sync for reauth; the
// successful reconnect path then clears QA server-owned state and rebuilds
// from the selected server. Local projections whose source of truth is not
// the server are preserved.

import Foundation
import Persistence

public enum AppSyncLocalStateResetResult: Equatable, Sendable {
    case success
    case failure(String)

    public var succeeded: Bool {
        self == .success
    }
}

@MainActor
public enum AppSyncLocalStateReset {

    @discardableResult
    public static func clearLocalServerData(
        persistence: PersistenceFactory
    ) async -> AppSyncLocalStateResetResult {
        await clearLocalState(
            clearWorkoutCache: { try await persistence.workoutCache.clear() },
            clearSession: { try await persistence.sessionStore.clear() },
            clearLastPerformed: { await persistence.lastPerformedStore.clear() },
            clearWorkoutKitHandoffAttempts: {
                await persistence.workoutKitHandoffAttemptStore.clear()
            },
            clearPushQueue: { try await persistence.pushQueueStore.clear() },
            clearSyncCursor: { await persistence.syncMetadataStore.clearLastSyncAt() },
            clearTokenRejected: { persistence.authRecoveryStore.clearTokenRejected() },
            clearToken: nil
        )
    }

    @discardableResult
    public static func clearConnectionAndLocalServerData(
        persistence: PersistenceFactory
    ) async -> AppSyncLocalStateResetResult {
        await clearLocalState(
            clearWorkoutCache: { try await persistence.workoutCache.clear() },
            clearSession: { try await persistence.sessionStore.clear() },
            clearLastPerformed: { await persistence.lastPerformedStore.clear() },
            clearWorkoutKitHandoffAttempts: {
                await persistence.workoutKitHandoffAttemptStore.clear()
            },
            clearPushQueue: { try await persistence.pushQueueStore.clear() },
            clearSyncCursor: { await persistence.syncMetadataStore.clearLastSyncAt() },
            clearTokenRejected: { persistence.authRecoveryStore.clearTokenRejected() },
            clearToken: { try persistence.tokenStore.clear() }
        )
    }

    @discardableResult
    public static func pauseForTokenRejected(
        persistence: PersistenceFactory
    ) async -> AppSyncLocalStateResetResult {
        persistence.authRecoveryStore.markTokenRejected()
        return .success
    }

    @discardableResult
    static func clearLocalState(
        clearWorkoutCache: () async throws -> Void,
        clearSession: () async throws -> Void,
        clearLastPerformed: () async -> Void,
        clearWorkoutKitHandoffAttempts: () async -> Void,
        clearPushQueue: () async throws -> Void,
        clearSyncCursor: () async -> Void,
        clearTokenRejected: () async -> Void,
        clearToken: (() throws -> Void)?
    ) async -> AppSyncLocalStateResetResult {
        do {
            await clearSyncCursor()
            try await clearWorkoutCache()
            try await clearSession()
            await clearLastPerformed()
            await clearWorkoutKitHandoffAttempts()
            try await clearPushQueue()
            try clearToken?()
        } catch {
            return .failure(String(describing: error))
        }
        await clearTokenRejected()
        return .success
    }
}
