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

// MARK: - General health data requests

runAsyncCase("HealthDataRequest preserves type, access, and delivery choices") {
    let request = HealthDataRequest(
        type: HealthDataTypeRegistry.heartRate,
        access: .read,
        delivery: .live
    )
    try expectEqual(request.type.defaultUnit, "count/min")
    try expectEqual(request.access, .read)
    try expectEqual(request.delivery, .live)
}

runAsyncCase("FakeHealthPermissionBroker records requested data types") {
    let broker = FakeHealthPermissionBroker()
    let requests = [
        HealthDataRequest(type: HealthDataTypeRegistry.heartRate, delivery: .live),
        HealthDataRequest(type: HealthDataTypeRegistry.bodyMass, delivery: .batch),
    ]
    try await broker.requestAuthorization(for: requests)
    try expectEqual(broker.requested, requests)
}

runAsyncCase("FakeHealthPermissionBroker validates authorization requests") {
    let broker = FakeHealthPermissionBroker()
    do {
        try await broker.requestAuthorization(for: [
            HealthDataRequest(
                type: HealthDataTypeRegistry.heartRate,
                access: .write,
                delivery: .live
            ),
        ])
        try expect(false, "expected live write-only authorization failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("write-only"), "unexpected message \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
    try expectEqual(broker.requested, [])
}

runCase("HealthDataRequestValidator rejects write-only batch fetches") {
    do {
        try HealthDataRequestValidator.validateBatchFetchRequests([
            HealthDataRequest(
                type: HealthDataTypeRegistry.stepCount,
                access: .write,
                delivery: .batch
            ),
        ])
        try expect(false, "expected read-access failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("requires read access"), "unexpected message \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
}

runCase("HealthDataRequestValidator rejects batch requests on live streams") {
    do {
        try HealthDataRequestValidator.validateLiveStreamRequests([
            HealthDataRequest(type: HealthDataTypeRegistry.heartRate, delivery: .batch),
        ])
        try expect(false, "expected delivery failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("Live stream"), "unexpected message \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
}

runAsyncCase("FakeHealthBatchDataProvider returns records and cursor") {
    let record = HealthDataRecord(
        id: "sample-1",
        type: HealthDataTypeRegistry.stepCount,
        start: Date(timeIntervalSince1970: 10),
        end: Date(timeIntervalSince1970: 20),
        value: .quantity(42, unit: "count")
    )
    let provider = FakeHealthBatchDataProvider(
        result: HealthBatchResult(
            records: [record],
            deletedRecords: [
                HealthDeletedRecord(
                    externalID: "deleted-1",
                    type: HealthDataTypeRegistry.stepCount
                ),
            ],
            nextCursor: HealthBatchCursor("cursor-2")
        )
    )
    let query = HealthBatchQuery(
        requests: [HealthDataRequest(type: HealthDataTypeRegistry.stepCount, delivery: .batch)],
        cursor: HealthBatchCursor("cursor-1")
    )
    let result = try await provider.fetch(query)
    try expectEqual(provider.queries, [query])
    try expectEqual(result.records, [record])
    try expectEqual(result.deletedExternalIDs, ["deleted-1"])
    try expectEqual(result.deletedRecords, [
        HealthDeletedRecord(externalID: "deleted-1", type: HealthDataTypeRegistry.stepCount),
    ])
    try expectEqual(result.nextCursor, HealthBatchCursor("cursor-2"))
}

runAsyncCase("FakeHealthBatchDataProvider validates query requests") {
    let provider = FakeHealthBatchDataProvider()
    let query = HealthBatchQuery(requests: [
        HealthDataRequest(
            type: HealthDataTypeRegistry.stepCount,
            access: .write,
            delivery: .batch
        ),
    ])
    do {
        _ = try await provider.fetch(query)
        try expect(false, "expected read-access failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("requires read access"), "unexpected message \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
    try expectEqual(provider.queries, [])
}

runAsyncCase("FakeHealthLiveDataProvider yields scripted records") {
    let record = HealthDataRecord(
        id: "hr-1",
        type: HealthDataTypeRegistry.heartRate,
        start: Date(timeIntervalSince1970: 30),
        value: .quantity(132, unit: "count/min")
    )
    let provider = FakeHealthLiveDataProvider(records: [record])
    let requests = [HealthDataRequest(type: HealthDataTypeRegistry.heartRate, delivery: .live)]
    let stream = try await provider.stream(for: requests)
    var collected: [HealthDataRecord] = []
    for try await item in stream {
        collected.append(item)
    }
    try expectEqual(provider.requested, [requests])
    try expectEqual(collected, [record])
}

runAsyncCase("FakeHealthLiveDataProvider validates requested streams") {
    let provider = FakeHealthLiveDataProvider()
    do {
        _ = try await provider.stream(for: [
            HealthDataRequest(type: HealthDataTypeRegistry.heartRate, delivery: .batch),
        ])
        try expect(false, "expected delivery failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("Live stream"), "unexpected message \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
    try expectEqual(provider.requested, [])
}

runAsyncCase("FixtureWorkoutMetricSource replays metric events deterministically") {
    let replay = WorkoutMetricReplay(events: [
        .sessionStarted(elapsedSeconds: 0),
        .metric(WorkoutMetricTick(
            elapsedSeconds: 60,
            heartRateBPM: 138,
            distanceMeters: 185,
            activeEnergyKCal: 12
        )),
        .paused(elapsedSeconds: 90),
        .resumed(elapsedSeconds: 120),
        .metric(WorkoutMetricTick(
            elapsedSeconds: 180,
            heartRateBPM: 146,
            distanceMeters: 560,
            activeEnergyKCal: 39,
            paceSecondsPerKilometer: 321
        )),
        .sessionEnded(elapsedSeconds: 210),
    ])
    let source = FixtureWorkoutMetricSource(replay: replay)
    let stream = try await source.start()
    var collected: [WorkoutMetricEvent] = []
    for await event in stream {
        collected.append(event)
    }
    await source.stop()

    try expectEqual(collected, replay.events)
    try expectEqual(source.startCallCount, 1)
    try expectEqual(source.stopCallCount, 1)
    try expectEqual(replay.ticks.count, 2)
    try expectEqual(replay.summary.elapsedSeconds, 210)
    try expectEqual(replay.summary.averageHeartRateBPM, 142)
    try expectEqual(replay.summary.maxHeartRateBPM, 146)
    try expectEqual(replay.summary.distanceMeters, 560)
    try expectEqual(replay.summary.activeEnergyKCal, 39)
}

runCase("WorkoutMetricReplay round-trips from JSON fixtures") {
    let json = """
    {
      "events": [
        {"type": "sessionStarted", "elapsedSeconds": 0},
        {
          "type": "metric",
          "tick": {"elapsedSeconds": 60, "heartRateBPM": 138, "distanceMeters": 185}
        },
        {"type": "paused", "elapsedSeconds": 90},
        {"type": "resumed", "elapsedSeconds": 120},
        {"type": "sessionEnded", "elapsedSeconds": 180}
      ]
    }
    """
    let replay = try JSONDecoder().decode(WorkoutMetricReplay.self, from: Data(json.utf8))
    try expectEqual(replay.events.count, 5)
    try expectEqual(replay.ticks.first?.heartRateBPM, 138)
    let encoded = try JSONEncoder().encode(replay)
    let decoded = try JSONDecoder().decode(WorkoutMetricReplay.self, from: encoded)
    try expectEqual(decoded, replay)
}

runCase("WorkoutMetricReplay decodes nested readable JSON trace fixtures") {
    let json = """
    {
      "events": [
        {"sessionStarted": {"elapsedSeconds": 0}},
        {"metric": {"elapsedSeconds": 60, "heartRateBPM": 138, "distanceMeters": 185}},
        {"paused": {"elapsedSeconds": 90}},
        {"resumed": {"elapsedSeconds": 120}},
        {"sessionEnded": {"elapsedSeconds": 180}}
      ]
    }
    """
    let replay = try JSONDecoder().decode(WorkoutMetricReplay.self, from: Data(json.utf8))
    try expectEqual(replay.events.count, 5)
    try expectEqual(replay.events[0], .sessionStarted(elapsedSeconds: 0))
    try expectEqual(replay.ticks, [
        WorkoutMetricTick(elapsedSeconds: 60, heartRateBPM: 138, distanceMeters: 185),
    ])
    try expectEqual(replay.summary.elapsedSeconds, 180)
}

runAsyncCase("HealthKitLiveWorkoutProbe reports unsupported platforms without step progress") {
    let result = await HealthKitLiveWorkoutProbeRunner().run(durationSeconds: 0, runID: "unsupported")
    try expectEqual(result.runID, "unsupported")
    try expect(!result.healthDataAvailable, "unsupported platform should not report health data")
    try expect(!result.sessionStarted, "unsupported platform should not report session start")
    try expect(!result.collectionStarted, "unsupported platform should not report collection start")
    try expect(!result.collectionEnded, "unsupported platform should not report collection end")
    try expect(!result.workoutSaved, "unsupported platform should not report saved workout")
}

runAsyncCase("HealthKitBridgeFactory.mock wires general providers") {
    let record = HealthDataRecord(
        id: "mass-1",
        type: HealthDataTypeRegistry.bodyMass,
        value: .quantity(81.2, unit: "kg")
    )
    let bundle = HealthKitBridgeFactory.mock(
        batch: FakeHealthBatchDataProvider(result: HealthBatchResult(records: [record]))
    )
    let result = try await bundle.batch.fetch(HealthBatchQuery(
        requests: [HealthDataRequest(type: HealthDataTypeRegistry.bodyMass, delivery: .batch)]
    ))
    try expectEqual(result.records, [record])
}

runCase("LiveHealthDataProvider exposes finite supported batch registry") {
    let ids = LiveHealthDataProvider.supportedBatchTypes().map(\.id)
    try expect(ids.contains(HealthDataTypeRegistry.heartRate.id))
    try expect(ids.contains(HealthDataTypeRegistry.bodyMass.id))
    try expect(ids.contains(HealthDataTypeRegistry.stepCount.id))
    try expect(ids.contains(HealthDataTypeRegistry.activeEnergyBurned.id))
    try expect(ids.contains(HealthDataTypeRegistry.sleepAnalysis.id))
    try expect(ids.contains(HealthDataTypeRegistry.workout.id))
    try expect(!ids.contains(HealthDataTypeRegistry.runningSpeed.id))
}

runCase("LiveHealthDataProvider derives permission sets from request access") {
    let set = try LiveHealthDataProvider.debugPermissionSet(for: [
        HealthDataRequest(type: HealthDataTypeRegistry.heartRate, access: .read, delivery: .batch),
        HealthDataRequest(type: HealthDataTypeRegistry.bodyMass, access: .write, delivery: .batch),
        HealthDataRequest(type: HealthDataTypeRegistry.workout, access: .readWrite, delivery: .batch),
    ])
    try expect(set.readTypeIDs.contains(HealthDataTypeRegistry.heartRate.id))
    try expect(set.readTypeIDs.contains(HealthDataTypeRegistry.workout.id))
    try expect(!set.readTypeIDs.contains(HealthDataTypeRegistry.bodyMass.id))
    try expect(set.shareTypeIDs.contains(HealthDataTypeRegistry.bodyMass.id))
    try expect(set.shareTypeIDs.contains(HealthDataTypeRegistry.workout.id))
    try expect(!set.shareTypeIDs.contains(HealthDataTypeRegistry.heartRate.id))
}

runCase("LiveHealthDataProvider rejects unsupported registry types explicitly") {
    do {
        _ = try LiveHealthDataProvider.debugPermissionSet(for: [
            HealthDataRequest(type: HealthDataTypeRegistry.runningSpeed, delivery: .batch),
        ])
        try expect(false, "expected unsupported type")
    } catch let err as HealthKitError {
        try expectEqual(err, .unsupportedType(HealthDataTypeRegistry.runningSpeed.id))
    }
}

runCase("LiveHealthDataProvider rejects mixed delivery batch queries explicitly") {
    do {
        _ = try LiveHealthDataProvider.debugValidatedBatchTypeIDs(HealthBatchQuery(requests: [
            HealthDataRequest(type: HealthDataTypeRegistry.heartRate, delivery: .batch),
            HealthDataRequest(type: HealthDataTypeRegistry.bodyMass, delivery: .live),
        ]))
        try expect(false, "expected delivery failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("live delivery"), "expected live delivery in \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
}

runCase("LiveHealthDataProvider rejects empty batch queries explicitly") {
    do {
        _ = try LiveHealthDataProvider.debugValidatedBatchTypeIDs(HealthBatchQuery(requests: []))
        try expect(false, "expected empty-query failure")
    } catch let err as HealthKitError {
        if case .queryFailed(let message) = err {
            try expect(message.contains("at least one request"), "expected empty-query message")
        } else {
            try expect(false, "expected .queryFailed, got \(err)")
        }
    }
}

runCase("LiveHealthDataProvider rejects write-only batch queries explicitly") {
    do {
        _ = try LiveHealthDataProvider.debugValidatedBatchTypeIDs(HealthBatchQuery(requests: [
            HealthDataRequest(
                type: HealthDataTypeRegistry.stepCount,
                access: .write,
                delivery: .batch
            ),
        ]))
        try expect(false, "expected read-access failure")
    } catch let err as HealthKitError {
        if case .notImplemented(let message) = err {
            try expect(message.contains("requires read access"), "expected read-access in \(message)")
        } else {
            try expect(false, "expected .notImplemented, got \(err)")
        }
    }
}

runCase("LiveHealthDataProvider uses overlap windows for interval samples") {
    try expectEqual(
        try LiveHealthDataProvider.debugWindowSemantics(for: HealthDataTypeRegistry.heartRate),
        .strictStart
    )
    try expectEqual(
        try LiveHealthDataProvider.debugWindowSemantics(for: HealthDataTypeRegistry.sleepAnalysis),
        .overlap
    )
    try expectEqual(
        try LiveHealthDataProvider.debugWindowSemantics(for: HealthDataTypeRegistry.workout),
        .overlap
    )
}

runCase("HealthKit archive probe failure is represented as failed fetch, not data") {
    let capability = HealthKitSimulatorProbeResult(
        runID: "probe-run",
        platform: "simulator",
        healthDataAvailable: true,
        authorization: ProbeStep(name: "authorization", success: true, detail: "ok"),
        quantitySamples: [],
        categorySample: ProbeStep(name: "sleepAnalysis", success: true, detail: "ok"),
        workoutSample: ProbeStep(name: "workout", success: true, detail: "ok"),
        anchoredInsert: ProbeStep(name: "anchoredInsert", success: true, detail: "ok"),
        anchoredDelete: ProbeStep(name: "anchoredDelete", success: true, detail: "ok"),
        notes: []
    )
    let result = HealthKitSimulatorArchiveProbeResult(
        runID: "probe-run",
        capability: capability,
        batch: nil,
        authorizationRequestCompleted: true,
        archiveFetchSucceeded: false,
        archiveFetchError: "boom"
    )
    try expect(result.batch == nil, "failed archive fetch should not carry a normal batch")
    try expect(!result.archiveFetchSucceeded, "fetch should be failed")
    try expectEqual(result.archiveFetchError, "boom")
}

runAsyncCase("HealthKit live workout probe reports unsupported outside watchOS") {
    let result = await HealthKitLiveWorkoutProbeRunner().run(durationSeconds: 0)
    #if os(watchOS)
    _ = result
    #else
    try expect(!result.healthDataAvailable, "non-watchOS probe should not claim HealthKit")
    try expect(!result.workoutSaved, "non-watchOS probe should not save workout")
    try expectEqual(result.error, "Live workout probe requires watchOS HealthKit")
    #endif
}

reportAndExit()
