// LiveHealthDataProvider.swift
//
// Production placeholder for the generalized HealthKit data module. The
// simulator spike proved that HealthKit can support the batch/query mechanics;
// the concrete broad exporter still needs type-by-type mapping work.

import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

public final class LiveHealthDataProvider:
    HealthPermissionBroker,
    HealthBatchDataProvider,
    HealthLiveDataProvider,
    @unchecked Sendable {

    #if canImport(HealthKit)
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }
    #else
    public init() {}
    #endif

    public func requestAuthorization(for requests: [HealthDataRequest]) async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try HealthDataRequestValidator.validateAuthorizationRequests(requests)
        let permissions = try HealthKitTypeMapper.permissionSet(for: requests)
        do {
            try await store.requestAuthorization(toShare: permissions.share, read: permissions.read)
        } catch {
            throw HealthKitError.queryFailed("HealthKit authorization failed: \(error)")
        }
        #else
        _ = requests
        throw HealthKitError.notAvailable
        #endif
    }

    public func fetch(_ query: HealthBatchQuery) async throws -> HealthBatchResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let mappings = try validateBatchQuery(query)
        let incomingAnchors = try HealthBatchCursorCodec.decode(query.cursor)
        var outgoingAnchors = incomingAnchors
        var records: [HealthDataRecord] = []
        var deletedRecords: [HealthDeletedRecord] = []

        for mapping in mappings {
            let result = try await anchoredQuery(
                store: store,
                type: mapping.sampleType,
                predicate: datePredicate(
                    start: query.start,
                    end: query.end,
                    semantics: mapping.windowSemantics
                ),
                anchor: incomingAnchors[mapping.typeID]
            )
            for sample in result.samples {
                records.append(try HealthKitRecordNormalizer.normalize(sample: sample, mapping: mapping))
            }
            deletedRecords.append(contentsOf: result.deleted.map {
                HealthDeletedRecord(externalID: $0.uuid.uuidString, type: mapping.descriptor)
            })
            if let anchor = result.anchor {
                outgoingAnchors[mapping.typeID] = anchor
            }
        }
        return HealthBatchResult(
            records: records,
            deletedRecords: deletedRecords,
            nextCursor: try HealthBatchCursorCodec.encode(outgoingAnchors)
        )
        #else
        _ = query
        throw HealthKitError.notAvailable
        #endif
    }

    public func stream(for requests: [HealthDataRequest]) async throws
        -> AsyncThrowingStream<HealthDataRecord, Error> {
        try HealthDataRequestValidator.validateLiveStreamRequests(requests)
        throw HealthKitError.notImplemented("General HealthKit live provider")
    }

    public static func supportedBatchTypes() -> [HealthDataTypeDescriptor] {
        HealthArchiveDescriptorCatalog.supportedBatchTypes()
    }

    public static func debugPermissionSet(for requests: [HealthDataRequest]) throws
        -> HealthKitPermissionSet {
        #if canImport(HealthKit)
        return try HealthKitTypeMapper.debugPermissionSet(for: requests)
        #else
        _ = requests
        throw HealthKitError.notAvailable
        #endif
    }

    public static func debugWindowSemantics(for descriptor: HealthDataTypeDescriptor) throws
        -> HealthBatchWindowSemantics {
        #if canImport(HealthKit)
        return try HealthKitTypeMapper.mapping(for: descriptor).windowSemantics
        #else
        _ = descriptor
        throw HealthKitError.notAvailable
        #endif
    }

    public static func debugValidatedBatchTypeIDs(_ query: HealthBatchQuery) throws -> [String] {
        #if canImport(HealthKit)
        return try validateBatchQuery(query).map(\.typeID)
        #else
        _ = query
        throw HealthKitError.notAvailable
        #endif
    }

}

#if !canImport(HealthKit)
public struct HealthKitPermissionSet: Sendable, Equatable {
    public let readTypeIDs: [String]
    public let shareTypeIDs: [String]

    public init(readTypeIDs: [String], shareTypeIDs: [String]) {
        self.readTypeIDs = readTypeIDs
        self.shareTypeIDs = shareTypeIDs
    }
}
#endif

#if canImport(HealthKit)
private func validateBatchQuery(_ query: HealthBatchQuery) throws -> [HealthKitTypeMapping] {
    try HealthDataRequestValidator.validateBatchFetchRequests(query.requests)
    return try query.requests.map { request in
        return try HealthKitTypeMapper.mapping(for: request.type)
    }
}

private func datePredicate(
    start: Date?,
    end: Date?,
    semantics: HealthBatchWindowSemantics
) -> NSPredicate? {
    guard start != nil || end != nil else { return nil }
    let options: HKQueryOptions = semantics == .strictStart ? [.strictStartDate] : []
    return HKQuery.predicateForSamples(
        withStart: start,
        end: end,
        options: options
    )
}

private func anchoredQuery(
    store: HKHealthStore,
    type: HKSampleType,
    predicate: NSPredicate?,
    anchor: HKQueryAnchor?
) async throws -> (samples: [HKSample], deleted: [HKDeletedObject], anchor: HKQueryAnchor?) {
    try await withCheckedThrowingContinuation { continuation in
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { _, samples, deletedObjects, newAnchor, error in
            if let error {
                continuation.resume(throwing: HealthKitError.queryFailed(String(describing: error)))
            } else {
                continuation.resume(returning: (
                    samples ?? [],
                    deletedObjects ?? [],
                    newAnchor
                ))
            }
        }
        store.execute(query)
    }
}
#endif
