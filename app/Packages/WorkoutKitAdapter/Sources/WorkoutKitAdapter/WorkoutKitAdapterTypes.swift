import Foundation
import WorkoutKitExportProfile

public struct WorkoutKitPushRequest: Sendable, Hashable, Codable {
    public var plan: WorkoutKitExportPlan
    public var path: WorkoutKitDeliveryPath
    public var occurrence: DateComponents?
    public var proofs: WorkoutKitDeliveryProofs

    public init(
        plan: WorkoutKitExportPlan,
        path: WorkoutKitDeliveryPath,
        occurrence: DateComponents?,
        proofs: WorkoutKitDeliveryProofs = WorkoutKitDeliveryProofs()
    ) {
        self.plan = plan
        self.path = path
        self.occurrence = occurrence
        self.proofs = proofs
    }
}

public enum WorkoutKitPushOutcome: Sendable, Hashable {
    case blocked(WorkoutKitDeliveryAssessment)
    case scheduled(WorkoutKitScheduledRecord)
    case opened(WorkoutKitOpenedRecord)
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

    public init(
        workoutID: UUID,
        workoutPlanID: UUID,
        occurrence: DateComponents,
        payloadFingerprint: WorkoutKitPayloadFingerprint,
        rowID: WorkoutKitMatrixRowID,
        supportState: WorkoutKitSupportState,
        degradation: WorkoutKitDegradation?
    ) {
        self.workoutID = workoutID
        self.workoutPlanID = workoutPlanID
        self.occurrence = occurrence
        self.payloadFingerprint = payloadFingerprint
        self.rowID = rowID
        self.supportState = supportState
        self.degradation = degradation
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
    case unsupportedPlatform(String)
    case schedulerUnavailable
    case capacityExceeded(maxAllowed: Int)
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
        case .unsupportedPlatform(let message):
            message
        case .schedulerUnavailable:
            "WorkoutKit scheduler is unavailable on this platform or device."
        case .capacityExceeded(let maxAllowed):
            "WorkoutKit scheduled workout capacity is full; max allowed is \(maxAllowed)."
        case .liveWorkoutKitUnavailable:
            "WorkoutKit is unavailable in this build."
        case .liveWorkoutKitFailure(let message):
            message
        }
    }
}

struct WorkoutKitPlanDescriptor: Sendable, Hashable, Codable {
    var id: UUID
    var displayName: String
    var family: WorkoutKitCandidateFamily
    var activity: WorkoutKitAdapterActivity
    var location: WorkoutKitAdapterLocation
    var goal: WorkoutKitAdapterGoal
    var intervalSteps: [WorkoutKitAdapterIntervalStep]

    init(
        id: UUID,
        displayName: String,
        family: WorkoutKitCandidateFamily,
        activity: WorkoutKitAdapterActivity,
        location: WorkoutKitAdapterLocation = .unknown,
        goal: WorkoutKitAdapterGoal,
        intervalSteps: [WorkoutKitAdapterIntervalStep] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.activity = activity
        self.location = location
        self.goal = goal
        self.intervalSteps = intervalSteps
    }
}

enum WorkoutKitAdapterActivity: String, Sendable, Hashable, Codable, CaseIterable {
    case cycling
    case functionalStrength
    case mixedCardio
    case walking
    case flexibility
    case other
}

enum WorkoutKitAdapterLocation: String, Sendable, Hashable, Codable, CaseIterable {
    case unknown
    case outdoor
}

enum WorkoutKitAdapterGoal: Sendable, Hashable, Codable {
    case open
    case timeSeconds(Double)
    case distanceMeters(Double)
}

struct WorkoutKitAdapterIntervalStep: Sendable, Hashable, Codable {
    enum Purpose: String, Sendable, Hashable, Codable {
        case work
        case recovery
    }

    var purpose: Purpose
    var goal: WorkoutKitAdapterGoal

    init(purpose: Purpose, goal: WorkoutKitAdapterGoal) {
        self.purpose = purpose
        self.goal = goal
    }
}
