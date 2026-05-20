import Foundation
import CoreTelemetry
import HealthKitBridge
import Persistence
import Sync

public enum HealthArchiveExportTrigger: String, Sendable, Equatable {
    case manual
    case foregroundCatchUp
    case backgroundScheduled
}

public enum HealthArchiveExportError: Error, Sendable, Equatable {
    case emptyExplicitScope
    case unsupportedDescriptorIDs([String])
    case requestSetAcknowledgementMismatch(expected: String, actual: String)
    case unsupportedSampleKind(String)
}

public struct HealthArchiveExportSummary: Sendable, Equatable {
    public let trigger: HealthArchiveExportTrigger
    public let recordsFetched: Int
    public let tombstonesFetched: Int
    public let acknowledgedCursor: String?
    public let alreadyRunning: Bool

    public init(
        trigger: HealthArchiveExportTrigger,
        recordsFetched: Int,
        tombstonesFetched: Int,
        acknowledgedCursor: String?,
        alreadyRunning: Bool = false
    ) {
        self.trigger = trigger
        self.recordsFetched = recordsFetched
        self.tombstonesFetched = tombstonesFetched
        self.acknowledgedCursor = acknowledgedCursor
        self.alreadyRunning = alreadyRunning
    }
}

public protocol HealthArchiveExportControlling: Sendable {
    func exportNow(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary

    func exportIfDue(serverURL: URL) async throws -> HealthArchiveExportSummary?
}

public actor HealthArchiveExportRuntime: HealthArchiveExportControlling {
    private let coordinator: HealthArchiveExportCoordinator
    private var isRetired = false
    private var generation = 0
    private var currentRun: CurrentRun?

    private struct CurrentRun: Sendable {
        let generation: Int
        let serverURL: URL
        let task: Task<HealthArchiveExportSummary, Error>
    }

    public init(coordinator: HealthArchiveExportCoordinator) {
        self.coordinator = coordinator
    }

    public func exportNow(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary {
        guard !isRetired else { throw CancellationError() }
        if let currentRun {
            await coordinator.markAlreadyRunning(
                serverURL: serverURL,
                isCurrent: { await self.isCurrent(currentRun.generation) }
            )
            return HealthArchiveExportSummary(
                trigger: trigger,
                recordsFetched: 0,
                tombstonesFetched: 0,
                acknowledgedCursor: nil,
                alreadyRunning: true
            )
        }
        generation += 1
        let runGeneration = generation
        let task = Task {
            try await coordinator.exportNow(
                serverURL: serverURL,
                trigger: trigger,
                isCurrent: { await self.isCurrent(runGeneration) }
            )
        }
        currentRun = CurrentRun(generation: runGeneration, serverURL: serverURL, task: task)
        do {
            let summary = try await task.value
            clearCurrentRun(generation: runGeneration)
            return summary
        } catch {
            clearCurrentRun(generation: runGeneration)
            throw error
        }
    }

    public func exportIfDue(serverURL: URL) async throws -> HealthArchiveExportSummary? {
        guard await coordinator.shouldRunAutomaticExport(serverURL: serverURL) else {
            return nil
        }
        return try await exportNow(serverURL: serverURL, trigger: .foregroundCatchUp)
    }

    public func retire() async {
        isRetired = true
        generation += 1
        let retiredRun = currentRun
        currentRun = nil
        retiredRun?.task.cancel()
        if let retiredRun {
            do {
                _ = try await retiredRun.task.value
            } catch {}
            await coordinator.markInterrupted(serverURL: retiredRun.serverURL)
        }
    }

    private func isCurrent(_ runGeneration: Int) -> Bool {
        !isRetired && generation == runGeneration
    }

    private func clearCurrentRun(generation runGeneration: Int) {
        guard currentRun?.generation == runGeneration else { return }
        currentRun = nil
    }
}

public struct HealthArchiveExportCoordinator: Sendable {
    private let permissions: HealthPermissionBroker
    private let batch: HealthBatchDataProvider
    private let archiveStore: HealthArchiveStore
    private let stateStore: HealthArchiveExportStateStore
    private let syncAPI: SyncAPI
    private let telemetry: TelemetryEmitter
    private let supportedDescriptors: [HealthDataTypeDescriptor]
    private let now: @Sendable () -> Date

    public init(
        permissions: HealthPermissionBroker,
        batch: HealthBatchDataProvider,
        archiveStore: HealthArchiveStore,
        stateStore: HealthArchiveExportStateStore,
        syncAPI: SyncAPI,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        supportedDescriptors: [HealthDataTypeDescriptor] =
            HealthArchiveDescriptorCatalog.supportedBatchTypes(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.permissions = permissions
        self.batch = batch
        self.archiveStore = archiveStore
        self.stateStore = stateStore
        self.syncAPI = syncAPI
        self.telemetry = telemetry
        self.supportedDescriptors = supportedDescriptors
        self.now = now
    }

    public func exportNow(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger = .manual,
        isCurrent: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> HealthArchiveExportSummary {
        let attemptedAt = now()
        let serverNamespace = normalizedServerNamespace(serverURL)
        let previousSnapshot = await stateStore.loadSnapshot(serverNamespace: serverNamespace)
        do {
            try await ensureCurrent(isCurrent)
            let descriptors = try effectiveDescriptors(for: previousSnapshot.scope)
            let fingerprint = descriptorFingerprint(descriptors)
            let scopeSlug = scopeSlug(previousSnapshot.scope)
            let requestSetKey = "\(serverNamespace)|\(scopeSlug)|\(fingerprint)"
            let storedCursor = try await archiveStore.loadCursor(requestSetKey: requestSetKey)
            let runningSnapshot = HealthArchiveExportSnapshot(
                scope: previousSnapshot.scope,
                serverNamespace: serverNamespace,
                requestSetKey: requestSetKey,
                descriptorFingerprint: fingerprint,
                acknowledgedCursor: storedCursor?.cursor,
                status: .running,
                lastFetchAt: previousSnapshot.lastFetchAt,
                lastUploadAt: previousSnapshot.lastUploadAt,
                lastRecordCount: previousSnapshot.lastRecordCount,
                lastTombstoneCount: previousSnapshot.lastTombstoneCount,
                lastFailureClass: nil,
                automaticEnabled: previousSnapshot.automaticEnabled,
                nextAttemptAt: previousSnapshot.nextAttemptAt,
                lastAttemptAt: attemptedAt
            )
            try await ensureCurrent(isCurrent)
            await stateStore.saveSnapshot(runningSnapshot)
            let requests = descriptors.map {
                HealthDataRequest(type: $0, access: .read, delivery: .batch)
            }
            try await permissions.requestAuthorization(for: requests)
            let result = try await batch.fetch(HealthBatchQuery(
                requests: requests,
                cursor: storedCursor.map { HealthBatchCursor($0.cursor) }
            ))
            let fetchedAt = now()
            let records = result.records.map(mapRecord)
            let deletions = result.deletedRecords.map { mapDeletion($0, observedAt: fetchedAt) }
            try await ensureCurrent(isCurrent)
            let uploadResult = try await syncAPI.uploadHealthArchive(HealthArchiveUploadRequest(
                requestSetKey: requestSetKey,
                serverNamespace: serverNamespace,
                descriptorFingerprint: fingerprint,
                nextCursor: result.nextCursor?.value,
                records: try records.map(mapUploadRecord),
                tombstones: deletions.map(mapUploadTombstone)
            ))
            guard uploadResult.requestSetKey == requestSetKey else {
                throw HealthArchiveExportError.requestSetAcknowledgementMismatch(
                    expected: requestSetKey,
                    actual: uploadResult.requestSetKey
                )
            }
            let cursors = uploadResult.acknowledgedCursor.map {
                [HealthArchiveCursor(
                    requestSetKey: requestSetKey,
                    cursor: $0,
                    updatedAt: uploadResult.serverTime
                )]
            } ?? []
            try await ensureCurrent(isCurrent)
            try await archiveStore.save(
                records: records,
                deletions: deletions,
                cursors: cursors
            )
            let nextAttempt = nextAttempt(after: uploadResult.serverTime)
            let success = HealthArchiveExportSnapshot(
                scope: previousSnapshot.scope,
                serverNamespace: serverNamespace,
                requestSetKey: requestSetKey,
                descriptorFingerprint: fingerprint,
                acknowledgedCursor: uploadResult.acknowledgedCursor,
                status: .succeeded,
                lastFetchAt: fetchedAt,
                lastUploadAt: uploadResult.serverTime,
                lastRecordCount: records.count,
                lastTombstoneCount: deletions.count,
                lastFailureClass: nil,
                automaticEnabled: previousSnapshot.automaticEnabled,
                nextAttemptAt: nextAttempt,
                lastAttemptAt: attemptedAt
            )
            try await ensureCurrent(isCurrent)
            await stateStore.saveSnapshot(success)
            telemetry.emit(Event(
                sessionID: TelemetrySession.id,
                kind: "health_archive",
                name: "health_archive.export_succeeded"
            ))
            return HealthArchiveExportSummary(
                trigger: trigger,
                recordsFetched: records.count,
                tombstonesFetched: deletions.count,
                acknowledgedCursor: uploadResult.acknowledgedCursor
            )
        } catch {
            if await isCurrent() {
                await stateStore.saveSnapshot(HealthArchiveExportSnapshot(
                    scope: previousSnapshot.scope,
                    serverNamespace: serverNamespace,
                    requestSetKey: previousSnapshot.requestSetKey,
                    descriptorFingerprint: previousSnapshot.descriptorFingerprint,
                    acknowledgedCursor: previousSnapshot.acknowledgedCursor,
                    status: .failed,
                    lastFetchAt: previousSnapshot.lastFetchAt,
                    lastUploadAt: previousSnapshot.lastUploadAt,
                    lastRecordCount: previousSnapshot.lastRecordCount,
                    lastTombstoneCount: previousSnapshot.lastTombstoneCount,
                    lastFailureClass: failureClass(for: error),
                    automaticEnabled: previousSnapshot.automaticEnabled,
                    nextAttemptAt: previousSnapshot.nextAttemptAt,
                    lastAttemptAt: attemptedAt
                ))
            }
            throw error
        }
    }

    public func shouldRunAutomaticExport(serverURL: URL) async -> Bool {
        let serverNamespace = normalizedServerNamespace(serverURL)
        let snapshot = await stateStore.loadSnapshot(serverNamespace: serverNamespace)
        guard snapshot.automaticEnabled else { return false }
        if snapshot.status == .failed { return true }
        guard let expectedRequestSetKey = try? requestSetKey(
            serverNamespace: serverNamespace,
            scope: snapshot.scope
        ) else {
            return true
        }
        if snapshot.requestSetKey != expectedRequestSetKey {
            return true
        }
        guard let nextAttemptAt = snapshot.nextAttemptAt else { return true }
        return nextAttemptAt <= now()
    }

    public func markAlreadyRunning(
        serverURL: URL,
        isCurrent: @escaping @Sendable () async -> Bool = { true }
    ) async {
        let serverNamespace = normalizedServerNamespace(serverURL)
        let snapshot = await stateStore.loadSnapshot(serverNamespace: serverNamespace)
        guard await isCurrent() else { return }
        await stateStore.saveSnapshot(HealthArchiveExportSnapshot(
            scope: snapshot.scope,
            serverNamespace: serverNamespace,
            requestSetKey: snapshot.requestSetKey,
            descriptorFingerprint: snapshot.descriptorFingerprint,
            acknowledgedCursor: snapshot.acknowledgedCursor,
            status: .alreadyRunning,
            lastFetchAt: snapshot.lastFetchAt,
            lastUploadAt: snapshot.lastUploadAt,
            lastRecordCount: snapshot.lastRecordCount,
            lastTombstoneCount: snapshot.lastTombstoneCount,
            lastFailureClass: snapshot.lastFailureClass,
            automaticEnabled: snapshot.automaticEnabled,
            nextAttemptAt: snapshot.nextAttemptAt,
            lastAttemptAt: snapshot.lastAttemptAt
        ))
    }

    public func markInterrupted(serverURL: URL) async {
        let serverNamespace = normalizedServerNamespace(serverURL)
        let snapshot = await stateStore.loadSnapshot(serverNamespace: serverNamespace)
        guard snapshot.status == .running || snapshot.status == .alreadyRunning else { return }
        await stateStore.saveSnapshot(HealthArchiveExportSnapshot(
            scope: snapshot.scope,
            serverNamespace: serverNamespace,
            requestSetKey: snapshot.requestSetKey,
            descriptorFingerprint: snapshot.descriptorFingerprint,
            acknowledgedCursor: snapshot.acknowledgedCursor,
            status: .failed,
            lastFetchAt: snapshot.lastFetchAt,
            lastUploadAt: snapshot.lastUploadAt,
            lastRecordCount: snapshot.lastRecordCount,
            lastTombstoneCount: snapshot.lastTombstoneCount,
            lastFailureClass: "InterruptedExport",
            automaticEnabled: snapshot.automaticEnabled,
            nextAttemptAt: snapshot.nextAttemptAt,
            lastAttemptAt: now()
        ))
    }

    private func ensureCurrent(_ isCurrent: @escaping @Sendable () async -> Bool) async throws {
        guard await isCurrent() else { throw CancellationError() }
    }

    private func failureClass(for error: Error) -> String {
        if let syncError = error as? SyncError, syncError == .tokenRejected {
            return "TokenRejected"
        }
        return String(describing: type(of: error))
    }

    private func effectiveDescriptors(
        for scope: HealthArchiveExportScope
    ) throws -> [HealthDataTypeDescriptor] {
        switch scope {
        case .allSupported:
            return supportedDescriptors
        case .explicitDescriptorIDs(let ids):
            guard !ids.isEmpty else {
                throw HealthArchiveExportError.emptyExplicitScope
            }
            let byID = Dictionary(uniqueKeysWithValues: supportedDescriptors.map { ($0.id, $0) })
            let unsupported = ids.filter { byID[$0] == nil }.sorted()
            guard unsupported.isEmpty else {
                throw HealthArchiveExportError.unsupportedDescriptorIDs(unsupported)
            }
            return ids.compactMap { byID[$0] }
        }
    }

    private func scopeSlug(_ scope: HealthArchiveExportScope) -> String {
        switch scope {
        case .allSupported:
            return "all-supported"
        case .explicitDescriptorIDs:
            return "explicit"
        }
    }

    private func requestSetKey(
        serverNamespace: String,
        scope: HealthArchiveExportScope
    ) throws -> String {
        let descriptors = try effectiveDescriptors(for: scope)
        let fingerprint = descriptorFingerprint(descriptors)
        let scopeSlug = scopeSlug(scope)
        return "\(serverNamespace)|\(scopeSlug)|\(fingerprint)"
    }

    private func nextAttempt(after date: Date) -> Date {
        date.addingTimeInterval(24 * 60 * 60)
    }

    private func normalizedServerNamespace(_ url: URL) -> String {
        HealthArchiveServerNamespace.normalized(from: url)
    }

    private func descriptorFingerprint(_ descriptors: [HealthDataTypeDescriptor]) -> String {
        descriptors.map(\.id).sorted().joined(separator: ",")
    }

    private func mapRecord(_ record: HealthDataRecord) -> HealthArchiveRecord {
        HealthArchiveRecord(
            externalID: record.id,
            descriptorID: record.type.id,
            sampleKindRaw: record.type.kind.rawValue,
            sourceBundleIdentifier: record.sourceBundleIdentifier,
            start: record.start,
            end: record.end,
            value: mapValue(record.value),
            metadata: record.metadata
        )
    }

    private func mapDeletion(
        _ deletion: HealthDeletedRecord,
        observedAt: Date
    ) -> HealthArchiveDeletion {
        HealthArchiveDeletion(
            descriptorID: deletion.type.id,
            externalID: deletion.externalID,
            observedAt: observedAt
        )
    }

    private func mapValue(_ value: HealthDataValue) -> HealthArchiveValue {
        switch value {
        case .quantity(let amount, let unit):
            return .quantity(amount, unit: unit)
        case .category(let value):
            return .category(value)
        case .workout(let activityType, let durationSeconds, let totalEnergyKcal):
            return .workout(
                activityType: activityType,
                durationSeconds: durationSeconds,
                totalEnergyKcal: totalEnergyKcal
            )
        case .text(let value):
            return .text(value)
        case .unsupported(let reason):
            return .unsupported(reason)
        }
    }

    private func mapUploadRecord(_ record: HealthArchiveRecord) throws -> HealthArchiveUploadRecord {
        guard let sampleKind = HealthArchiveUploadSampleKind(rawValue: record.sampleKindRaw) else {
            throw HealthArchiveExportError.unsupportedSampleKind(record.sampleKindRaw)
        }
        return HealthArchiveUploadRecord(
            id: record.id.uuidString.lowercased(),
            externalID: record.externalID,
            descriptorID: record.descriptorID,
            sampleKind: sampleKind,
            sourceBundleIdentifier: record.sourceBundleIdentifier,
            start: record.start,
            end: record.end,
            value: mapUploadValue(record.value),
            metadata: record.metadata
        )
    }

    private func mapUploadTombstone(
        _ deletion: HealthArchiveDeletion
    ) -> HealthArchiveUploadTombstone {
        HealthArchiveUploadTombstone(
            id: deletion.id.uuidString.lowercased(),
            descriptorID: deletion.descriptorID,
            externalID: deletion.externalID,
            observedAt: deletion.observedAt
        )
    }

    private func mapUploadValue(_ value: HealthArchiveValue) -> HealthArchiveUploadValue {
        switch value {
        case .quantity(let amount, let unit):
            return HealthArchiveUploadValue(kind: .quantity, quantityValue: amount, unit: unit)
        case .category(let value):
            return HealthArchiveUploadValue(kind: .category, categoryValue: value)
        case .workout(let activityType, let durationSeconds, let totalEnergyKcal):
            return HealthArchiveUploadValue(
                kind: .workout,
                workoutActivityType: activityType,
                durationSeconds: durationSeconds,
                totalEnergyKcal: totalEnergyKcal
            )
        case .text(let value):
            return HealthArchiveUploadValue(kind: .text, text: value)
        case .unsupported(let reason):
            return HealthArchiveUploadValue(kind: .unsupported, reason: reason)
        }
    }
}

public enum HealthArchiveExportFactory {
    public static func live(
        archiveStore: HealthArchiveStore,
        stateStore: HealthArchiveExportStateStore,
        syncAPI: SyncAPI,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) -> HealthArchiveExportRuntime {
        let bridge = HealthKitBridgeFactory.live()
        return HealthArchiveExportRuntime(coordinator: HealthArchiveExportCoordinator(
            permissions: bridge.permissions,
            batch: bridge.batch,
            archiveStore: archiveStore,
            stateStore: stateStore,
            syncAPI: syncAPI,
            telemetry: telemetry
        ))
    }
}
