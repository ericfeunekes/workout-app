import Foundation
import WorkoutDBSchema

public struct HealthArchiveUploadValue: Sendable, Equatable {
    public let kind: Kind
    public let quantityValue: Double?
    public let unit: String?
    public let categoryValue: Int?
    public let workoutActivityType: String?
    public let durationSeconds: Double?
    public let totalEnergyKcal: Double?
    public let text: String?
    public let reason: String?

    public enum Kind: String, Sendable {
        case quantity
        case category
        case workout
        case text
        case unsupported
    }

    public init(
        kind: Kind,
        quantityValue: Double? = nil,
        unit: String? = nil,
        categoryValue: Int? = nil,
        workoutActivityType: String? = nil,
        durationSeconds: Double? = nil,
        totalEnergyKcal: Double? = nil,
        text: String? = nil,
        reason: String? = nil
    ) {
        self.kind = kind
        self.quantityValue = quantityValue
        self.unit = unit
        self.categoryValue = categoryValue
        self.workoutActivityType = workoutActivityType
        self.durationSeconds = durationSeconds
        self.totalEnergyKcal = totalEnergyKcal
        self.text = text
        self.reason = reason
    }
}

public struct HealthArchiveUploadRecord: Sendable, Equatable {
    public let id: String
    public let externalID: String
    public let descriptorID: String
    public let sampleKind: String
    public let sourceBundleIdentifier: String?
    public let start: Date?
    public let end: Date?
    public let value: HealthArchiveUploadValue
    public let metadata: [String: String]

    public init(
        id: String,
        externalID: String,
        descriptorID: String,
        sampleKind: String,
        sourceBundleIdentifier: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        value: HealthArchiveUploadValue,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.externalID = externalID
        self.descriptorID = descriptorID
        self.sampleKind = sampleKind
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.start = start
        self.end = end
        self.value = value
        self.metadata = metadata
    }
}

public struct HealthArchiveUploadTombstone: Sendable, Equatable {
    public let id: String
    public let descriptorID: String
    public let externalID: String
    public let observedAt: Date

    public init(id: String, descriptorID: String, externalID: String, observedAt: Date) {
        self.id = id
        self.descriptorID = descriptorID
        self.externalID = externalID
        self.observedAt = observedAt
    }
}

public struct HealthArchiveUploadRequest: Sendable, Equatable {
    public let requestSetKey: String
    public let serverNamespace: String
    public let descriptorFingerprint: String
    public let nextCursor: String?
    public let records: [HealthArchiveUploadRecord]
    public let tombstones: [HealthArchiveUploadTombstone]

    public init(
        requestSetKey: String,
        serverNamespace: String,
        descriptorFingerprint: String,
        nextCursor: String?,
        records: [HealthArchiveUploadRecord],
        tombstones: [HealthArchiveUploadTombstone]
    ) {
        self.requestSetKey = requestSetKey
        self.serverNamespace = serverNamespace
        self.descriptorFingerprint = descriptorFingerprint
        self.nextCursor = nextCursor
        self.records = records
        self.tombstones = tombstones
    }
}

public struct HealthArchiveUploadResult: Sendable, Equatable {
    public let acknowledgedCursor: String?
    public let recordsReceived: Int
    public let tombstonesReceived: Int
    public let serverTime: Date

    public init(
        acknowledgedCursor: String?,
        recordsReceived: Int,
        tombstonesReceived: Int,
        serverTime: Date
    ) {
        self.acknowledgedCursor = acknowledgedCursor
        self.recordsReceived = recordsReceived
        self.tombstonesReceived = tombstonesReceived
        self.serverTime = serverTime
    }
}

public protocol HealthArchiveUploading: Sendable {
    func upload(_ request: HealthArchiveUploadRequest, bearerToken: String) async throws
        -> HealthArchiveUploadResult
}

public struct HealthArchiveUploadService: HealthArchiveUploading {
    private let transport: HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(transport: HTTPTransport) {
        self.transport = transport
        self.encoder = JSONEncoder.workoutDB()
        self.decoder = JSONDecoder.workoutDB()
    }

    public func upload(
        _ request: HealthArchiveUploadRequest,
        bearerToken: String
    ) async throws -> HealthArchiveUploadResult {
        let body: Data
        do {
            body = try encoder.encode(mapRequest(request))
        } catch {
            throw SyncError.encode("health archive upload body: \(error)")
        }

        let response: HTTPResponse
        do {
            response = try await transport.post(
                path: "/api/health/archive",
                body: body,
                bearerToken: bearerToken
            )
        } catch let err as SyncError {
            throw err
        } catch {
            throw SyncError.network(error.localizedDescription)
        }

        switch response.status {
        case 200...299:
            do {
                let dto = try decoder.decode(
                    WorkoutDBSchema.HealthArchiveUploadResponse.self,
                    from: response.body
                )
                return HealthArchiveUploadResult(
                    acknowledgedCursor: dto.acknowledgedCursor,
                    recordsReceived: dto.recordsReceived,
                    tombstonesReceived: dto.tombstonesReceived,
                    serverTime: dto.serverTime
                )
            } catch {
                throw SyncError.decode("health archive upload body: \(error)")
            }
        case 401:
            throw SyncError.tokenRejected
        default:
            throw SyncError.server(status: response.status, message: String(
                data: response.body,
                encoding: .utf8
            ))
        }
    }

    private func mapRequest(
        _ request: HealthArchiveUploadRequest
    ) -> WorkoutDBSchema.HealthArchiveUploadPayload {
        WorkoutDBSchema.HealthArchiveUploadPayload(
            requestSetKey: request.requestSetKey,
            serverNamespace: request.serverNamespace,
            descriptorFingerprint: request.descriptorFingerprint,
            nextCursor: request.nextCursor,
            records: request.records.map(mapRecord),
            tombstones: request.tombstones.map(mapTombstone)
        )
    }

    private func mapRecord(
        _ record: HealthArchiveUploadRecord
    ) -> WorkoutDBSchema.HealthArchiveRecord {
        WorkoutDBSchema.HealthArchiveRecord(
            id: record.id,
            externalId: record.externalID,
            descriptorId: record.descriptorID,
            sampleKind: record.sampleKind,
            sourceBundleIdentifier: record.sourceBundleIdentifier,
            startAt: record.start,
            endAt: record.end,
            value: mapValue(record.value),
            metadata: record.metadata
        )
    }

    private func mapTombstone(
        _ tombstone: HealthArchiveUploadTombstone
    ) -> WorkoutDBSchema.HealthArchiveTombstone {
        WorkoutDBSchema.HealthArchiveTombstone(
            id: tombstone.id,
            descriptorId: tombstone.descriptorID,
            externalId: tombstone.externalID,
            observedAt: tombstone.observedAt
        )
    }

    private func mapValue(
        _ value: HealthArchiveUploadValue
    ) -> WorkoutDBSchema.HealthArchiveValue {
        WorkoutDBSchema.HealthArchiveValue(
            kind: WorkoutDBSchema.HealthArchiveValue.Kind(rawValue: value.kind.rawValue)!,
            quantityValue: value.quantityValue,
            unit: value.unit,
            categoryValue: value.categoryValue,
            workoutActivityType: value.workoutActivityType,
            durationSeconds: value.durationSeconds,
            totalEnergyKcal: value.totalEnergyKcal,
            text: value.text,
            reason: value.reason
        )
    }
}
