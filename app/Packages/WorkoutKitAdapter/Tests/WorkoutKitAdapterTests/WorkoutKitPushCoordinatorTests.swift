import Foundation
import XCTest
@testable import WorkoutKitAdapter
import WorkoutKitExportProfile

final class WorkoutKitPushCoordinatorTests: XCTestCase {
    func testBlockedPlanDoesNotCallScheduler() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(
                supportState: .unsupported,
                rowID: .unsupported,
                payload: .none,
                unresolvedRequirements: [.targetCapabilityUnavailable]
            ),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        guard case .blocked = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testScheduleWithoutOccurrenceFailsBeforeCallingScheduler() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .scheduleOnPhone,
            occurrence: nil,
            proofs: completeScheduleProofs()
        ))

        XCTAssertEqual(outcome, .failed(.missingOccurrenceDate))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testScheduleMissingRealDeviceProofIsBlocked() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: WorkoutKitDeliveryProofs(proven: [.sdkCompile, .simulatorConstruction])
        ))

        guard case .blocked(let assessment) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertTrue(assessment.blockingReasons.contains(.scheduleVisibilityProofRequired))
        XCTAssertTrue(assessment.blockingReasons.contains(.duplicateUpdateProofRequired))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testDegradedScheduleWithoutAcknowledgementIsBlocked() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: degradedPlan(),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: WorkoutKitDeliveryProofs(proven: [
                .sdkCompile,
                .simulatorConstruction,
                .realDeviceScheduleVisibility,
                .duplicateUpdateBehavior,
            ])
        ))

        guard case .blocked(let assessment) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertTrue(assessment.blockingReasons.contains(.degradationAcknowledgementRequired))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testSupportedScheduleWithAllProofsCallsSchedulerOnce() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let date = occurrence()
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .scheduleOnPhone,
            occurrence: date,
            proofs: completeScheduleProofs()
        ))

        guard case .scheduled(let record) = outcome else {
            return XCTFail("expected scheduled, got \(outcome)")
        }
        XCTAssertEqual(record.workoutPlanID, stableWorkoutID)
        XCTAssertEqual(record.occurrence.year, date.year)
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 1)
    }

    func testSchedulePathNotDeclaredByPlanDoesNotCallScheduler() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(deliveryPaths: [.previewOnly]),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        guard case .blocked(let assessment) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertTrue(assessment.blockingReasons.contains(.deliveryPathUnavailable))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testValueBackedPayloadDoesNotCallSchedulerUntilExactTargetMappingExists() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .cardio,
                goal: .time
            ), descriptor: .incomplete([.exactTargetValuesUnavailable])),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        guard case .blocked(let assessment) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertTrue(assessment.blockingReasons.contains(.exactTargetValuesUnavailable))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testOpenCustomIntervalsDoNotCallSchedulerUntilDescriptorIsConcrete() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .mixed,
                goal: .open,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: false)]
            ), descriptor: .incomplete([.exactTargetValuesUnavailable])),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        guard case .blocked(let assessment) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertTrue(assessment.blockingReasons.contains(.exactTargetValuesUnavailable))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testProductionDescriptorRejectsIncompleteCustomIntervals() throws {
        let incomplete = plan(payload: WorkoutKitPayloadBlueprint(
            shape: .customIntervals,
            activitySelection: .mixed,
            goal: .open,
            steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: false)]
        ), descriptor: .incomplete([.exactTargetValuesUnavailable]))

        XCTAssertThrowsError(try WorkoutKitPlanFactory.descriptor(for: incomplete)) { error in
            XCTAssertEqual(error as? WorkoutKitAdapterError, .incompleteWorkoutKitDescriptor)
        }
    }

    func testProductionDescriptorUsesResolvedConcreteValues() throws {
        let time = plan(
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .running,
                goal: .time
            ),
            descriptor: .resolved(WorkoutKitResolvedDescriptorBlueprint(
                activitySelection: .running,
                goal: .timeSeconds(1_234)
            ))
        )
        let timeDescriptor = try WorkoutKitPlanFactory.descriptor(for: time)
        XCTAssertEqual(timeDescriptor.activity, .running)
        XCTAssertEqual(timeDescriptor.goal, .timeSeconds(1_234))

        let intervals = plan(
            payload: WorkoutKitPayloadBlueprint(
                shape: .customIntervals,
                activitySelection: .hiit,
                goal: .intervalSteps,
                steps: [WorkoutKitStepBlueprint(preservesOrder: true, preservesWorkRestCadence: true)]
            ),
            descriptor: .resolved(WorkoutKitResolvedDescriptorBlueprint(
                activitySelection: .hiit,
                goal: .open,
                steps: [
                    WorkoutKitDescriptorStep(purpose: .work, goal: .timeSeconds(45)),
                    WorkoutKitDescriptorStep(purpose: .recovery, goal: .timeSeconds(15)),
                ],
                intervalIterations: 3
            ))
        )
        let intervalDescriptor = try WorkoutKitPlanFactory.descriptor(for: intervals)
        XCTAssertEqual(intervalDescriptor.activity, .hiit)
        XCTAssertEqual(intervalDescriptor.goal, .open)
        XCTAssertEqual(intervalDescriptor.intervalSteps.map(\.goal), [.timeSeconds(45), .timeSeconds(15)])
        XCTAssertEqual(intervalDescriptor.intervalIterations, 3)

        let pacer = plan(
            rowID: .paceTargetRun,
            candidateFamily: .pacer,
            payload: WorkoutKitPayloadBlueprint(
                shape: .pacer,
                activitySelection: .running,
                goal: .pacer
            ),
            descriptor: .resolved(WorkoutKitResolvedDescriptorBlueprint(
                activitySelection: .running,
                goal: .pacer(distanceMeters: 5_000, timeSeconds: 1_500)
            ))
        )
        let pacerDescriptor = try WorkoutKitPlanFactory.descriptor(for: pacer)
        XCTAssertEqual(pacerDescriptor.family, .pacer)
        XCTAssertEqual(pacerDescriptor.activity, .running)
        XCTAssertEqual(pacerDescriptor.goal, .pacer(distanceMeters: 5_000, timeSeconds: 1_500))
    }

    func testSetmarkOnlyNeverCallsScheduler() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(
                supportState: .setmarkOnly,
                rowID: .setmarkOnlyRest,
                payload: .none,
                unresolvedRequirements: [.setmarkOnly]
            ),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        guard case .blocked = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testPayloadFingerprintIsStableForIdenticalRequests() throws {
        let exportPlan = plan()
        let descriptor = try WorkoutKitPlanFactory.descriptor(for: exportPlan)
        let date = occurrence()
        let first = try WorkoutKitPayloadFingerprint.make(
            plan: exportPlan,
            descriptor: descriptor,
            occurrence: date
        )
        let second = try WorkoutKitPayloadFingerprint.make(
            plan: exportPlan,
            descriptor: descriptor,
            occurrence: date
        )
        XCTAssertEqual(first, second)
    }

    func testPayloadFingerprintChangesWhenOccurrenceChanges() throws {
        let exportPlan = plan()
        let descriptor = try WorkoutKitPlanFactory.descriptor(for: exportPlan)
        let first = try WorkoutKitPayloadFingerprint.make(
            plan: exportPlan,
            descriptor: descriptor,
            occurrence: occurrence(day: 18)
        )
        let second = try WorkoutKitPayloadFingerprint.make(
            plan: exportPlan,
            descriptor: descriptor,
            occurrence: occurrence(day: 19)
        )
        XCTAssertNotEqual(first, second)
    }

    func testIOSOpenPathDoesNotClaimWatchOpenSupport() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .openOnWatch,
            occurrence: nil,
            proofs: WorkoutKitDeliveryProofs(proven: [
                .sdkCompile,
                .simulatorConstruction,
                .realDeviceStartability,
            ])
        ))

        guard case .unsupportedPlatform = outcome else {
            return XCTFail("expected unsupportedPlatform on iOS, got \(outcome)")
        }
        let openedCount = await client.openedDescriptorCount()
        XCTAssertEqual(openedCount, 0)
    }

    func testWatchOpenPathCallsOpenClientWhenAllLocalGatesAreSatisfied() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeWatchCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .openOnWatch,
            occurrence: nil,
            proofs: WorkoutKitDeliveryProofs(proven: [
                .sdkCompile,
                .simulatorConstruction,
                .realDeviceStartability,
            ])
        ))

        guard case .opened(let record) = outcome else {
            return XCTFail("expected opened, got \(outcome)")
        }
        XCTAssertEqual(record.workoutPlanID, stableWorkoutID)
        let openedCount = await client.openedDescriptorCount()
        XCTAssertEqual(openedCount, 1)
    }

    func testSchedulePathIsUnsupportedOffIOSBeforeCallingClient() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeWatchCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        guard case .unsupportedPlatform = outcome else {
            return XCTFail("expected unsupportedPlatform on watchOS, got \(outcome)")
        }
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testPreviewPathIsBlockedBeforeDescriptorConstruction() async {
        let client = FakeWorkoutKitSchedulingClient()
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(deliveryPaths: [.previewOnly]),
            path: .previewOnly,
            occurrence: nil,
            proofs: WorkoutKitDeliveryProofs(proven: [.sdkCompile, .simulatorConstruction])
        ))

        guard case .blocked(let assessment) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertEqual(assessment.blockingReasons, [.deliveryPathUnavailable])
        let scheduledCount = await client.scheduledRequestCount()
        let openedCount = await client.openedDescriptorCount()
        XCTAssertEqual(scheduledCount, 0)
        XCTAssertEqual(openedCount, 0)
    }

    func testCapacityFullFailsBeforeSchedule() async {
        let client = FakeWorkoutKitSchedulingClient(support: WorkoutKitScheduleSupport(
            isSupported: true,
            scheduledCount: 15,
            maxAllowedCount: 15
        ))
        let coordinator = makeIOSCoordinator(client: client)
        let outcome = await coordinator.push(WorkoutKitPushRequest(
            plan: plan(),
            path: .scheduleOnPhone,
            occurrence: occurrence(),
            proofs: completeScheduleProofs()
        ))

        XCTAssertEqual(outcome, .failed(.capacityExceeded(maxAllowed: 15)))
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 0)
    }

    func testDiagnosticRunnerCanCallFakeClientWithoutProductionProof() async {
        let client = FakeWorkoutKitSchedulingClient()
        let runner = WorkoutKitDiagnosticProbeRunner(client: client)
        let events = await runner.runScheduleProbe(
            descriptor: WorkoutKitDiagnosticProbeFixture.scheduleProbeDescriptor(),
            occurrence: occurrence()
        )

        XCTAssertEqual(events.map(\.outcome), ["supported", "scheduled"])
        let scheduledCount = await client.scheduledRequestCount()
        XCTAssertEqual(scheduledCount, 1)
    }

    func testDiagnosticFixtureKeepsExportTypesBehindAdapterBoundary() throws {
        let descriptor = WorkoutKitDiagnosticProbeFixture.scheduleProbeDescriptor()
        XCTAssertEqual(descriptor.displayName, "Setmark WorkoutKit Probe")
        XCTAssertEqual(descriptor.goal, .timeSeconds(20 * 60))

        let fixedNow = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let date = WorkoutKitDiagnosticProbeFixture.scheduleProbeOccurrence(
            now: fixedNow,
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertNotNil(date.year)
        XCTAssertNotNil(date.minute)
    }
}

private let stableWorkoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000101")!

private func makeIOSCoordinator(
    client: any WorkoutKitSchedulingClient
) -> WorkoutKitPushCoordinator {
    WorkoutKitPushCoordinator(client: client, runtimePlatform: .iOS)
}

private func makeWatchCoordinator(
    client: any WorkoutKitSchedulingClient
) -> WorkoutKitPushCoordinator {
    WorkoutKitPushCoordinator(client: client, runtimePlatform: .watchOS)
}

private func occurrence(day: Int = 18) -> DateComponents {
    DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 5,
        day: day,
        hour: 9,
        minute: 30
    )
}

private func completeScheduleProofs() -> WorkoutKitDeliveryProofs {
    WorkoutKitDeliveryProofs(
        proven: [
            .sdkCompile,
            .simulatorConstruction,
            .realDeviceScheduleVisibility,
            .duplicateUpdateBehavior,
        ],
        degradationAcknowledged: true
    )
}

private func plan(
    supportState: WorkoutKitSupportState = .native,
    rowID: WorkoutKitMatrixRowID = .continuousCardio,
    candidateFamily: WorkoutKitCandidateFamily = .singleGoal,
    deliveryPaths: Set<WorkoutKitDeliveryPath> = [.scheduleOnPhone, .openOnWatch],
    payload: WorkoutKitPayloadBlueprint = WorkoutKitPayloadBlueprint(
        shape: .singleGoal,
        activitySelection: .running,
        goal: .open
    ),
    descriptor: WorkoutKitDescriptorBlueprint = .resolved(WorkoutKitResolvedDescriptorBlueprint(
        activitySelection: .running,
        goal: .open
    )),
    degradation: WorkoutKitDegradation? = nil,
    unresolvedRequirements: Set<WorkoutKitBlockReason> = []
) -> WorkoutKitExportPlan {
    WorkoutKitExportPlan(
        workoutID: stableWorkoutID,
        workoutName: "Bike",
        rowID: rowID,
        deliveryPaths: deliveryPaths,
        selectionPolicy: supportState == .unsupported ? .none : .exact(candidateFamily),
        supportState: supportState,
        payload: payload,
        pushIdentity: WorkoutKitPushIdentity(requirements: [
            .stableWorkoutPlanID,
            .payloadFingerprint,
            .occurrenceDateComponents,
        ]),
        degradation: degradation,
        proofRequirements: [.sdkCompile, .simulatorConstruction],
        unresolvedRequirements: unresolvedRequirements,
        sourceAmbiguities: [],
        descriptor: descriptor
    )
}

private func degradedPlan() -> WorkoutKitExportPlan {
    plan(
        supportState: .degraded,
        rowID: .straightStrength,
        payload: WorkoutKitPayloadBlueprint(
            shape: .singleGoal,
            activitySelection: .functionalStrength,
            goal: .open
        ),
        degradation: WorkoutKitDegradation(
            preservedFacts: [.activityType, .broadActivity],
            omittedFacts: [.load, .reps, .rir, .setmarkHierarchy],
            visibleResult: .workoutDurationVisibleInAppleWorkout
        )
    )
}

private extension WorkoutKitPayloadBlueprint {
    static let none = WorkoutKitPayloadBlueprint(
        shape: .noPayload,
        activitySelection: .unknown,
        goal: .none
    )
}
