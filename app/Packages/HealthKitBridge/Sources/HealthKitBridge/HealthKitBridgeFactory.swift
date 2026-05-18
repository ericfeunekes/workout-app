// HealthKitBridgeFactory.swift
//
// Single composition point that returns the tuple of protocol instances the
// app needs — one for authorization, one for HR observation, one for body
// weight. Two variants:
//
//   • `.live()` — wraps `HKHealthStore`. On macOS (where HealthKit does not
//     exist) the stubs throw `.notAvailable` so the package still links.
//   • `.mock(...)` — in-memory fakes for Features tests. Each slot is
//     configurable independently.
//
// Features depend on the protocols, not the concrete types. This factory
// is the one place where "real" vs "mock" is chosen.

import Foundation

public struct HealthKitBridgeBundle: Sendable {
    public let auth: HealthAuthorization
    public let hr: HeartRateObserver
    public let bw: BodyWeightReader
    public let permissions: HealthPermissionBroker
    public let batch: HealthBatchDataProvider
    public let live: HealthLiveDataProvider

    public init(
        auth: HealthAuthorization,
        hr: HeartRateObserver,
        bw: BodyWeightReader,
        permissions: HealthPermissionBroker,
        batch: HealthBatchDataProvider,
        live: HealthLiveDataProvider
    ) {
        self.auth = auth
        self.hr = hr
        self.bw = bw
        self.permissions = permissions
        self.batch = batch
        self.live = live
    }
}

public enum HealthKitBridgeFactory {

    /// Live HealthKit-backed bundle. On macOS the three `Live…` stubs throw
    /// `.notAvailable` — building against them is fine; calling them isn't.
    public static func live() -> HealthKitBridgeBundle {
        #if canImport(HealthKit)
        return HealthKitBridgeBundle(
            auth: LiveHealthKitAuthorization(),
            hr: LiveHeartRateObserver(),
            bw: LiveBodyWeightReader(),
            permissions: LiveHealthDataProvider(),
            batch: LiveHealthDataProvider(),
            live: LiveHealthDataProvider()
        )
        #else
        return HealthKitBridgeBundle(
            auth: LiveHealthKitAuthorization(),
            hr: LiveHeartRateObserver(),
            bw: LiveBodyWeightReader(),
            permissions: LiveHealthDataProvider(),
            batch: LiveHealthDataProvider(),
            live: LiveHealthDataProvider()
        )
        #endif
    }

    /// In-memory fakes. All three slots default to "authorized + empty"
    /// — pass explicit fakes to script richer behavior.
    public static func mock(
        auth: HealthAuthorization = FakeHealthAuthorization(initiallyAuthorized: true),
        hr: HeartRateObserver = FakeHeartRateObserver(),
        bw: BodyWeightReader = FakeBodyWeightReader(kg: nil),
        permissions: HealthPermissionBroker = FakeHealthPermissionBroker(),
        batch: HealthBatchDataProvider = FakeHealthBatchDataProvider(),
        live: HealthLiveDataProvider = FakeHealthLiveDataProvider()
    ) -> HealthKitBridgeBundle {
        HealthKitBridgeBundle(
            auth: auth,
            hr: hr,
            bw: bw,
            permissions: permissions,
            batch: batch,
            live: live
        )
    }
}
