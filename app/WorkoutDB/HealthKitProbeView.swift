#if DEBUG
import SwiftUI
import HealthKitBridge
import Persistence

struct HealthKitProbeView: View {
    @State private var output: String = "Running HealthKit simulator probe..."
    let archiveStore: HealthArchiveStore

    var body: some View {
        ScrollView {
            Text(output)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .accessibilityIdentifier("healthkit-probe-output")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black)
        .task {
            var result = await HealthKitSimulatorProbe.runArchiveFetch()
            result = await persistArchive(result)
            let json = HealthKitSimulatorProbe.encodedArchiveJSON(result)
            output = json
            writeProbeResult(json)
        }
    }

    private func writeProbeResult(_ json: String) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        let url = documents.appendingPathComponent("healthkit-simulator-probe.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func persistArchive(
        _ result: HealthKitSimulatorArchiveProbeResult
    ) async -> HealthKitSimulatorArchiveProbeResult {
        guard result.archiveFetchSucceeded, let batch = result.batch else {
            return result.withProjectionResult(success: false, error: "Archive fetch did not succeed")
        }
        do {
            try await archiveStore.save(
                records: batch.records.map(archiveRecord(from:)),
                deletions: batch.deletedRecords.map {
                    HealthArchiveDeletion(
                        descriptorID: $0.type.id,
                        externalID: $0.externalID
                    )
                },
                cursors: batch.nextCursor.map {
                    [HealthArchiveCursor(
                        requestSetKey: result.requestSetKey,
                        cursor: $0.value
                    )]
                } ?? []
            )
            let persistedRecordIDs = try await archiveStore.loadRecords(descriptorID: nil)
                .map(\.externalID)
                .sorted()
            let persistedDeletions = try await archiveStore.loadDeletions(descriptorID: nil)
            let persistedDeletedIDs = persistedDeletions.map(\.externalID).sorted()
            let persistedDeletionKeys = Set(persistedDeletions.map(deletionKey))
            let persistedCursor = try await archiveStore.loadCursor(
                requestSetKey: result.requestSetKey
            )?.cursor
            let expectedRecordIDs = result.representativeRecordIDs
                .filter { !result.deletedExternalIDs.contains($0) }
            let matchedRecords = !expectedRecordIDs.isEmpty
                && expectedRecordIDs.allSatisfy { persistedRecordIDs.contains($0) }
            let expectedDeletionKeys = Set(batch.deletedRecords.map(deletionKey))
            let matchedDelete = !expectedDeletionKeys.isEmpty
                && expectedDeletionKeys.isSubset(of: persistedDeletionKeys)
            let matchedCursor = persistedCursor == result.secondCursorValue
            let storeKind = ProcessInfo.processInfo.environment[
                "WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE"
            ] == "1" ? "default_on_disk" : "in_memory"
            let reopenMatched = try await verifyDefaultStoreReopenIfRequested(
                expectedRecordIDs: expectedRecordIDs,
                expectedDeletionKeys: expectedDeletionKeys,
                expectedCursor: result.secondCursorValue,
                requestSetKey: result.requestSetKey
            )
            return result.withProjectionResult(
                success: true,
                projectionDeletedExternalIDs: persistedDeletedIDs,
                projectionMatchedDeletedRecord: matchedDelete,
                projectionRecordExternalIDs: persistedRecordIDs,
                projectionMatchedRecords: matchedRecords,
                projectionCursorValue: persistedCursor,
                projectionMatchedCursor: matchedCursor,
                projectionStoreKind: storeKind,
                projectionReopenMatched: reopenMatched
            )
        } catch {
            return result.withProjectionResult(success: false, error: String(describing: error))
        }
    }

    private func verifyDefaultStoreReopenIfRequested(
        expectedRecordIDs: [String],
        expectedDeletionKeys: Set<String>,
        expectedCursor: String?,
        requestSetKey: String
    ) async throws -> Bool {
        guard ProcessInfo.processInfo.environment[
            "WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE"
        ] == "1" else {
            return true
        }
        let reopened = try PersistenceFactory.makeDefault()
        let records = try await reopened.healthArchiveStore.loadRecords(descriptorID: nil)
        let deletions = try await reopened.healthArchiveStore.loadDeletions(descriptorID: nil)
        let cursor = try await reopened.healthArchiveStore.loadCursor(
            requestSetKey: requestSetKey
        )?.cursor
        return expectedRecordIDs.allSatisfy { expected in
            records.contains { $0.externalID == expected }
        }
        && expectedDeletionKeys.isSubset(of: Set(deletions.map(deletionKey)))
        && cursor == expectedCursor
    }

    private func archiveRecord(from record: HealthDataRecord) -> HealthArchiveRecord {
        HealthArchiveRecord(
            externalID: record.id,
            descriptorID: record.type.id,
            sampleKindRaw: record.type.kind.rawValue,
            sourceBundleIdentifier: record.sourceBundleIdentifier,
            start: record.start,
            end: record.end,
            value: archiveValue(from: record.value),
            metadata: record.metadata
        )
    }

    private func deletionKey(_ deletion: HealthDeletedRecord) -> String {
        "\(deletion.type.id)\u{1F}\(deletion.externalID)"
    }

    private func deletionKey(_ deletion: HealthArchiveDeletion) -> String {
        "\(deletion.descriptorID)\u{1F}\(deletion.externalID)"
    }

    private func archiveValue(from value: HealthDataValue) -> HealthArchiveValue {
        switch value {
        case .quantity(let number, let unit):
            return .quantity(number, unit: unit)
        case .category(let raw):
            return .category(raw)
        case .workout(let activityType, let durationSeconds, let totalEnergyKcal):
            return .workout(
                activityType: activityType,
                durationSeconds: durationSeconds,
                totalEnergyKcal: totalEnergyKcal
            )
        case .text(let text):
            return .text(text)
        case .unsupported(let reason):
            return .unsupported(reason)
        }
    }
}
#endif
