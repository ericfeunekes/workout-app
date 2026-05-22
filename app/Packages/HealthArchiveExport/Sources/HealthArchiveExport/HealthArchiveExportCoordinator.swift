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

    func exportIfDue(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary?

    func retire() async
}

public extension HealthArchiveExportControlling {
    func exportIfDue(serverURL: URL) async throws -> HealthArchiveExportSummary? {
        try await exportIfDue(serverURL: serverURL, trigger: .foregroundCatchUp)
    }

    func retire() async {}
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
            let summary = try await currentRun.task.value
            return HealthArchiveExportSummary(
                trigger: trigger,
                recordsFetched: summary.recordsFetched,
                tombstonesFetched: summary.tombstonesFetched,
                acknowledgedCursor: summary.acknowledgedCursor,
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

    public func exportIfDue(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger = .foregroundCatchUp
    ) async throws -> HealthArchiveExportSummary? {
        guard await coordinator.shouldRunAutomaticExport(serverURL: serverURL) else {
            return nil
        }
        return try await exportNow(serverURL: serverURL, trigger: trigger)
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
        var stage = "start"
        do {
            try await ensureCurrent(isCurrent)
            let descriptors = try effectiveDescriptors(for: previousSnapshot.scope)
            let fingerprint = descriptorFingerprint(descriptors)
            let scopeSlug = scopeSlug(previousSnapshot.scope)
            let requestSetKey = "\(serverNamespace)|\(scopeSlug)|\(fingerprint)"
            let storedCursor = try await archiveStore.loadCursor(requestSetKey: requestSetKey)
            emitExportStage(
                name: "health_archive.export_started",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint,
                cursorPresent: storedCursor != nil
            )
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
            stage = "authorization"
            emitExportStage(
                name: "health_archive.authorization_requested",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint
            )
            try await permissions.requestAuthorization(for: requests)
            emitExportStage(
                name: "health_archive.authorization_completed",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint
            )
            stage = "fetch"
            emitExportStage(
                name: "health_archive.fetch_started",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint,
                cursorPresent: storedCursor != nil
            )
            let result = try await batch.fetch(HealthBatchQuery(
                requests: requests,
                cursor: storedCursor.map { HealthBatchCursor($0.cursor) }
            ))
            let fetchedAt = now()
            let records = result.records.map(mapRecord)
            let deletions = result.deletedRecords.map { mapDeletion($0, observedAt: fetchedAt) }
            emitExportStage(
                name: "health_archive.fetch_completed",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint,
                cursorPresent: result.nextCursor != nil,
                recordsFetched: records.count,
                tombstonesFetched: deletions.count,
                descriptorCounts: descriptorCounts(records)
            )
            try await ensureCurrent(isCurrent)
            stage = "upload"
            emitExportStage(
                name: "health_archive.upload_started",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint,
                cursorPresent: result.nextCursor != nil,
                recordsFetched: records.count,
                tombstonesFetched: deletions.count
            )
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
            emitExportStage(
                name: "health_archive.upload_completed",
                trigger: trigger,
                serverNamespace: serverNamespace,
                descriptorCount: descriptors.count,
                descriptorFingerprint: fingerprint,
                acknowledgedCursorPresent: uploadResult.acknowledgedCursor != nil,
                recordsFetched: records.count,
                tombstonesFetched: deletions.count
            )
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
            return HealthArchiveExportSummary(
                trigger: trigger,
                recordsFetched: records.count,
                tombstonesFetched: deletions.count,
                acknowledgedCursor: uploadResult.acknowledgedCursor
            )
        } catch {
            emitExportStage(
                name: "health_archive.export_internal_failed",
                trigger: trigger,
                serverNamespace: serverNamespace,
                failureClass: failureClass(for: error),
                stage: stage
            )
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

    private func descriptorCounts(_ records: [HealthArchiveRecord]) -> [String: Int] {
        records.reduce(into: [:]) { counts, record in
            counts[record.descriptorID, default: 0] += 1
        }
    }

    private func emitExportStage(
        name: String,
        trigger: HealthArchiveExportTrigger,
        serverNamespace: String,
        descriptorCount: Int? = nil,
        descriptorFingerprint: String? = nil,
        cursorPresent: Bool? = nil,
        acknowledgedCursorPresent: Bool? = nil,
        recordsFetched: Int? = nil,
        tombstonesFetched: Int? = nil,
        descriptorCounts: [String: Int]? = nil,
        failureClass: String? = nil,
        stage: String? = nil
    ) {
        let payload = HealthArchiveCoordinatorTelemetryPayload(
            trigger: trigger.rawValue,
            serverNamespace: serverNamespace,
            descriptorCount: descriptorCount,
            descriptorFingerprint: descriptorFingerprint,
            cursorPresent: cursorPresent,
            acknowledgedCursorPresent: acknowledgedCursorPresent,
            recordsFetched: recordsFetched,
            tombstonesFetched: tombstonesFetched,
            descriptorCounts: descriptorCounts,
            failureClass: failureClass,
            stage: stage
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try? encoder.encode(payload)
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "health_archive",
            name: name,
            dataJSON: data.flatMap { String(data: $0, encoding: .utf8) }
        ))
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

private struct HealthArchiveCoordinatorTelemetryPayload: Encodable {
    let trigger: String
    let serverNamespace: String
    let descriptorCount: Int?
    let descriptorFingerprint: String?
    let cursorPresent: Bool?
    let acknowledgedCursorPresent: Bool?
    let recordsFetched: Int?
    let tombstonesFetched: Int?
    let descriptorCounts: [String: Int]?
    let failureClass: String?
    let stage: String?
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
