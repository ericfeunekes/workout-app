import Foundation
import CoreDomain
import PrimitiveExportProfile
import WorkoutCoreFoundation

public enum WorkoutKitMatrixRowID: String, Sendable, Hashable, Codable, CaseIterable {
    case paceTargetRun
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

public enum WorkoutKitClassificationCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case firstClass
    case lossyPushable
    case broadTrackerWithDisclosedLoss
    case needsSourceChoice
    case proofBlocked
    case misleading
    case setmarkOnly
    case unsupported
}

public enum WorkoutKitSelectionPolicy: Sendable, Hashable, Codable {
    case exact(WorkoutKitCandidateFamily)
    case firstSupported([WorkoutKitCandidateFamily])
    case none
}

public enum WorkoutKitPayloadShape: String, Sendable, Hashable, Codable, CaseIterable {
    case pacer
    case singleGoal
    case customIntervals
    case openFunctionalStrength
    case noPayload
}

public enum WorkoutKitActivitySelection: String, Sendable, Hashable, Codable, CaseIterable {
    case cardio
    case running
    case cycling
    case rowing
    case swimming
    case walking
    case hiking
    case functionalStrength
    case traditionalStrength
    case hiit
    case mixed
    case carry
    case recovery
    case unknown
}

public enum WorkoutKitGoalBlueprint: String, Sendable, Hashable, Codable, CaseIterable {
    case pacer
    case open
    case time
    case distance
    case intervalSteps
    case none
}

public enum WorkoutKitDescriptorCompleteness: String, Sendable, Hashable, Codable, CaseIterable {
    case complete
    case incomplete
}

public enum WorkoutKitAdmissionState: String, Sendable, Hashable, Codable, CaseIterable {
    case pushReady
    case sourceChoiceRequired
    case descriptorIncomplete
    case degradationAcknowledgementRequired
    case proofBlocked
    case setmarkOnly
    case unsupported
    case misleading
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

public enum WorkoutKitDescriptorGoal: Sendable, Hashable, Codable {
    case open
    case timeSeconds(Double)
    case distanceMeters(Double)
    case pacer(distanceMeters: Double, timeSeconds: Double)
}

public enum WorkoutKitDescriptorStepPurpose: String, Sendable, Hashable, Codable, CaseIterable {
    case work
    case recovery
}

public struct WorkoutKitDescriptorStep: Sendable, Hashable, Codable {
    public var purpose: WorkoutKitDescriptorStepPurpose
    public var goal: WorkoutKitDescriptorGoal

    public init(purpose: WorkoutKitDescriptorStepPurpose, goal: WorkoutKitDescriptorGoal) {
        self.purpose = purpose
        self.goal = goal
    }
}

public struct WorkoutKitResolvedDescriptorBlueprint: Sendable, Hashable, Codable {
    public var activitySelection: WorkoutKitActivitySelection
    public var location: WorkoutKitResolvedLocation
    public var goal: WorkoutKitDescriptorGoal
    public var steps: [WorkoutKitDescriptorStep]
    public var intervalIterations: Int

    public init(
        activitySelection: WorkoutKitActivitySelection,
        location: WorkoutKitResolvedLocation = .unknown,
        goal: WorkoutKitDescriptorGoal,
        steps: [WorkoutKitDescriptorStep] = [],
        intervalIterations: Int = 1
    ) {
        self.activitySelection = activitySelection
        self.location = location
        self.goal = goal
        self.steps = steps
        self.intervalIterations = intervalIterations
    }
}

public enum WorkoutKitDescriptorBlueprint: Sendable, Hashable, Codable {
    case resolved(WorkoutKitResolvedDescriptorBlueprint)
    case incomplete(Set<WorkoutKitBlockReason>)

    public var completeness: WorkoutKitDescriptorCompleteness {
        switch self {
        case .resolved:
            .complete
        case .incomplete:
            .incomplete
        }
    }

    public var incompleteReasons: Set<WorkoutKitBlockReason> {
        switch self {
        case .resolved:
            []
        case .incomplete(let reasons):
            reasons
        }
    }
}

public struct WorkoutKitPlanDescriptor: Sendable, Hashable, Codable {
    public var id: UUID
    public var displayName: String
    public var family: WorkoutKitCandidateFamily
    public var activity: WorkoutKitResolvedActivity
    public var location: WorkoutKitResolvedLocation
    public var goal: WorkoutKitResolvedGoal
    public var intervalSteps: [WorkoutKitResolvedIntervalStep]
    public var intervalIterations: Int

    public init(
        id: UUID,
        displayName: String,
        family: WorkoutKitCandidateFamily,
        activity: WorkoutKitResolvedActivity,
        location: WorkoutKitResolvedLocation = .unknown,
        goal: WorkoutKitResolvedGoal,
        intervalSteps: [WorkoutKitResolvedIntervalStep] = [],
        intervalIterations: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.activity = activity
        self.location = location
        self.goal = goal
        self.intervalSteps = intervalSteps
        self.intervalIterations = intervalIterations
    }
}

public enum WorkoutKitResolvedActivity: String, Sendable, Hashable, Codable, CaseIterable {
    case running
    case cycling
    case rowing
    case swimming
    case hiking
    case functionalStrength
    case traditionalStrength
    case hiit
    case mixedCardio
    case walking
    case flexibility
    case other
}

public enum WorkoutKitResolvedLocation: String, Sendable, Hashable, Codable, CaseIterable {
    case unknown
    case indoor
    case outdoor
}

public enum WorkoutKitResolvedGoal: Sendable, Hashable, Codable {
    case open
    case timeSeconds(Double)
    case distanceMeters(Double)
    case pacer(distanceMeters: Double, timeSeconds: Double)
}

public struct WorkoutKitResolvedIntervalStep: Sendable, Hashable, Codable {
    public enum Purpose: String, Sendable, Hashable, Codable {
        case work
        case recovery
    }

    public var purpose: Purpose
    public var goal: WorkoutKitResolvedGoal

    public init(purpose: Purpose, goal: WorkoutKitResolvedGoal) {
        self.purpose = purpose
        self.goal = goal
    }
}

public enum WorkoutKitDescriptorResolutionError: Error, Sendable, Hashable, Codable {
    case nonConstructible(Set<WorkoutKitBlockReason>)
    case unsupportedSelectionPolicy
    case unsupportedPayloadShape(WorkoutKitPayloadShape)
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
    case needsSourceChoice
    case misleadingRepresentation
    case targetCapabilityUnavailable
    case targetFamilyUnavailable
    case deliveryPathUnavailable
    case exactTargetValuesUnavailable
    case setmarkOnly
    case realDeviceProofRequired
    case scheduleVisibilityProofRequired
    case watchStartabilityProofRequired
    case duplicateUpdateProofRequired
    case degradationAcknowledgementRequired
    case activitySupportUnproven
}

public enum WorkoutKitSourceChoice: String, Sendable, Hashable, Codable, CaseIterable {
    case activityDomain
    case environment
    case preservationPolicy
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
    public var classificationCategories: Set<WorkoutKitClassificationCategory>
    public var sourceChoicesRequired: Set<WorkoutKitSourceChoice>
    public var descriptor: WorkoutKitDescriptorBlueprint

    public var requiresExactTargetValues: Bool {
        descriptor.incompleteReasons.contains(.exactTargetValuesUnavailable)
    }

    public var admissionState: WorkoutKitAdmissionState {
        if unresolvedRequirements.contains(.needsSourceChoice)
            || unresolvedRequirements.contains(.sourceAmbiguity)
        {
            return .sourceChoiceRequired
        }
        if unresolvedRequirements.contains(.misleadingRepresentation) {
            return .misleading
        }
        if supportState == .setmarkOnly || unresolvedRequirements.contains(.setmarkOnly) {
            return .setmarkOnly
        }
        if supportState == .unsupported
            || unresolvedRequirements.contains(.targetCapabilityUnavailable)
            || unresolvedRequirements.contains(.targetFamilyUnavailable)
        {
            return .unsupported
        }
        if descriptor.completeness == .incomplete
            || unresolvedRequirements.contains(.exactTargetValuesUnavailable)
        {
            return .descriptorIncomplete
        }
        if supportState == .degraded
            && proofRequirements.contains(.degradationAcknowledgement)
            && !unresolvedRequirements.contains(.degradationAcknowledgementRequired)
        {
            return .degradationAcknowledgementRequired
        }
        if !unresolvedRequirements.isEmpty || !proofRequirements.isEmpty {
            return .proofBlocked
        }
        return .pushReady
    }

    public func resolvedPlanDescriptor() throws -> WorkoutKitPlanDescriptor {
        guard supportState != .unsupported,
              supportState != .setmarkOnly,
              payload.shape != .noPayload
        else {
            throw WorkoutKitDescriptorResolutionError.unsupportedPayloadShape(payload.shape)
        }
        guard case .resolved(let resolved) = descriptor else {
            throw WorkoutKitDescriptorResolutionError.nonConstructible(
                descriptor.incompleteReasons.union(unresolvedRequirements)
            )
        }
        let family = try resolvedCandidateFamily()
        return WorkoutKitPlanDescriptor(
            id: workoutID,
            displayName: workoutName,
            family: family,
            activity: Self.resolvedActivity(from: resolved.activitySelection),
            location: resolved.location,
            goal: Self.resolvedGoal(from: resolved.goal),
            intervalSteps: resolved.steps.map(Self.resolvedIntervalStep(from:)),
            intervalIterations: resolved.intervalIterations
        )
    }

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
        sourceAmbiguities: Set<PrimitiveExportAmbiguity>,
        classificationCategories: Set<WorkoutKitClassificationCategory> = [],
        sourceChoicesRequired: Set<WorkoutKitSourceChoice> = [],
        descriptor: WorkoutKitDescriptorBlueprint
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
        self.classificationCategories = classificationCategories
        self.sourceChoicesRequired = sourceChoicesRequired
        self.descriptor = descriptor
    }

    private func resolvedCandidateFamily() throws -> WorkoutKitCandidateFamily {
        switch selectionPolicy {
        case .exact(let family):
            return family
        case .firstSupported(let families):
            guard let family = families.first else {
                throw WorkoutKitDescriptorResolutionError.unsupportedSelectionPolicy
            }
            return family
        case .none:
            throw WorkoutKitDescriptorResolutionError.unsupportedSelectionPolicy
        }
    }

    private static func resolvedGoal(
        from goal: WorkoutKitDescriptorGoal
    ) -> WorkoutKitResolvedGoal {
        switch goal {
        case .open:
            .open
        case .timeSeconds(let seconds):
            .timeSeconds(seconds)
        case .distanceMeters(let meters):
            .distanceMeters(meters)
        case .pacer(let distanceMeters, let timeSeconds):
            .pacer(distanceMeters: distanceMeters, timeSeconds: timeSeconds)
        }
    }

    private static func resolvedIntervalStep(
        from step: WorkoutKitDescriptorStep
    ) -> WorkoutKitResolvedIntervalStep {
        WorkoutKitResolvedIntervalStep(
            purpose: step.purpose == .work ? .work : .recovery,
            goal: resolvedGoal(from: step.goal)
        )
    }

    private static func resolvedActivity(
        from selection: WorkoutKitActivitySelection
    ) -> WorkoutKitResolvedActivity {
        switch selection {
        case .running:
            .running
        case .cycling:
            .cycling
        case .rowing:
            .rowing
        case .swimming:
            .swimming
        case .hiking:
            .hiking
        case .functionalStrength:
            .functionalStrength
        case .traditionalStrength:
            .traditionalStrength
        case .hiit:
            .hiit
        case .mixed:
            .mixedCardio
        case .walking, .carry:
            .walking
        case .recovery:
            .flexibility
        case .cardio, .unknown:
            .other
        }
    }
}

public struct WorkoutKitClassificationReport: Sendable, Hashable, Codable {
    public var plan: WorkoutKitExportPlan
    public var sourceFactsConsulted: ActivityIntent?
    public var missingSourceChoices: Set<WorkoutKitSourceChoice>
    public var categories: Set<WorkoutKitClassificationCategory>
    public var preservedFacts: Set<WorkoutKitExportFact>
    public var omittedFacts: Set<WorkoutKitExportFact>
    public var blockingReasons: Set<WorkoutKitBlockReason>
    public var neutralFactRemedies: [WorkoutKitSourceChoice: String]

    public init(
        plan: WorkoutKitExportPlan,
        sourceFactsConsulted: ActivityIntent?,
        missingSourceChoices: Set<WorkoutKitSourceChoice>,
        categories: Set<WorkoutKitClassificationCategory>,
        preservedFacts: Set<WorkoutKitExportFact>,
        omittedFacts: Set<WorkoutKitExportFact>,
        blockingReasons: Set<WorkoutKitBlockReason>,
        neutralFactRemedies: [WorkoutKitSourceChoice: String] = [:]
    ) {
        self.plan = plan
        self.sourceFactsConsulted = sourceFactsConsulted
        self.missingSourceChoices = missingSourceChoices
        self.categories = categories
        self.preservedFacts = preservedFacts
        self.omittedFacts = omittedFacts
        self.blockingReasons = blockingReasons
        self.neutralFactRemedies = neutralFactRemedies
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
