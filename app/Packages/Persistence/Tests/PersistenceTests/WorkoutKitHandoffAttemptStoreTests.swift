import XCTest
@testable import Persistence

final class WorkoutKitHandoffAttemptStoreTests: XCTestCase {
    func testLatestAttemptAndReceiptsPersistPrimitiveValues() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WorkoutKitHandoffAttemptStoreTests.\(UUID().uuidString)"))
        let store = UserDefaultsWorkoutKitHandoffAttemptStore(defaults: defaults)
        let workoutID = UUID()
        let snapshot = WorkoutKitHandoffAttemptSnapshot(
            workoutID: workoutID,
            occurrenceKey: "2026-05-22",
            path: "scheduleOnPhone",
            payloadFingerprint: "abc123",
            lastAttemptAt: Date(timeIntervalSince1970: 1_800_000_000),
            outcome: "scheduled",
            workoutPlanID: workoutID
        )
        let receipt = WorkoutKitHandoffReceipt(
            workoutID: workoutID,
            rowID: "paceTargetRun",
            path: "scheduleOnPhone",
            occurrenceKey: snapshot.occurrenceKey,
            payloadFingerprint: snapshot.payloadFingerprint,
            workoutPlanID: workoutID,
            outcome: "scheduled"
        )

        await store.save(snapshot: snapshot, receipt: receipt)

        let latest = await store.latest(
            workoutID: workoutID,
            occurrenceKey: snapshot.occurrenceKey,
            path: snapshot.path
        )
        XCTAssertEqual(latest, snapshot)
        let latestScheduled = await store.latestSuccessfulSchedule(
            workoutID: workoutID,
            occurrenceKey: snapshot.occurrenceKey,
            path: snapshot.path
        )
        XCTAssertEqual(latestScheduled?.payloadFingerprint, "abc123")
        let receipts = await store.receipts()
        XCTAssertEqual(receipts, [receipt])

        await store.clear()
        let clearedLatest = await store.latest(
            workoutID: workoutID,
            occurrenceKey: snapshot.occurrenceKey,
            path: snapshot.path
        )
        XCTAssertNil(clearedLatest)
        let clearedReceipts = await store.receipts()
        XCTAssertEqual(clearedReceipts, [])
    }

    func testLatestSuccessfulScheduleSurvivesLaterBlockedReceipt() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WorkoutKitHandoffAttemptStoreTests.\(UUID().uuidString)"))
        let store = UserDefaultsWorkoutKitHandoffAttemptStore(defaults: defaults)
        let workoutID = UUID()
        let occurrenceKey = "2026-05-22"
        let path = "scheduleOnPhone"
        let workoutPlanID = UUID()
        let scheduledSnapshot = WorkoutKitHandoffAttemptSnapshot(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path,
            payloadFingerprint: "scheduled-fingerprint",
            lastAttemptAt: Date(timeIntervalSince1970: 1_800_000_000),
            outcome: "scheduled",
            workoutPlanID: workoutPlanID
        )
        let scheduledReceipt = WorkoutKitHandoffReceipt(
            createdAt: scheduledSnapshot.lastAttemptAt,
            workoutID: workoutID,
            rowID: "paceTargetRun",
            path: path,
            occurrenceKey: occurrenceKey,
            payloadFingerprint: scheduledSnapshot.payloadFingerprint,
            workoutPlanID: workoutPlanID,
            outcome: "scheduled"
        )
        let blockedSnapshot = WorkoutKitHandoffAttemptSnapshot(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path,
            payloadFingerprint: "blocked-fingerprint",
            lastAttemptAt: Date(timeIntervalSince1970: 1_800_000_060),
            outcome: "blocked",
            failureClass: "same_payload_already_scheduled"
        )
        let blockedReceipt = WorkoutKitHandoffReceipt(
            createdAt: blockedSnapshot.lastAttemptAt,
            workoutID: workoutID,
            rowID: "paceTargetRun",
            path: path,
            occurrenceKey: occurrenceKey,
            payloadFingerprint: blockedSnapshot.payloadFingerprint,
            workoutPlanID: nil,
            outcome: "blocked",
            failureClass: blockedSnapshot.failureClass
        )

        await store.save(snapshot: scheduledSnapshot, receipt: scheduledReceipt)
        await store.save(snapshot: blockedSnapshot, receipt: blockedReceipt)

        let latest = await store.latest(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path
        )
        XCTAssertEqual(latest, blockedSnapshot)
        let latestScheduled = await store.latestSuccessfulSchedule(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path
        )
        XCTAssertEqual(latestScheduled?.payloadFingerprint, "scheduled-fingerprint")
        XCTAssertEqual(latestScheduled?.outcome, "scheduled")
        XCTAssertEqual(latestScheduled?.workoutPlanID, workoutPlanID)
    }

    func testLatestSuccessfulScheduleIsClearedByLaterMissingVerification() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WorkoutKitHandoffAttemptStoreTests.\(UUID().uuidString)"))
        let store = UserDefaultsWorkoutKitHandoffAttemptStore(defaults: defaults)
        let workoutID = UUID()
        let occurrenceKey = "2026-05-22"
        let path = "scheduleOnPhone"
        let workoutPlanID = UUID()
        let scheduledSnapshot = WorkoutKitHandoffAttemptSnapshot(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path,
            payloadFingerprint: "scheduled-fingerprint",
            lastAttemptAt: Date(timeIntervalSince1970: 1_800_000_000),
            outcome: "scheduled",
            workoutPlanID: workoutPlanID
        )
        let scheduledReceipt = WorkoutKitHandoffReceipt(
            createdAt: scheduledSnapshot.lastAttemptAt,
            workoutID: workoutID,
            rowID: "paceTargetRun",
            path: path,
            occurrenceKey: occurrenceKey,
            payloadFingerprint: scheduledSnapshot.payloadFingerprint,
            workoutPlanID: workoutPlanID,
            outcome: "scheduled"
        )
        let missingSnapshot = WorkoutKitHandoffAttemptSnapshot(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path,
            payloadFingerprint: "scheduled-fingerprint",
            lastAttemptAt: Date(timeIntervalSince1970: 1_800_000_060),
            outcome: "missing",
            workoutPlanID: workoutPlanID,
            failureClass: "scheduled_workout_missing"
        )
        let missingReceipt = WorkoutKitHandoffReceipt(
            createdAt: missingSnapshot.lastAttemptAt,
            workoutID: workoutID,
            rowID: "paceTargetRun",
            path: path,
            occurrenceKey: occurrenceKey,
            payloadFingerprint: missingSnapshot.payloadFingerprint,
            workoutPlanID: workoutPlanID,
            outcome: "missing",
            failureClass: missingSnapshot.failureClass
        )

        await store.save(snapshot: scheduledSnapshot, receipt: scheduledReceipt)
        await store.save(snapshot: missingSnapshot, receipt: missingReceipt)

        let latest = await store.latest(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path
        )
        XCTAssertEqual(latest, missingSnapshot)
        let latestScheduled = await store.latestSuccessfulSchedule(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path
        )
        XCTAssertNil(latestScheduled)
    }
}
