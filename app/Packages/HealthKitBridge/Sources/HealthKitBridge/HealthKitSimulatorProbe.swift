import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

public struct HealthKitSimulatorProbeResult: Codable, Sendable {
    public var runID: String?
    public var platform: String
    public var healthDataAvailable: Bool
    public var authorization: ProbeStep
    public var quantitySamples: [ProbeStep]
    public var categorySample: ProbeStep
    public var workoutSample: ProbeStep
    public var anchoredInsert: ProbeStep
    public var anchoredDelete: ProbeStep
    public var notes: [String]

    public init(
        runID: String? = nil,
        platform: String,
        healthDataAvailable: Bool,
        authorization: ProbeStep,
        quantitySamples: [ProbeStep],
        categorySample: ProbeStep,
        workoutSample: ProbeStep,
        anchoredInsert: ProbeStep,
        anchoredDelete: ProbeStep,
        notes: [String]
    ) {
        self.runID = runID
        self.platform = platform
        self.healthDataAvailable = healthDataAvailable
        self.authorization = authorization
        self.quantitySamples = quantitySamples
        self.categorySample = categorySample
        self.workoutSample = workoutSample
        self.anchoredInsert = anchoredInsert
        self.anchoredDelete = anchoredDelete
        self.notes = notes
    }
}

public struct HealthKitSimulatorArchiveProbeResult: Codable, Sendable {
    public var runID: String?
    public var requestSetKey: String
    public var authorizedRequestTypeIDs: [String]
    public var fetchedRequestTypeIDs: [String]
    public var authorizedRequestFingerprints: [String]
    public var fetchedRequestFingerprints: [String]
    public var capability: HealthKitSimulatorProbeResult
    public var batch: HealthBatchResult?
    public var authorizationRequestCompleted: Bool
    public var archiveFetchSucceeded: Bool
    public var archiveFetchError: String?
    public var projectionPersisted: Bool
    public var projectionError: String?
    public var thisRunSamplesFetched: Bool
    public var cursorPresent: Bool
    public var firstCursorPresent: Bool
    public var secondCursorPresent: Bool
    public var secondFetchUsedFirstCursor: Bool
    public var firstCursorValue: String?
    public var secondFetchCursorInput: String?
    public var secondCursorValue: String?
    public var deletedExternalIDs: [String]
    public var deletedRecordMatchedFirstPass: Bool
    public var projectionDeletedExternalIDs: [String]
    public var projectionMatchedDeletedRecord: Bool
    public var projectionRecordExternalIDs: [String]
    public var projectionMatchedRecords: Bool
    public var projectionCursorValue: String?
    public var projectionMatchedCursor: Bool
    public var projectionStoreKind: String?
    public var projectionReopenMatched: Bool
    public var representativeRecordIDs: [String]

    public init(
        runID: String? = nil,
        requestSetKey: String = "",
        authorizedRequestTypeIDs: [String] = [],
        fetchedRequestTypeIDs: [String] = [],
        authorizedRequestFingerprints: [String] = [],
        fetchedRequestFingerprints: [String] = [],
        capability: HealthKitSimulatorProbeResult,
        batch: HealthBatchResult?,
        authorizationRequestCompleted: Bool,
        archiveFetchSucceeded: Bool,
        archiveFetchError: String? = nil,
        projectionPersisted: Bool = false,
        projectionError: String? = nil,
        thisRunSamplesFetched: Bool = false,
        cursorPresent: Bool = false,
        firstCursorPresent: Bool = false,
        secondCursorPresent: Bool = false,
        secondFetchUsedFirstCursor: Bool = false,
        firstCursorValue: String? = nil,
        secondFetchCursorInput: String? = nil,
        secondCursorValue: String? = nil,
        deletedExternalIDs: [String] = [],
        deletedRecordMatchedFirstPass: Bool = false,
        projectionDeletedExternalIDs: [String] = [],
        projectionMatchedDeletedRecord: Bool = false,
        projectionRecordExternalIDs: [String] = [],
        projectionMatchedRecords: Bool = false,
        projectionCursorValue: String? = nil,
        projectionMatchedCursor: Bool = false,
        projectionStoreKind: String? = nil,
        projectionReopenMatched: Bool = false,
        representativeRecordIDs: [String] = []
    ) {
        self.runID = runID
        self.requestSetKey = requestSetKey
        self.authorizedRequestTypeIDs = authorizedRequestTypeIDs
        self.fetchedRequestTypeIDs = fetchedRequestTypeIDs
        self.authorizedRequestFingerprints = authorizedRequestFingerprints
        self.fetchedRequestFingerprints = fetchedRequestFingerprints
        self.capability = capability
        self.batch = batch
        self.authorizationRequestCompleted = authorizationRequestCompleted
        self.archiveFetchSucceeded = archiveFetchSucceeded
        self.archiveFetchError = archiveFetchError
        self.projectionPersisted = projectionPersisted
        self.projectionError = projectionError
        self.thisRunSamplesFetched = thisRunSamplesFetched
        self.cursorPresent = cursorPresent
        self.firstCursorPresent = firstCursorPresent
        self.secondCursorPresent = secondCursorPresent
        self.secondFetchUsedFirstCursor = secondFetchUsedFirstCursor
        self.firstCursorValue = firstCursorValue
        self.secondFetchCursorInput = secondFetchCursorInput
        self.secondCursorValue = secondCursorValue
        self.deletedExternalIDs = deletedExternalIDs
        self.deletedRecordMatchedFirstPass = deletedRecordMatchedFirstPass
        self.projectionDeletedExternalIDs = projectionDeletedExternalIDs
        self.projectionMatchedDeletedRecord = projectionMatchedDeletedRecord
        self.projectionRecordExternalIDs = projectionRecordExternalIDs
        self.projectionMatchedRecords = projectionMatchedRecords
        self.projectionCursorValue = projectionCursorValue
        self.projectionMatchedCursor = projectionMatchedCursor
        self.projectionStoreKind = projectionStoreKind
        self.projectionReopenMatched = projectionReopenMatched
        self.representativeRecordIDs = representativeRecordIDs
    }

    public func withProjectionResult(
        success: Bool,
        error: String? = nil,
        projectionDeletedExternalIDs: [String] = [],
        projectionMatchedDeletedRecord: Bool = false,
        projectionRecordExternalIDs: [String] = [],
        projectionMatchedRecords: Bool = false,
        projectionCursorValue: String? = nil,
        projectionMatchedCursor: Bool = false,
        projectionStoreKind: String? = nil,
        projectionReopenMatched: Bool = false
    ) -> Self {
        var copy = self
        copy.projectionPersisted = success
        copy.projectionError = error
        copy.projectionDeletedExternalIDs = projectionDeletedExternalIDs
        copy.projectionMatchedDeletedRecord = projectionMatchedDeletedRecord
        copy.projectionRecordExternalIDs = projectionRecordExternalIDs
        copy.projectionMatchedRecords = projectionMatchedRecords
        copy.projectionCursorValue = projectionCursorValue
        copy.projectionMatchedCursor = projectionMatchedCursor
        copy.projectionStoreKind = projectionStoreKind
        copy.projectionReopenMatched = projectionReopenMatched
        return copy
    }
}

public struct ProbeStep: Codable, Sendable {
    public var name: String
    public var success: Bool
    public var detail: String

    public init(name: String, success: Bool, detail: String) {
        self.name = name
        self.success = success
        self.detail = detail
    }
}

public enum HealthKitSimulatorProbe {
    public static func run() async -> HealthKitSimulatorProbeResult {
        #if canImport(HealthKit)
        let store = HKHealthStore()
        let available = HKHealthStore.isHealthDataAvailable()
        guard available else {
            return HealthKitSimulatorProbeResult(
                platform: platformName,
                healthDataAvailable: false,
                authorization: ProbeStep(name: "authorization", success: false, detail: "Health data unavailable"),
                quantitySamples: [],
                categorySample: ProbeStep(name: "sleepAnalysis", success: false, detail: "Not run"),
                workoutSample: ProbeStep(name: "workout", success: false, detail: "Not run"),
                anchoredInsert: ProbeStep(name: "anchoredInsert", success: false, detail: "Not run"),
                anchoredDelete: ProbeStep(name: "anchoredDelete", success: false, detail: "Not run"),
                notes: ["HKHealthStore.isHealthDataAvailable() returned false"]
            )
        }

        let descriptors = quantityDescriptors()
        let quantityTypes = descriptors.compactMap { HKQuantityType.quantityType(forIdentifier: $0.identifier) }
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        let workoutType = HKObjectType.workoutType()
        let readTypes = Set<HKObjectType>(quantityTypes + [sleepType, workoutType].compactMap { $0 })
        let shareTypes = Set<HKSampleType>(quantityTypes + [sleepType, workoutType].compactMap { $0 })
        let authorization = await requestAuthorization(store, toShare: shareTypes, read: readTypes)

        var notes: [String] = []
        if !authorization.success {
            notes.append("Authorization failed; subsequent writes and reads may fail.")
        }

        let runID = UUID().uuidString
        let now = Date()
        let quantityResults = await writeAndReadQuantities(
            store,
            descriptors: descriptors,
            runID: runID,
            start: now
        )
        let categoryResult = await writeAndReadSleep(store, runID: runID, start: now)
        let workoutResult = await writeAndReadWorkout(store, runID: runID, start: now)
        let anchorResults = await runAnchorRoundTrip(store, runID: runID, start: now)

        return HealthKitSimulatorProbeResult(
            runID: runID,
            platform: platformName,
            healthDataAvailable: available,
            authorization: authorization,
            quantitySamples: quantityResults,
            categorySample: categoryResult,
            workoutSample: workoutResult,
            anchoredInsert: anchorResults.insert,
            anchoredDelete: anchorResults.delete,
            notes: notes
        )
        #else
        return HealthKitSimulatorProbeResult(
            platform: platformName,
            healthDataAvailable: false,
            authorization: ProbeStep(name: "authorization", success: false, detail: "HealthKit not importable"),
            quantitySamples: [],
            categorySample: ProbeStep(name: "sleepAnalysis", success: false, detail: "Not run"),
            workoutSample: ProbeStep(name: "workout", success: false, detail: "Not run"),
            anchoredInsert: ProbeStep(name: "anchoredInsert", success: false, detail: "Not run"),
            anchoredDelete: ProbeStep(name: "anchoredDelete", success: false, detail: "Not run"),
            notes: ["HealthKit cannot be imported on this platform"]
        )
        #endif
    }

    public static func encodedJSON(_ result: HealthKitSimulatorProbeResult) -> String {
        encoded(result)
    }

    public static func encodedArchiveJSON(_ result: HealthKitSimulatorArchiveProbeResult) -> String {
        encoded(result)
    }

    public static func runArchiveFetch() async -> HealthKitSimulatorArchiveProbeResult {
        #if canImport(HealthKit)
        let runID = UUID().uuidString
        let requestSetKey = "debug-healthkit-simulator-probe"
        let store = HKHealthStore()
        let provider = LiveHealthDataProvider(store: store)
        let now = Date()
        let requests = HealthKitTypeMapper.supportedBatchDescriptors.map {
            HealthDataRequest(type: $0, access: .readWrite, delivery: .batch)
        }
        let requestTypeIDs = requests.map(\.type.id).sorted()
        let requestFingerprints = requestFingerprints(for: requests)
        let notRunCapability = HealthKitSimulatorProbeResult(
            runID: runID,
            platform: platformName,
            healthDataAvailable: HKHealthStore.isHealthDataAvailable(),
            authorization: ProbeStep(name: "authorization", success: false, detail: "Archive proof handles authorization"),
            quantitySamples: [],
            categorySample: ProbeStep(name: "sleepAnalysis", success: false, detail: "Archive proof handles samples"),
            workoutSample: ProbeStep(name: "workout", success: false, detail: "Archive proof handles samples"),
            anchoredInsert: ProbeStep(name: "anchoredInsert", success: false, detail: "Archive proof handles cursor"),
            anchoredDelete: ProbeStep(name: "anchoredDelete", success: false, detail: "Archive proof handles delete"),
            notes: ["Dedicated archive proof flow"]
        )
        do {
            try await provider.requestAuthorization(for: requests)
        } catch {
            return HealthKitSimulatorArchiveProbeResult(
                runID: runID,
                requestSetKey: requestSetKey,
                authorizedRequestTypeIDs: requestTypeIDs,
                fetchedRequestTypeIDs: requestTypeIDs,
                authorizedRequestFingerprints: requestFingerprints,
                fetchedRequestFingerprints: requestFingerprints,
                capability: notRunCapability,
                batch: nil,
                authorizationRequestCompleted: false,
                archiveFetchSucceeded: false,
                archiveFetchError: "Authorization failed: \(error)"
            )
        }
        let query = HealthBatchQuery(
            requests: requests,
            start: now.addingTimeInterval(-600),
            end: now.addingTimeInterval(600)
        )
        do {
            let proofSamples = try archiveProofSamples(runID: runID, start: now)
            for sample in proofSamples {
                try await save(store, sample)
            }
            let firstBatch = try await provider.fetch(query)
            let firstRecords = firstBatch.records.filter {
                $0.metadata["setmark_probe_run_id"] == runID
            }
            guard let sampleToDelete = proofSamples.first(where: { sample in
                firstRecords.contains { $0.id == sample.uuid.uuidString }
            }) else {
                return HealthKitSimulatorArchiveProbeResult(
                    runID: runID,
                    requestSetKey: requestSetKey,
                    authorizedRequestTypeIDs: requestTypeIDs,
                    fetchedRequestTypeIDs: requestTypeIDs,
                    authorizedRequestFingerprints: requestFingerprints,
                    fetchedRequestFingerprints: requestFingerprints,
                    capability: notRunCapability,
                    batch: firstBatch,
                    authorizationRequestCompleted: true,
                    archiveFetchSucceeded: true,
                    thisRunSamplesFetched: false,
                    cursorPresent: firstBatch.nextCursor != nil,
                    firstCursorPresent: firstBatch.nextCursor != nil,
                    representativeRecordIDs: firstRecords.map(\.id).sorted()
                )
            }
            try await delete(store, sampleToDelete)
            let secondQuery = HealthBatchQuery(
                requests: requests,
                start: now.addingTimeInterval(-600),
                end: now.addingTimeInterval(600),
                cursor: firstBatch.nextCursor
            )
            let secondBatch = try await provider.fetch(secondQuery)
            let deletedIDs = secondBatch.deletedRecords.map(\.externalID).sorted()
            let deletedID = sampleToDelete.uuid.uuidString
            let matchedDelete = deletedIDs.contains(deletedID)
            let combinedBatch = HealthBatchResult(
                records: firstBatch.records + secondBatch.records,
                deletedRecords: secondBatch.deletedRecords,
                nextCursor: secondBatch.nextCursor
            )
            return HealthKitSimulatorArchiveProbeResult(
                runID: runID,
                requestSetKey: requestSetKey,
                authorizedRequestTypeIDs: requestTypeIDs,
                fetchedRequestTypeIDs: requestTypeIDs,
                authorizedRequestFingerprints: requestFingerprints,
                fetchedRequestFingerprints: requestFingerprints,
                capability: HealthKitSimulatorProbeResult(
                    runID: runID,
                    platform: platformName,
                    healthDataAvailable: true,
                    authorization: ProbeStep(name: "authorization", success: true, detail: "provider requestAuthorization returned success"),
                    quantitySamples: [],
                    categorySample: ProbeStep(name: "sleepAnalysis", success: true, detail: "archive proof wrote samples"),
                    workoutSample: ProbeStep(name: "workout", success: true, detail: "archive proof wrote samples"),
                    anchoredInsert: ProbeStep(name: "anchoredInsert", success: !firstRecords.isEmpty, detail: "first records=\(firstRecords.count)"),
                    anchoredDelete: ProbeStep(name: "anchoredDelete", success: matchedDelete, detail: "deleted=\(deletedIDs.count)"),
                    notes: ["Dedicated archive proof flow"]
                ),
                batch: combinedBatch,
                authorizationRequestCompleted: true,
                archiveFetchSucceeded: true,
                thisRunSamplesFetched: !firstRecords.isEmpty,
                cursorPresent: firstBatch.nextCursor != nil && secondBatch.nextCursor != nil,
                firstCursorPresent: firstBatch.nextCursor != nil,
                secondCursorPresent: secondBatch.nextCursor != nil,
                secondFetchUsedFirstCursor: secondQuery.cursor == firstBatch.nextCursor,
                firstCursorValue: firstBatch.nextCursor?.value,
                secondFetchCursorInput: secondQuery.cursor?.value,
                secondCursorValue: secondBatch.nextCursor?.value,
                deletedExternalIDs: deletedIDs,
                deletedRecordMatchedFirstPass: matchedDelete,
                representativeRecordIDs: firstRecords.map(\.id).sorted()
            )
        } catch {
            return HealthKitSimulatorArchiveProbeResult(
                runID: runID,
                requestSetKey: requestSetKey,
                authorizedRequestTypeIDs: requestTypeIDs,
                fetchedRequestTypeIDs: requestTypeIDs,
                authorizedRequestFingerprints: requestFingerprints,
                fetchedRequestFingerprints: requestFingerprints,
                capability: notRunCapability,
                batch: nil,
                authorizationRequestCompleted: true,
                archiveFetchSucceeded: false,
                archiveFetchError: String(describing: error)
            )
        }
        #else
        return HealthKitSimulatorArchiveProbeResult(
            capability: HealthKitSimulatorProbeResult(
                platform: platformName,
                healthDataAvailable: false,
                authorization: ProbeStep(name: "authorization", success: false, detail: "HealthKit not importable"),
                quantitySamples: [],
                categorySample: ProbeStep(name: "sleepAnalysis", success: false, detail: "Not run"),
                workoutSample: ProbeStep(name: "workout", success: false, detail: "Not run"),
                anchoredInsert: ProbeStep(name: "anchoredInsert", success: false, detail: "Not run"),
                anchoredDelete: ProbeStep(name: "anchoredDelete", success: false, detail: "Not run"),
                notes: ["HealthKit cannot be imported on this platform"]
            ),
            batch: nil,
            authorizationRequestCompleted: false,
            archiveFetchSucceeded: false,
            archiveFetchError: "HealthKit cannot be imported on this platform"
        )
        #endif
    }
}

private func encoded<T: Encodable>(_ result: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"failed to encode probe result"}"#
        }
        return string
}

private func requestFingerprints(for requests: [HealthDataRequest]) -> [String] {
    requests
        .map {
            "\($0.type.id)|\($0.type.kind.rawValue)|\($0.access.rawValue)|\($0.delivery.rawValue)"
        }
        .sorted()
}

private var platformName: String {
    #if targetEnvironment(simulator)
    return "simulator"
    #elseif os(iOS)
    return "iOS-device"
    #elseif os(watchOS)
    return "watchOS"
    #else
    return "other"
    #endif
}

#if canImport(HealthKit)
private struct QuantityDescriptor {
    let name: String
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let value: Double
}

private func quantityDescriptors() -> [QuantityDescriptor] {
    [
        QuantityDescriptor(name: "heartRate", identifier: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), value: 123),
        QuantityDescriptor(name: "bodyMass", identifier: .bodyMass, unit: .gramUnit(with: .kilo), value: 81.2),
        QuantityDescriptor(name: "stepCount", identifier: .stepCount, unit: .count(), value: 42),
        QuantityDescriptor(name: "activeEnergyBurned", identifier: .activeEnergyBurned, unit: .kilocalorie(), value: 12.3),
    ]
}

private func archiveProofSamples(runID: String, start: Date) throws -> [HKSample] {
    var samples: [HKSample] = []
    for (offset, descriptor) in quantityDescriptors().enumerated() {
        guard let type = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) else {
            throw HealthKitError.unsupportedType(descriptor.identifier.rawValue)
        }
        let sampleStart = start.addingTimeInterval(Double(offset))
        samples.append(HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: descriptor.unit, doubleValue: descriptor.value),
            start: sampleStart,
            end: sampleStart,
            metadata: probeMetadata(runID)
        ))
    }
    guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
        throw HealthKitError.unsupportedType(HealthDataTypeRegistry.sleepAnalysis.id)
    }
    samples.append(HKCategorySample(
        type: sleepType,
        value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        start: start.addingTimeInterval(10),
        end: start.addingTimeInterval(70),
        metadata: probeMetadata(runID)
    ))
    samples.append(HKWorkout(
        activityType: .traditionalStrengthTraining,
        start: start.addingTimeInterval(80),
        end: start.addingTimeInterval(140),
        duration: 60,
        totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 8),
        totalDistance: nil,
        metadata: probeMetadata(runID)
    ))
    return samples
}

private func requestAuthorization(
    _ store: HKHealthStore,
    toShare shareTypes: Set<HKSampleType>,
    read readTypes: Set<HKObjectType>
) async -> ProbeStep {
    do {
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        return ProbeStep(name: "authorization", success: true, detail: "requestAuthorization returned success")
    } catch {
        return ProbeStep(name: "authorization", success: false, detail: String(describing: error))
    }
}

private func writeAndReadQuantities(
    _ store: HKHealthStore,
    descriptors: [QuantityDescriptor],
    runID: String,
    start: Date
) async -> [ProbeStep] {
    var results: [ProbeStep] = []
    for (offset, descriptor) in descriptors.enumerated() {
        guard let type = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) else {
            results.append(ProbeStep(name: descriptor.name, success: false, detail: "Type unavailable"))
            continue
        }
        let sampleStart = start.addingTimeInterval(Double(offset))
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: descriptor.unit, doubleValue: descriptor.value),
            start: sampleStart,
            end: sampleStart,
            metadata: probeMetadata(runID)
        )
        do {
            try await save(store, sample)
            let count = try await sampleCount(store, type: type, runID: runID)
            results.append(ProbeStep(name: descriptor.name, success: count > 0, detail: "saved; matching sample count=\(count)"))
        } catch {
            results.append(ProbeStep(name: descriptor.name, success: false, detail: String(describing: error)))
        }
    }
    return results
}

private func writeAndReadSleep(_ store: HKHealthStore, runID: String, start: Date) async -> ProbeStep {
    guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
        return ProbeStep(name: "sleepAnalysis", success: false, detail: "Type unavailable")
    }
    let sample = HKCategorySample(
        type: type,
        value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        start: start.addingTimeInterval(10),
        end: start.addingTimeInterval(70),
        metadata: probeMetadata(runID)
    )
    do {
        try await save(store, sample)
        let count = try await sampleCount(store, type: type, runID: runID)
        return ProbeStep(name: "sleepAnalysis", success: count > 0, detail: "saved; matching sample count=\(count)")
    } catch {
        return ProbeStep(name: "sleepAnalysis", success: false, detail: String(describing: error))
    }
}

private func writeAndReadWorkout(_ store: HKHealthStore, runID: String, start: Date) async -> ProbeStep {
    let workout = HKWorkout(
        activityType: .traditionalStrengthTraining,
        start: start.addingTimeInterval(80),
        end: start.addingTimeInterval(140),
        duration: 60,
        totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 8),
        totalDistance: nil,
        metadata: probeMetadata(runID)
    )
    do {
        try await save(store, workout)
        let count = try await sampleCount(store, type: HKObjectType.workoutType(), runID: runID)
        return ProbeStep(name: "workout", success: count > 0, detail: "saved; matching sample count=\(count)")
    } catch {
        return ProbeStep(name: "workout", success: false, detail: String(describing: error))
    }
}

private func runAnchorRoundTrip(
    _ store: HKHealthStore,
    runID: String,
    start: Date
) async -> (insert: ProbeStep, delete: ProbeStep) {
    guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
        let step = ProbeStep(name: "anchoredInsert", success: false, detail: "heartRate type unavailable")
        return (step, ProbeStep(name: "anchoredDelete", success: false, detail: "heartRate type unavailable"))
    }
    do {
        let predicate = metadataPredicate(runID)
        let initial = try await anchoredQuery(store, type: type, predicate: predicate, anchor: nil)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 131),
            start: start.addingTimeInterval(160),
            end: start.addingTimeInterval(160),
            metadata: probeMetadata(runID)
        )
        try await save(store, sample)
        let afterInsert = try await anchoredQuery(store, type: type, predicate: predicate, anchor: initial.anchor)
        try await delete(store, sample)
        let afterDelete = try await anchoredQuery(store, type: type, predicate: predicate, anchor: afterInsert.anchor)
        return (
            ProbeStep(
                name: "anchoredInsert",
                success: !afterInsert.samples.isEmpty,
                detail: "insert samples=\(afterInsert.samples.count); deleted=\(afterInsert.deleted.count)"
            ),
            ProbeStep(
                name: "anchoredDelete",
                success: !afterDelete.deleted.isEmpty,
                detail: "insert samples=\(afterDelete.samples.count); deleted=\(afterDelete.deleted.count)"
            )
        )
    } catch {
        let detail = String(describing: error)
        return (
            ProbeStep(name: "anchoredInsert", success: false, detail: detail),
            ProbeStep(name: "anchoredDelete", success: false, detail: detail)
        )
    }
}

private func probeMetadata(_ runID: String) -> [String: Any] {
    ["setmark_probe_run_id": runID]
}

private func metadataPredicate(_ runID: String) -> NSPredicate {
    HKQuery.predicateForObjects(withMetadataKey: "setmark_probe_run_id", allowedValues: [runID])
}

private func save(_ store: HKHealthStore, _ object: HKObject) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        store.save(object) { _, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

private func delete(_ store: HKHealthStore, _ object: HKObject) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        store.delete(object) { _, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

private func sampleCount(_ store: HKHealthStore, type: HKSampleType, runID: String) async throws -> Int {
    try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: type,
            predicate: metadataPredicate(runID),
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: samples?.count ?? 0)
            }
        }
        store.execute(query)
    }
}

private func anchoredQuery(
    _ store: HKHealthStore,
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
                continuation.resume(throwing: error)
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
