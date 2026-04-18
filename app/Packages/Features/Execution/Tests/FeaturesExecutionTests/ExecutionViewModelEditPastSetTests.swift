// ExecutionViewModelEditPastSetTests.swift
//
// Covers the past-set-edit → push path. Closes bug-010 (edit was
// local-only) and bug-017 (no telemetry on edit). The invariants under
// test:
//
//   - `editPastSet` enqueues a `SetLog` through `push.onSetLogged`.
//   - The pushed UUID is DETERMINISTIC from `(itemID, setIndex)` — the
//     original log and every subsequent edit push share the same id so
//     the server upserts in place rather than inserting a second row.
//   - The pushed payload carries the POST-edit `reps` / `weight` / `rir`
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
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        let originalUUID = await recorder.setLogs.first?.id
        XCTAssertNotNil(originalUUID)

        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: 95, reps: nil, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 2, "edit must enqueue a second push")
        let second = try XCTUnwrap(logs.last)
        XCTAssertEqual(second.id, originalUUID,
                       "edit UUID must match original so server upserts in place")
        XCTAssertEqual(second.setIndex, 1)
        XCTAssertEqual(second.workoutItemID, itemID)
    }

    func testEditPastSetEnqueuesWithUpdatedValues() async throws {
        // Log reps=5, rir=2 → edit reps=4, rir=1. The second push must
        // carry the POST-edit values — otherwise the server would
        // upsert the pre-edit numbers back on top of the corrected ones.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_100))
        let (ctx, itemID) = Fixtures.context()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 4, rir: 1)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 2)
        let edited = try XCTUnwrap(logs.last)
        XCTAssertEqual(edited.reps, 4)
        XCTAssertEqual(edited.rir, 1)
        // loadKg not touched by the edit → stays at the prescribed value.
        XCTAssertEqual(edited.weight, 100)
        XCTAssertEqual(edited.weightUnit, .kg)
        XCTAssertEqual(edited.id, logs.first?.id)
    }

    func testEditPastSetEmitsTelemetry() async throws {
        // Bug-017: editPastSet previously bypassed telemetry — the
        // corrective-edit trail was missing from the event log. Assert
        // `execution.past_set_edited` fires exactly once, tagged with
        // workoutID + setLogID and a payload carrying itemID + setIndex.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_001_200))
        let (ctx, itemID) = Fixtures.context()
        let telemetry = TelemetryRecorder()
        let vm = ExecutionViewModel(context: ctx, clock: fixed, telemetry: telemetry)
        vm.start()
        vm.logSet(reps: 5, rir: 2)
        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: 97.5, reps: nil, rir: nil)

        let events = telemetry.events.filter { $0.name == "execution.past_set_edited" }
        XCTAssertEqual(events.count, 1, "edit must emit exactly one past_set_edited event")
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.workoutID, ctx.workout.id)
        XCTAssertEqual(
            event.setLogID,
            ExecutionViewModel.setLogID(itemID: itemID, setIndex: 1)
        )
        let payload = event.dataJSON ?? ""
        XCTAssertTrue(payload.contains("\"setIndex\":1"),
                      "payload must carry setIndex — got \(payload)")
        XCTAssertTrue(payload.contains(itemID.uuidString),
                      "payload must carry itemID — got \(payload)")
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
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)
        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 4, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        vm.editPastSet(itemID: itemID, setIndex: 1, loadKg: nil, reps: 3, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
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
    static func context() -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
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
