// HealthDataTypes.swift
//
// Typed, HealthKit-free data contract for consumers. Features declare the
// HealthKit data they need through these descriptors and requests; only this
// package translates them to HealthKit identifiers, units, queries, and
// permissions.

import Foundation

public enum HealthDataSampleKind: String, Codable, Sendable, Equatable {
    case quantity
    case category
    case workout
    case characteristic
    case correlation
    case clinical
}

public enum HealthDataDeliveryMode: String, Codable, Sendable, Equatable {
    case batch
    case live
}

public enum HealthDataAccessMode: String, Codable, Sendable, Equatable {
    case read
    case write
    case readWrite
}

public struct HealthDataTypeDescriptor: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let kind: HealthDataSampleKind
    public let defaultUnit: String?

    public init(
        id: String,
        kind: HealthDataSampleKind,
        defaultUnit: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.defaultUnit = defaultUnit
    }
}

public enum HealthDataTypeRegistry {
    public static let heartRate = HealthDataTypeDescriptor(
        id: "HKQuantityTypeIdentifierHeartRate",
        kind: .quantity,
        defaultUnit: "count/min"
    )
    public static let bodyMass = HealthDataTypeDescriptor(
        id: "HKQuantityTypeIdentifierBodyMass",
        kind: .quantity,
        defaultUnit: "kg"
    )
    public static let stepCount = HealthDataTypeDescriptor(
        id: "HKQuantityTypeIdentifierStepCount",
        kind: .quantity,
        defaultUnit: "count"
    )
    public static let activeEnergyBurned = HealthDataTypeDescriptor(
        id: "HKQuantityTypeIdentifierActiveEnergyBurned",
        kind: .quantity,
        defaultUnit: "kcal"
    )
    public static let runningSpeed = HealthDataTypeDescriptor(
        id: "HKQuantityTypeIdentifierRunningSpeed",
        kind: .quantity,
        defaultUnit: "m/s"
    )
    public static let sleepAnalysis = HealthDataTypeDescriptor(
        id: "HKCategoryTypeIdentifierSleepAnalysis",
        kind: .category
    )
    public static let workout = HealthDataTypeDescriptor(
        id: "HKWorkoutTypeIdentifier",
        kind: .workout
    )
}

public struct HealthDataRequest: Codable, Sendable, Equatable, Hashable {
    public let type: HealthDataTypeDescriptor
    public let access: HealthDataAccessMode
    public let delivery: HealthDataDeliveryMode

    public init(
        type: HealthDataTypeDescriptor,
        access: HealthDataAccessMode = .read,
        delivery: HealthDataDeliveryMode
    ) {
        self.type = type
        self.access = access
        self.delivery = delivery
    }
}

public struct HealthBatchCursor: Codable, Sendable, Equatable, Hashable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

public struct HealthBatchQuery: Sendable, Equatable {
    public let requests: [HealthDataRequest]
    public let start: Date?
    public let end: Date?
    public let cursor: HealthBatchCursor?

    public init(
        requests: [HealthDataRequest],
        start: Date? = nil,
        end: Date? = nil,
        cursor: HealthBatchCursor? = nil
    ) {
        self.requests = requests
        self.start = start
        self.end = end
        self.cursor = cursor
    }
}

public struct HealthBatchResult: Sendable, Equatable {
    public let records: [HealthDataRecord]
    public let deletedExternalIDs: [String]
    public let nextCursor: HealthBatchCursor?

    public init(
        records: [HealthDataRecord],
        deletedExternalIDs: [String] = [],
        nextCursor: HealthBatchCursor? = nil
    ) {
        self.records = records
        self.deletedExternalIDs = deletedExternalIDs
        self.nextCursor = nextCursor
    }
}

public struct HealthDataRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: HealthDataTypeDescriptor
    public let sourceBundleIdentifier: String?
    public let start: Date?
    public let end: Date?
    public let value: HealthDataValue
    public let metadata: [String: String]

    public init(
        id: String,
        type: HealthDataTypeDescriptor,
        sourceBundleIdentifier: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        value: HealthDataValue,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.start = start
        self.end = end
        self.value = value
        self.metadata = metadata
    }
}

public enum HealthDataValue: Codable, Sendable, Equatable {
    case quantity(Double, unit: String)
    case category(Int)
    case workout(activityType: String, durationSeconds: Double, totalEnergyKcal: Double?)
    case text(String)
    case unsupported(String)
}
