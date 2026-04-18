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

    public init(
        auth: HealthAuthorization,
        hr: HeartRateObserver,
        bw: BodyWeightReader
    ) {
        self.auth = auth
        self.hr = hr
        self.bw = bw
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
            bw: LiveBodyWeightReader()
        )
        #else
        return HealthKitBridgeBundle(
            auth: LiveHealthKitAuthorization(),
            hr: LiveHeartRateObserver(),
            bw: LiveBodyWeightReader()
        )
        #endif
    }

    /// In-memory fakes. All three slots default to "authorized + empty"
    /// — pass explicit fakes to script richer behavior.
    public static func mock(
        auth: HealthAuthorization = FakeHealthAuthorization(initiallyAuthorized: true),
        hr: HeartRateObserver = FakeHeartRateObserver(),
        bw: BodyWeightReader = FakeBodyWeightReader(kg: nil)
    ) -> HealthKitBridgeBundle {
        HealthKitBridgeBundle(auth: auth, hr: hr, bw: bw)
    }
}
