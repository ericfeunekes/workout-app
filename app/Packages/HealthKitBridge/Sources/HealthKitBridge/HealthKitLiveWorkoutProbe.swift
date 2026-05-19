// HealthKitLiveWorkoutProbe.swift
//
// watchOS simulator/device diagnostic for the live workout layer. This is not
// app UX. It proves whether HKWorkoutSession + HKLiveWorkoutBuilder can start,
// collect live metrics, end collection, and save a workout on the current
// runtime.

import Foundation

#if canImport(HealthKit) && os(watchOS)
import HealthKit
#endif

public struct HealthKitLiveWorkoutProbeResult: Codable, Sendable, Equatable {
    public let runID: String
    public let platform: String
    public let healthDataAvailable: Bool
    public let sessionStarted: Bool
    public let collectionStarted: Bool
    public let collectionEnded: Bool
    public let collectedTicks: [WorkoutMetricTick]
    public let workoutSaved: Bool
    public let savedWorkoutDurationSeconds: Double?
    public let error: String?

    public init(
        runID: String,
        platform: String,
        healthDataAvailable: Bool,
        sessionStarted: Bool,
        collectionStarted: Bool,
        collectionEnded: Bool,
        collectedTicks: [WorkoutMetricTick],
        workoutSaved: Bool,
        savedWorkoutDurationSeconds: Double? = nil,
        error: String? = nil
    ) {
        self.runID = runID
        self.platform = platform
        self.healthDataAvailable = healthDataAvailable
        self.sessionStarted = sessionStarted
        self.collectionStarted = collectionStarted
        self.collectionEnded = collectionEnded
        self.collectedTicks = collectedTicks
        self.workoutSaved = workoutSaved
        self.savedWorkoutDurationSeconds = savedWorkoutDurationSeconds
        self.error = error
    }
}

public final class HealthKitLiveWorkoutProbeRunner: NSObject, @unchecked Sendable {
    #if canImport(HealthKit) && os(watchOS)
    private let store: HKHealthStore
    nonisolated(unsafe) private var startDate: Date?
    nonisolated(unsafe) private var collectedTicks: [WorkoutMetricTick] = []
    nonisolated(unsafe) private var delegateError: String?
    nonisolated(unsafe) private var sessionEnded = false

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func run(
        durationSeconds: TimeInterval = 8,
        runID: String = UUID().uuidString,
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> HealthKitLiveWorkoutProbeResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthKitLiveWorkoutProbeResult(
                runID: runID,
                platform: currentHealthKitProbePlatform(),
                healthDataAvailable: false,
                sessionStarted: false,
                collectionStarted: false,
                collectionEnded: false,
                collectedTicks: [],
                workoutSaved: false,
                error: "HealthKit is not available"
            )
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        var sessionStarted = false
        var collectionStarted = false
        var collectionEnded = false
        do {
            progress?("requesting authorization")
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [
                    HKQuantityType(.heartRate),
                    HKQuantityType(.activeEnergyBurned),
                    HKQuantityType(.distanceWalkingRunning),
                ]
            )
            progress?("creating session")
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

            let start = Date()
            startDate = start
            collectedTicks = []
            delegateError = nil
            sessionEnded = false

            progress?("starting session")
            session.startActivity(with: start)
            sessionStarted = true
            try await builder.beginCollection(at: start)
            collectionStarted = true

            progress?("collecting")
            try await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))

            let end = Date()
            progress?("ending session")
            session.end()
            await waitForSessionEnded(timeoutSeconds: 4)
            progress?("ending collection")
            try await builder.endCollection(at: end)
            collectionEnded = true
            progress?("saving workout")
            let workout = try await builder.finishWorkout()
            progress?("done")

            return HealthKitLiveWorkoutProbeResult(
                runID: runID,
                platform: currentHealthKitProbePlatform(),
                healthDataAvailable: true,
                sessionStarted: sessionStarted,
                collectionStarted: collectionStarted,
                collectionEnded: collectionEnded,
                collectedTicks: collectedTicks,
                workoutSaved: workout != nil,
                savedWorkoutDurationSeconds: workout?.duration,
                error: delegateError
            )
        } catch {
            return HealthKitLiveWorkoutProbeResult(
                runID: runID,
                platform: currentHealthKitProbePlatform(),
                healthDataAvailable: true,
                sessionStarted: sessionStarted,
                collectionStarted: collectionStarted,
                collectionEnded: collectionEnded,
                collectedTicks: collectedTicks,
                workoutSaved: false,
                error: String(describing: error)
            )
        }
    }
    #else
    public override init() {}

    public func run(
        durationSeconds: TimeInterval = 8,
        runID: String = UUID().uuidString,
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> HealthKitLiveWorkoutProbeResult {
        _ = durationSeconds
        _ = progress
        return HealthKitLiveWorkoutProbeResult(
            runID: runID,
            platform: currentHealthKitProbePlatform(),
            healthDataAvailable: false,
            sessionStarted: false,
            collectionStarted: false,
            collectionEnded: false,
            collectedTicks: [],
            workoutSaved: false,
            error: "Live workout probe requires watchOS HealthKit"
        )
    }
    #endif
}

#if canImport(HealthKit) && os(watchOS)
extension HealthKitLiveWorkoutProbeRunner: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        _ = workoutSession
        _ = toState
        _ = fromState
        _ = date
        guard toState == .ended else { return }
        sessionEnded = true
    }

    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        _ = workoutSession
        delegateError = String(describing: error)
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
        collectedTicks.append(WorkoutMetricTick(
            elapsedSeconds: elapsed,
            heartRateBPM: heartRate,
            distanceMeters: distance,
            activeEnergyKCal: energy
        ))
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

    private func waitForSessionEnded(timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !sessionEnded && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
#endif

private func currentHealthKitProbePlatform() -> String {
    #if os(watchOS)
    return "watchOS"
    #elseif os(iOS)
    return "iOS"
    #else
    return "unsupported"
    #endif
}
