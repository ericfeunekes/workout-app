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
            unresolved.insert(.targetFamilyUnavailable)
        }
        if !facts.ambiguities.isEmpty,
           contract.blocksOnSourceAmbiguity,
           !unresolved.contains(.needsSourceChoice)
        {
            unresolved.insert(.sourceAmbiguity)
        }
        if !unsupported,
           contract.supportState != .unsupported,
           contract.descriptor.completeness == .incomplete,
           contract.descriptor.incompleteReasons.contains(.exactTargetValuesUnavailable)
        {
            unresolved.insert(.exactTargetValuesUnavailable)
        }
        let sourceChoices = contract.sourceChoicesRequired
        var categories = contract.classificationCategories
        if contract.supportState == .native {
            categories.insert(.firstClass)
        }
        if contract.supportState == .degraded {
            categories.insert(.lossyPushable)
        }
        if contract.supportState == .setmarkOnly {
            categories.insert(.setmarkOnly)
        }
        if unsupported || (
            contract.supportState == .unsupported
                && !unresolved.contains(.needsSourceChoice)
                && !unresolved.contains(.misleadingRepresentation)
        ) {
            categories.insert(.unsupported)
        }
        if unresolved.contains(.sourceAmbiguity) || unresolved.contains(.needsSourceChoice) {
            categories.insert(.needsSourceChoice)
        }
        if unresolved.contains(.misleadingRepresentation) {
            categories.insert(.misleading)
        }
        if unresolved.contains(.realDeviceProofRequired)
            || unresolved.contains(.scheduleVisibilityProofRequired)
            || unresolved.contains(.watchStartabilityProofRequired)
            || unresolved.contains(.duplicateUpdateProofRequired)
            || unresolved.contains(.activitySupportUnproven)
        {
            categories.insert(.proofBlocked)
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
            sourceAmbiguities: facts.ambiguities,
            classificationCategories: categories,
            sourceChoicesRequired: sourceChoices,
            descriptor: unsupported ? .incomplete([.targetFamilyUnavailable]) : contract.descriptor
        )
    }

    public func report(for workout: PrimitiveWorkout) throws -> WorkoutKitClassificationReport {
        try report(for: PrimitiveExportProfileBuilder.build(workout: workout))
    }

    public func report(for facts: PrimitiveExportFacts) throws -> WorkoutKitClassificationReport {
        let plan = try classify(facts)
        let degradation = plan.degradation
        return WorkoutKitClassificationReport(
            plan: plan,
            sourceFactsConsulted: facts.activityIntent,
            missingSourceChoices: plan.sourceChoicesRequired,
            categories: plan.classificationCategories,
            preservedFacts: degradation?.preservedFacts ?? [],
            omittedFacts: degradation?.omittedFacts ?? [],
            blockingReasons: reportBlockReasons(for: plan),
            neutralFactRemedies: remedies(for: plan.sourceChoicesRequired)
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
        if let rowBlockers = terminalRowBlockers(in: plan.unresolvedRequirements) {
            return WorkoutKitDeliveryAssessment(
                path: path,
                unmetProofRequirements: [],
                unmetAcknowledgementRequirements: [],
                blockingReasons: rowBlockers
            )
        }
        var acknowledgement: Set<WorkoutKitProofRequirement> = []
        if plan.supportState == .degraded, !proofs.degradationAcknowledged {
            acknowledgement.insert(.degradationAcknowledgement)
        }
        let unmet = required.subtracting(proofs.proven)
        var reasons = plan.unresolvedRequirements
        if !plan.deliveryPaths.contains(path) {
            reasons.insert(.deliveryPathUnavailable)
            return WorkoutKitDeliveryAssessment(
                path: path,
                unmetProofRequirements: [],
                unmetAcknowledgementRequirements: [],
                blockingReasons: reasons
            )
        }
        if plan.descriptor.completeness == .incomplete {
            reasons.formUnion(plan.descriptor.incompleteReasons)
        }
        if plan.requiresExactTargetValues {
            reasons.insert(.exactTargetValuesUnavailable)
        }
        insertBlockReasons(for: unmet, into: &reasons)
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

private func terminalRowBlockers(
    in reasons: Set<WorkoutKitBlockReason>
) -> Set<WorkoutKitBlockReason>? {
    let terminal = reasons.intersection([
        .setmarkOnly,
        .sourceAmbiguity,
        .needsSourceChoice,
        .misleadingRepresentation,
        .targetCapabilityUnavailable,
        .targetFamilyUnavailable,
    ])
    return terminal.isEmpty ? nil : terminal
}

private func insertBlockReasons(
    for unmet: Set<WorkoutKitProofRequirement>,
    into reasons: inout Set<WorkoutKitBlockReason>
) {
    if unmet.contains(.realDeviceScheduleVisibility) {
        reasons.insert(.scheduleVisibilityProofRequired)
    }
    if unmet.contains(.realDeviceStartability) {
        reasons.insert(.watchStartabilityProofRequired)
    }
    if unmet.contains(.activitySupport) {
        reasons.insert(.activitySupportUnproven)
    }
    let remaining = unmet.subtracting([
        .realDeviceScheduleVisibility,
        .realDeviceStartability,
        .activitySupport,
        .duplicateUpdateBehavior,
    ])
    if !remaining.isEmpty {
        reasons.insert(.realDeviceProofRequired)
    }
}

private func reportBlockReasons(
    for plan: WorkoutKitExportPlan
) -> Set<WorkoutKitBlockReason> {
    var reasons = plan.unresolvedRequirements
    if plan.descriptor.completeness == .incomplete {
        reasons.formUnion(plan.descriptor.incompleteReasons)
    }
    var proofRequirements = plan.proofRequirements
    if proofRequirements.remove(.degradationAcknowledgement) != nil,
       plan.supportState == .degraded
    {
        reasons.insert(.degradationAcknowledgementRequired)
    }
    insertBlockReasons(for: proofRequirements, into: &reasons)
    return reasons
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
    var classificationCategories: Set<WorkoutKitClassificationCategory>
    var sourceChoicesRequired: Set<WorkoutKitSourceChoice>
    var descriptor: WorkoutKitDescriptorBlueprint

    var requiresExactTargetValues: Bool {
        descriptor.incompleteReasons.contains(.exactTargetValuesUnavailable)
    }

    static func contract(for facts: PrimitiveExportFacts) -> WorkoutKitMatrixContract {
        let axes = facts.axes
        if axes.slotCount == 0 {
            return .unsupported()
        }
        if isMixedDistanceStation(axes: axes) {
            return .mixedDistanceStation(axes: axes, facts: facts)
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
        if axes.metrics.contains(.loadCarried) {
            return .loadedCarry(axes: axes, facts: facts)
        }
        if axes.traversals.contains(.roundRobin), axes.slotCount > 1 {
            return .roundRobinStrength(axes: axes)
        }
        if axes.setTimings.contains(.capBounded) {
            return .cappedForTime(axes: axes)
        }
        if axes.setTimings.contains(.timeBounded), axes.hasRest, !axes.hasLoad {
            return .simpleIntervals(facts: facts)
        }
        if let paceTargetRun = paceTargetRun(facts: facts) {
            return paceTargetRun
        }
        if axes.metrics.contains(.distance), !axes.hasLoad {
            return .continuousCardio(facts: facts, distanceBased: true)
        }
        if axes.metrics.contains(.duration),
           !axes.hasLoad,
           !axes.hasRest,
           !axes.setTimings.contains(.timeBounded)
        {
            return .continuousCardio(facts: facts, distanceBased: false)
        }
        if axes.hasLoad || axes.hasRir || axes.metrics.contains(.reps) {
            return .straightStrength(axes: axes, facts: facts)
        }
        if axes.setTimings.contains(.timeBounded) {
            return .mobilityRecovery(facts: facts)
        }
        return .unsupported()
    }

    static func continuousCardio(
        facts: PrimitiveExportFacts,
        distanceBased: Bool
    ) -> WorkoutKitMatrixContract {
        guard let intent = facts.activityIntent else {
            return needsSourceChoice(rowID: .continuousCardio, choices: [.activityDomain])
        }
        let activitySelection = activitySelection(for: intent.activityDomain)
        let descriptorGoal: WorkoutKitDescriptorGoal?
        let goal: WorkoutKitGoalBlueprint
        if distanceBased {
            goal = .distance
            descriptorGoal = singleTargetValue(in: facts, metric: .distance).map { .distanceMeters($0) }
        } else {
            goal = .time
            descriptorGoal = singleTargetValue(in: facts, metric: .duration).map { .timeSeconds($0) }
        }
        return native(
            rowID: .continuousCardio,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: activitySelection,
                goal: goal
            ),
            descriptor: resolvedDescriptorBlueprint(
                activitySelection: activitySelection,
                location: location(for: intent),
                goal: descriptorGoal
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: distanceBased ? [.activityType, .distanceGoal] : [.activityType, .timeGoal],
                omittedFacts: [.setmarkHierarchy],
                visibleResult: .workoutCompletionVisibleInAppleWorkout
            )
        )
    }

    static func paceTargetRun(facts: PrimitiveExportFacts) -> WorkoutKitMatrixContract? {
        guard facts.axes.blockCount == 1,
              facts.axes.setCount == 1,
              facts.axes.slotCount == 1,
              let block = facts.blocks.first,
              block.repeatCount == 1,
              block.workTargets.isEmpty,
              let set = block.sets.first,
              set.repeatCount == 1,
              set.workTargets.isEmpty,
              let slot = set.slots.first,
              !slot.isWarmup,
              slot.load == nil,
              slot.postRestSec == 0,
              slot.stimuli.isEmpty
        else {
            return nil
        }
        guard let intent = facts.activityIntent else {
            return needsSourceChoice(rowID: .paceTargetRun, choices: [.activityDomain])
        }
        guard intent.activityDomain == .running else {
            return nil
        }

        let distanceTargets = slot.workTargets.filter {
            $0.metric == .distance && $0.valueForm == .single && $0.role == .completion
        }
        let durationTargets = slot.workTargets.filter {
            $0.metric == .duration && $0.valueForm == .single && $0.role == .observation
        }
        guard distanceTargets.count == 1,
              durationTargets.count == 1,
              slot.workTargets.count == 2,
              let distanceMeters = distanceTargets[0].value,
              let timeSeconds = durationTargets[0].value,
              distanceMeters > 0,
              timeSeconds > 0
        else {
            return nil
        }

        return native(
            rowID: .paceTargetRun,
            family: .pacer,
            payload: WorkoutKitPayloadBlueprint(
                shape: .pacer,
                activitySelection: .running,
                goal: .pacer
            ),
            descriptor: .resolved(WorkoutKitResolvedDescriptorBlueprint(
                activitySelection: .running,
                location: location(for: intent),
                goal: .pacer(distanceMeters: distanceMeters, timeSeconds: timeSeconds)
            )),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .distanceGoal, .timeGoal],
                omittedFacts: [.setmarkHierarchy],
                visibleResult: .distanceOrDurationVisibleInAppleWorkout
            )
        )
    }

    static func simpleIntervals(facts: PrimitiveExportFacts) -> WorkoutKitMatrixContract {
        guard let intent = facts.activityIntent else {
            return needsSourceChoice(rowID: .simpleIntervals, choices: [.activityDomain])
        }
        let activitySelection = activitySelection(for: intent.activityDomain)
        let intervalSteps = intervalDescriptorSteps(in: facts)
        let canPreserveAuthoredMetric = !facts.axes.metrics.contains(.distance)
        return native(
            rowID: .simpleIntervals,
            family: .customWorkout,
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: activitySelection,
                goal: .intervalSteps,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: true)]
            ),
            descriptor: intervalSteps.flatMap { steps in
                guard canPreserveAuthoredMetric else {
                    return nil
                }
                return .resolved(WorkoutKitResolvedDescriptorBlueprint(
                    activitySelection: activitySelection,
                    location: location(for: intent),
                    goal: .open,
                    steps: steps,
                    intervalIterations: intervalIterations(in: facts)
                ))
            } ?? .incomplete([.exactTargetValuesUnavailable]),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .intervalOrder, .workRestCadence],
                omittedFacts: [.setmarkHierarchy, .customStepNames],
                visibleResult: .intervalCompletionVisibleInAppleWorkout
            )
        )
    }

    static func straightStrength(
        axes: PrimitiveAxisSummary,
        facts: PrimitiveExportFacts
    ) -> WorkoutKitMatrixContract {
        let activitySelection = strengthActivitySelection(for: facts.activityIntent)
        let duration = axes.metrics.contains(.duration)
            ? singleTargetValue(in: facts, metric: .duration).map { WorkoutKitDescriptorGoal.timeSeconds($0) }
            : WorkoutKitDescriptorGoal.open
        return degraded(
            rowID: .straightStrength,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: activitySelection,
                goal: axes.metrics.contains(.duration) ? .time : .open
            ),
            descriptor: resolvedDescriptorBlueprint(
                activitySelection: activitySelection,
                location: location(for: facts.activityIntent),
                goal: duration
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

    static func loadedCarry(
        axes: PrimitiveAxisSummary,
        facts: PrimitiveExportFacts
    ) -> WorkoutKitMatrixContract {
        guard facts.activityIntent?.activityDomain == .carry else {
            return needsSourceChoice(
                rowID: .loadedCarry,
                choices: [.activityDomain],
                supportState: .degraded
            )
        }
        let distanceBased = axes.metrics.contains(.distance)
        return degraded(
            rowID: .loadedCarry,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .carry,
                goal: distanceBased ? .distance : .time
            ),
            descriptor: resolvedDescriptorBlueprint(
                activitySelection: .carry,
                location: location(for: facts.activityIntent),
                goal: distanceBased
                    ? singleTargetValue(in: facts, metric: .distance).map { .distanceMeters($0) }
                    : singleTargetValue(in: facts, metric: .duration).map { .timeSeconds($0) }
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: distanceBased ? [.activityType, .distanceGoal] : [.activityType, .timeGoal],
                omittedFacts: [.setmarkHierarchy, .exerciseIdentity, .carryLoad, .load, .perSlotResults],
                visibleResult: .distanceOrDurationVisibleInAppleWorkout
            )
        )
    }

    static func mobilityRecovery(facts: PrimitiveExportFacts) -> WorkoutKitMatrixContract {
        guard facts.activityIntent?.activityDomain == .mobility else {
            return needsSourceChoice(rowID: .mobilityRecovery, choices: [.activityDomain])
        }
        let descriptorGoal = singleTargetValue(in: facts, metric: .duration).map {
            WorkoutKitDescriptorGoal.timeSeconds($0)
        }
        var contract = degraded(
            rowID: .mobilityRecovery,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .recovery,
                goal: .time
            ),
            descriptor: resolvedDescriptorBlueprint(
                activitySelection: .recovery,
                location: location(for: facts.activityIntent),
                goal: descriptorGoal
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity, .timeGoal],
                omittedFacts: [.setmarkHierarchy, .poseSequence],
                visibleResult: .workoutDurationVisibleInAppleWorkout
            ),
            proofRequirements: [.sdkCompile, .simulatorConstruction, .activitySupport, .degradationAcknowledgement]
        )
        contract.blocksOnSourceAmbiguity = false
        return contract
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
            blocksOnSourceAmbiguity: true,
            classificationCategories: [.needsSourceChoice],
            sourceChoicesRequired: [],
            descriptor: .incomplete([.needsSourceChoice])
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
            blocksOnSourceAmbiguity: false,
            classificationCategories: [.setmarkOnly],
            sourceChoicesRequired: [],
            descriptor: .incomplete([.setmarkOnly])
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
            blocksOnSourceAmbiguity: false,
            classificationCategories: [.unsupported],
            sourceChoicesRequired: [],
            descriptor: .incomplete([.targetCapabilityUnavailable])
        )
    }

    static func mixedDistanceStation(
        axes: PrimitiveAxisSummary,
        facts: PrimitiveExportFacts
    ) -> WorkoutKitMatrixContract {
        let intent = facts.activityIntent
        guard let intent else {
            return needsSourceChoice(
                rowID: .continuousCardio,
                choices: [.activityDomain, .preservationPolicy],
                supportState: .degraded
            )
        }

        switch (intent.activityDomain, intent.preservationPolicy) {
        case (.running, .preservePrimaryActivity), (.running, .preserveDistance):
            return runningFirstMixedDistanceStation(axes: axes, facts: facts)
        case (.mixedModal, .preserveStructure), (.mixedModal, .preserveMixedModality):
            return structureFirstMixedDistanceStation(axes: axes)
        case (.mixedModal, nil):
            return needsSourceChoice(
                rowID: .cappedForTime,
                choices: [.preservationPolicy],
                supportState: .degraded
            )
        case (.running, .preserveStructure), (.running, .preserveMixedModality):
            return misleadingSourceChoice(rowID: .continuousCardio)
        case (_, nil):
            return needsSourceChoice(
                rowID: .cappedForTime,
                choices: [.preservationPolicy],
                supportState: .degraded
            )
        default:
            return needsSourceChoice(
                rowID: .cappedForTime,
                choices: [.preservationPolicy],
                supportState: .degraded
            )
        }
    }

    static func runningFirstMixedDistanceStation(
        axes: PrimitiveAxisSummary,
        facts: PrimitiveExportFacts
    ) -> WorkoutKitMatrixContract {
        degraded(
            rowID: .continuousCardio,
            family: .singleGoal,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .running,
                goal: .distance
            ),
            descriptor: resolvedDescriptorBlueprint(
                activitySelection: .running,
                location: location(for: facts.activityIntent),
                goal: singleTargetValue(in: facts, metric: .distance).map { .distanceMeters($0) }
            ),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .distanceGoal],
                omittedFacts: strengthOmittedFacts(axes: axes).union([.setmarkHierarchy]),
                visibleResult: .distanceOrDurationVisibleInAppleWorkout
            )
        )
    }

    static func structureFirstMixedDistanceStation(axes: PrimitiveAxisSummary) -> WorkoutKitMatrixContract {
        degraded(
            rowID: .cappedForTime,
            family: .customWorkout,
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .mixed,
                goal: .open,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: axes.hasRest)]
            ),
            descriptor: .incomplete([.exactTargetValuesUnavailable]),
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity, .setmarkHierarchy],
                omittedFacts: strengthOmittedFacts(axes: axes).union([.distanceGoal, .customStepNames]),
                visibleResult: .intervalCompletionVisibleInAppleWorkout
            )
        )
    }

    static func needsSourceChoice(
        rowID: WorkoutKitMatrixRowID,
        choices: Set<WorkoutKitSourceChoice>,
        supportState: WorkoutKitSupportState = .native
    ) -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: rowID,
            candidateFamilies: [.singleGoal, .customWorkout],
            deliveryPaths: [],
            selectionPolicy: .firstSupported([.singleGoal, .customWorkout]),
            supportState: supportState,
            payload: .none,
            pushIdentity: .none,
            degradation: nil,
            proofRequirements: [.sdkCompile],
            unresolvedRequirements: [.needsSourceChoice],
            blocksOnSourceAmbiguity: true,
            classificationCategories: [.needsSourceChoice],
            sourceChoicesRequired: choices,
            descriptor: .incomplete([.needsSourceChoice])
        )
    }

    static func misleadingSourceChoice(rowID: WorkoutKitMatrixRowID) -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: rowID,
            candidateFamilies: [.singleGoal, .customWorkout],
            deliveryPaths: [],
            selectionPolicy: .firstSupported([.singleGoal, .customWorkout]),
            supportState: .degraded,
            payload: .none,
            pushIdentity: .none,
            degradation: nil,
            proofRequirements: [.sdkCompile],
            unresolvedRequirements: [.misleadingRepresentation],
            blocksOnSourceAmbiguity: false,
            classificationCategories: [.misleading],
            sourceChoicesRequired: [.preservationPolicy],
            descriptor: .incomplete([.misleadingRepresentation])
        )
    }

    private static func native(
        rowID: WorkoutKitMatrixRowID,
        family: WorkoutKitCandidateFamily,
        payload: WorkoutKitPayloadBlueprint,
        descriptor: WorkoutKitDescriptorBlueprint? = nil,
        degradation: WorkoutKitDegradation,
        proofRequirements: Set<WorkoutKitProofRequirement> = [
            .sdkCompile,
            .simulatorConstruction,
        ]
    ) -> WorkoutKitMatrixContract {
        WorkoutKitMatrixContract(
            rowID: rowID,
            candidateFamilies: [family],
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
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
            blocksOnSourceAmbiguity: true,
            classificationCategories: [.firstClass],
            sourceChoicesRequired: [],
            descriptor: descriptor ?? defaultDescriptorBlueprint(for: payload)
        )
    }

    private static func degraded(
        rowID: WorkoutKitMatrixRowID,
        family: WorkoutKitCandidateFamily,
        payload: WorkoutKitPayloadBlueprint,
        descriptor: WorkoutKitDescriptorBlueprint? = nil,
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
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
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
            blocksOnSourceAmbiguity: true,
            classificationCategories: [.lossyPushable],
            sourceChoicesRequired: [],
            descriptor: descriptor ?? defaultDescriptorBlueprint(for: payload)
        )
    }

    private static func strengthOmittedFacts(axes: PrimitiveAxisSummary) -> Set<WorkoutKitExportFact> {
        var facts: Set<WorkoutKitExportFact> = [.setmarkHierarchy, .exerciseIdentity, .perSlotResults]
        if axes.hasLoad { facts.insert(.load) }
        if axes.hasRir { facts.insert(.rir) }
        if axes.metrics.contains(.reps) { facts.insert(.reps) }
        return facts
    }

    private static func isMixedDistanceStation(axes: PrimitiveAxisSummary) -> Bool {
        axes.metrics.contains(.distance)
            && !axes.metrics.contains(.loadCarried)
            && (
                axes.metrics.contains(.reps)
                    || axes.hasLoad
            )
    }

    private static func defaultDescriptorBlueprint(
        for payload: WorkoutKitPayloadBlueprint
    ) -> WorkoutKitDescriptorBlueprint {
        switch (payload.shape, payload.goal) {
        case (.noPayload, _), (_, .none):
            .incomplete([.targetCapabilityUnavailable])
        case (_, .pacer):
            .incomplete([.exactTargetValuesUnavailable])
        case (.customIntervals, _), (_, .time), (_, .distance), (_, .intervalSteps):
            .incomplete([.exactTargetValuesUnavailable])
        case (_, .open):
            .resolved(WorkoutKitResolvedDescriptorBlueprint(
                activitySelection: payload.activitySelection,
                goal: .open
            ))
        }
    }

    private static func resolvedDescriptorBlueprint(
        activitySelection: WorkoutKitActivitySelection,
        location: WorkoutKitResolvedLocation = .unknown,
        goal: WorkoutKitDescriptorGoal?
    ) -> WorkoutKitDescriptorBlueprint {
        guard let goal else {
            return .incomplete([.exactTargetValuesUnavailable])
        }
        return .resolved(WorkoutKitResolvedDescriptorBlueprint(
            activitySelection: activitySelection,
            location: location,
            goal: goal
        ))
    }

    private static func location(for intent: ActivityIntent?) -> WorkoutKitResolvedLocation {
        switch intent?.environment {
        case .indoor:
            .indoor
        case .outdoor:
            .outdoor
        case .unspecified, nil:
            .unknown
        }
    }

    private static func activitySelection(for domain: ActivityDomain) -> WorkoutKitActivitySelection {
        switch domain {
        case .running:
            .running
        case .cycling:
            .cycling
        case .rowing:
            .rowing
        case .swimming:
            .swimming
        case .walking:
            .walking
        case .hiking:
            .hiking
        case .functionalStrength:
            .functionalStrength
        case .traditionalStrength:
            .traditionalStrength
        case .hiit:
            .hiit
        case .mobility:
            .recovery
        case .mixedModal:
            .mixed
        case .carry:
            .carry
        case .other:
            .cardio
        }
    }

    private static func strengthActivitySelection(
        for intent: ActivityIntent?
    ) -> WorkoutKitActivitySelection {
        switch intent?.activityDomain {
        case .traditionalStrength:
            .traditionalStrength
        default:
            .functionalStrength
        }
    }

    private static func singleTargetValue(
        in facts: PrimitiveExportFacts,
        metric: PrimitiveMetric
    ) -> Double? {
        let targets = facts.blocks.flatMap { block in
            block.workTargets
                + block.sets.flatMap { set in
                    set.workTargets + set.slots.flatMap(\.workTargets)
                }
        }
        let matching = targets.filter {
            $0.metric == metric && $0.valueForm == .single
        }
        guard matching.count == 1 else {
            return nil
        }
        return matching[0].value
    }

    private static func intervalIterations(in facts: PrimitiveExportFacts) -> Int {
        facts.blocks
            .flatMap(\.sets)
            .first?
            .timing
            .rounds ?? 1
    }

    private static func intervalDescriptorSteps(
        in facts: PrimitiveExportFacts
    ) -> [WorkoutKitDescriptorStep]? {
        let sets = facts.blocks.flatMap(\.sets)
        guard sets.count == 1,
              let firstSet = sets.first,
              firstSet.slots.count == 1,
              let intervalSec = firstSet.timing.intervalSec
        else {
            return nil
        }
        let work = WorkoutKitDescriptorStep(
            purpose: .work,
            goal: .timeSeconds(Double(intervalSec))
        )
        guard let restSeconds = firstSet.slots.first?.postRestSec,
              restSeconds > 0
        else {
            return [work]
        }
        return [
            work,
            WorkoutKitDescriptorStep(
                purpose: .recovery,
                goal: .timeSeconds(Double(restSeconds))
            ),
        ]
    }
}

private extension WorkoutKitPayloadBlueprint {
    static let none = WorkoutKitPayloadBlueprint(
        shape: .noPayload,
        activitySelection: .unknown,
        goal: .none
    )
}

private func remedies(
    for choices: Set<WorkoutKitSourceChoice>
) -> [WorkoutKitSourceChoice: String] {
    var remedies: [WorkoutKitSourceChoice: String] = [:]
    if choices.contains(.activityDomain) {
        remedies[.activityDomain] = "Choose the workout activity domain that should anchor the Apple Workout export."
    }
    if choices.contains(.environment) {
        remedies[.environment] = "Choose indoor, outdoor, or unspecified when location affects target semantics."
    }
    if choices.contains(.preservationPolicy) {
        remedies[.preservationPolicy] = "Choose whether the export should preserve primary activity, structure, elapsed time, distance, or mixed modality."
    }
    return remedies
}
