// LiveHealthKitAuthorization.swift
//
// Wraps `HKHealthStore.requestAuthorization(toShare:read:)` with the three
// read types this app needs: HR, cadence (running step cadence), and
// body-mass. We do not request any write permissions — the workout session
// does not write `HKWorkout` samples in v1 (see ADR-2026-04-17-ux-scope §4).
//
// Compile-guard: HealthKit is only available on iOS and watchOS. On macOS
// (where tests compile on a CLT-only machine) the guard falls through to the
// stub below, which always throws `.notAvailable`.

import Foundation

#if canImport(HealthKit)
import HealthKit

/// Live authorization wrapper. Thread-safe because `HKHealthStore` is
/// documented as safe to call from any thread.
public final class LiveHealthKitAuthorization: HealthAuthorization, @unchecked Sendable {
    private let store: HKHealthStore
    // `nonisolated(unsafe)` because the Sendable-checker can't see through
    // HealthKit's pre-concurrency Objective-C API. The underlying Bool is
    // only mutated inside the actor-serialized `requestAuthorization`.
    nonisolated(unsafe) private var requested: Bool = false

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public var isAuthorized: Bool {
        // HealthKit deliberately does not expose read-authorization status
        // for privacy. "We've asked" is the best proxy we get. Callers must
        // still handle query failures gracefully.
        requested
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.bodyMass),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            requested = true
        } catch {
            throw HealthKitError.queryFailed(String(describing: error))
        }
    }
}

#else

/// Non-iOS/watchOS stub. HealthKit is unavailable — surface that cleanly.
public final class LiveHealthKitAuthorization: HealthAuthorization, @unchecked Sendable {
    public init() {}
    public var isAuthorized: Bool { false }
    public func requestAuthorization() async throws {
        throw HealthKitError.notAvailable
    }
}

#endif
