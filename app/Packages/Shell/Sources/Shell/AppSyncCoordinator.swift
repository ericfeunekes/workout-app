// AppSyncCoordinator.swift
//
// App-level sync policy owner. SyncAPI owns transport mechanics; Persistence
// owns stores. This coordinator is the Shell boundary that decides when a
// foreground pull happens, where pulled rows are written, and when the
// foreground push flusher starts or stops.

import Foundation
import CoreDomain
import CoreTelemetry
import Persistence
import Sync
import WorkoutCoreFoundation

public enum AppSyncTrigger: String, Sendable {
    case bootstrap
    case foreground
    case manualTodayRefresh
    case emptyRetry
}

public enum AppSyncRefreshResult: Equatable, Sendable {
    case pulled(serverTime: Date)
    case fallback(errorDescription: String)
    case tokenRejected
}

public enum AppSyncPushResult: Equatable, Sendable {
    case completed
    case tokenRejected
}

public enum AppSyncLifecycleResult: Equatable, Sendable {
    case foreground(refresh: AppSyncRefreshResult)
    case background
}

public protocol ForegroundPushFlushing: Sendable {
    func start() async
    func stop() async
    func flushNow() async -> AppSyncPushResult
}

public struct PushFlusherAdapter: ForegroundPushFlushing {
    private let flusher: PushFlusher

    public init(flusher: PushFlusher) {
        self.flusher = flusher
    }

    public func start() async {
        await flusher.start()
    }

    public func stop() async {
        await flusher.stop()
    }

    public func flushNow() async -> AppSyncPushResult {
        switch await flusher.flushNow() {
        case .completed:
            return .completed
        case .tokenRejected:
            return .tokenRejected
        }
    }
}

@MainActor
public final class AppSyncCoordinator: Sendable {
    public let syncAPI: SyncAPI
    private let persistence: PersistenceFactory
    private let telemetry: TelemetryEmitter
    private var flusher: (any ForegroundPushFlushing)!
    private let onTokenRejected: (@Sendable @MainActor () async -> Void)?
    private var foregroundRefreshHandler:
        (@Sendable @MainActor (AppSyncTrigger, AppSyncRefreshResult) async -> Void)?
    private var isForegroundFlushing = false
    private var hasStartedFlushing = false
    private var isRetired = false
    private var refreshInFlight: Task<AppSyncRefreshResult, Never>?
    private var foregroundCycle = 0

    public init(
        syncAPI: SyncAPI,
        persistence: PersistenceFactory,
        telemetry: TelemetryEmitter,
        flusher: (any ForegroundPushFlushing)? = nil,
        onTokenRejected: (@Sendable @MainActor () async -> Void)? = nil
    ) {
        self.syncAPI = syncAPI
        self.persistence = persistence
        self.telemetry = telemetry
        self.onTokenRejected = onTokenRejected
        if let flusher {
            self.flusher = flusher
        } else {
            self.flusher = PushFlusherAdapter(flusher: PushFlusher(
                api: syncAPI,
                onTokenRejected: { [weak self] in
                    await self?.handlePushTokenRejected(trigger: .foreground)
                }
            ))
        }
    }

    public func setForegroundRefreshHandler(
        _ handler: (@Sendable @MainActor (AppSyncTrigger, AppSyncRefreshResult) async -> Void)?
    ) {
        foregroundRefreshHandler = handler
    }

    public func refresh(trigger: AppSyncTrigger) async -> AppSyncRefreshResult {
        if let refreshInFlight {
            emitLifecycle(
                kind: "state",
                name: "sync.pull_coalesced",
                trigger: trigger,
                outcome: "coalesced"
            )
            return await refreshInFlight.value
        }
        let task = Task { @MainActor in
            await self.performRefresh(trigger: trigger)
        }
        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        return result
    }

    private func performRefresh(trigger: AppSyncTrigger) async -> AppSyncRefreshResult {
        guard !isRetired else {
            return .fallback(errorDescription: "coordinator retired")
        }
        if trigger == .manualTodayRefresh {
            emitLifecycle(
                kind: "state",
                name: "sync.manual_refresh_started",
                trigger: trigger,
                outcome: "started"
            )
        }
        emitLifecycle(
            kind: "state",
            name: "sync.pull_started",
            trigger: trigger,
            outcome: "started"
        )
        do {
            let lastSyncAt = await persistence.syncMetadataStore.getLastSyncAt()
            let result = try await syncAPI.pullLatest(since: lastSyncAt)
            guard !isRetired else {
                return .fallback(errorDescription: "coordinator retired")
            }
            emitLifecycle(
                kind: "state",
                name: "sync.cache_write_started",
                trigger: trigger,
                sincePresent: lastSyncAt != nil,
                pulledWorkoutCount: result.workouts.count,
                outcome: "started"
            )
            do {
                try await AppBootstrap.savePull(result, into: persistence.workoutCache)
            } catch {
                emitLifecycle(
                    kind: "error",
                    name: "sync.cache_write_failed",
                    trigger: trigger,
                    error: String(describing: error),
                    sincePresent: lastSyncAt != nil,
                    pulledWorkoutCount: result.workouts.count,
                    outcome: "failed"
                )
                throw error
            }
            guard !isRetired else {
                return .fallback(errorDescription: "coordinator retired")
            }
            if !result.lastPerformed.isEmpty {
                let lastPerformedMap = LastPerformedFormatter.buildMap(
                    from: result.lastPerformed
                )
                await persistence.lastPerformedStore.save(lastPerformedMap)
            }
            await persistence.syncMetadataStore.setLastSyncAt(result.serverTime)
            emitLifecycle(
                kind: "state",
                name: "sync.cache_write_succeeded",
                trigger: trigger,
                sincePresent: lastSyncAt != nil,
                pulledWorkoutCount: result.workouts.count,
                outcome: "succeeded"
            )
            emitLifecycle(
                kind: "state",
                name: "sync.pull_succeeded",
                trigger: trigger,
                sincePresent: lastSyncAt != nil,
                pulledWorkoutCount: result.workouts.count,
                outcome: "succeeded"
            )
            if trigger == .manualTodayRefresh {
                emitLifecycle(
                    kind: "state",
                    name: "sync.manual_refresh_completed",
                    trigger: trigger,
                    outcome: "succeeded"
                )
            }
            return .pulled(serverTime: result.serverTime)
        } catch SyncError.tokenRejected {
            await stopFlushing(trigger: trigger, name: "sync.token_rejected")
            emitLifecycle(
                kind: "error",
                name: "sync.pull_token_rejected",
                trigger: trigger,
                outcome: "token_rejected"
            )
            if trigger == .manualTodayRefresh {
                emitLifecycle(
                    kind: "error",
                    name: "sync.manual_refresh_completed",
                    trigger: trigger,
                    error: "tokenRejected",
                    outcome: "token_rejected"
                )
            }
            return .tokenRejected
        } catch {
            emitLifecycle(
                kind: "error",
                name: "sync.pull_failed",
                trigger: trigger,
                error: String(describing: error),
                outcome: "failed"
            )
            if trigger == .manualTodayRefresh {
                emitLifecycle(
                    kind: "error",
                    name: "sync.manual_refresh_completed",
                    trigger: trigger,
                    error: String(describing: error),
                    outcome: "failed"
                )
            }
            return .fallback(errorDescription: String(describing: error))
        }
    }

    public func enterForeground(
        trigger: AppSyncTrigger = .foreground
    ) async -> AppSyncLifecycleResult {
        foregroundCycle += 1
        let cycle = foregroundCycle
        emitLifecycle(
            kind: "state",
            name: "sync.lifecycle_foreground_requested",
            trigger: trigger,
            outcome: "started"
        )
        let result = await refresh(trigger: trigger)
        guard !isRetired, cycle == foregroundCycle else {
            return .foreground(refresh: result)
        }
        if case .pulled = result {
            await foregroundRefreshHandler?(trigger, result)
        }
        if result != .tokenRejected {
            await startFlushing(trigger: trigger)
        }
        return .foreground(refresh: result)
    }

    public func enterBackground() async -> AppSyncLifecycleResult {
        foregroundCycle += 1
        await stopFlushing(trigger: .foreground, name: "sync.lifecycle_background")
        return .background
    }

    @discardableResult
    public func flushNow() async -> AppSyncPushResult {
        emitLifecycle(
            kind: "state",
            name: "sync.flusher_manual_kicked",
            trigger: .foreground,
            outcome: "started"
        )
        let result = await flusher.flushNow()
        if result == .tokenRejected {
            await handlePushTokenRejected(trigger: .foreground)
        }
        return result
    }

    public func startForegroundFlushing(
        trigger: AppSyncTrigger = .foreground
    ) async {
        await startFlushing(trigger: trigger)
    }

    public func stopForegroundFlushing(
        trigger: AppSyncTrigger = .foreground
    ) async {
        await stopFlushing(trigger: trigger)
    }

    public func stopForTokenRejected(trigger: AppSyncTrigger) async {
        await stopFlushing(trigger: trigger, name: "sync.token_rejected")
    }

    public func retire(trigger: AppSyncTrigger = .foreground) async {
        isRetired = true
        foregroundCycle += 1
        let task = refreshInFlight
        await stopFlushing(trigger: trigger, name: "sync.flusher_retired")
        _ = await task?.value
        refreshInFlight = nil
    }

    private func startFlushing(trigger: AppSyncTrigger) async {
        guard !isRetired else { return }
        if isForegroundFlushing {
            emitLifecycle(
                kind: "state",
                name: "sync.flusher_start_skipped",
                trigger: trigger,
                outcome: "skipped"
            )
            return
        }
        let name = hasStartedFlushing
            ? "sync.flusher_restarted"
            : "sync.flusher_started"
        await flusher.start()
        isForegroundFlushing = true
        hasStartedFlushing = true
        emitLifecycle(kind: "state", name: name, trigger: trigger, outcome: "started")
    }

    private func stopFlushing(
        trigger: AppSyncTrigger,
        name: String = "sync.flusher_stopped"
    ) async {
        await flusher.stop()
        isForegroundFlushing = false
        emitLifecycle(kind: "state", name: name, trigger: trigger, outcome: "stopped")
    }

    private func handlePushTokenRejected(trigger: AppSyncTrigger) async {
        guard !isRetired else { return }
        isForegroundFlushing = false
        emitLifecycle(
            kind: "error",
            name: "sync.push_token_rejected",
            trigger: trigger,
            outcome: "token_rejected"
        )
        await stopFlushing(trigger: trigger, name: "sync.token_rejected")
        await onTokenRejected?()
    }

    private nonisolated func emitLifecycle(
        kind: String,
        name: String,
        trigger: AppSyncTrigger,
        error: String? = nil,
        sincePresent: Bool? = nil,
        pulledWorkoutCount: Int? = nil,
        outcome: String? = nil
    ) {
        let payload = AppSyncTelemetryPayload(
            trigger: trigger.rawValue,
            error: error.map { String($0.prefix(240)) },
            errorClass: error.map { _ in "sync" },
            sincePresent: sincePresent,
            pulledWorkoutCount: pulledWorkoutCount,
            outcome: outcome
        )
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: kind,
            name: name,
            dataJSON: encodeTelemetryPayload(payload)
        ))
    }

    private nonisolated func encodeTelemetryPayload<Payload: Encodable>(
        _ payload: Payload
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(payload)
        // swiftlint:disable:next force_unwrapping
        return String(data: data, encoding: .utf8)!
    }
}

private struct AppSyncTelemetryPayload: Encodable {
    let trigger: String
    let error: String?
    let errorClass: String?
    let sincePresent: Bool?
    let pulledWorkoutCount: Int?
    let outcome: String?
}
