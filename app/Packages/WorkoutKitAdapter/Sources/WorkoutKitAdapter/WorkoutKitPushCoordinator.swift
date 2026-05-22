import Foundation
import WorkoutKitExportProfile

public struct WorkoutKitPushCoordinator: Sendable {
    private let classifier: WorkoutKitExportClassifier
    private let client: any WorkoutKitSchedulingClient
    private let runtimePlatform: WorkoutKitRuntimePlatform
    private let readbackMaxAttempts: Int
    private let readbackDelayNanoseconds: UInt64

    public init() {
        self.init(
            classifier: WorkoutKitExportClassifier(),
            client: LiveWorkoutKitSchedulingClient(),
            runtimePlatform: .current
        )
    }

    public static func live() -> WorkoutKitPushCoordinator {
        WorkoutKitPushCoordinator()
    }

    init(
        classifier: WorkoutKitExportClassifier = WorkoutKitExportClassifier(),
        client: any WorkoutKitSchedulingClient,
        runtimePlatform: WorkoutKitRuntimePlatform = .current,
        readbackMaxAttempts: Int = 4,
        readbackDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.classifier = classifier
        self.client = client
        self.runtimePlatform = runtimePlatform
        self.readbackMaxAttempts = max(1, readbackMaxAttempts)
        self.readbackDelayNanoseconds = readbackDelayNanoseconds
    }

    public func push(_ request: WorkoutKitPushRequest) async -> WorkoutKitPushOutcome {
        if request.path == .previewOnly {
            return .blocked(WorkoutKitDeliveryAssessment(
                path: request.path,
                unmetProofRequirements: [],
                unmetAcknowledgementRequirements: [],
                blockingReasons: [.deliveryPathUnavailable]
            ))
        }
        var assessment = classifier.assessDelivery(
            request.plan,
            path: request.path,
            proofs: request.proofs
        )
        if request.proofMode == .proofCollection,
           request.path == .scheduleOnPhone
        {
            assessment.blockingReasons.remove(.scheduleVisibilityProofRequired)
            assessment.blockingReasons.remove(.duplicateUpdateProofRequired)
            assessment.unmetProofRequirements.remove(.realDeviceScheduleVisibility)
            assessment.unmetProofRequirements.remove(.duplicateUpdateBehavior)
        }
        guard assessment.blockingReasons.isEmpty else {
            return .blocked(assessment)
        }
        if let platformError = unsupportedPlatformError(for: request.path) {
            return .unsupportedPlatform(platformError)
        }

        do {
            let descriptor = try WorkoutKitPlanFactory.descriptor(for: request.plan)
            let fingerprint = try WorkoutKitPayloadFingerprint.make(
                plan: request.plan,
                descriptor: descriptor,
                occurrence: request.occurrence
            )
            switch request.path {
            case .scheduleOnPhone:
                guard let occurrence = request.occurrence else {
                    return .failed(.missingOccurrenceDate)
                }
                let authorization = try await ensureSchedulingAuthorization()
                guard authorization == .authorized else {
                    return .failed(.schedulerAuthorizationDenied(authorization))
                }
                let support = try await client.support()
                guard support.isSupported else {
                    return .failed(.schedulerUnavailable)
                }
                guard support.scheduledCount < support.maxAllowedCount else {
                    return .failed(.capacityExceeded(maxAllowed: support.maxAllowedCount))
                }
                try await client.schedule(descriptor, at: occurrence)
                let record = try await readScheduledRecord(
                    workoutID: request.plan.workoutID,
                    descriptorID: descriptor.id,
                    occurrence: occurrence,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation
                )
                guard record.matchingScheduledWorkout != nil else {
                    return .failed(.scheduledWorkoutMissingAfterSchedule(
                        readbackCount: record.readback.count
                    ))
                }
                return .scheduled(record)

            case .openOnWatch:
                try await client.open(descriptor)
                return .opened(WorkoutKitOpenedRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation
                ))

            case .previewOnly:
                return .failed(.unsupportedDeliveryPath(request.path))
            }
        } catch let error as WorkoutKitAdapterError {
            return .failed(error)
        } catch {
            return .failed(.liveWorkoutKitFailure(String(describing: error)))
        }
    }

    public func verifySchedule(
        _ request: WorkoutKitPushRequest
    ) async -> WorkoutKitScheduleVerificationOutcome {
        var assessment = classifier.assessDelivery(
            request.plan,
            path: .scheduleOnPhone,
            proofs: request.proofs
        )
        if request.proofMode == .proofCollection {
            assessment.blockingReasons.remove(.scheduleVisibilityProofRequired)
            assessment.blockingReasons.remove(.duplicateUpdateProofRequired)
            assessment.unmetProofRequirements.remove(.realDeviceScheduleVisibility)
            assessment.unmetProofRequirements.remove(.duplicateUpdateBehavior)
        }
        guard assessment.blockingReasons.isEmpty else {
            return .blocked(assessment)
        }
        if let platformError = unsupportedPlatformError(for: .scheduleOnPhone) {
            return .unsupportedPlatform(platformError)
        }

        do {
            guard let occurrence = request.occurrence else {
                return .failed(.missingOccurrenceDate)
            }
            let authorization = try await ensureSchedulingAuthorization()
            guard authorization == .authorized else {
                return .failed(.schedulerAuthorizationDenied(authorization))
            }
            let descriptor = try WorkoutKitPlanFactory.descriptor(for: request.plan)
            let fingerprint = try WorkoutKitPayloadFingerprint.make(
                plan: request.plan,
                descriptor: descriptor,
                occurrence: occurrence
            )
            let scheduledWorkouts = try await client.scheduledWorkouts()
            let record = WorkoutKitScheduledRecord(
                workoutID: request.plan.workoutID,
                workoutPlanID: descriptor.id,
                occurrence: occurrence,
                payloadFingerprint: fingerprint,
                rowID: request.plan.rowID,
                supportState: request.plan.supportState,
                degradation: request.plan.degradation,
                readback: scheduledWorkouts
            )
            return record.matchingScheduledWorkout == nil ? .missing(record) : .found(record)
        } catch let error as WorkoutKitAdapterError {
            return .failed(error)
        } catch {
            return .failed(.liveWorkoutKitFailure(String(describing: error)))
        }
    }

    private func ensureSchedulingAuthorization() async throws -> WorkoutKitSchedulerAuthorizationState {
        let current = try await client.authorizationState()
        guard current == .notDetermined else {
            return current
        }
        return try await client.requestAuthorization()
    }

    private func readScheduledRecord(
        workoutID: UUID,
        descriptorID: UUID,
        occurrence: DateComponents,
        payloadFingerprint: WorkoutKitPayloadFingerprint,
        rowID: WorkoutKitMatrixRowID,
        supportState: WorkoutKitSupportState,
        degradation: WorkoutKitDegradation?
    ) async throws -> WorkoutKitScheduledRecord {
        var latest: [WorkoutKitScheduledWorkoutSnapshot] = []
        for attempt in 0..<readbackMaxAttempts {
            latest = try await client.scheduledWorkouts()
            let record = WorkoutKitScheduledRecord(
                workoutID: workoutID,
                workoutPlanID: descriptorID,
                occurrence: occurrence,
                payloadFingerprint: payloadFingerprint,
                rowID: rowID,
                supportState: supportState,
                degradation: degradation,
                readback: latest
            )
            if record.matchingScheduledWorkout != nil || attempt == readbackMaxAttempts - 1 {
                return record
            }
            if readbackDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: readbackDelayNanoseconds)
            }
        }
        return WorkoutKitScheduledRecord(
            workoutID: workoutID,
            workoutPlanID: descriptorID,
            occurrence: occurrence,
            payloadFingerprint: payloadFingerprint,
            rowID: rowID,
            supportState: supportState,
            degradation: degradation,
            readback: latest
        )
    }

    private func unsupportedPlatformError(
        for path: WorkoutKitDeliveryPath
    ) -> WorkoutKitAdapterError? {
        switch (path, runtimePlatform) {
        case (.scheduleOnPhone, .iOS):
            nil
        case (.openOnWatch, .watchOS):
            nil
        case (.scheduleOnPhone, _):
            .unsupportedPlatform("WorkoutKit scheduling is available from the iOS app.")
        case (.openOnWatch, _):
            .unsupportedPlatform("WorkoutPlan.openInWorkoutApp() is watchOS-only.")
        case (.previewOnly, _):
            .unsupportedDeliveryPath(path)
        }
    }
}

enum WorkoutKitRuntimePlatform: Sendable, Hashable {
    case iOS
    case watchOS
    case unsupported

    static var current: WorkoutKitRuntimePlatform {
        #if os(iOS)
        .iOS
        #elseif os(watchOS)
        .watchOS
        #else
        .unsupported
        #endif
    }
}
