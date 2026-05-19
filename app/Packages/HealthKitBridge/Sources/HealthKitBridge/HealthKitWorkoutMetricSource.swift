// HealthKitWorkoutMetricSource.swift
//
// Production `WorkoutMetricSource` for watchOS live workout metrics.
// App/watch features consume the typed `WorkoutMetricSource` protocol; raw
// HealthKit session, builder, authorization, and unit mapping stay here.

import Foundation

#if canImport(HealthKit) && os(watchOS)
import HealthKit
#endif

public final class HealthKitWorkoutMetricSource: NSObject, WorkoutMetricSource, @unchecked Sendable {
    #if canImport(HealthKit) && os(watchOS)
    private let store: HKHealthStore
    nonisolated(unsafe) private var session: HKWorkoutSession?
    nonisolated(unsafe) private var builder: HKLiveWorkoutBuilder?
    nonisolated(unsafe) private var continuation: AsyncStream<WorkoutMetricEvent>.Continuation?
    nonisolated(unsafe) private var startDate: Date?

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func start() async throws -> AsyncStream<WorkoutMetricEvent> {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [
                HKQuantityType(.heartRate),
                HKQuantityType(.activeEnergyBurned),
                HKQuantityType(.distanceWalkingRunning),
            ]
        )

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(
            healthStore: store,
            configuration: configuration
        )
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: store,
            workoutConfiguration: configuration
        )
        session.delegate = self
        builder.delegate = self

        let stream = AsyncStream<WorkoutMetricEvent> { continuation in
            self.continuation = continuation
        }

        let start = Date()
        self.session = session
        self.builder = builder
        self.startDate = start
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
        continuation?.yield(.sessionStarted(elapsedSeconds: 0))
        return stream
    }

    public func stop() async {
        let end = Date()
        let elapsed = startDate.map { end.timeIntervalSince($0) } ?? 0
        session?.end()
        if let builder {
            try? await builder.endCollection(at: end)
            _ = try? await builder.finishWorkout()
        }
        continuation?.yield(.sessionEnded(elapsedSeconds: elapsed))
        continuation?.finish()
        continuation = nil
        session = nil
        builder = nil
        startDate = nil
    }
    #else
    public override init() {}

    public func start() async throws -> AsyncStream<WorkoutMetricEvent> {
        throw HealthKitError.notAvailable
    }

    public func stop() async {}
    #endif
}

#if canImport(HealthKit) && os(watchOS)
extension HealthKitWorkoutMetricSource: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        _ = workoutSession
        let elapsed = startDate.map { date.timeIntervalSince($0) } ?? 0
        switch toState {
        case .paused:
            continuation?.yield(.paused(elapsedSeconds: elapsed))
        case .running:
            continuation?.yield(.resumed(elapsedSeconds: elapsed))
        case .ended, .stopped:
            continuation?.yield(.sessionEnded(elapsedSeconds: elapsed))
        default:
            return
        }
    }

    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        _ = workoutSession
        _ = error
        continuation?.finish()
    }

    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        _ = workoutBuilder
    }

    public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let now = Date()
        let elapsed = startDate.map { now.timeIntervalSince($0) } ?? 0

        let heartRate = quantityValue(
            for: heartRateType,
            builder: workoutBuilder,
            unit: HKUnit.count().unitDivided(by: .minute()),
            collectedTypes: collectedTypes
        )
        let energy = quantityValue(
            for: energyType,
            builder: workoutBuilder,
            unit: .kilocalorie(),
            collectedTypes: collectedTypes
        )
        let distance = quantityValue(
            for: distanceType,
            builder: workoutBuilder,
            unit: .meter(),
            collectedTypes: collectedTypes
        )

        guard heartRate != nil || energy != nil || distance != nil else {
            return
        }
        continuation?.yield(.metric(WorkoutMetricTick(
            elapsedSeconds: elapsed,
            heartRateBPM: heartRate,
            distanceMeters: distance,
            activeEnergyKCal: energy
        )))
    }

    private func quantityValue(
        for type: HKQuantityType,
        builder: HKLiveWorkoutBuilder,
        unit: HKUnit,
        collectedTypes: Set<HKSampleType>
    ) -> Double? {
        guard collectedTypes.contains(type) else { return nil }
        return builder.statistics(for: type)?
            .mostRecentQuantity()?
            .doubleValue(for: unit)
    }
}
#endif
