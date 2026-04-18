// LiveHeartRateObserver.swift
//
// HKWorkoutSession + HKLiveWorkoutBuilder wrapper that yields live HR
// samples through an AsyncThrowingStream. Per ADR-2026-04-17-ux-scope §4,
// v1 records avg + max into `set_log` only — no sample timeseries are
// persisted. Aggregation lives in the caller (Features/Execution).
//
// Platform availability:
//   • HKWorkoutSession + HKLiveWorkoutBuilder are watchOS-only.
//   • On iOS the iPhone-side observer does not start a session; HR is
//     read via a `HKAnchoredObjectQuery` over the heartRate sample type
//     driven by the watch's session. The protocol shape stays the same
//     either way — the stream is the boundary.
//   • On macOS the stub throws `.notAvailable`.

import Foundation

#if canImport(HealthKit) && os(watchOS)
import HealthKit

public final class LiveHeartRateObserver: NSObject, HeartRateObserver, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {

    private let store: HKHealthStore
    nonisolated(unsafe) private var session: HKWorkoutSession?
    nonisolated(unsafe) private var builder: HKLiveWorkoutBuilder?
    nonisolated(unsafe) private var continuation: AsyncThrowingStream<HeartRateSample, Error>.Continuation?

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func startWorkoutSession() async throws -> AsyncThrowingStream<HeartRateSample, Error> {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            return AsyncThrowingStream { cont in
                self.continuation = cont
                cont.onTermination = { [weak self] _ in
                    // `onTermination` is a synchronous non-isolated callback
                    // fired by the stream machinery (possibly on a HealthKit
                    // background queue). There is no structured parent task
                    // to inherit from; `.detached` makes the lack of
                    // cancellation-inheritance explicit.
                    Task.detached { await self?.endWorkoutSession() }
                }
            }
        } catch {
            throw HealthKitError.queryFailed(String(describing: error))
        }
    }

    public func endWorkoutSession() async {
        session?.end()
        if let builder = builder {
            try? await builder.endCollection(at: Date())
        }
        continuation?.finish()
        continuation = nil
        session = nil
        builder = nil
    }

    // MARK: HKWorkoutSessionDelegate

    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .ended || toState == .stopped {
            continuation?.finish()
            continuation = nil
        }
    }

    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        continuation?.finish(throwing: HealthKitError.queryFailed(String(describing: error)))
        continuation = nil
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }
        guard let stats = workoutBuilder.statistics(for: hrType) else { return }
        guard let quantity = stats.mostRecentQuantity() else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = Int(quantity.doubleValue(for: unit).rounded())
        let timestamp = stats.mostRecentQuantityDateInterval()?.end ?? Date()
        continuation?.yield(HeartRateSample(timestamp: timestamp, bpm: bpm))
    }
}

#else

/// Non-watchOS platforms: HKWorkoutSession is unavailable. The stub throws
/// cleanly so callers can fall through to a no-HR code path.
public final class LiveHeartRateObserver: HeartRateObserver, @unchecked Sendable {
    public init() {}
    public func startWorkoutSession() async throws -> AsyncThrowingStream<HeartRateSample, Error> {
        throw HealthKitError.notAvailable
    }
    public func endWorkoutSession() async {}
}

#endif
