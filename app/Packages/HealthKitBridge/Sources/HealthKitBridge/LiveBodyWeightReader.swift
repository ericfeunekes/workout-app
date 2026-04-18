// LiveBodyWeightReader.swift
//
// Reads the most recent `bodyMass` sample from HealthKit. Per
// `docs/prescription.md`, the iOS app prefers the server-pushed
// `user_parameters["bodyweight_kg"]` value; this reader is the fallback
// for when no parameter has been synced.

import Foundation

#if canImport(HealthKit)
import HealthKit

public final class LiveBodyWeightReader: BodyWeightReader, @unchecked Sendable {
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func latestBodyWeightKg() async throws -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let type = HKQuantityType(.bodyMass)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error = error {
                    cont.resume(throwing: HealthKitError.queryFailed(String(describing: error)))
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                cont.resume(returning: kg)
            }
            store.execute(query)
        }
    }
}

#else

public final class LiveBodyWeightReader: BodyWeightReader, @unchecked Sendable {
    public init() {}
    public func latestBodyWeightKg() async throws -> Double? {
        throw HealthKitError.notAvailable
    }
}

#endif
