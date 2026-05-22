import XCTest
import CoreDomain
import CoreTelemetry
import Persistence
import WorkoutKitAdapter
import WorkoutKitExportProfile
@testable import WorkoutKitHandoff

final class WorkoutKitHandoffCoordinatorTests: XCTestCase {
    func testPresentationHiddenUntilProofSourceIsAvailable() async throws {
        let store = InMemoryAttemptStore()
        let telemetry = CapturingTelemetryEmitter()
        let coordinator = WorkoutKitHandoffCoordinator(
            attemptStore: store,
            telemetry: telemetry,
            proofSource: .incomplete,
            now: { Self.now }
        )

        let presentation = await coordinator.presentation(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )

        XCTAssertNil(presentation)
        XCTAssertEqual(telemetry.events.map(\.name), [
            "workoutkit.presentation_evaluated",
            "workoutkit.action_blocked",
        ])
    }

    func testScheduleWritesReceiptAndSuccessTelemetryAfterSchedulerSuccess() async throws {
        let store = InMemoryAttemptStore()
        let telemetry = CapturingTelemetryEmitter()
        let coordinator = WorkoutKitHandoffCoordinator(
            attemptStore: store,
            telemetry: telemetry,
            proofSource: .proofCollection,
            now: { Self.now },
            push: { request in
                XCTAssertEqual(request.occurrence?.year, 2026)
                XCTAssertEqual(request.occurrence?.month, 5)
                XCTAssertEqual(request.occurrence?.day, 22)
                XCTAssertNil(request.occurrence?.hour)
                XCTAssertNil(request.occurrence?.minute)
                XCTAssertNil(request.occurrence?.second)
                let descriptor = try! request.plan.resolvedPlanDescriptor()
                let fingerprint = try! WorkoutKitPayloadFingerprint.make(
                    plan: request.plan,
                    descriptor: descriptor,
                    occurrence: request.occurrence
                )
                return .scheduled(WorkoutKitScheduledRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    occurrence: request.occurrence!,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation,
                    readback: [
                        WorkoutKitScheduledWorkoutSnapshot(
                            workoutPlanID: descriptor.id,
                            occurrence: request.occurrence!,
                            complete: false
                        ),
                    ]
                ))
            }
        )

        let result = await coordinator.schedule(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )

        XCTAssertEqual(result.presentation.state, .scheduled)
        XCTAssertEqual(result.presentation.actionTitle, "Check")
        XCTAssertTrue(result.presentation.isActionable)
        XCTAssertTrue(result.presentation.message.contains("May 22, 2026"))
        XCTAssertFalse(result.presentation.message.contains("12:00"))
        let receipts = await store.receipts()
        XCTAssertEqual(receipts[0].rowID, "paceTargetRun")
        XCTAssertEqual(receipts[0].outcome, "scheduled")
        XCTAssertTrue(telemetry.events.contains { $0.name == "workoutkit.schedule_succeeded" })
        XCTAssertFalse(telemetry.events.contains { $0.name == "workoutkit.schedule_failed" })

        let successEvent = try XCTUnwrap(telemetry.events.first {
            $0.name == "workoutkit.schedule_succeeded"
        })
        let payload = try Self.telemetryPayload(successEvent)
        XCTAssertEqual(payload["rowID"] as? String, "paceTargetRun")
        XCTAssertEqual(payload["path"] as? String, "scheduleOnPhone")
        XCTAssertEqual(payload["distanceMeters"] as? String, "5000")
        XCTAssertEqual(payload["targetTimeSeconds"] as? String, "1500")
        XCTAssertEqual(payload["derivedPaceSecondsPerKilometer"] as? String, "300")
        XCTAssertEqual(payload["scheduledReadbackCount"] as? String, "1")
        XCTAssertEqual(payload["matchingScheduledWorkoutFound"] as? String, "true")
        XCTAssertEqual(payload["matchingScheduledWorkoutComplete"] as? String, "false")
    }

    func testRepeatSamePayloadChecksExistingSchedule() async throws {
        let store = InMemoryAttemptStore()
        let telemetry = CapturingTelemetryEmitter()
        let coordinator = WorkoutKitHandoffCoordinator(
            attemptStore: store,
            telemetry: telemetry,
            proofSource: .proofCollection,
            now: { Self.now },
            push: { request in
                let descriptor = try! request.plan.resolvedPlanDescriptor()
                let fingerprint = try! WorkoutKitPayloadFingerprint.make(
                    plan: request.plan,
                    descriptor: descriptor,
                    occurrence: request.occurrence
                )
                return .scheduled(WorkoutKitScheduledRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    occurrence: request.occurrence!,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation
                ))
            },
            verifySchedule: { request in
                let descriptor = try! request.plan.resolvedPlanDescriptor()
                let fingerprint = try! WorkoutKitPayloadFingerprint.make(
                    plan: request.plan,
                    descriptor: descriptor,
                    occurrence: request.occurrence
                )
                return .found(WorkoutKitScheduledRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    occurrence: request.occurrence!,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation,
                    readback: [
                        WorkoutKitScheduledWorkoutSnapshot(
                            workoutPlanID: descriptor.id,
                            occurrence: request.occurrence!,
                            complete: false
                        ),
                    ]
                ))
            }
        )

        _ = await coordinator.schedule(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )
        let repeatResult = await coordinator.schedule(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )

        XCTAssertEqual(repeatResult.presentation.state, .scheduled)
        XCTAssertEqual(repeatResult.presentation.actionTitle, "Check")
        XCTAssertTrue(repeatResult.presentation.isActionable)
        let receipts = await store.receipts()
        XCTAssertEqual(receipts.count, 2)
        XCTAssertEqual(receipts[1].outcome, "verified")
        XCTAssertNil(receipts[1].failureClass)
        XCTAssertTrue(telemetry.events.contains { $0.name == "workoutkit.schedule_verified" })
    }

    func testMissingVerificationClearsPriorScheduledPresentation() async throws {
        let store = InMemoryAttemptStore()
        let pushCount = LockedCounter()
        let coordinator = WorkoutKitHandoffCoordinator(
            attemptStore: store,
            proofSource: .proofCollection,
            now: { Self.now },
            push: { request in
                pushCount.increment()
                let descriptor = try! request.plan.resolvedPlanDescriptor()
                let fingerprint = try! WorkoutKitPayloadFingerprint.make(
                    plan: request.plan,
                    descriptor: descriptor,
                    occurrence: request.occurrence
                )
                return .scheduled(WorkoutKitScheduledRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    occurrence: request.occurrence!,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation
                ))
            },
            verifySchedule: { request in
                let descriptor = try! request.plan.resolvedPlanDescriptor()
                let fingerprint = try! WorkoutKitPayloadFingerprint.make(
                    plan: request.plan,
                    descriptor: descriptor,
                    occurrence: request.occurrence
                )
                return .missing(WorkoutKitScheduledRecord(
                    workoutID: request.plan.workoutID,
                    workoutPlanID: descriptor.id,
                    occurrence: request.occurrence!,
                    payloadFingerprint: fingerprint,
                    rowID: request.plan.rowID,
                    supportState: request.plan.supportState,
                    degradation: request.plan.degradation
                ))
            }
        )

        _ = await coordinator.schedule(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )
        let missingResult = await coordinator.schedule(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )
        let presentation = await coordinator.presentation(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )
        let rescheduleResult = await coordinator.schedule(
            workout: Self.runningPacerWorkout,
            scheduledDate: Self.scheduledDate
        )

        XCTAssertEqual(missingResult.presentation.state, .failed)
        XCTAssertEqual(missingResult.presentation.actionTitle, "Check")
        XCTAssertEqual(presentation?.state, .ready)
        XCTAssertEqual(presentation?.actionTitle, "Watch")
        XCTAssertEqual(rescheduleResult.presentation.state, .scheduled)
        XCTAssertEqual(pushCount.value, 2)
        let receipts = await store.receipts()
        XCTAssertEqual(receipts.map(\.outcome), ["scheduled", "missing", "scheduled"])
        XCTAssertEqual(receipts[1].failureClass, "scheduled_workout_missing")
    }

    func testChangedPayloadAfterScheduledAttemptIsBlockedAsStale() async throws {
        let store = InMemoryAttemptStore()
        let telemetry = CapturingTelemetryEmitter()
        let coordinator = WorkoutKitHandoffCoordinator(
            attemptStore: store,
            telemetry: telemetry,
            proofSource: .proofCollection,
            now: { Self.now },
            push: { _ in
                XCTFail("changed payload must not call scheduler without update proof")
                return .failed(.liveWorkoutKitFailure("unexpected"))
            }
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let occurrenceKey = WorkoutKitHandoffCoordinator.occurrenceKey(
            for: calendar.dateComponents(
                [.year, .month, .day],
                from: Self.scheduledDate
            )
        )
        let workoutID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        await store.save(
            snapshot: WorkoutKitHandoffAttemptSnapshot(
                workoutID: workoutID,
                occurrenceKey: occurrenceKey,
                path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue,
                payloadFingerprint: "older-fingerprint",
                lastAttemptAt: Self.now,
                outcome: "scheduled",
                workoutPlanID: UUID(),
                failureClass: nil
            ),
            receipt: WorkoutKitHandoffReceipt(
                createdAt: Self.now,
                workoutID: workoutID,
                rowID: "paceTargetRun",
                path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue,
                occurrenceKey: occurrenceKey,
                payloadFingerprint: "older-fingerprint",
                workoutPlanID: UUID(),
                outcome: "scheduled",
                failureClass: nil
            )
        )

        let result = await coordinator.schedule(
            workout: Self.runningPacerWorkout(timeSeconds: 1_800),
            scheduledDate: Self.scheduledDate
        )

        XCTAssertEqual(result.presentation.state, WorkoutKitHandoffPresentationState.unavailable)
        let repeatEvent = try XCTUnwrap(telemetry.events.first {
            $0.name == "workoutkit.repeat_blocked"
        })
        let payload = try Self.telemetryPayload(repeatEvent)
        XCTAssertEqual(payload["blockerClass"] as? String, "changed_payload_already_scheduled")
    }

    private static let now = ISO8601DateFormatter().date(from: "2026-05-21T12:00:00Z")!
    private static let scheduledDate = ISO8601DateFormatter().date(from: "2026-05-22T12:00:00Z")!

    private static func telemetryPayload(_ event: Event) throws -> [String: Any] {
        let data = try XCTUnwrap(event.dataJSON?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static var runningPacerWorkout: PrimitiveWorkout {
        runningPacerWorkout(timeSeconds: 1_500)
    }

    private static func runningPacerWorkout(timeSeconds: Double) -> PrimitiveWorkout {
        PrimitiveWorkout(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Tomorrow Run",
            activityIntent: ActivityIntent(activityDomain: .running),
            blocks: [
                PrimitiveBlock(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    sets: [
                        PrimitiveSet(
                            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                            timing: PrimitiveTiming(mode: .targetBounded),
                            slots: [
                                PrimitiveSlot(
                                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                                    exerciseID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .distance,
                                            valueForm: .single,
                                            value: 5_000,
                                            role: .completion
                                        ),
                                        PrimitiveWorkTarget(
                                            metric: .duration,
                                            valueForm: .single,
                                            value: timeSeconds,
                                            role: .observation
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )
    }
}

private actor InMemoryAttemptStore: WorkoutKitHandoffAttemptStore {
    private var latestSnapshots: [String: WorkoutKitHandoffAttemptSnapshot] = [:]
    private var storedReceipts: [WorkoutKitHandoffReceipt] = []

    func latest(
        workoutID: UUID,
        occurrenceKey: String,
        path: String
    ) async -> WorkoutKitHandoffAttemptSnapshot? {
        latestSnapshots["\(workoutID.uuidString)|\(occurrenceKey)|\(path)"]
    }

    func latestSuccessfulSchedule(
        workoutID: UUID,
        occurrenceKey: String,
        path: String
    ) async -> WorkoutKitHandoffAttemptSnapshot? {
        let latestMatchingReceipt = storedReceipts.reversed().first {
            $0.workoutID == workoutID
                && $0.occurrenceKey == occurrenceKey
                && $0.path == path
        }
        if latestMatchingReceipt?.outcome == "missing" {
            return nil
        }
        return storedReceipts.reversed().first {
            $0.workoutID == workoutID
                && $0.occurrenceKey == occurrenceKey
                && $0.path == path
                && $0.outcome == "scheduled"
        }.map { receipt in
            WorkoutKitHandoffAttemptSnapshot(
                workoutID: receipt.workoutID,
                occurrenceKey: receipt.occurrenceKey,
                path: receipt.path,
                payloadFingerprint: receipt.payloadFingerprint,
                lastAttemptAt: receipt.createdAt,
                outcome: receipt.outcome,
                workoutPlanID: receipt.workoutPlanID,
                failureClass: receipt.failureClass
            )
        }
    }

    func save(
        snapshot: WorkoutKitHandoffAttemptSnapshot,
        receipt: WorkoutKitHandoffReceipt
    ) async {
        latestSnapshots["\(snapshot.workoutID.uuidString)|\(snapshot.occurrenceKey)|\(snapshot.path)"] = snapshot
        storedReceipts.append(receipt)
    }

    func receipts() async -> [WorkoutKitHandoffReceipt] {
        storedReceipts
    }

    func clear() async {
        latestSnapshots.removeAll()
        storedReceipts.removeAll()
    }
}

private final class CapturingTelemetryEmitter: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [Event] = []

    var events: [Event] {
        lock.withLock { storedEvents }
    }

    func emit(_ event: Event) {
        lock.withLock {
            storedEvents.append(event)
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
