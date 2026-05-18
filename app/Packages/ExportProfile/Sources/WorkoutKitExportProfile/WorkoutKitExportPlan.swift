import Foundation
import CoreDomain
import PrimitiveExportProfile
import WorkoutCoreFoundation

public enum WorkoutKitMatrixRowID: String, Sendable, Hashable, Codable, CaseIterable {
    case continuousCardio
    case simpleIntervals
    case straightStrength
    case roundRobinStrength
    case cappedForTime
    case loadedCarry
    case mobilityRecovery
    case setmarkOnlyRest
    case ambiguousAmrap
    case unsupported
}

public enum WorkoutKitDeliveryPath: String, Sendable, Hashable, Codable, CaseIterable {
    case scheduleOnPhone
    case openOnWatch
    case previewOnly
}

public enum WorkoutKitCandidateFamily: String, Sendable, Hashable, Codable, CaseIterable {
    case singleGoal
    case customWorkout
    case pacer
    case swimBikeRun
    case none
}

public enum WorkoutKitSupportState: String, Sendable, Hashable, Codable, CaseIterable {
    case native
    case degraded
    case setmarkOnly
    case unsupported
}

public enum WorkoutKitSelectionPolicy: Sendable, Hashable, Codable {
    case exact(WorkoutKitCandidateFamily)
    case firstSupported([WorkoutKitCandidateFamily])
    case none
}

public enum WorkoutKitPayloadShape: String, Sendable, Hashable, Codable, CaseIterable {
    case singleGoal
    case customIntervals
    case openFunctionalStrength
    case noPayload
}

public enum WorkoutKitActivitySelection: String, Sendable, Hashable, Codable, CaseIterable {
    case cardio
    case functionalStrength
    case mixed
    case carry
    case recovery
    case unknown
}

public enum WorkoutKitGoalBlueprint: String, Sendable, Hashable, Codable, CaseIterable {
    case open
    case time
    case distance
    case intervalSteps
    case none
}

public struct WorkoutKitStepBlueprint: Sendable, Hashable, Codable {
    public var preservesOrder: Bool
    public var preservesWorkRestCadence: Bool
    public var notes: String?

    public init(
        preservesOrder: Bool,
        preservesWorkRestCadence: Bool,
        notes: String? = nil
    ) {
        self.preservesOrder = preservesOrder
        self.preservesWorkRestCadence = preservesWorkRestCadence
        self.notes = notes
    }
}

public struct WorkoutKitPayloadBlueprint: Sendable, Hashable, Codable {
    public var shape: WorkoutKitPayloadShape
    public var activitySelection: WorkoutKitActivitySelection
    public var goal: WorkoutKitGoalBlueprint
    public var steps: [WorkoutKitStepBlueprint]

    public init(
        shape: WorkoutKitPayloadShape,
        activitySelection: WorkoutKitActivitySelection,
        goal: WorkoutKitGoalBlueprint,
        steps: [WorkoutKitStepBlueprint] = []
    ) {
        self.shape = shape
        self.activitySelection = activitySelection
        self.goal = goal
        self.steps = steps
    }
}

public enum WorkoutKitPushIdentityRequirement: String, Sendable, Hashable, Codable, CaseIterable {
    case stableWorkoutPlanID
    case payloadFingerprint
    case degradationDisclosure
    case occurrenceDateComponents
}

public struct WorkoutKitPushIdentity: Sendable, Hashable, Codable {
    public var requirements: Set<WorkoutKitPushIdentityRequirement>

    public init(requirements: Set<WorkoutKitPushIdentityRequirement>) {
        self.requirements = requirements
    }

    public static let none = WorkoutKitPushIdentity(requirements: [])
}

public enum WorkoutKitProofRequirement: String, Sendable, Hashable, Codable, CaseIterable {
    case sdkCompile
    case simulatorConstruction
    case realDeviceScheduleVisibility
    case realDeviceStartability
    case duplicateUpdateBehavior
    case degradationAcknowledgement
    case activitySupport
}

public enum WorkoutKitBlockReason: String, Sendable, Hashable, Codable, CaseIterable {
    case sourceAmbiguity
    case targetCapabilityUnavailable
    case setmarkOnly
    case realDeviceProofRequired
    case duplicateUpdateProofRequired
    case degradationAcknowledgementRequired
    case activitySupportUnproven
}

public enum WorkoutKitVisibleResult: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case workoutCompletionVisibleInAppleWorkout
    case workoutDurationVisibleInAppleWorkout
    case distanceOrDurationVisibleInAppleWorkout
    case intervalCompletionVisibleInAppleWorkout
}

public enum WorkoutKitExportFact: String, Sendable, Hashable, Codable, CaseIterable {
    case activityType
    case location
    case timeGoal
    case distanceGoal
    case intervalOrder
    case workRestCadence
    case broadActivity
    case setmarkHierarchy
    case exerciseIdentity
    case load
    case reps
    case rir
    case alternatives
    case perSlotResults
    case aggregateScore
    case partialCompletion
    case carryLoad
    case poseSequence
    case customStepNames
}

public struct WorkoutKitDegradation: Sendable, Hashable, Codable {
    public var preservedFacts: Set<WorkoutKitExportFact>
    public var omittedFacts: Set<WorkoutKitExportFact>
    public var visibleResult: WorkoutKitVisibleResult

    public init(
        preservedFacts: Set<WorkoutKitExportFact>,
        omittedFacts: Set<WorkoutKitExportFact>,
        visibleResult: WorkoutKitVisibleResult
    ) {
        self.preservedFacts = preservedFacts
        self.omittedFacts = omittedFacts
        self.visibleResult = visibleResult
    }
}

public struct WorkoutKitExportPlan: Sendable, Hashable, Codable {
    public var workoutID: WorkoutID
    public var workoutName: String
    public var rowID: WorkoutKitMatrixRowID
    public var deliveryPaths: Set<WorkoutKitDeliveryPath>
    public var selectionPolicy: WorkoutKitSelectionPolicy
    public var supportState: WorkoutKitSupportState
    public var payload: WorkoutKitPayloadBlueprint
    public var pushIdentity: WorkoutKitPushIdentity
    public var degradation: WorkoutKitDegradation?
    public var proofRequirements: Set<WorkoutKitProofRequirement>
    public var unresolvedRequirements: Set<WorkoutKitBlockReason>
    public var sourceAmbiguities: Set<PrimitiveExportAmbiguity>

    public init(
        workoutID: WorkoutID,
        workoutName: String,
        rowID: WorkoutKitMatrixRowID,
        deliveryPaths: Set<WorkoutKitDeliveryPath>,
        selectionPolicy: WorkoutKitSelectionPolicy,
        supportState: WorkoutKitSupportState,
        payload: WorkoutKitPayloadBlueprint,
        pushIdentity: WorkoutKitPushIdentity,
        degradation: WorkoutKitDegradation?,
        proofRequirements: Set<WorkoutKitProofRequirement>,
        unresolvedRequirements: Set<WorkoutKitBlockReason>,
        sourceAmbiguities: Set<PrimitiveExportAmbiguity>
    ) {
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.rowID = rowID
        self.deliveryPaths = deliveryPaths
        self.selectionPolicy = selectionPolicy
        self.supportState = supportState
        self.payload = payload
        self.pushIdentity = pushIdentity
        self.degradation = degradation
        self.proofRequirements = proofRequirements
        self.unresolvedRequirements = unresolvedRequirements
        self.sourceAmbiguities = sourceAmbiguities
    }
}

public struct WorkoutKitDeliveryProofs: Sendable, Hashable, Codable {
    public var proven: Set<WorkoutKitProofRequirement>
    public var degradationAcknowledged: Bool

    public init(
        proven: Set<WorkoutKitProofRequirement> = [],
        degradationAcknowledged: Bool = false
    ) {
        self.proven = proven
        self.degradationAcknowledged = degradationAcknowledged
    }
}

public struct WorkoutKitDeliveryAssessment: Sendable, Hashable, Codable {
    public var path: WorkoutKitDeliveryPath
    public var unmetProofRequirements: Set<WorkoutKitProofRequirement>
    public var unmetAcknowledgementRequirements: Set<WorkoutKitProofRequirement>
    public var blockingReasons: Set<WorkoutKitBlockReason>

    public init(
        path: WorkoutKitDeliveryPath,
        unmetProofRequirements: Set<WorkoutKitProofRequirement>,
        unmetAcknowledgementRequirements: Set<WorkoutKitProofRequirement>,
        blockingReasons: Set<WorkoutKitBlockReason>
    ) {
        self.path = path
        self.unmetProofRequirements = unmetProofRequirements
        self.unmetAcknowledgementRequirements = unmetAcknowledgementRequirements
        self.blockingReasons = blockingReasons
    }
}
