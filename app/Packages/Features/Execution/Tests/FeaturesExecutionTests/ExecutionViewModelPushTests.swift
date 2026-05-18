// ExecutionViewModelPushTests.swift
//
// Covers the push-enqueue hooks on ExecutionViewModel introduced when
// the push queue wiring landed (see `docs/sync.md` § "Push protocol").
//   - logSet invokes the SetLogEnqueuer exactly once with the correct
//     SetLog shape (UUID, workoutItemID, setIndex, reps, weight, rir,
//     isWarmup=false, completedAt=now).
//   - saveAndDone invokes the CompletionEnqueuer exactly once with
//     the app-owned completion record, and the kick runs once.
//   - no-op when enqueuers are nil — the existing offline-first tests
//     still pass because the fire-and-forget Task has nothing to do.

import XCTest
import CoreDomain
import CoreSession
import CoreTelemetry
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
        vm.startCurrentSet()
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
        vm.startCurrentSet()
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

    func testSkipCurrentSetEnqueuesSkippedSetLogWithoutPerformanceMetrics() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_100))
        let (ctx, itemID) = PushTestFixtures.context(sets: 2, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.appendSet(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        XCTAssertTrue(vm.canSkipCurrentSet)

        vm.skipCurrentSet()
        try await Task.sleep(nanoseconds: 50_000_000)

        let set = try XCTUnwrap(vm.state.items.first?.sets.first)
        XCTAssertTrue(set.done)
        XCTAssertTrue(set.skipped)
        XCTAssertEqual(vm.state.route, .rest)
        let logs = await recorder.setLogs
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.workoutItemID, itemID)
        XCTAssertEqual(log.setIndex, 1)
        XCTAssertTrue(log.skipped)
        XCTAssertNil(log.reps)
        XCTAssertNil(log.weight)
        XCTAssertNil(log.weightUnit)
        XCTAssertNil(log.rir)
        XCTAssertNil(log.durationSec)
        XCTAssertNil(log.distanceM)
        XCTAssertEqual(log.side, .bilateral)
        XCTAssertEqual(log.completedAt, fixed.now)
    }

    func testCompleteAloneDoesNotPublishCompletion() async throws {
        // `complete()` is the "force-complete" affordance. It transitions
        // route but does NOT publish the completion record — that's the
        // terminal action's responsibility (`saveAndDone`). Previously
        // complete() must not enqueue by itself or the explicit End →
        // save & done path would produce a double publication.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let kickRecorder = KickRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in
                await recorder.appendSet(log)
            },
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
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
        vm.startCurrentSet()
        vm.complete()

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        XCTAssertEqual(completions.count, 0, "complete() must not publish completion")
        XCTAssertEqual(vm.state.route, .complete)
        let kicks = await kickRecorder.count
        XCTAssertEqual(kicks, 0, "complete() must not kick the push flusher")
    }

    func testSaveAndDoneNotesRideOnCompletionRecord() async throws {
        // The terminal completion record carries the user's post-workout
        // note so every publisher sees the same app-owned value.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.complete()
        vm.saveAndDone(note: "  leg day PR!  ", bodyweightKg: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        XCTAssertEqual(completions.count, 1)
        let completion = try XCTUnwrap(completions.first)
        XCTAssertEqual(
            completion.workout.notes, "leg day PR!",
            "whitespace-trimmed note must ride on the completion record"
        )
    }

    func testSaveAndDoneEmptyNoteSendsNilOnCompletionRecord() async throws {
        // `normalizeNote` collapses whitespace-only strings to nil —
        // sending nil leaves the existing server-side notes untouched
        // instead of wiping them.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.complete()
        vm.saveAndDone(note: "   ", bodyweightKg: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        let completion = try XCTUnwrap(completions.first)
        XCTAssertNil(completion.workout.notes, "whitespace-only → nil on the completion record")
    }

    func testSaveAndDoneEnqueuesCompletionExactlyOnce() async throws {
        // `saveAndDone` is the sole terminal enqueue path. It must fire
        // for both routes into `.complete` — auto-advance from last set
        // AND explicit End — so the test here covers both paths.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let kickRecorder = KickRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            },
            onPushKick: { [kickRecorder] in
                await kickRecorder.bump()
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.complete()
        vm.saveAndDone()

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        XCTAssertEqual(completions.count, 1, "explicit End → saveAndDone must enqueue exactly once")
        let completion = try XCTUnwrap(completions.first)
        XCTAssertEqual(completion.workout.id, vm.state.workoutID)
        XCTAssertEqual(completion.workout.status, .completed)
        XCTAssertEqual(completion.workout.completedAt, fixed.now)
        XCTAssertEqual(completion.setLogs.count, 0, "no set was logged on explicit End path")
        let kicks = await kickRecorder.count
        XCTAssertEqual(kicks, 1, "one kick per terminal push, not two")
    }

    func testSaveAndDoneEmitsCompletionProofTelemetry() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = PushTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueRecorder()
        let telemetry = TelemetryRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            push: hooks,
            localCompletionWriter: { _ in },
            telemetry: telemetry
        )
        vm.start()
        vm.startCurrentSet()
        vm.complete()
        vm.saveAndDone(note: "done", bodyweightKg: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        let completionEvents = telemetry.events.filter {
            $0.name.hasPrefix("execution.completion_")
        }
        XCTAssertEqual(
            completionEvents.map(\.name),
            [
                "execution.completion_record_built",
                "execution.completion_publish_finished",
                "execution.completion_local_writer_completed",
            ]
        )
        XCTAssertTrue(
            completionEvents.allSatisfy { $0.workoutID == ctx.workout.id },
            "every completion proof event must be correlated to the workout"
        )
        let builtPayload = try XCTUnwrap(completionEvents.first?.dataJSON)
        XCTAssertTrue(builtPayload.contains(#""set_log_count":0"#))
        XCTAssertTrue(builtPayload.contains(#""primitive_set_log_count":0"#))
        XCTAssertTrue(builtPayload.contains(#""has_note":true"#))
        let publishPayload = try XCTUnwrap(completionEvents.dropFirst().first?.dataJSON)
        XCTAssertTrue(publishPayload.contains(#""publisher_installed":true"#))
    }

    func testSaveAndDoneCarriesRecordedPrimitiveResults() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let ctx = PushTestFixtures.primitiveContext()
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)

        vm.recordPrimitiveSetResult(
            blockIndex: 0,
            setIndexInBlock: 0,
            reps: 4,
            rounds: 7,
            durationSec: 300
        )
        vm.complete()
        vm.saveAndDone()

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        let completion = try XCTUnwrap(completions.first)
        XCTAssertEqual(completion.primitiveSetLogs.count, 1)
        let log = try XCTUnwrap(completion.primitiveSetLogs.first)
        XCTAssertEqual(log.role, .setResult)
        XCTAssertEqual(log.workoutID, ctx.workout.id)
        XCTAssertEqual(log.setIndex, 0)
        XCTAssertEqual(log.reps, 4)
        XCTAssertEqual(log.rounds, 7)
        XCTAssertEqual(log.durationSec, 300)
        XCTAssertEqual(log.completedAt, fixed.now)
    }

    func testNilEnqueuersPreserveExistingBehavior() async throws {
        // Regression: the default path (no push hooks) must still
        // produce the same state transitions and not crash.
        let (ctx, _) = PushTestFixtures.context(sets: 2, reps: 5, loadKg: 100)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.startCurrentSet()
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
        vm.startCurrentSet()
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

    static func primitiveContext() -> WorkoutContext {
        let userID = UUID(uuidString: "01000000-0000-4000-8000-000000000001")!
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000051")!
        let legacyBlockID = UUID(uuidString: "20000000-0000-4000-8000-000000000050")!
        let primitiveBlockID = UUID(uuidString: "20000000-0000-4000-8000-000000000051")!
        let primitiveSetID = UUID(uuidString: "30000000-0000-4000-8000-000000000051")!
        let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000051")!
        let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000051")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Primitive Push Test",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            createdAt: now,
            updatedAt: now
        )
        let block = Block(
            id: legacyBlockID,
            workoutID: workoutID,
            position: 0,
            timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#
        )
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive Push Test",
            blocks: [
                PrimitiveBlock(id: primitiveBlockID, sets: [
                    PrimitiveSet(
                        id: primitiveSetID,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        traversal: .amrap,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                        ],
                        slots: [
                            PrimitiveSlot(
                                id: slotID,
                                exerciseID: exerciseID,
                                workTargets: [
                                    PrimitiveWorkTarget(
                                        metric: .reps,
                                        valueForm: .single,
                                        value: 10,
                                        role: .completion
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]),
            ]
        )
        let plan = try! ExecutionPlan.validated(workout: primitive)
        return WorkoutContext(
            workout: workout,
            primitiveWorkout: primitive,
            primitiveExecutionPlan: plan,
            blocks: [block],
            itemsByBlock: [[]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Push-up")]
        )
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
    private(set) var completions: [WorkoutCompletionRecord] = []
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

    func appendCompletion(_ record: WorkoutCompletionRecord) {
        completions.append(record)
    }

    func appendUserParameter(_ param: UserParameter) {
        userParameters.append(param)
    }
}

actor KickRecorder {
    private(set) var count = 0
    func bump() { count += 1 }
}
