// ExecutionViewModelEditPastSetTests.swift
//
// Covers the past-set-edit → push path. Closes bug-010 (edit was
// local-only) and bug-017 (no telemetry on edit). The invariants under
// test:
//
//   - `editPastSet` enqueues a `PrimitiveSetLog` through the primitive push hook.
//   - The pushed UUID is DETERMINISTIC from `(itemID, setIndex)` — the
//     original log and every subsequent edit push share the same id so
//     the server upserts in place rather than inserting a second row.
//   - The primitive payload carries the POST-edit `reps` / `weight` / `rir`
//     (so the edit isn't silently reverted on the wire).
//   - `execution.past_set_edited` telemetry fires once per edit, tagged
//     with workoutID + setLogID and a payload carrying `itemID` +
//     `setIndex`.
//   - Repeated edits against the same set keep converging on the same
//     UUID — no fan-out, no drift.
//
// Test helpers (`EnqueueRecorder`) are defined in
// `ExecutionViewModelPushTests.swift` and shared across the target.

import XCTest
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelEditPastSetTests: XCTestCase {

    func testEditPastSetEnqueuesSameUUIDAsOriginalLog() async throws {
        // Log set 1 → capture the UUID. Edit set 1 → the second push
        // must carry the SAME UUID so the server upserts in place.
        // Fresh UUIDs (the bug-010 regression) would create a second
        // set_log row.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_000))
        let (ctx, itemID) = Fixtures.context()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        let originalUUID = await recorder.primitiveSetLogs.first?.id
        XCTAssertNotNil(originalUUID)

        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: 95, reps: nil, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 2, "edit must enqueue a second push")
        let second = try XCTUnwrap(logs.last)
        XCTAssertEqual(second.id, originalUUID,
                       "edit UUID must match original so server upserts in place")
        XCTAssertEqual(second.setIndex, 0)
        XCTAssertEqual(second.slotID, itemID)
    }

    func testEditPastSetEnqueuesWithUpdatedValues() async throws {
        // Log reps=5, rir=2 → edit reps=4, rir=1. The second push must
        // carry the POST-edit values — otherwise the server would
        // upsert the pre-edit numbers back on top of the corrected ones.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_100))
        let (ctx, itemID) = Fixtures.context()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 4, rir: 1)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 2)
        let edited = try XCTUnwrap(logs.last)
        XCTAssertEqual(edited.reps, 4)
        XCTAssertEqual(edited.rir, 1)
        // loadKg not touched by the edit → stays at the prescribed value.
        XCTAssertEqual(edited.weight, 100)
        // R2.10: pound-default — JSON fixture omits `weight_unit` so the
        // SetPlan seeds as .lb and the pushed SetLog stamps .lb.
        XCTAssertEqual(edited.weightUnit, .lb)
        XCTAssertEqual(edited.id, logs.first?.id)
    }

    func testEditPastSetEmitsTelemetry() async throws {
        // Bug-017: editPastSet previously bypassed telemetry — the
        // corrective-edit trail was missing from the event log. Assert
        // `execution.past_set_edited` fires exactly once, tagged with
        // workoutID + setLogID and a payload carrying itemID + setIndex.
        //
        // Wire-casing (R1.3): `itemID` / `setLogID` in the dataJSON
        // payload must be LOWERCASE — the "every id + *_id on the wire
        // is a lowercase UUID" invariant. The fixture seeds a
        // known-lowercase `itemID` so a regression that re-leaked
        // `.uuidString` (uppercase) fails this assertion by casing.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_200))
        // swiftlint:disable:next force_unwrapping
        let seededItemID = UUID(uuidString: "aaaaaaaa-1111-4222-8333-444444444444")!
        let (ctx, itemID) = Fixtures.context(itemID: seededItemID)
        let telemetry = TelemetryRecorder()
        let vm = ExecutionViewModel(context: ctx, clock: fixed, telemetry: telemetry)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: 97.5, reps: nil, rir: nil)

        let events = telemetry.events.filter { $0.name == "execution.past_set_edited" }
        XCTAssertEqual(events.count, 1, "edit must emit exactly one past_set_edited event")
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.workoutID, ctx.workout.id)
        let expectedSetLogID = ExecutionViewModel.setLogID(itemID: itemID, setIndex: 1)
        XCTAssertEqual(event.setLogID, expectedSetLogID)
        let payload = event.dataJSON ?? ""
        XCTAssertTrue(payload.contains("\"setIndex\":1"),
                      "payload must carry setIndex — got \(payload)")
        XCTAssertTrue(
            payload.contains("\"itemID\":\"aaaaaaaa-1111-4222-8333-444444444444\""),
            "payload must carry EXACT lowercase itemID — got \(payload)"
        )
        XCTAssertTrue(
            payload.contains("\"setLogID\":\"\(expectedSetLogID.uuidString.lowercased())\""),
            "payload must carry EXACT lowercase setLogID — got \(payload)"
        )
        // Any UUID-shaped substring in the payload must be all-lowercase.
        // Extract every UUID-shaped match, then assert it equals its own
        // `.lowercased()` so a partial-uppercase regression is caught
        // regardless of which UUID leaked.
        let uuidShape = try NSRegularExpression(
            pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        )
        let hits = uuidShape.matches(
            in: payload, range: NSRange(payload.startIndex..., in: payload)
        )
        for hit in hits {
            // swiftlint:disable:next force_unwrapping
            let range = Range(hit.range, in: payload)!
            let substr = String(payload[range])
            XCTAssertEqual(
                substr, substr.lowercased(),
                "payload leaked an uppercase UUID: \(substr) in \(payload)"
            )
        }
    }

    func testEditedSetPreservesOriginalCompletedAt() async throws {
        // Regression: `enqueueEditedSet` previously sent `clock.now` as
        // the pushed `completedAt`, and the server's `_upsert_set_log`
        // overwrites the timestamp on every push. A past-set edit would
        // retroactively move the set's wall-clock onto the edit moment,
        // diverging from History's edit path (which preserves the
        // cached stamp) and corrupting any rest-time / duration analysis.
        //
        // Seed: log set 1 at T0 via a clock fixed at T0. Swap the clock
        // forward to T0 + 60s. Edit reps. Assert the pushed DTO carries
        // `completed_at = T0` — the original log moment, not the edit
        // moment.
        let t0 = Date(timeIntervalSince1970: 1_700_002_000)
        let clock = EditTestMutableClock(now: t0)
        let (ctx, itemID) = Fixtures.context()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Move the clock 60s forward — any use of `clock.now` in the
        // edit push path would now stamp the later moment. Class-backed
        // so the VM's captured reference sees the update.
        clock.now = t0.addingTimeInterval(60)

        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 4, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 2, "edit must enqueue a second push")
        let original = try XCTUnwrap(logs.first)
        let edited = try XCTUnwrap(logs.last)
        XCTAssertEqual(original.completedAt, t0, "original push stamped at T0")
        XCTAssertEqual(edited.completedAt, t0,
                       "edit must preserve the original completedAt, not rewrite to edit time")
        XCTAssertEqual(edited.reps, 4, "edit payload still carries updated reps")
    }

    func testMultipleEditsOfSameSetAllUseSameUUID() async throws {
        // Edit twice → 3 total pushes (original log + 2 edits), all
        // sharing one deterministic UUID. This is the repeated-
        // correction path: user logs 5 reps, corrects to 4, then
        // realizes it was actually 3. Every push lands on the same
        // server row.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_300))
        let (ctx, itemID) = Fixtures.context()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onPrimitiveSetLogged: { [recorder] log in await recorder.appendPrimitiveSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)
        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 4, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 3, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.primitiveSetLogs
        XCTAssertEqual(logs.count, 3, "1 original log + 2 edits = 3 pushes")
        let ids = Set(logs.map(\.id))
        XCTAssertEqual(ids.count, 1, "all three pushes share one UUID")
        XCTAssertEqual(logs.last?.reps, 3)
    }
}

// MARK: - Fixtures

/// Single-block, single-item straight-sets context sized for edit tests.
/// Kept local to this file so test changes don't ripple through the
/// already-oversized `ExecutionViewModelTests.swift`.
private enum Fixtures {
    /// `itemID` defaults to a fresh `UUID()` — callers that need to
    /// assert exact lowercase substrings in telemetry payloads pass a
    /// known-lowercase id so the assertion can match verbatim. Swift's
    /// `UUID().uuidString` is uppercase, which would let a payload with
    /// either casing pass a naive `contains(uuidString)` check.
    static func context(itemID: UUID = UUID()) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "EditTest",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON:
                #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
        return (ctx, itemID)
    }
}

/// Synchronous telemetry recorder for VM-level tests. `TelemetryEmitter`
/// is `Sendable` and `emit` is non-throwing; production implementations
/// offload to an actor, but for tests we read the buffer back on the
/// main actor where the VM runs. `NSLock` guards the array so a future
/// caller that emits from a background Task still sees consistent state.
final class TelemetryRecorder: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func emit(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(event)
    }
}

/// Class-backed `Clock` for the edit-preserves-completedAt regression —
/// the VM captures the Clock reference, so a test that advances "now"
/// between `logSet` and `editPastSet` needs class semantics (value-type
/// `FixedClock` would copy). Scoped to this file so the name doesn't
/// collide with the private `MutableClock` in `ExecutionViewModelTests`.
private final class EditTestMutableClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
