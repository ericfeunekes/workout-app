import Foundation
import CoreDomain
import PrimitiveExportProfile

public struct WorkoutKitExportClassifier: Sendable {
    private let supportedCandidates: Set<WorkoutKitCandidateFamily>

    public init(
        supportedCandidates: Set<WorkoutKitCandidateFamily> = Set(WorkoutKitCandidateFamily.allCases)
    ) {
        self.supportedCandidates = supportedCandidates
    }

    public func classify(workout: PrimitiveWorkout) throws -> WorkoutKitExportPlan {
        try classify(PrimitiveExportProfileBuilder.build(workout: workout))
    }

    public func classify(_ facts: PrimitiveExportFacts) throws -> WorkoutKitExportPlan {
        let contract = WorkoutKitMatrixContract.contract(for: facts)
        let unsupported = !contract.candidateFamilies.isEmpty
            && contract.candidateFamilies.isDisjoint(with: supportedCandidates)
        var unresolved = contract.unresolvedRequirements
        if unsupported {
            unresolved.insert(.targetCapabilityUnavailable)
        }
        if !facts.ambiguities.isEmpty, contract.blocksOnSourceAmbiguity {
            unresolved.insert(.sourceAmbiguity)
        }

        return WorkoutKitExportPlan(
            workoutID: facts.workoutID,
            workoutName: facts.workoutName,
            rowID: contract.rowID,
            deliveryPaths: contract.deliveryPaths,
            selectionPolicy: contract.selectionPolicy,
            supportState: unsupported ? .unsupported : contract.supportState,
            payload: unsupported ? .none : contract.payload,
            pushIdentity: contract.pushIdentity,
            degradation: unsupported ? nil : contract.degradation,
            proofRequirements: contract.proofRequirements,
            unresolvedRequirements: unresolved,
            sourceAmbiguities: facts.ambiguities
        )
    }

    public func assessDelivery(
        _ plan: WorkoutKitExportPlan,
        path: WorkoutKitDeliveryPath,
        proofs: WorkoutKitDeliveryProofs = WorkoutKitDeliveryProofs()
    ) -> WorkoutKitDeliveryAssessment {
        var required = plan.proofRequirements
        required.remove(.degradationAcknowledgement)
        if path == .scheduleOnPhone {
            required.formUnion([.realDeviceScheduleVisibility, .duplicateUpdateBehavior])
        }
        if path == .openOnWatch {
            required.insert(.realDeviceStartability)
        }
        var acknowledgement: Set<WorkoutKitProofRequirement> = []
        if plan.supportState == .degraded, !proofs.degradationAcknowledged {
            acknowledgement.insert(.degradationAcknowledgement)
        }
        let unmet = required.subtracting(proofs.proven)
        var reasons = plan.unresolvedRequirements
        if !unmet.isEmpty {
            reasons.insert(.realDeviceProofRequired)
        }
        if unmet.contains(.duplicateUpdateBehavior) {
            reasons.insert(.duplicateUpdateProofRequired)
        }
        if !acknowledgement.isEmpty {
            reasons.insert(.degradationAcknowledgementRequired)
        }

        return WorkoutKitDeliveryAssessment(
            path: path,
            unmetProofRequirements: unmet,
            unmetAcknowledgementRequirements: acknowledgement,
            blockingReasons: reasons
        )
    }
}

private struct WorkoutKitMatrixContract: Sendable, Hashable {
    var rowID: WorkoutKitMatrixRowID
    var candidateFamilies: Set<WorkoutKitCandidateFamily>
    var deliveryPaths: Set<WorkoutKitDeliveryPath>
    var selectionPolicy: WorkoutKitSelectionPolicy
    var supportState: WorkoutKitSupportState
    var payload: WorkoutKitPayloadBlueprint
    var pushIdentity: WorkoutKitPushIdentity
    var degradation: WorkoutKitDegradation?
    var proofRequirements: Set<WorkoutKitProofRequirement>
    var unresolvedRequirements: Set<WorkoutKitBlockReason>
    var blocksOnSourceAmbiguity: Bool

    static func contract(for facts: PrimitiveExportFacts) -> WorkoutKitMatrixContract {
        let axes = facts.axes
        if axes.slotCount == 0 {
            return .unsupported()
        }
        if axes.setTimings == [.timeBounded],
           axes.metrics.isEmpty,
           axes.hasRest,
           axes.slotCount == 1
        {
            return .setmarkOnlyRest()
        }
        if axes.traversals.contains(.amrap),
           axes.metrics.contains(.rounds)
        {
            return .ambiguousAmrap()
        }
        if axes.slotsWithLoadAndDistance > 0 || axes.metrics.contains(.loadCarried) {
            return .loadedCarry(distanceBased: axes.metrics.contains(.distance))
        }
        if axes.traversals.contains(.roundRobin), axes.slotCount > 1 {
            return .roundRobinStrength(axes: axes)
        }
        if axes.setTimings.contains(.capBounded) {
            return .cappedForTime(axes: axes)
        }
        if axes.metrics.contains(.distance), !axes.hasLoad {
            return .continuousCardio(distanceBased: true)
        }
        if axes.metrics.contains(.duration),
           !axes.hasLoad,
           !axes.hasRest,
           !axes.setTimings.contains(.timeBounded)
        {
            return .continuousCardio(distanceBased: false)
        }
        if axes.hasLoad || axes.hasRir || axes.metrics.contains(.reps) {
            return .straightStrength(axes: axes)
        }
        if axes.setTimings.contains(.timeBounded), axes.hasRest {
            return .simpleIntervals()
        }
        if axes.setTimings.contains(.timeBounded) {
            return .mobilityRecovery()
        }
        return .unsupported()
    }

    static func continuousCardio(distanceBased: Bool) -> WorkoutKitMatrixContract {
        native(
            rowID: .continuousCardio,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .cardio,
                goal: distanceBased ? .distance : .time
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: distanceBased ? [.activityType, .distanceGoal] : [.activityType, .timeGoal],
                omittedFacts: [.setmarkHierarchy],
                visibleResult: .workoutCompletionVisibleInAppleWorkout
            )
        )
    }

    static func simpleIntervals() -> WorkoutKitMatrixContract {
        native(
            rowID: .simpleIntervals,
            family: .customWorkout,
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .cardio,
                goal: .intervalSteps,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: true)]
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .intervalOrder, .workRestCadence],
                omittedFacts: [.setmarkHierarchy, .customStepNames],
                visibleResult: .intervalCompletionVisibleInAppleWorkout
            )
        )
    }

    static func straightStrength(axes: PrimitiveAxisSummary) -> WorkoutKitMatrixContract {
        degraded(
            rowID: .straightStrength,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .functionalStrength,
                goal: axes.metrics.contains(.duration) ? .time : .open
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity],
                omittedFacts: strengthOmittedFacts(axes: axes),
                visibleResult: .workoutDurationVisibleInAppleWorkout
            )
        )
    }

    static func roundRobinStrength(axes: PrimitiveAxisSummary) -> WorkoutKitMatrixContract {
        degraded(
            rowID: .roundRobinStrength,
            family: .customWorkout,
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .functionalStrength,
                goal: axes.setTimings.contains(.timeBounded) ? .intervalSteps : .open,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: axes.hasRest)]
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity],
                omittedFacts: strengthOmittedFacts(axes: axes).union([.alternatives]),
                visibleResult: .intervalCompletionVisibleInAppleWorkout
            )
        )
    }

    static func cappedForTime(axes: PrimitiveAxisSummary) -> WorkoutKitMatrixContract {
        degraded(
            rowID: .cappedForTime,
            family: .customWorkout,
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .mixed,
                goal: .time,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: axes.hasRest)]
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity, .timeGoal],
                omittedFacts: strengthOmittedFacts(axes: axes).union([.aggregateScore, .partialCompletion]),
                visibleResult: .workoutDurationVisibleInAppleWorkout
            )
        )
    }

    static func loadedCarry(distanceBased: Bool) -> WorkoutKitMatrixContract {
        degraded(
            rowID: .loadedCarry,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .carry,
                goal: distanceBased ? .distance : .time
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: distanceBased ? [.activityType, .distanceGoal] : [.activityType, .timeGoal],
                omittedFacts: [.setmarkHierarchy, .exerciseIdentity, .carryLoad, .load, .perSlotResults],
                visibleResult: .distanceOrDurationVisibleInAppleWorkout
            )
        )
    }

    static func mobilityRecovery() -> WorkoutKitMatrixContract {
        degraded(
            rowID: .mobilityRecovery,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .recovery,
                goal: .time
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity, .timeGoal],
                omittedFacts: [.setmarkHierarchy, .poseSequence],
                visibleResult: .workoutDurationVisibleInAppleWorkout
            ),
            proofRequirements: [.sdkCompile, .simulatorConstruction, .activitySupport, .degradationAcknowledgement]
        )
    }

    static func ambiguousAmrap() -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: .ambiguousAmrap,
            candidateFamilies: [.customWorkout],
            deliveryPaths: [],
            selectionPolicy: .firstSupported([.customWorkout, .singleGoal]),
            supportState: .unsupported,
            payload: .none,
            pushIdentity: .none,
            degradation: nil,
            proofRequirements: [.sdkCompile],
            unresolvedRequirements: [.sourceAmbiguity],
            blocksOnSourceAmbiguity: true
        )
    }

    static func setmarkOnlyRest() -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: .setmarkOnlyRest,
            candidateFamilies: [],
            deliveryPaths: [],
            selectionPolicy: .none,
            supportState: .setmarkOnly,
            payload: .none,
            pushIdentity: .none,
            degradation: nil,
            proofRequirements: [],
            unresolvedRequirements: [.setmarkOnly],
            blocksOnSourceAmbiguity: false
        )
    }

    static func unsupported() -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: .unsupported,
            candidateFamilies: [],
            deliveryPaths: [],
            selectionPolicy: .none,
            supportState: .unsupported,
            payload: .none,
            pushIdentity: .none,
            degradation: nil,
            proofRequirements: [.sdkCompile],
            unresolvedRequirements: [.targetCapabilityUnavailable],
            blocksOnSourceAmbiguity: false
        )
    }

    private static func native(
        rowID: WorkoutKitMatrixRowID,
        family: WorkoutKitCandidateFamily,
        payload: WorkoutKitPayloadBlueprint,
        degradation: WorkoutKitDegradation,
        proofRequirements: Set<WorkoutKitProofRequirement> = [
            .sdkCompile,
            .simulatorConstruction,
        ]
    ) -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: rowID,
            candidateFamilies: [family],
            deliveryPaths: [.scheduleOnPhone, .openOnWatch, .previewOnly],
            selectionPolicy: .exact(family),
            supportState: .native,
            payload: payload,
            pushIdentity: WorkoutKitPushIdentity(requirements: [
                .stableWorkoutPlanID,
                .payloadFingerprint,
                .occurrenceDateComponents,
            ]),
            degradation: degradation,
            proofRequirements: proofRequirements,
            unresolvedRequirements: [],
            blocksOnSourceAmbiguity: true
        )
    }

    private static func degraded(
        rowID: WorkoutKitMatrixRowID,
        family: WorkoutKitCandidateFamily,
        payload: WorkoutKitPayloadBlueprint,
        degradation: WorkoutKitDegradation,
        proofRequirements: Set<WorkoutKitProofRequirement> = [
            .sdkCompile,
            .simulatorConstruction,
            .degradationAcknowledgement,
        ]
    ) -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: rowID,
            candidateFamilies: [family],
            deliveryPaths: [.scheduleOnPhone, .openOnWatch, .previewOnly],
            selectionPolicy: .exact(family),
            supportState: .degraded,
            payload: payload,
            pushIdentity: WorkoutKitPushIdentity(requirements: [
                .stableWorkoutPlanID,
                .payloadFingerprint,
                .degradationDisclosure,
                .occurrenceDateComponents,
            ]),
            degradation: degradation,
            proofRequirements: proofRequirements,
            unresolvedRequirements: [],
            blocksOnSourceAmbiguity: true
        )
    }

    private static func strengthOmittedFacts(axes: PrimitiveAxisSummary) -> Set<WorkoutKitExportFact> {
        var facts: Set<WorkoutKitExportFact> = [.setmarkHierarchy, .exerciseIdentity, .perSlotResults]
        if axes.hasLoad { facts.insert(.load) }
        if axes.hasRir { facts.insert(.rir) }
        if axes.metrics.contains(.reps) { facts.insert(.reps) }
        return facts
    }
}

private extension WorkoutKitPayloadBlueprint {
    static let none = WorkoutKitPayloadBlueprint(
        shape: .noPayload,
        activitySelection: .unknown,
        goal: .none
    )
}
