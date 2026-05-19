import XCTest
import CoreDomain
import PrimitiveExportProfile
import WorkoutCoreFoundation
import WorkoutKitExportProfile

final class WorkoutKitExportClassifierTests: XCTestCase {
    func testPrimitiveFactsPreserveSourceStructureAndAxisCoOccurrence() throws {
        let workout = Self.workout(
            timing: PrimitiveTiming(mode: .targetBounded),
            slots: [
                Self.slot(
                    targets: [Self.target(.distance, value: 400)],
                    load: PrimitiveLoad(value: 24, unit: .kg, unitType: .absolute),
                    stimuli: [PrimitiveStimulus(type: .rir, target: 3)],
                    postRestSec: 60,
                    isWarmup: true
                ),
            ]
        )

        let facts = try PrimitiveExportProfileBuilder.build(workout: workout)

        XCTAssertEqual(facts.workoutID, workout.id)
        XCTAssertEqual(facts.blocks[0].id, workout.blocks[0].id)
        XCTAssertEqual(facts.blocks[0].order, 0)
        XCTAssertEqual(facts.blocks[0].sets[0].id, workout.blocks[0].sets[0].id)
        XCTAssertEqual(facts.blocks[0].sets[0].order, 0)
        XCTAssertEqual(facts.blocks[0].sets[0].slots[0].id, workout.blocks[0].sets[0].slots[0].id)
        XCTAssertEqual(facts.blocks[0].sets[0].slots[0].order, 0)
        XCTAssertEqual(facts.axes.targetScopes, [.slot])
        XCTAssertEqual(facts.axes.metrics, [.distance])
        XCTAssertTrue(facts.axes.hasLoad)
        XCTAssertTrue(facts.axes.hasRir)
        XCTAssertTrue(facts.axes.hasRest)
        XCTAssertTrue(facts.axes.hasWarmup)
        XCTAssertEqual(facts.axes.slotsWithLoadAndDistance, 1)
    }

    func testPrimitiveFactsSurfaceSourceAmbiguityWithoutTargetPolicy() throws {
        let facts = try PrimitiveExportProfileBuilder.build(workout: Self.amrapWorkout())

        XCTAssertEqual(facts.axes.setTimings, [.capBounded])
        XCTAssertEqual(facts.axes.traversals, [.amrap])
        XCTAssertEqual(facts.axes.metrics, [.rounds, .reps])
        XCTAssertEqual(facts.ambiguities, [.resultOverlayNotRepresentedInPrimitives])
    }

    func testPrimitiveFactsRequireSourceFactForCardioMapping() throws {
        let facts = try PrimitiveExportProfileBuilder.build(workout: Self.continuousCardioWorkout())

        XCTAssertTrue(facts.axes.metrics.contains(.distance))
        XCTAssertTrue(facts.ambiguities.contains(.missingSourceFact))
    }

    func testClassifiesRepresentativePrimitiveRowsThroughRealBuilder() throws {
        let classifier = WorkoutKitExportClassifier()

        let cases: [(PrimitiveWorkout, WorkoutKitMatrixRowID, WorkoutKitSupportState, WorkoutKitPayloadShape)] = [
            (Self.continuousCardioWorkout(), .continuousCardio, .native, .singleGoal),
            (Self.timeGoalCardioWorkout(), .continuousCardio, .native, .singleGoal),
            (Self.simpleIntervalWorkout(), .simpleIntervals, .native, .customIntervals),
            (Self.restTimerWorkout(), .setmarkOnlyRest, .setmarkOnly, .noPayload),
            (Self.straightStrengthWorkout(), .straightStrength, .degraded, .singleGoal),
            (Self.timeBoundedStrengthWithRestWorkout(), .straightStrength, .degraded, .singleGoal),
            (Self.roundRobinStrengthWorkout(), .roundRobinStrength, .degraded, .customIntervals),
            (Self.cappedForTimeWorkout(), .cappedForTime, .degraded, .customIntervals),
            (Self.loadedCarryWorkout(), .loadedCarry, .degraded, .singleGoal),
            (Self.mobilityRecoveryWorkout(), .mobilityRecovery, .degraded, .singleGoal),
        ]

        for (workout, rowID, support, payloadShape) in cases {
            let plan = try classifier.classify(workout: workout)
            XCTAssertEqual(plan.rowID, rowID, workout.name)
            XCTAssertEqual(plan.supportState, support, workout.name)
            XCTAssertEqual(plan.payload.shape, payloadShape, workout.name)
        }
    }

    func testConcreteRowsHaveExactWorkoutKitSemantics() throws {
        let classifier = WorkoutKitExportClassifier()
        let baseProofs: Set<WorkoutKitProofRequirement> = [.sdkCompile, .simulatorConstruction]
        let degradedProofs = baseProofs.union([.degradationAcknowledgement])
        let nativeIdentity: Set<WorkoutKitPushIdentityRequirement> = [
            .stableWorkoutPlanID,
            .payloadFingerprint,
            .occurrenceDateComponents,
        ]
        let degradedIdentity = nativeIdentity.union([.degradationDisclosure])

        try Self.assertPlan(
            try classifier.classify(workout: Self.continuousCardioWorkout()),
            support: .native,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.singleGoal),
            payload: WorkoutKitPayloadBlueprint(shape: .singleGoal, activitySelection: .cardio, goal: .distance),
            identity: nativeIdentity,
            proofRequirements: baseProofs,
            unresolvedRequirements: [.exactTargetValuesUnavailable, .sourceAmbiguity],
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .distanceGoal],
                omittedFacts: [.setmarkHierarchy],
                visibleResult: .workoutCompletionVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.timeGoalCardioWorkout()),
            support: .native,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.singleGoal),
            payload: WorkoutKitPayloadBlueprint(shape: .singleGoal, activitySelection: .cardio, goal: .time),
            identity: nativeIdentity,
            proofRequirements: baseProofs,
            unresolvedRequirements: [.exactTargetValuesUnavailable, .sourceAmbiguity],
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .timeGoal],
                omittedFacts: [.setmarkHierarchy],
                visibleResult: .workoutCompletionVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.simpleIntervalWorkout()),
            support: .native,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.customWorkout),
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .cardio,
                goal: .intervalSteps,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: true)]
            ),
            identity: nativeIdentity,
            proofRequirements: baseProofs,
            unresolvedRequirements: [.exactTargetValuesUnavailable, .sourceAmbiguity],
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .intervalOrder, .workRestCadence],
                omittedFacts: [.setmarkHierarchy, .customStepNames],
                visibleResult: .intervalCompletionVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.straightStrengthWorkout()),
            support: .degraded,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.singleGoal),
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .functionalStrength,
                goal: .open
            ),
            identity: degradedIdentity,
            proofRequirements: degradedProofs,
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity],
                omittedFacts: [.setmarkHierarchy, .exerciseIdentity, .load, .reps, .rir, .perSlotResults],
                visibleResult: .workoutDurationVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.roundRobinStrengthWorkout()),
            support: .degraded,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.customWorkout),
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .functionalStrength,
                goal: .open,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: false)]
            ),
            identity: degradedIdentity,
            proofRequirements: degradedProofs,
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity],
                omittedFacts: [.setmarkHierarchy, .exerciseIdentity, .reps, .alternatives, .perSlotResults],
                visibleResult: .intervalCompletionVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.cappedForTimeWorkout()),
            support: .degraded,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.customWorkout),
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .mixed,
                goal: .time,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: false)]
            ),
            identity: degradedIdentity,
            proofRequirements: degradedProofs,
            unresolvedRequirements: [.exactTargetValuesUnavailable, .sourceAmbiguity],
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity, .timeGoal],
                omittedFacts: [.setmarkHierarchy, .exerciseIdentity, .reps, .perSlotResults, .aggregateScore, .partialCompletion],
                visibleResult: .workoutDurationVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.loadedCarryWorkout()),
            support: .degraded,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.singleGoal),
            payload: WorkoutKitPayloadBlueprint(shape: .singleGoal, activitySelection: .carry, goal: .distance),
            identity: degradedIdentity,
            proofRequirements: degradedProofs,
            unresolvedRequirements: [.exactTargetValuesUnavailable],
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .distanceGoal],
                omittedFacts: [.setmarkHierarchy, .exerciseIdentity, .load, .carryLoad, .perSlotResults],
                visibleResult: .distanceOrDurationVisibleInAppleWorkout
            )
        )
        try Self.assertPlan(
            try classifier.classify(workout: Self.mobilityRecoveryWorkout()),
            support: .degraded,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.singleGoal),
            payload: WorkoutKitPayloadBlueprint(shape: .singleGoal, activitySelection: .recovery, goal: .time),
            identity: degradedIdentity,
            proofRequirements: degradedProofs.union([.activitySupport]),
            unresolvedRequirements: [.exactTargetValuesUnavailable],
            degradation: WorkoutKitDegradation(
                preservedFacts: [.activityType, .broadActivity, .timeGoal],
                omittedFacts: [.setmarkHierarchy, .poseSequence],
                visibleResult: .workoutDurationVisibleInAppleWorkout
            )
        )
    }

    func testStrengthAndCarryDegradationTracksOmittedSetmarkFactsAndIdentityDisclosure() throws {
        let classifier = WorkoutKitExportClassifier()

        let strength = try classifier.classify(workout: Self.straightStrengthWorkout())
        XCTAssertEqual(strength.supportState, .degraded)
        XCTAssertTrue(strength.degradation?.omittedFacts.contains(.load) == true)
        XCTAssertTrue(strength.degradation?.omittedFacts.contains(.reps) == true)
        XCTAssertTrue(strength.degradation?.omittedFacts.contains(.rir) == true)
        XCTAssertTrue(strength.proofRequirements.contains(.degradationAcknowledgement))

        let carry = try classifier.classify(workout: Self.loadedCarryWorkout())
        XCTAssertEqual(carry.supportState, .degraded)
        XCTAssertTrue(carry.degradation?.omittedFacts.contains(.carryLoad) == true)
        XCTAssertTrue(carry.pushIdentity.requirements.contains(.degradationDisclosure))
    }

    func testLoadedCarryRequiresExplicitCarryAuthority() throws {
        let classifier = WorkoutKitExportClassifier()

        let explicitCarry = try classifier.classify(workout: Self.loadedCarryWorkout())
        XCTAssertEqual(explicitCarry.rowID, .loadedCarry)
        XCTAssertEqual(explicitCarry.payload.activitySelection, .carry)

        let weightedDistance = try classifier.classify(workout: Self.genericWeightedDistanceWorkout())
        XCTAssertNotEqual(weightedDistance.rowID, .loadedCarry)
        XCTAssertNotEqual(weightedDistance.payload.activitySelection, .carry)
    }

    func testAmbiguousAmrapFailsClosedEvenWhenConstructionProofsExist() throws {
        let classifier = WorkoutKitExportClassifier()
        let plan = try classifier.classify(workout: Self.amrapWorkout())

        XCTAssertEqual(plan.rowID, .ambiguousAmrap)
        XCTAssertEqual(plan.supportState, .unsupported)
        XCTAssertTrue(plan.deliveryPaths.isEmpty)
        XCTAssertTrue(plan.unresolvedRequirements.contains(.sourceAmbiguity))
        XCTAssertTrue(plan.sourceAmbiguities.contains(.resultOverlayNotRepresentedInPrimitives))

        let assessment = classifier.assessDelivery(
            plan,
            path: .previewOnly,
            proofs: WorkoutKitDeliveryProofs()
        )
        XCTAssertTrue(assessment.unmetProofRequirements.isEmpty)
        XCTAssertEqual(assessment.blockingReasons, [.sourceAmbiguity])
    }

    func testDeliveryAssessmentKeepsPathSpecificProofsOutOfTheBasePlan() throws {
        let classifier = WorkoutKitExportClassifier()
        var plan = try classifier.classify(workout: Self.continuousCardioWorkout())
        plan.unresolvedRequirements.remove(.sourceAmbiguity)

        XCTAssertEqual(plan.proofRequirements, [.sdkCompile, .simulatorConstruction])

        let noProofs = classifier.assessDelivery(plan, path: .previewOnly)
        XCTAssertTrue(noProofs.unmetProofRequirements.isEmpty)
        XCTAssertEqual(noProofs.blockingReasons, [
            .deliveryPathUnavailable,
            .exactTargetValuesUnavailable,
        ])

        let preview = classifier.assessDelivery(plan, path: .previewOnly, proofs: WorkoutKitDeliveryProofs(
            proven: [.sdkCompile, .simulatorConstruction]
        ))
        XCTAssertTrue(preview.unmetProofRequirements.isEmpty)
        XCTAssertEqual(preview.blockingReasons, [
            .deliveryPathUnavailable,
            .exactTargetValuesUnavailable,
        ])

        let scheduled = classifier.assessDelivery(plan, path: .scheduleOnPhone, proofs: WorkoutKitDeliveryProofs(
            proven: [.sdkCompile, .simulatorConstruction]
        ))
        XCTAssertEqual(scheduled.unmetProofRequirements, [.realDeviceScheduleVisibility, .duplicateUpdateBehavior])
        XCTAssertEqual(scheduled.blockingReasons, [
            .scheduleVisibilityProofRequired,
            .duplicateUpdateProofRequired,
            .exactTargetValuesUnavailable,
        ])

        let opened = classifier.assessDelivery(plan, path: .openOnWatch, proofs: WorkoutKitDeliveryProofs(
            proven: [.sdkCompile, .simulatorConstruction]
        ))
        XCTAssertEqual(opened.unmetProofRequirements, [.realDeviceStartability])
        XCTAssertEqual(opened.blockingReasons, [
            .watchStartabilityProofRequired,
            .exactTargetValuesUnavailable,
        ])
    }

    func testDeliveryAssessmentBlocksPathsOutsidePlanContract() throws {
        let classifier = WorkoutKitExportClassifier()
        var plan = try classifier.classify(workout: Self.straightStrengthWorkout())
        plan.deliveryPaths = [.previewOnly]

        let assessment = classifier.assessDelivery(
            plan,
            path: .scheduleOnPhone,
            proofs: WorkoutKitDeliveryProofs(
                proven: [
                    .sdkCompile,
                    .simulatorConstruction,
                    .realDeviceScheduleVisibility,
                    .duplicateUpdateBehavior,
                ],
                degradationAcknowledged: true
            )
        )

        XCTAssertEqual(assessment.blockingReasons, [.deliveryPathUnavailable])
    }

    func testValueBackedWorkoutKitRowsBlockUntilExactTargetMappingExists() throws {
        let classifier = WorkoutKitExportClassifier()
        let timePlan = try classifier.classify(workout: Self.timeGoalCardioWorkout())
        let distancePlan = try classifier.classify(workout: Self.continuousCardioWorkout())
        let intervalPlan = try classifier.classify(workout: Self.simpleIntervalWorkout())
        let openPlan = try classifier.classify(workout: Self.straightStrengthWorkout())

        XCTAssertTrue(timePlan.unresolvedRequirements.contains(.exactTargetValuesUnavailable))
        XCTAssertTrue(distancePlan.unresolvedRequirements.contains(.exactTargetValuesUnavailable))
        XCTAssertTrue(intervalPlan.unresolvedRequirements.contains(.exactTargetValuesUnavailable))
        XCTAssertFalse(openPlan.unresolvedRequirements.contains(.exactTargetValuesUnavailable))
    }

    func testUnavailableCandidateFamilyDoesNotAlsoReportExactTargetGap() throws {
        let classifier = WorkoutKitExportClassifier(supportedCandidates: [.customWorkout])
        let plan = try classifier.classify(workout: Self.continuousCardioWorkout())

        XCTAssertEqual(plan.supportState, .unsupported)
        XCTAssertEqual(plan.payload.shape, .noPayload)
        XCTAssertEqual(plan.unresolvedRequirements, [.sourceAmbiguity, .targetFamilyUnavailable])

        let assessment = classifier.assessDelivery(
            plan,
            path: .scheduleOnPhone,
            proofs: WorkoutKitDeliveryProofs()
        )
        XCTAssertEqual(assessment.blockingReasons, [.sourceAmbiguity, .targetFamilyUnavailable])
        XCTAssertTrue(assessment.unmetProofRequirements.isEmpty)
    }

    func testDegradationAcknowledgementIsNotCountedAsDeviceProof() throws {
        let classifier = WorkoutKitExportClassifier()
        let plan = try classifier.classify(workout: Self.straightStrengthWorkout())

        let missingAcknowledgement = classifier.assessDelivery(
            plan,
            path: .scheduleOnPhone,
            proofs: WorkoutKitDeliveryProofs(proven: [.sdkCompile, .simulatorConstruction])
        )
        XCTAssertEqual(
            missingAcknowledgement.unmetProofRequirements,
            [.realDeviceScheduleVisibility, .duplicateUpdateBehavior]
        )
        XCTAssertEqual(missingAcknowledgement.unmetAcknowledgementRequirements, [.degradationAcknowledgement])
        XCTAssertEqual(missingAcknowledgement.blockingReasons, [
            .scheduleVisibilityProofRequired,
            .duplicateUpdateProofRequired,
            .degradationAcknowledgementRequired,
        ])

        let acknowledged = classifier.assessDelivery(
            plan,
            path: .scheduleOnPhone,
            proofs: WorkoutKitDeliveryProofs(
                proven: [
                    .sdkCompile,
                    .simulatorConstruction,
                    .realDeviceScheduleVisibility,
                    .duplicateUpdateBehavior,
                ],
                degradationAcknowledged: true
            )
        )
        XCTAssertTrue(acknowledged.unmetProofRequirements.isEmpty)
        XCTAssertTrue(acknowledged.unmetAcknowledgementRequirements.isEmpty)
        XCTAssertTrue(acknowledged.blockingReasons.isEmpty)
    }

    func testActivitySupportIsExplicitForMobilityRecovery() throws {
        let classifier = WorkoutKitExportClassifier()
        let plan = try classifier.classify(workout: Self.mobilityRecoveryWorkout())

        XCTAssertTrue(plan.proofRequirements.contains(.activitySupport))

        let assessment = classifier.assessDelivery(plan, path: .scheduleOnPhone, proofs: WorkoutKitDeliveryProofs(
            proven: [.sdkCompile, .simulatorConstruction],
            degradationAcknowledged: true
        ))
        XCTAssertTrue(assessment.unmetProofRequirements.contains(.activitySupport))
        XCTAssertEqual(assessment.blockingReasons, [
            .exactTargetValuesUnavailable,
            .activitySupportUnproven,
            .scheduleVisibilityProofRequired,
            .duplicateUpdateProofRequired,
        ])
    }

    private static func continuousCardioWorkout() -> PrimitiveWorkout {
        workout(
            name: "Continuous cardio",
            timing: PrimitiveTiming(mode: .targetBounded),
            slots: [slot(targets: [target(.distance, value: 5_000)])]
        )
    }

    private static func timeGoalCardioWorkout() -> PrimitiveWorkout {
        workout(
            name: "Time goal cardio",
            timing: PrimitiveTiming(mode: .targetBounded),
            slots: [slot(targets: [target(.duration, value: 1_800)])]
        )
    }

    private static func simpleIntervalWorkout() -> PrimitiveWorkout {
        workout(
            name: "Simple intervals",
            timing: PrimitiveTiming(mode: .timeBounded, intervalSec: 60, rounds: 4),
            slots: [slot(targets: [target(.duration, value: 60)], postRestSec: 30)]
        )
    }

    private static func restTimerWorkout() -> PrimitiveWorkout {
        workout(
            name: "Rest timer",
            timing: PrimitiveTiming(mode: .timeBounded, intervalSec: 60, rounds: 4),
            slots: [slot(targets: [], postRestSec: 30)]
        )
    }

    private static func straightStrengthWorkout() -> PrimitiveWorkout {
        workout(
            name: "Straight strength",
            timing: PrimitiveTiming(mode: .setBounded),
            repeatCount: 3,
            slots: [
                slot(
                    targets: [target(.reps, value: 5)],
                    load: PrimitiveLoad(value: 100, unit: .kg, unitType: .absolute),
                    stimuli: [PrimitiveStimulus(type: .rir, target: 2)]
                ),
            ]
        )
    }

    private static func timeBoundedStrengthWithRestWorkout() -> PrimitiveWorkout {
        workout(
            name: "Time-bounded strength",
            timing: PrimitiveTiming(mode: .timeBounded, intervalSec: 60, rounds: 4),
            slots: [
                slot(
                    targets: [target(.reps, value: 10)],
                    load: PrimitiveLoad(value: 24, unit: .kg, unitType: .absolute),
                    postRestSec: 30
                ),
            ]
        )
    }

    private static func roundRobinStrengthWorkout() -> PrimitiveWorkout {
        workout(
            name: "Round-robin strength",
            timing: PrimitiveTiming(mode: .setBounded),
            traversal: .roundRobin,
            slots: [
                slot(targets: [target(.reps, value: 8)]),
                slot(targets: [target(.reps, value: 12)]),
            ]
        )
    }

    private static func cappedForTimeWorkout() -> PrimitiveWorkout {
        workout(
            name: "Capped for time",
            timing: PrimitiveTiming(mode: .capBounded, capSec: 600),
            setTargets: [target(.duration, role: .observation)],
            slots: [slot(targets: [target(.reps, value: 50)])]
        )
    }

    private static func loadedCarryWorkout() -> PrimitiveWorkout {
        workout(
            name: "Loaded carry",
            timing: PrimitiveTiming(mode: .targetBounded),
            slots: [
                slot(
                    targets: [
                        target(.distance, value: 400),
                        target(.loadCarried, value: 32, role: .observation),
                    ]
                ),
            ]
        )
    }

    private static func genericWeightedDistanceWorkout() -> PrimitiveWorkout {
        workout(
            name: "Generic weighted distance",
            timing: PrimitiveTiming(mode: .targetBounded),
            slots: [
                slot(
                    targets: [target(.distance, value: 400)],
                    load: PrimitiveLoad(value: 32, unit: .kg, unitType: .absolute)
                ),
            ]
        )
    }

    private static func mobilityRecoveryWorkout() -> PrimitiveWorkout {
        workout(
            name: "Mobility recovery",
            timing: PrimitiveTiming(mode: .timeBounded, intervalSec: 120, rounds: 3),
            slots: [slot(targets: [target(.duration, value: 120)])]
        )
    }

    private static func amrapWorkout() -> PrimitiveWorkout {
        workout(
            name: "AMRAP score",
            timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
            traversal: .amrap,
            setTargets: [target(.rounds, role: .observation)],
            slots: [slot(targets: [target(.reps, value: 10)])]
        )
    }

    private static func workout(
        name: String = "Primitive workout",
        timing: PrimitiveTiming,
        traversal: PrimitiveTraversal = .sequential,
        repeatCount: Int = 1,
        setTargets: [PrimitiveWorkTarget] = [],
        slots: [PrimitiveSlot]
    ) -> PrimitiveWorkout {
        PrimitiveWorkout(
            id: UUID(),
            name: name,
            blocks: [
                PrimitiveBlock(
                    id: UUID(),
                    sets: [
                        PrimitiveSet(
                            id: UUID(),
                            timing: timing,
                            traversal: traversal,
                            repeatCount: repeatCount,
                            workTargets: setTargets,
                            slots: slots
                        ),
                    ]
                ),
            ]
        )
    }

    private static func slot(
        targets: [PrimitiveWorkTarget],
        load: PrimitiveLoad? = nil,
        stimuli: [PrimitiveStimulus] = [],
        postRestSec: Int = 0,
        isWarmup: Bool = false
    ) -> PrimitiveSlot {
        PrimitiveSlot(
            id: UUID(),
            exerciseID: UUID(),
            workTargets: targets,
            load: load,
            stimuli: stimuli,
            postRestSec: postRestSec,
            isWarmup: isWarmup
        )
    }

    private static func target(
        _ metric: PrimitiveMetric,
        value: Double? = nil,
        role: PrimitiveWorkRole = .completion
    ) -> PrimitiveWorkTarget {
        PrimitiveWorkTarget(
            metric: metric,
            valueForm: value == nil ? .open : .single,
            value: value,
            role: role
        )
    }

    private static func assertPlan(
        _ plan: WorkoutKitExportPlan,
        support: WorkoutKitSupportState,
        deliveryPaths: Set<WorkoutKitDeliveryPath>,
        selectionPolicy: WorkoutKitSelectionPolicy,
        payload: WorkoutKitPayloadBlueprint,
        identity: Set<WorkoutKitPushIdentityRequirement>,
        proofRequirements: Set<WorkoutKitProofRequirement>,
        unresolvedRequirements: Set<WorkoutKitBlockReason> = [],
        degradation: WorkoutKitDegradation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(plan.supportState, support, file: file, line: line)
        XCTAssertEqual(plan.deliveryPaths, deliveryPaths, file: file, line: line)
        XCTAssertEqual(plan.selectionPolicy, selectionPolicy, file: file, line: line)
        XCTAssertEqual(plan.payload, payload, file: file, line: line)
        XCTAssertEqual(plan.pushIdentity.requirements, identity, file: file, line: line)
        XCTAssertEqual(plan.proofRequirements, proofRequirements, file: file, line: line)
        XCTAssertEqual(plan.degradation, degradation, file: file, line: line)
        XCTAssertEqual(plan.unresolvedRequirements, unresolvedRequirements, file: file, line: line)
    }
}
