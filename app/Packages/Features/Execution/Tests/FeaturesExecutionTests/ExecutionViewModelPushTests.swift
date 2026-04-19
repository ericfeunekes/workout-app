// ExecutionViewModelPushTests.swift
//
// Covers the push-enqueue hooks on ExecutionViewModel introduced when
// the push queue wiring landed (see `docs/sync.md` § "Push protocol").
//   - logSet invokes the SetLogEnqueuer exactly once with the correct
//     SetLog shape (UUID, workoutItemID, setIndex, reps, weight, rir,
//     isWarmup=false, completedAt=now).
//   - complete invokes the StatusEnqueuer exactly once with
//     .completed + completedAt, and the kick runs once.
//   - no-op when enqueuers are nil — the existing offline-first tests
//     still pass because the fire-and-forget Task has nothing to do.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelPushTests: XCTestCase {

    func testLogSetStampsUnitKgWhenPrescribedKg() async throws {
        // R2.10: an explicit `weight_unit: "kg"` on the prescription
        // carries through to the pushed SetLog.weightUnit. This locks the
        // cutover — before R2.10 the push path hardcoded .kg, so this
        // regression-proofs that unit now follows SetPlan.unit.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_500))
        let (ctx, _) = PushTestFixtures.context(
            sets: 3, reps: 5, loadKg: 100,
            prescriptionJSONOverride: #"{"sets":3,"reps":5,"load_kg":100,"weight_unit":"kg"}"#
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.logSet(reps: 5, rir: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.weight, 100)
        XCTAssertEqual(log.weightUnit, .kg)
    }

    func testLogSetInvokesSetLogEnqueuerExactlyOnce() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let (ctx, itemID) = PushTestFixtures.context(sets: 4, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in
                await recorder.appendSet(log)
            }
        )
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            push: hooks
        )
        vm.start()
        vm.logSet(reps: 5, rir: 2)

        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.workoutItemID, itemID)
        XCTAssertEqual(log.setIndex, 1)
        XCTAssertEqual(log.reps, 5)
        XCTAssertEqual(log.rir, 2)
        XCTAssertEqual(log.weight, 100)
        // R2.10: JSON fixture omits `weight_unit` → defaults to .lb.
        XCTAssertEqual(log.weightUnit, .lb)
        XCTAssertFalse(log.isWarmup)
        XCTAssertEqual(log.completedAt, fixed.now)
        XCTAssertNil(log.performedExerciseID)
    }

    func testCompleteAloneDoesNotEnqueueStatus() async throws {
        // `complete()` is the "force-complete" affordance. It transitions
        // route but does NOT enqueue the status_update — that's the
        // terminal action's responsibility (`saveAndDone`). Previously
        // complete() enqueued and so did saveAndDone() when reached via
        // the explicit End → save & done path — producing a double push.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let kickRecorder = KickRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in
                await recorder.appendSet(log)
            },
            onStatusChanged: { [recorder] id, status, completedAt, notes in
                await recorder.appendStatus(
                    workoutID: id, status: status, at: completedAt, notes: notes
                )
            },
            onPushKick: { [kickRecorder] in
                await kickRecorder.bump()
            }
        )

        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            push: hooks
        )
        vm.start()
        vm.complete()

        try await Task.sleep(nanoseconds: 50_000_000)

        let statuses = await recorder.statusUpdates
        XCTAssertEqual(statuses.count, 0, "complete() must not enqueue status_update")
        XCTAssertEqual(vm.state.route, .complete)
        let kicks = await kickRecorder.count
        XCTAssertEqual(kicks, 0, "complete() must not kick the push flusher")
    }

    func testSaveAndDoneNotesRideOnStatusPush() async throws {
        // The terminal status_update carries the user's post-workout
        // note so the server is authoritative for the value — without
        // this the next `sync/pull` overwrote the local cache's
        // freshly-typed note with the server's stale value.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onStatusChanged: { [recorder] id, status, completedAt, notes in
                await recorder.appendStatus(
                    workoutID: id, status: status, at: completedAt, notes: notes
                )
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.complete()
        vm.saveAndDone(note: "  leg day PR!  ", bodyweightKg: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        let statuses = await recorder.statusUpdates
        XCTAssertEqual(statuses.count, 1)
        let status = try XCTUnwrap(statuses.first)
        XCTAssertEqual(
            status.notes, "leg day PR!",
            "whitespace-trimmed note must ride on the status push"
        )
    }

    func testSaveAndDoneEmptyNoteSendsNilOnStatusPush() async throws {
        // `normalizeNote` collapses whitespace-only strings to nil —
        // sending nil leaves the existing server-side notes untouched
        // instead of wiping them.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onStatusChanged: { [recorder] id, status, completedAt, notes in
                await recorder.appendStatus(
                    workoutID: id, status: status, at: completedAt, notes: notes
                )
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.complete()
        vm.saveAndDone(note: "   ", bodyweightKg: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        let statuses = await recorder.statusUpdates
        let status = try XCTUnwrap(statuses.first)
        XCTAssertNil(status.notes, "whitespace-only → nil on the wire")
    }

    func testSaveAndDoneEnqueuesStatusExactlyOnce() async throws {
        // `saveAndDone` is the sole terminal enqueue path. It must fire
        // for both routes into `.complete` — auto-advance from last set
        // AND explicit End — so the test here covers both paths.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let kickRecorder = KickRecorder()
        let hooks = ExecutionPushHooks(
            onStatusChanged: { [recorder] id, status, completedAt, notes in
                await recorder.appendStatus(
                    workoutID: id, status: status, at: completedAt, notes: notes
                )
            },
            onPushKick: { [kickRecorder] in
                await kickRecorder.bump()
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.complete()
        vm.saveAndDone()

        try await Task.sleep(nanoseconds: 50_000_000)

        let statuses = await recorder.statusUpdates
        XCTAssertEqual(statuses.count, 1, "explicit End → saveAndDone must enqueue exactly once")
        let status = try XCTUnwrap(statuses.first)
        XCTAssertEqual(status.workoutID, vm.state.workoutID)
        XCTAssertEqual(status.status, .completed)
        XCTAssertEqual(status.completedAt, fixed.now)
        let kicks = await kickRecorder.count
        XCTAssertEqual(kicks, 1, "one kick per terminal push, not two")
    }

    func testNilEnqueuersPreserveExistingBehavior() async throws {
        // Regression: the default path (no push hooks) must still
        // produce the same state transitions and not crash.
        let (ctx, _) = PushTestFixtures.context(sets: 2, reps: 5, loadKg: 100)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.logSet(reps: 5, rir: 2)
        XCTAssertEqual(vm.state.route, .rest)

        try await Task.sleep(nanoseconds: 20_000_000)
        // Nothing beyond "no crash" — the closures being nil means the
        // fire-and-forget Task never finds work to do.
    }

    /// Regression for the loadless-row push bug: a bodyweight
    /// prescription must push `SetLog.weight = nil` (not 0) so History
    /// renders "BW" instead of "0 lb". Before the fix the seeder wrote
    /// loadKg = 0 on BW rows and the 0 propagated into the pushed log.
    func testLogSetWritesNilWeightForBodyweight() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_777))
        let (ctx, _) = PushTestFixtures.context(
            sets: 3, reps: 8, loadKg: 0,
            prescriptionJSONOverride: #"{"sets":3,"reps":8}"#
        )
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.logSet(reps: 8, rir: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.weight, "BW row pushes nil weight, NOT 0")
        XCTAssertNil(log.weightUnit, "no weight unit when there's no weight")
    }
}

// MARK: - Test helpers

private enum PushTestFixtures {

    /// Builds a single-block, single-item straight-sets workout context.
    /// Matches the shape used by ExecutionViewModelTests' `makeContext`
    /// but is duplicated here so the push tests stay independent of that
    /// file's internal helpers.
    static func context(
        sets: Int,
        reps: Int,
        loadKg: Double,
        prescriptionJSONOverride: String? = nil
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Push Test",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let prescriptionJSON = prescriptionJSONOverride
            ?? #"{"sets":\#(sets),"reps":\#(reps),"load_kg":\#(loadKg)}"#
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
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

/// Records the set_logs, status updates, and user-parameter rows routed
/// through the view model's push enqueuers. Actor-isolated so parallel
/// closure invocations are serialized.
actor EnqueueRecorder {
    struct StatusObservation: Equatable {
        let workoutID: UUID
        let status: WorkoutStatus
        let completedAt: Date?
        let notes: String?
    }

    private(set) var setLogs: [SetLog] = []
    private(set) var statusUpdates: [StatusObservation] = []
    private(set) var userParameters: [UserParameter] = []

    func appendSet(_ log: SetLog) {
        setLogs.append(log)
    }

    func appendStatus(
        workoutID: UUID,
        status: WorkoutStatus,
        at: Date?,
        notes: String? = nil
    ) {
        statusUpdates.append(
            StatusObservation(
                workoutID: workoutID, status: status, completedAt: at, notes: notes
            )
        )
    }

    func appendUserParameter(_ param: UserParameter) {
        userParameters.append(param)
    }
}

actor KickRecorder {
    private(set) var count = 0
    func bump() { count += 1 }
}
