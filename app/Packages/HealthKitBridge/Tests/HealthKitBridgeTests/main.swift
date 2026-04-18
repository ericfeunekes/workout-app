// main.swift — entry point for `swift run HealthKitBridgeTests`.
//
// Covers the fake doubles. The live wrappers (`LiveHealthKitAuthorization`,
// `LiveHeartRateObserver`, `LiveBodyWeightReader`) require a device or
// simulator with HealthKit permissions and are NOT exercised here — they'd
// fail on CLT-only macOS and in CI.

import Foundation
import HealthKitBridge

// MARK: - FakeHealthAuthorization

runAsyncCase("FakeHealthAuthorization flips to authorized after request") {
    let auth = FakeHealthAuthorization(initiallyAuthorized: false)
    try expect(!auth.isAuthorized, "should start unauthorized")
    try await auth.requestAuthorization()
    try expect(auth.isAuthorized, "should flip to authorized after request")
}

runAsyncCase("FakeHealthAuthorization honors primed failure") {
    let auth = FakeHealthAuthorization(
        initiallyAuthorized: false,
        shouldFailWith: .notAvailable
    )
    do {
        try await auth.requestAuthorization()
        try expect(false, "expected throw")
    } catch let err as HealthKitError {
        try expect(err == .notAvailable, "expected .notAvailable, got \(err)")
    }
    try expect(!auth.isAuthorized, "should stay unauthorized after failure")
}

runAsyncCase("FakeHealthAuthorization respects initiallyAuthorized") {
    let auth = FakeHealthAuthorization(initiallyAuthorized: true)
    try expect(auth.isAuthorized, "should report authorized when seeded true")
}

// MARK: - FakeHeartRateObserver

private func hr(_ epoch: TimeInterval, _ bpm: Int) -> HeartRateSample {
    HeartRateSample(timestamp: Date(timeIntervalSince1970: epoch), bpm: bpm)
}

runAsyncCase("FakeHeartRateObserver yields scripted samples in order then finishes") {
    let scripted = [
        hr(1_700_000_000, 120),
        hr(1_700_000_001, 125),
        hr(1_700_000_002, 130),
    ]
    let observer = FakeHeartRateObserver(scripted: scripted)
    let stream = try await observer.startWorkoutSession()

    var collected: [HeartRateSample] = []
    for try await sample in stream {
        collected.append(sample)
    }
    try expectEqual(collected, scripted)
}

runAsyncCase("FakeHeartRateObserver records endWorkoutSession calls") {
    let observer = FakeHeartRateObserver(scripted: [hr(1, 100)])
    let stream = try await observer.startWorkoutSession()
    // Drain the stream (it finishes immediately because the scripted array
    // is small) and then call end; we're asserting that end is safe to call
    // after natural termination.
    for try await _ in stream {}
    await observer.endWorkoutSession()
    try expectEqual(observer.endCallCount, 1)
}

runAsyncCase("FakeHeartRateObserver throws primed failure before yielding") {
    let observer = FakeHeartRateObserver(
        scripted: [hr(1, 100)],
        shouldFailWith: .notAuthorized
    )
    do {
        _ = try await observer.startWorkoutSession()
        try expect(false, "expected throw")
    } catch let err as HealthKitError {
        try expect(err == .notAuthorized, "expected .notAuthorized, got \(err)")
    }
}

runAsyncCase("FakeHeartRateObserver with empty script finishes the stream immediately") {
    let observer = FakeHeartRateObserver(scripted: [])
    let stream = try await observer.startWorkoutSession()
    var count = 0
    for try await _ in stream { count += 1 }
    try expectEqual(count, 0)
}

// MARK: - FakeBodyWeightReader

runAsyncCase("FakeBodyWeightReader returns the seeded value") {
    let reader = FakeBodyWeightReader(kg: 81.5)
    let value = try await reader.latestBodyWeightKg()
    try expectEqual(value, 81.5)
}

runAsyncCase("FakeBodyWeightReader returns nil when seeded nil") {
    let reader = FakeBodyWeightReader(kg: nil)
    let value = try await reader.latestBodyWeightKg()
    try expect(value == nil, "expected nil, got \(String(describing: value))")
}

runAsyncCase("FakeBodyWeightReader propagates primed failure") {
    let reader = FakeBodyWeightReader(kg: 80, shouldFailWith: .queryFailed("db locked"))
    do {
        _ = try await reader.latestBodyWeightKg()
        try expect(false, "expected throw")
    } catch let err as HealthKitError {
        if case .queryFailed(let msg) = err {
            try expectEqual(msg, "db locked")
        } else {
            try expect(false, "expected .queryFailed, got \(err)")
        }
    }
}

// MARK: - HealthKitBridgeFactory

runAsyncCase("HealthKitBridgeFactory.mock wires fakes through") {
    let bundle = HealthKitBridgeFactory.mock(
        auth: FakeHealthAuthorization(initiallyAuthorized: true),
        hr: FakeHeartRateObserver(scripted: [hr(1, 110)]),
        bw: FakeBodyWeightReader(kg: 82.1)
    )
    try expect(bundle.auth.isAuthorized, "auth should be authorized")
    let stream = try await bundle.hr.startWorkoutSession()
    var samples: [HeartRateSample] = []
    for try await s in stream { samples.append(s) }
    try expectEqual(samples.count, 1)
    try expectEqual(samples[0].bpm, 110)
    let kg = try await bundle.bw.latestBodyWeightKg()
    try expectEqual(kg, 82.1)
}

runAsyncCase("HealthKitBridgeFactory.mock default wiring is usable") {
    // Defaults: auth authorized, empty HR script, nil body weight.
    let bundle = HealthKitBridgeFactory.mock()
    try expect(bundle.auth.isAuthorized, "default auth should be authorized")
    let stream = try await bundle.hr.startWorkoutSession()
    var count = 0
    for try await _ in stream { count += 1 }
    try expectEqual(count, 0)
    let kg = try await bundle.bw.latestBodyWeightKg()
    try expect(kg == nil, "default bw should be nil")
}

reportAndExit()
