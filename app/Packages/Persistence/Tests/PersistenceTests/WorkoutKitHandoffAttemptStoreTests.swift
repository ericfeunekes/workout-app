import XCTest
@testable import Persistence

final class WorkoutKitHandoffAttemptStoreTests: XCTestCase {
    func testLatestAttemptAndReceiptsPersistPrimitiveValues() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WorkoutKitHandoffAttemptStoreTests.\(UUID().uuidString)"))
        let store = UserDefaultsWorkoutKitHandoffAttemptStore(defaults: defaults)
        let workoutID = UUID()
        let snapshot = WorkoutKitHandoffAttemptSnapshot(
            workoutID: workoutID,
            occurrenceKey: "2026-05-22-12-00-00",
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
        let receipts = await store.receipts()
        XCTAssertEqual(receipts, [receipt])
    }
}
