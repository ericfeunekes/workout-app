// HealthKitTypeMapping.swift
//
// Internal bridge from the HealthKit-free descriptor contract to concrete
// HealthKit sample types, units, permission sets, and cursor anchors.

import Foundation

#if canImport(HealthKit)
import HealthKit

public struct HealthKitPermissionSet: Sendable, Equatable {
    public let readTypeIDs: [String]
    public let shareTypeIDs: [String]

    public init(readTypeIDs: [String], shareTypeIDs: [String]) {
        self.readTypeIDs = readTypeIDs
        self.shareTypeIDs = shareTypeIDs
    }
}

struct HealthKitTypeMapping {
    let descriptor: HealthDataTypeDescriptor
    let objectType: HKObjectType
    let sampleType: HKSampleType
    let unit: HKUnit?
    let windowSemantics: HealthBatchWindowSemantics

    var typeID: String { descriptor.id }
}

enum HealthKitTypeMapper {
    static let supportedBatchDescriptors: [HealthDataTypeDescriptor] = [
        HealthDataTypeRegistry.heartRate,
        HealthDataTypeRegistry.bodyMass,
        HealthDataTypeRegistry.stepCount,
        HealthDataTypeRegistry.activeEnergyBurned,
        HealthDataTypeRegistry.sleepAnalysis,
        HealthDataTypeRegistry.workout,
    ]

    static func permissionSet(for requests: [HealthDataRequest]) throws
        -> (read: Set<HKObjectType>, share: Set<HKSampleType>) {
        try HealthDataRequestValidator.validateAuthorizationRequests(requests)
        var read: Set<HKObjectType> = []
        var share: Set<HKSampleType> = []
        for request in requests {
            let mapping = try mapping(for: request.type)
            switch request.access {
            case .read:
                read.insert(mapping.objectType)
            case .write:
                share.insert(mapping.sampleType)
            case .readWrite:
                read.insert(mapping.objectType)
                share.insert(mapping.sampleType)
            }
        }
        return (read, share)
    }

    static func debugPermissionSet(for requests: [HealthDataRequest]) throws -> HealthKitPermissionSet {
        let permissionSet = try permissionSet(for: requests)
        return HealthKitPermissionSet(
            readTypeIDs: permissionSet.read.map(typeIdentifier).sorted(),
            shareTypeIDs: permissionSet.share.map(typeIdentifier).sorted()
        )
    }

    static func mapping(for descriptor: HealthDataTypeDescriptor) throws -> HealthKitTypeMapping {
        switch descriptor.id {
        case HealthDataTypeRegistry.heartRate.id:
            return try quantityMapping(
                descriptor: HealthDataTypeRegistry.heartRate,
                identifier: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute())
            )
        case HealthDataTypeRegistry.bodyMass.id:
            return try quantityMapping(
                descriptor: HealthDataTypeRegistry.bodyMass,
                identifier: .bodyMass,
                unit: .gramUnit(with: .kilo)
            )
        case HealthDataTypeRegistry.stepCount.id:
            return try quantityMapping(
                descriptor: HealthDataTypeRegistry.stepCount,
                identifier: .stepCount,
                unit: .count()
            )
        case HealthDataTypeRegistry.activeEnergyBurned.id:
            return try quantityMapping(
                descriptor: HealthDataTypeRegistry.activeEnergyBurned,
                identifier: .activeEnergyBurned,
                unit: .kilocalorie()
            )
        case HealthDataTypeRegistry.sleepAnalysis.id:
            guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
                throw HealthKitError.unsupportedType(descriptor.id)
            }
            return HealthKitTypeMapping(
                descriptor: HealthDataTypeRegistry.sleepAnalysis,
                objectType: type,
                sampleType: type,
                unit: nil,
                windowSemantics: .overlap
            )
        case HealthDataTypeRegistry.workout.id:
            let type = HKObjectType.workoutType()
            return HealthKitTypeMapping(
                descriptor: HealthDataTypeRegistry.workout,
                objectType: type,
                sampleType: type,
                unit: nil,
                windowSemantics: .overlap
            )
        default:
            throw HealthKitError.unsupportedType(descriptor.id)
        }
    }

    private static func quantityMapping(
        descriptor: HealthDataTypeDescriptor,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) throws -> HealthKitTypeMapping {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.unsupportedType(descriptor.id)
        }
        return HealthKitTypeMapping(
            descriptor: descriptor,
            objectType: type,
            sampleType: type,
            unit: unit,
            windowSemantics: .strictStart
        )
    }

    private static func typeIdentifier(_ type: HKObjectType) -> String {
        if let quantity = type as? HKQuantityType {
            return quantity.identifier
        }
        if let category = type as? HKCategoryType {
            return category.identifier
        }
        if type == HKObjectType.workoutType() {
            return HealthDataTypeRegistry.workout.id
        }
        return String(describing: type)
    }
}

enum HealthBatchCursorCodec {
    struct Payload: Codable, Equatable {
        var anchorsByTypeID: [String: String]
    }

    static func decode(_ cursor: HealthBatchCursor?) throws -> [String: HKQueryAnchor] {
        guard let cursor else { return [:] }
        guard let data = Data(base64Encoded: cursor.value) else {
            throw HealthKitError.queryFailed("Invalid HealthKit batch cursor encoding")
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            var anchors: [String: HKQueryAnchor] = [:]
            for (typeID, anchorString) in payload.anchorsByTypeID {
                guard let anchorData = Data(base64Encoded: anchorString) else {
                    throw HealthKitError.queryFailed("Invalid HealthKit anchor encoding for \(typeID)")
                }
                guard let anchor = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: HKQueryAnchor.self,
                    from: anchorData
                ) else {
                    throw HealthKitError.queryFailed("Missing HealthKit anchor for \(typeID)")
                }
                anchors[typeID] = anchor
            }
            return anchors
        } catch let error as HealthKitError {
            throw error
        } catch {
            throw HealthKitError.queryFailed("Unable to decode HealthKit batch cursor: \(error)")
        }
    }

    static func encode(_ anchors: [String: HKQueryAnchor]) throws -> HealthBatchCursor? {
        guard !anchors.isEmpty else { return nil }
        do {
            var payload = Payload(anchorsByTypeID: [:])
            for (typeID, anchor) in anchors {
                let anchorData = try NSKeyedArchiver.archivedData(
                    withRootObject: anchor,
                    requiringSecureCoding: true
                )
                payload.anchorsByTypeID[typeID] = anchorData.base64EncodedString()
            }
            let data = try JSONEncoder().encode(payload)
            return HealthBatchCursor(data.base64EncodedString())
        } catch {
            throw HealthKitError.queryFailed("Unable to encode HealthKit batch cursor: \(error)")
        }
    }
}

enum HealthKitRecordNormalizer {
    static func normalize(sample: HKSample, mapping: HealthKitTypeMapping) throws -> HealthDataRecord {
        if let quantity = sample as? HKQuantitySample {
            guard let unit = mapping.unit else {
                throw HealthKitError.queryFailed("Missing unit for quantity \(mapping.typeID)")
            }
            return HealthDataRecord(
                id: quantity.uuid.uuidString,
                type: mapping.descriptor,
                sourceBundleIdentifier: quantity.sourceRevision.source.bundleIdentifier,
                start: quantity.startDate,
                end: quantity.endDate,
                value: .quantity(quantity.quantity.doubleValue(for: unit), unit: mapping.descriptor.defaultUnit ?? unit.unitString),
                metadata: safeMetadata(quantity.metadata)
            )
        }
        if let category = sample as? HKCategorySample {
            return HealthDataRecord(
                id: category.uuid.uuidString,
                type: mapping.descriptor,
                sourceBundleIdentifier: category.sourceRevision.source.bundleIdentifier,
                start: category.startDate,
                end: category.endDate,
                value: .category(category.value),
                metadata: safeMetadata(category.metadata)
            )
        }
        if let workout = sample as? HKWorkout {
            let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            return HealthDataRecord(
                id: workout.uuid.uuidString,
                type: mapping.descriptor,
                sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
                start: workout.startDate,
                end: workout.endDate,
                value: .workout(
                    activityType: String(workout.workoutActivityType.rawValue),
                    durationSeconds: workout.duration,
                    totalEnergyKcal: energy
                ),
                metadata: safeMetadata(workout.metadata)
            )
        }
        throw HealthKitError.unsupportedType(mapping.typeID)
    }

    private static func safeMetadata(_ metadata: [String: Any]?) -> [String: String] {
        guard let metadata else { return [:] }
        var output: [String: String] = [:]
        for (key, value) in metadata {
            switch value {
            case let string as String:
                output[key] = string
            case let number as NSNumber:
                output[key] = number.stringValue
            case let date as Date:
                output[key] = ISO8601DateFormatter().string(from: date)
            default:
                output[key] = String(describing: value)
            }
        }
        return output
    }
}
#endif
