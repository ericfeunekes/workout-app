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

public enum HealthBatchWindowSemantics: String, Codable, Sendable, Equatable {
    case strictStart
    case overlap
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

public enum HealthDataRequestValidator {
    public static func validateAuthorizationRequests(_ requests: [HealthDataRequest]) throws {
        guard !requests.isEmpty else {
            throw HealthKitError.queryFailed("HealthKit authorization requires at least one request")
        }
        for request in requests {
            if request.delivery == .live && request.access == .write {
                throw HealthKitError.notImplemented(
                    "Live HealthKit delivery does not support write-only access for \(request.type.id)"
                )
            }
        }
    }

    public static func validateBatchFetchRequests(_ requests: [HealthDataRequest]) throws {
        guard !requests.isEmpty else {
            throw HealthKitError.queryFailed("HealthKit batch query requires at least one request")
        }
        for request in requests {
            guard request.delivery == .batch else {
                throw HealthKitError.notImplemented(
                    "Batch fetch does not support \(request.delivery.rawValue) delivery for \(request.type.id)"
                )
            }
            guard request.access == .read || request.access == .readWrite else {
                throw HealthKitError.notImplemented(
                    "Batch fetch requires read access for \(request.type.id)"
                )
            }
        }
    }

    public static func validateLiveStreamRequests(_ requests: [HealthDataRequest]) throws {
        guard !requests.isEmpty else {
            throw HealthKitError.queryFailed("HealthKit live stream requires at least one request")
        }
        for request in requests {
            guard request.delivery == .live else {
                throw HealthKitError.notImplemented(
                    "Live stream does not support \(request.delivery.rawValue) delivery for \(request.type.id)"
                )
            }
            guard request.access == .read || request.access == .readWrite else {
                throw HealthKitError.notImplemented(
                    "Live stream requires read access for \(request.type.id)"
                )
            }
        }
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

public struct HealthBatchResult: Codable, Sendable, Equatable {
    public let records: [HealthDataRecord]
    public let deletedRecords: [HealthDeletedRecord]
    public let nextCursor: HealthBatchCursor?

    public var deletedExternalIDs: [String] {
        deletedRecords.map(\.externalID)
    }

    public init(
        records: [HealthDataRecord],
        nextCursor: HealthBatchCursor? = nil
    ) {
        self.records = records
        self.deletedRecords = []
        self.nextCursor = nextCursor
    }

    public init(
        records: [HealthDataRecord],
        deletedRecords: [HealthDeletedRecord],
        nextCursor: HealthBatchCursor? = nil
    ) {
        self.records = records
        self.deletedRecords = deletedRecords
        self.nextCursor = nextCursor
    }
}

public struct HealthDeletedRecord: Codable, Sendable, Equatable, Hashable {
    public let externalID: String
    public let type: HealthDataTypeDescriptor

    public init(externalID: String, type: HealthDataTypeDescriptor) {
        self.externalID = externalID
        self.type = type
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

public struct WorkoutMetricTick: Codable, Sendable, Equatable {
    public let elapsedSeconds: TimeInterval
    public let heartRateBPM: Double?
    public let distanceMeters: Double?
    public let activeEnergyKCal: Double?
    public let paceSecondsPerKilometer: Double?

    public init(
        elapsedSeconds: TimeInterval,
        heartRateBPM: Double? = nil,
        distanceMeters: Double? = nil,
        activeEnergyKCal: Double? = nil,
        paceSecondsPerKilometer: Double? = nil
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.heartRateBPM = heartRateBPM
        self.distanceMeters = distanceMeters
        self.activeEnergyKCal = activeEnergyKCal
        self.paceSecondsPerKilometer = paceSecondsPerKilometer
    }
}

public enum WorkoutMetricEvent: Sendable, Equatable {
    case sessionStarted(elapsedSeconds: TimeInterval)
    case metric(WorkoutMetricTick)
    case paused(elapsedSeconds: TimeInterval)
    case resumed(elapsedSeconds: TimeInterval)
    case sessionEnded(elapsedSeconds: TimeInterval)
}

extension WorkoutMetricEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case elapsedSeconds
        case tick
        case sessionStarted
        case metric
        case paused
        case resumed
        case sessionEnded
    }

    private enum ElapsedCodingKeys: String, CodingKey {
        case elapsedSeconds
    }

    private enum EventType: String, Codable {
        case sessionStarted
        case metric
        case paused
        case resumed
        case sessionEnded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if !container.contains(.type) {
            if container.contains(.sessionStarted) {
                let value = try container.nestedContainer(
                    keyedBy: ElapsedCodingKeys.self,
                    forKey: .sessionStarted
                )
                self = .sessionStarted(
                    elapsedSeconds: try value.decode(TimeInterval.self, forKey: .elapsedSeconds)
                )
                return
            }
            if container.contains(.metric) {
                self = .metric(try container.decode(WorkoutMetricTick.self, forKey: .metric))
                return
            }
            if container.contains(.paused) {
                let value = try container.nestedContainer(
                    keyedBy: ElapsedCodingKeys.self,
                    forKey: .paused
                )
                self = .paused(
                    elapsedSeconds: try value.decode(TimeInterval.self, forKey: .elapsedSeconds)
                )
                return
            }
            if container.contains(.resumed) {
                let value = try container.nestedContainer(
                    keyedBy: ElapsedCodingKeys.self,
                    forKey: .resumed
                )
                self = .resumed(
                    elapsedSeconds: try value.decode(TimeInterval.self, forKey: .elapsedSeconds)
                )
                return
            }
            let value = try container.nestedContainer(
                keyedBy: ElapsedCodingKeys.self,
                forKey: .sessionEnded
            )
            self = .sessionEnded(
                elapsedSeconds: try value.decode(TimeInterval.self, forKey: .elapsedSeconds)
            )
            return
        }
        let type = try container.decode(EventType.self, forKey: .type)
        switch type {
        case .sessionStarted:
            self = .sessionStarted(
                elapsedSeconds: try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
            )
        case .metric:
            self = .metric(try container.decode(WorkoutMetricTick.self, forKey: .tick))
        case .paused:
            self = .paused(
                elapsedSeconds: try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
            )
        case .resumed:
            self = .resumed(
                elapsedSeconds: try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
            )
        case .sessionEnded:
            self = .sessionEnded(
                elapsedSeconds: try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStarted(let elapsedSeconds):
            try container.encode(EventType.sessionStarted, forKey: .type)
            try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        case .metric(let tick):
            try container.encode(EventType.metric, forKey: .type)
            try container.encode(tick, forKey: .tick)
        case .paused(let elapsedSeconds):
            try container.encode(EventType.paused, forKey: .type)
            try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        case .resumed(let elapsedSeconds):
            try container.encode(EventType.resumed, forKey: .type)
            try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        case .sessionEnded(let elapsedSeconds):
            try container.encode(EventType.sessionEnded, forKey: .type)
            try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        }
    }
}

public struct WorkoutMetricSummary: Codable, Sendable, Equatable {
    public let elapsedSeconds: TimeInterval
    public let averageHeartRateBPM: Double?
    public let maxHeartRateBPM: Double?
    public let distanceMeters: Double?
    public let activeEnergyKCal: Double?

    public init(
        elapsedSeconds: TimeInterval,
        averageHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil,
        distanceMeters: Double? = nil,
        activeEnergyKCal: Double? = nil
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.averageHeartRateBPM = averageHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.distanceMeters = distanceMeters
        self.activeEnergyKCal = activeEnergyKCal
    }
}

public struct WorkoutMetricReplay: Codable, Sendable, Equatable {
    public let events: [WorkoutMetricEvent]

    public init(events: [WorkoutMetricEvent]) {
        self.events = events
    }

    public var ticks: [WorkoutMetricTick] {
        events.compactMap { event in
            if case .metric(let tick) = event {
                return tick
            }
            return nil
        }
    }

    public var summary: WorkoutMetricSummary {
        let ticks = self.ticks
        let elapsed = events.reduce(TimeInterval(0)) { latest, event in
            max(latest, event.elapsedSeconds)
        }
        let heartRates = ticks.compactMap(\.heartRateBPM)
        return WorkoutMetricSummary(
            elapsedSeconds: elapsed,
            averageHeartRateBPM: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
            maxHeartRateBPM: heartRates.max(),
            distanceMeters: ticks.compactMap(\.distanceMeters).max(),
            activeEnergyKCal: ticks.compactMap(\.activeEnergyKCal).max()
        )
    }

    public func stream() -> AsyncStream<WorkoutMetricEvent> {
        let scripted = events
        return AsyncStream { continuation in
            for event in scripted {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

public extension WorkoutMetricEvent {
    var elapsedSeconds: TimeInterval {
        switch self {
        case .sessionStarted(let elapsedSeconds),
             .paused(let elapsedSeconds),
             .resumed(let elapsedSeconds),
             .sessionEnded(let elapsedSeconds):
            return elapsedSeconds
        case .metric(let tick):
            return tick.elapsedSeconds
        }
    }
}
