import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

public struct HealthKitSimulatorProbeResult: Codable, Sendable {
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"failed to encode probe result"}"#
        }
        return string
    }
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
