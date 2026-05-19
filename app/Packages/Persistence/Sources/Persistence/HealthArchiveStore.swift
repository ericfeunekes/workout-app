// HealthArchiveStore.swift
//
// SwiftData-backed projection store for normalized HealthKit archive data.
// HealthKit remains authoritative; this store exists so export/readback
// consumers can persist deduplicated local records, tombstones, and cursors.

import Foundation
import SwiftData

public enum HealthArchiveValue: Codable, Sendable, Equatable {
    case quantity(Double, unit: String)
    case category(Int)
    case workout(activityType: String, durationSeconds: Double, totalEnergyKcal: Double?)
    case text(String)
    case unsupported(String)

    public var unit: String? {
        if case .quantity(_, let unit) = self {
            return unit
        }
        return nil
    }
}

public struct HealthArchiveRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let externalID: String
    public let descriptorID: String
    public let sampleKindRaw: String
    public let sourceBundleIdentifier: String?
    public let start: Date?
    public let end: Date?
    public let value: HealthArchiveValue
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        externalID: String,
        descriptorID: String,
        sampleKindRaw: String,
        sourceBundleIdentifier: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        value: HealthArchiveValue,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.externalID = externalID
        self.descriptorID = descriptorID
        self.sampleKindRaw = sampleKindRaw
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.start = start
        self.end = end
        self.value = value
        self.metadata = metadata
    }
}

public struct HealthArchiveDeletion: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let descriptorID: String
    public let externalID: String
    public let observedAt: Date

    public init(
        id: UUID = UUID(),
        descriptorID: String,
        externalID: String,
        observedAt: Date = Date()
    ) {
        self.id = id
        self.descriptorID = descriptorID
        self.externalID = externalID
        self.observedAt = observedAt
    }
}

public struct HealthArchiveCursor: Sendable, Equatable {
    public let requestSetKey: String
    public let cursor: String
    public let updatedAt: Date

    public init(
        requestSetKey: String,
        cursor: String,
        updatedAt: Date = Date()
    ) {
        self.requestSetKey = requestSetKey
        self.cursor = cursor
        self.updatedAt = updatedAt
    }
}

public protocol HealthArchiveStore: Sendable {
    func save(
        records: [HealthArchiveRecord],
        deletions: [HealthArchiveDeletion],
        cursors: [HealthArchiveCursor]
    ) async throws

    func loadRecords(descriptorID: String?) async throws -> [HealthArchiveRecord]
    func loadDeletions(descriptorID: String?) async throws -> [HealthArchiveDeletion]
    func loadCursor(requestSetKey: String) async throws -> HealthArchiveCursor?
    func clear() async throws
}

@ModelActor
public actor HealthArchiveStoreImpl: HealthArchiveStore {
    public func save(
        records: [HealthArchiveRecord],
        deletions: [HealthArchiveDeletion],
        cursors: [HealthArchiveCursor]
    ) async throws {
        let now = Date()
        do {
            for record in records {
                try upsert(record, now: now)
            }
            for deletion in deletions {
                try upsert(deletion)
            }
            for cursor in cursors {
                try upsert(cursor)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func loadRecords(descriptorID: String? = nil) async throws -> [HealthArchiveRecord] {
        let models: [HealthDataRecordModel]
        if let descriptorID {
            let descriptor = FetchDescriptor<HealthDataRecordModel>(
                predicate: #Predicate<HealthDataRecordModel> { $0.descriptorID == descriptorID },
                sortBy: [SortDescriptor(\.start)]
            )
            models = try modelContext.fetch(descriptor)
        } else {
            models = try modelContext.fetch(FetchDescriptor<HealthDataRecordModel>(
                sortBy: [SortDescriptor(\.start)]
            ))
        }
        let deleted = try deletedRecordKeys(descriptorID: descriptorID)
        return try models
            .filter { !deleted.contains(archiveKey(descriptorID: $0.descriptorID, externalID: $0.externalID)) }
            .map(decodeRecord)
    }

    public func loadDeletions(descriptorID: String? = nil) async throws -> [HealthArchiveDeletion] {
        let models: [HealthDataDeletionModel]
        if let descriptorID {
            let descriptor = FetchDescriptor<HealthDataDeletionModel>(
                predicate: #Predicate<HealthDataDeletionModel> { $0.descriptorID == descriptorID },
                sortBy: [SortDescriptor(\.observedAt)]
            )
            models = try modelContext.fetch(descriptor)
        } else {
            models = try modelContext.fetch(FetchDescriptor<HealthDataDeletionModel>(
                sortBy: [SortDescriptor(\.observedAt)]
            ))
        }
        return models.map {
            HealthArchiveDeletion(
                id: $0.id,
                descriptorID: $0.descriptorID,
                externalID: $0.externalID,
                observedAt: $0.observedAt
            )
        }
    }

    public func loadCursor(requestSetKey: String) async throws -> HealthArchiveCursor? {
        let descriptor = FetchDescriptor<HealthBatchCursorModel>(
            predicate: #Predicate<HealthBatchCursorModel> {
                $0.requestSetKey == requestSetKey
            }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            return nil
        }
        return HealthArchiveCursor(
            requestSetKey: model.requestSetKey,
            cursor: model.cursor,
            updatedAt: model.updatedAt
        )
    }

    public func clear() async throws {
        do {
            try modelContext.delete(model: HealthDataRecordModel.self)
            try modelContext.delete(model: HealthDataDeletionModel.self)
            try modelContext.delete(model: HealthBatchCursorModel.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func upsert(_ record: HealthArchiveRecord, now: Date) throws {
        let externalID = record.externalID
        let descriptorID = record.descriptorID
        let descriptor = FetchDescriptor<HealthDataRecordModel>(
            predicate: #Predicate<HealthDataRecordModel> {
                $0.externalID == externalID && $0.descriptorID == descriptorID
            }
        )
        let model = try modelContext.fetch(descriptor).first
        let valueJSON = try encode(record.value)
        let metadataJSON = try encode(record.metadata)
        if let model {
            model.sampleKindRaw = record.sampleKindRaw
            model.sourceBundleIdentifier = record.sourceBundleIdentifier
            model.start = record.start
            model.end = record.end
            model.unit = record.value.unit
            model.valueJSON = valueJSON
            model.metadataJSON = metadataJSON
            model.lastSeenAt = now
        } else {
            modelContext.insert(HealthDataRecordModel(
                id: record.id,
                externalID: record.externalID,
                descriptorID: record.descriptorID,
                sampleKindRaw: record.sampleKindRaw,
                sourceBundleIdentifier: record.sourceBundleIdentifier,
                start: record.start,
                end: record.end,
                unit: record.value.unit,
                valueJSON: valueJSON,
                metadataJSON: metadataJSON,
                firstSeenAt: now,
                lastSeenAt: now
            ))
        }
    }

    private func upsert(_ deletion: HealthArchiveDeletion) throws {
        let externalID = deletion.externalID
        let descriptorID = deletion.descriptorID
        let descriptor = FetchDescriptor<HealthDataDeletionModel>(
            predicate: #Predicate<HealthDataDeletionModel> {
                $0.externalID == externalID && $0.descriptorID == descriptorID
            }
        )
        if let model = try modelContext.fetch(descriptor).first {
            model.observedAt = deletion.observedAt
        } else {
            modelContext.insert(HealthDataDeletionModel(
                id: deletion.id,
                descriptorID: deletion.descriptorID,
                externalID: deletion.externalID,
                observedAt: deletion.observedAt
            ))
        }
    }

    private func upsert(_ cursor: HealthArchiveCursor) throws {
        let requestSetKey = cursor.requestSetKey
        let descriptor = FetchDescriptor<HealthBatchCursorModel>(
            predicate: #Predicate<HealthBatchCursorModel> {
                $0.requestSetKey == requestSetKey
            }
        )
        if let model = try modelContext.fetch(descriptor).first {
            model.cursor = cursor.cursor
            model.updatedAt = cursor.updatedAt
        } else {
            modelContext.insert(HealthBatchCursorModel(
                id: UUID(),
                requestSetKey: cursor.requestSetKey,
                cursor: cursor.cursor,
                updatedAt: cursor.updatedAt
            ))
        }
    }

    private func deletedRecordKeys(descriptorID: String?) throws -> Set<String> {
        let deletions: [HealthDataDeletionModel]
        if let descriptorID {
            let descriptor = FetchDescriptor<HealthDataDeletionModel>(
                predicate: #Predicate<HealthDataDeletionModel> { $0.descriptorID == descriptorID }
            )
            deletions = try modelContext.fetch(descriptor)
        } else {
            deletions = try modelContext.fetch(FetchDescriptor<HealthDataDeletionModel>())
        }
        return Set(deletions.map {
            archiveKey(descriptorID: $0.descriptorID, externalID: $0.externalID)
        })
    }

    private func archiveKey(descriptorID: String, externalID: String) -> String {
        "\(descriptorID)\u{1F}\(externalID)"
    }

    private func decodeRecord(_ model: HealthDataRecordModel) throws -> HealthArchiveRecord {
        HealthArchiveRecord(
            id: model.id,
            externalID: model.externalID,
            descriptorID: model.descriptorID,
            sampleKindRaw: model.sampleKindRaw,
            sourceBundleIdentifier: model.sourceBundleIdentifier,
            start: model.start,
            end: model.end,
            value: try decode(HealthArchiveValue.self, from: model.valueJSON),
            metadata: try decode([String: String].self, from: model.metadataJSON)
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PersistenceError.encode("health archive value is not UTF-8")
        }
        return string
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw PersistenceError.decode("health archive value is not UTF-8")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
