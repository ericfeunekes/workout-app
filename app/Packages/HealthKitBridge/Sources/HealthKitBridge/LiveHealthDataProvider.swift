// LiveHealthDataProvider.swift
//
// Production placeholder for the generalized HealthKit data module. The
// simulator spike proved that HealthKit can support the batch/query mechanics;
// the concrete broad exporter still needs type-by-type mapping work.

import Foundation

public final class LiveHealthDataProvider:
    HealthPermissionBroker,
    HealthBatchDataProvider,
    HealthLiveDataProvider,
    @unchecked Sendable {

    public init() {}

    public func requestAuthorization(for requests: [HealthDataRequest]) async throws {
        _ = requests
        throw HealthKitError.notImplemented("General HealthKit permission broker")
    }

    public func fetch(_ query: HealthBatchQuery) async throws -> HealthBatchResult {
        _ = query
        throw HealthKitError.notImplemented("General HealthKit batch provider")
    }

    public func stream(for requests: [HealthDataRequest]) async throws
        -> AsyncThrowingStream<HealthDataRecord, Error> {
        _ = requests
        throw HealthKitError.notImplemented("General HealthKit live provider")
    }
}
