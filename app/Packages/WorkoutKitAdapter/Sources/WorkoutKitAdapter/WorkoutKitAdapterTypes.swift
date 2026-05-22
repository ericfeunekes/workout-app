import Foundation
import WorkoutKitExportProfile

public struct WorkoutKitPushRequest: Sendable, Hashable, Codable {
    public var plan: WorkoutKitExportPlan
    public var path: WorkoutKitDeliveryPath
    public var occurrence: DateComponents?
    public var proofs: WorkoutKitDeliveryProofs
    public var proofMode: WorkoutKitPushProofMode

    public init(
        plan: WorkoutKitExportPlan,
        path: WorkoutKitDeliveryPath,
        occurrence: DateComponents?,
        proofs: WorkoutKitDeliveryProofs = WorkoutKitDeliveryProofs(),
        proofMode: WorkoutKitPushProofMode = .complete
    ) {
        self.plan = plan
        self.path = path
        self.occurrence = occurrence
        self.proofs = proofs
        self.proofMode = proofMode
    }
}

public enum WorkoutKitPushProofMode: String, Sendable, Hashable, Codable {
    case complete
    case proofCollection
}

public enum WorkoutKitPushOutcome: Sendable, Hashable {
    case blocked(WorkoutKitDeliveryAssessment)
    case scheduled(WorkoutKitScheduledRecord)
    case opened(WorkoutKitOpenedRecord)
    case unsupportedPlatform(WorkoutKitAdapterError)
    case failed(WorkoutKitAdapterError)
}

public enum WorkoutKitScheduleVerificationOutcome: Sendable, Hashable {
    case blocked(WorkoutKitDeliveryAssessment)
    case found(WorkoutKitScheduledRecord)
    case missing(WorkoutKitScheduledRecord)
    case unsupportedPlatform(WorkoutKitAdapterError)
    case failed(WorkoutKitAdapterError)
}

public struct WorkoutKitScheduledRecord: Sendable, Hashable, Codable {
    public var workoutID: UUID
    public var workoutPlanID: UUID
    public var occurrence: DateComponents
    public var payloadFingerprint: WorkoutKitPayloadFingerprint
    public var rowID: WorkoutKitMatrixRowID
    public var supportState: WorkoutKitSupportState
    public var degradation: WorkoutKitDegradation?
    public var readback: [WorkoutKitScheduledWorkoutSnapshot]

    public init(
        workoutID: UUID,
        workoutPlanID: UUID,
        occurrence: DateComponents,
        payloadFingerprint: WorkoutKitPayloadFingerprint,
        rowID: WorkoutKitMatrixRowID,
        supportState: WorkoutKitSupportState,
        degradation: WorkoutKitDegradation?,
        readback: [WorkoutKitScheduledWorkoutSnapshot] = []
    ) {
        self.workoutID = workoutID
        self.workoutPlanID = workoutPlanID
        self.occurrence = occurrence
        self.payloadFingerprint = payloadFingerprint
        self.rowID = rowID
        self.supportState = supportState
        self.degradation = degradation
        self.readback = readback
    }

    public var matchingScheduledWorkout: WorkoutKitScheduledWorkoutSnapshot? {
        readback.first {
            $0.workoutPlanID == workoutPlanID
                && Self.sameDay($0.occurrence, occurrence)
        }
    }

    private static func sameDay(_ lhs: DateComponents, _ rhs: DateComponents) -> Bool {
        lhs.era == rhs.era
            && lhs.year == rhs.year
            && lhs.month == rhs.month
            && lhs.day == rhs.day
    }
}

public struct WorkoutKitOpenedRecord: Sendable, Hashable, Codable {
    public var workoutID: UUID
    public var workoutPlanID: UUID
    public var payloadFingerprint: WorkoutKitPayloadFingerprint
    public var rowID: WorkoutKitMatrixRowID
    public var supportState: WorkoutKitSupportState
    public var degradation: WorkoutKitDegradation?

    public init(
        workoutID: UUID,
        workoutPlanID: UUID,
        payloadFingerprint: WorkoutKitPayloadFingerprint,
        rowID: WorkoutKitMatrixRowID,
        supportState: WorkoutKitSupportState,
        degradation: WorkoutKitDegradation?
    ) {
        self.workoutID = workoutID
        self.workoutPlanID = workoutPlanID
        self.payloadFingerprint = payloadFingerprint
        self.rowID = rowID
        self.supportState = supportState
        self.degradation = degradation
    }
}

public enum WorkoutKitAdapterError: Error, Sendable, Hashable, Codable, CustomStringConvertible {
    case missingOccurrenceDate
    case unsupportedPayloadShape(WorkoutKitPayloadShape)
    case unsupportedSelectionPolicy
    case unsupportedDeliveryPath(WorkoutKitDeliveryPath)
    case incompleteWorkoutKitDescriptor
    case unsupportedPlatform(String)
    case schedulerUnavailable
    case capacityExceeded(maxAllowed: Int)
    case scheduledWorkoutMissingAfterSchedule(readbackCount: Int)
    case liveWorkoutKitUnavailable
    case liveWorkoutKitFailure(String)

    public var description: String {
        switch self {
        case .missingOccurrenceDate:
            "WorkoutKit schedule requests require occurrence date components."
        case .unsupportedPayloadShape(let shape):
            "WorkoutKit adapter cannot construct payload shape '\(shape.rawValue)'."
        case .unsupportedSelectionPolicy:
            "WorkoutKit adapter cannot choose a candidate from this selection policy."
        case .unsupportedDeliveryPath(let path):
            "WorkoutKit adapter does not support delivery path '\(path.rawValue)'."
        case .incompleteWorkoutKitDescriptor:
            "WorkoutKit adapter cannot construct a production plan until target values and interval steps are concrete."
        case .unsupportedPlatform(let message):
            message
        case .schedulerUnavailable:
            "WorkoutKit scheduler is unavailable on this platform or device."
        case .capacityExceeded(let maxAllowed):
            "WorkoutKit scheduled workout capacity is full; max allowed is \(maxAllowed)."
        case .scheduledWorkoutMissingAfterSchedule(let readbackCount):
            "WorkoutKit accepted the schedule request but did not return the workout in scheduled readback; "
                + "readback count is \(readbackCount)."
        case .liveWorkoutKitUnavailable:
            "WorkoutKit is unavailable in this build."
        case .liveWorkoutKitFailure(let message):
            message
        }
    }
}
