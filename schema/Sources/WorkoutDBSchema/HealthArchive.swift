import Foundation

public struct HealthArchiveValue: Codable, Sendable, Equatable {
    public let kind: Kind
    public let quantityValue: Double?
    public let unit: String?
    public let categoryValue: Int?
    public let workoutActivityType: String?
    public let durationSeconds: Double?
    public let totalEnergyKcal: Double?
    public let text: String?
    public let reason: String?

    public enum Kind: String, Codable, Sendable {
        case quantity
        case category
        case workout
        case text
        case unsupported
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case quantityValue = "quantity_value"
        case unit
        case categoryValue = "category_value"
        case workoutActivityType = "workout_activity_type"
        case durationSeconds = "duration_seconds"
        case totalEnergyKcal = "total_energy_kcal"
        case text
        case reason
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

public struct HealthArchiveRecord: Codable, Sendable, Equatable {
    public let id: String
    public let externalId: String
    public let descriptorId: String
    public let sampleKind: String
    public let sourceBundleIdentifier: String?
    public let startAt: Date?
    public let endAt: Date?
    public let value: HealthArchiveValue
    public let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case externalId = "external_id"
        case descriptorId = "descriptor_id"
        case sampleKind = "sample_kind"
        case sourceBundleIdentifier = "source_bundle_identifier"
        case startAt = "start_at"
        case endAt = "end_at"
        case value
        case metadata
    }

    public init(
        id: String,
        externalId: String,
        descriptorId: String,
        sampleKind: String,
        sourceBundleIdentifier: String? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        value: HealthArchiveValue,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.externalId = externalId
        self.descriptorId = descriptorId
        self.sampleKind = sampleKind
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.startAt = startAt
        self.endAt = endAt
        self.value = value
        self.metadata = metadata
    }
}

public struct HealthArchiveTombstone: Codable, Sendable, Equatable {
    public let id: String
    public let descriptorId: String
    public let externalId: String
    public let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case descriptorId = "descriptor_id"
        case externalId = "external_id"
        case observedAt = "observed_at"
    }

    public init(id: String, descriptorId: String, externalId: String, observedAt: Date) {
        self.id = id
        self.descriptorId = descriptorId
        self.externalId = externalId
        self.observedAt = observedAt
    }
}

public struct HealthArchiveUploadPayload: Codable, Sendable, Equatable {
    public let requestSetKey: String
    public let serverNamespace: String
    public let descriptorFingerprint: String
    public let nextCursor: String?
    public let records: [HealthArchiveRecord]
    public let tombstones: [HealthArchiveTombstone]

    enum CodingKeys: String, CodingKey {
        case requestSetKey = "request_set_key"
        case serverNamespace = "server_namespace"
        case descriptorFingerprint = "descriptor_fingerprint"
        case nextCursor = "next_cursor"
        case records
        case tombstones
    }

    public init(
        requestSetKey: String,
        serverNamespace: String,
        descriptorFingerprint: String,
        nextCursor: String?,
        records: [HealthArchiveRecord],
        tombstones: [HealthArchiveTombstone]
    ) {
        self.requestSetKey = requestSetKey
        self.serverNamespace = serverNamespace
        self.descriptorFingerprint = descriptorFingerprint
        self.nextCursor = nextCursor
        self.records = records
        self.tombstones = tombstones
    }
}

public struct HealthArchiveUploadResponse: Codable, Sendable, Equatable {
    public let requestSetKey: String
    public let acknowledgedCursor: String?
    public let recordsReceived: Int
    public let tombstonesReceived: Int
    public let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case requestSetKey = "request_set_key"
        case acknowledgedCursor = "acknowledged_cursor"
        case recordsReceived = "records_received"
        case tombstonesReceived = "tombstones_received"
        case serverTime = "server_time"
    }
}
