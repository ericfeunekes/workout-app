import Foundation
import WorkoutKitExportProfile

public struct WorkoutKitPushCoordinator: Sendable {
    private let classifier: WorkoutKitExportClassifier
    private let client: any WorkoutKitSchedulingClient
    private let runtimePlatform: WorkoutKitRuntimePlatform

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
        runtimePlatform: WorkoutKitRuntimePlatform = .current
    ) {
        self.classifier = classifier
        self.client = client
        self.runtimePlatform = runtimePlatform
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
                let support = try await client.support()
                guard support.isSupported else {
                    return .failed(.schedulerUnavailable)
                }
                guard support.scheduledCount < support.maxAllowedCount else {
                    return .failed(.capacityExceeded(maxAllowed: support.maxAllowedCount))
                }
                try await client.schedule(descriptor, at: occurrence)
                let scheduledWorkouts = try await client.scheduledWorkouts()
                return .scheduled(WorkoutKitScheduledRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    occurrence: occurrence,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation,
                    readback: scheduledWorkouts
                ))

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
