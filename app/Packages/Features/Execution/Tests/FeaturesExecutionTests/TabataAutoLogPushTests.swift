// TabataAutoLogPushTests.swift
//
// qa-050 regression coverage. The Tabata 20s work-window expiry path
// (`autoLogAndRestForTabata` in `ExecutionViewModel+Persistence.swift`)
// used to dispatch `.logSet` directly through `apply(_:)` — mutating
// SessionState but bypassing the post-log side-effects the user-tap
// `logSet()` runs through `handleLogSetSideEffects`. That meant:
//
//   - the push hook (`onSetLogged`) never fired → the `set_log` row
//     never reached the server (the bug the user reported: "JUST LOGGED
//     | 0 REPS" renders from SessionState but no SetLog lands)
//   - the `execution.session_mutation(logSet)` telemetry never fired
//     → analytics saw zero logSet events for tabata auto-logs
//   - `writeCompletionToLocalCache` on save-and-done reads from
//     `state.items`, so the cache DID eventually pick up the rows on
//     save — but any user who force-quit between auto-log and save-
//     and-done would still have the row on disk (persisted session
//     state) but no server copy, and no history cache either
//
// Post-fix: `autoLogAndRestForTabata` calls `enqueueLoggedSet` and
// `emitSessionMutation("logSet")` after the `apply(_:)` — mirroring
// the user-tap path's `handleLogSetSideEffects`. The same treatment
// applies to the companion EMOM cap auto-log
// (`autoLogPlaceholderForEMOM`) which had the same gap.

import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class TabataAutoLogPushTests: XCTestCase {

    // MARK: - Fixtures

    /// Single-item Tabata context. Shape mirrors the one in
    /// `ExecutionViewModelTickBlockTimerTests.makeTabataContext` so the
    /// auto-log path (which drives `enterBlockTimerIfNeeded` on `.start`)
    /// stamps `workEndsAt` + `blockEndsAt` as expected.
    private func makeTabataContext() -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Tabata",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .tabata,
            timingConfigJSON: "{}",
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":20}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Air Squats")]
        )
        return (ctx, itemID)
    }

    // MARK: - Tests

    /// qa-050 — the core regression. A single 20s work-window expiry
    /// tick fires `onSetLogged` exactly once with a placeholder SetLog
    /// (`reps = 0`, `rir = nil`). Before the fix the state mutation
    /// happened but the hook never ran, so the server never received
    /// the row and the user's "JUST LOGGED" UI was a lie.
    func testTabataAutoLogEnqueuesSetLog() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TabataAutoLogClock(now: start)
        let (ctx, itemID) = makeTabataContext()
        let recorder = AutoLogEnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.append(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        // Jump to exactly the 20s work-window boundary and tick. The
        // `state.workEndsAt` anchor was stamped on `.start` via
        // `enterBlockTimerIfNeeded`, so `clock.now >= workEndsAt` trips
        // the auto-log path on this single tick.
        clock.now = start.addingTimeInterval(TabataDriver.workSec)
        vm.tickBlockTimer()

        // Small sleep — `enqueueLoggedSet` hands work to a fire-and-
        // forget `Task { @MainActor in await onSetLogged(setLog) }`,
        // so the recorder sees the call only after that task runs.
        try await Task.sleep(nanoseconds: 50_000_000)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 1, "one work-window expiry = one pushed SetLog")
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.workoutItemID, itemID)
        XCTAssertEqual(log.setIndex, 1, "first round = setIndex 1")
        XCTAssertEqual(log.reps, 0, "Tabata auto-log is a 0-rep placeholder")
        XCTAssertNil(log.rir, "Tabata auto-log carries nil RIR")
        XCTAssertFalse(log.isWarmup)
        // completedAt stamped on the log mutation = clock.now at tick time.
        XCTAssertEqual(log.completedAt, clock.now)
    }

    /// qa-050 companion — the `.enterRest` flip that ships alongside the
    /// placeholder log must gate the next tick from re-entering the
    /// helper, so a second tick inside the same work window does not
    /// double-enqueue. Mirrors the "no double-enqueue if the auto-log
    /// fires twice" requirement in the fix brief.
    func testTabataAutoLogDoesNotDoubleEnqueueOnRepeatedTicks() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TabataAutoLogClock(now: start)
        let (ctx, _) = makeTabataContext()
        let recorder = AutoLogEnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [recorder] log in await recorder.append(log) }
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock, push: hooks)
        vm.start()

        // Tick once at the work-window boundary — fires the auto-log +
        // flips route to `.rest`.
        clock.now = start.addingTimeInterval(TabataDriver.workSec)
        vm.tickBlockTimer()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(vm.state.route, .rest,
            "auto-log dispatches .enterRest — route is .rest after the tick")

        // A second tick 1s later must NOT re-enter the helper (route
        // guard on `.active` blocks re-entry) so the enqueue count
        // stays at 1.
        clock.now = start.addingTimeInterval(TabataDriver.workSec + 1)
        vm.tickBlockTimer()
        try await Task.sleep(nanoseconds: 20_000_000)

        let logs = await recorder.setLogs
        XCTAssertEqual(logs.count, 1,
            "repeated ticks inside the rest phase must not re-enqueue the placeholder")
    }

    /// qa-050 — after a full 8-round Tabata (auto-logs land as placeholders
    /// on each work-window expiry), `saveAndDone` must ship all 8 rows to
    /// the local WorkoutCache so History renders the session immediately
    /// without waiting for a server round-trip. This is the "local cache
    /// write works on save & done" clause of the fix brief — the cache
    /// writer reads `state.items`, so the auto-logs that flow through
    /// `apply(_:)` already land there; this test proves the end-to-end.
    func testTabataAutoLogUpdatesLocalCacheOnSave() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TabataAutoLogClock(now: start)
        let (ctx, itemID) = makeTabataContext()
        let pushRecorder = AutoLogEnqueueRecorder()
        let cacheRecorder = AutoLogCompletionRecorder()
        let hooks = ExecutionPushHooks(
            onSetLogged: { [pushRecorder] log in await pushRecorder.append(log) }
        )
        let vm = ExecutionViewModel(
            context: ctx,
            clock: clock,
            push: hooks,
            localCompletionWriter: { [cacheRecorder] workout, setLogs in
                await cacheRecorder.record(workout: workout, setLogs: setLogs)
            }
        )
        vm.start()

        // Walk through all 8 rounds. Each round's cycle: tick at the
        // work-window boundary (auto-log placeholder + enter rest),
        // tick past the rest boundary (reducer advances into the next
        // round on `advance()` — we drive it here by calling
        // `vm.advance()` so the cursor bumps and `workEndsAt`
        // refreshes via `enterTabataWorkWindowIfNeeded`).
        let cycleSec = TabataDriver.workSec + TabataDriver.restSec
        for round in 0..<TabataDriver.rounds {
            let workBoundary = start.addingTimeInterval(
                Double(round) * cycleSec + TabataDriver.workSec
            )
            clock.now = workBoundary
            vm.tickBlockTimer()
            try await Task.sleep(nanoseconds: 10_000_000)
            // Advance out of rest into the next round (or .complete on
            // the final round). Simulates the rest-timer elapsing.
            // On the final round, a Tabata block's round-robin cursor
            // wraps to setIndex 9 which is past `rounds`; the reducer's
            // `advanceFromRest` flips route to .complete for us.
            vm.advance()
        }

        // After 8 rounds the workout is complete in memory — fire
        // saveAndDone to hand the session to the cache writer.
        vm.saveAndDone(note: nil, bodyweightKg: nil)
        try await Task.sleep(nanoseconds: 80_000_000)

        let calls = await cacheRecorder.calls
        XCTAssertEqual(calls.count, 1, "saveAndDone invokes the cache writer once")
        let call = try XCTUnwrap(calls.first)
        let cachedSetLogs = call.setLogs.filter { $0.workoutItemID == itemID }
        XCTAssertEqual(
            cachedSetLogs.count, TabataDriver.rounds,
            "each of the 8 Tabata rounds lands in the local cache"
        )
        // Every cached row is the placeholder shape: 0 reps, nil rir.
        for log in cachedSetLogs {
            XCTAssertEqual(log.reps, 0)
            XCTAssertNil(log.rir)
        }
        // And the push path saw the same 8 rows, deterministic id each.
        let pushed = await pushRecorder.setLogs
        XCTAssertEqual(pushed.count, TabataDriver.rounds)
        let pushedIDs = Set(pushed.map(\.id))
        let cachedIDs = Set(cachedSetLogs.map(\.id))
        XCTAssertEqual(
            pushedIDs, cachedIDs,
            "push + cache share the deterministic SetLog ids — one logical set, one UUID everywhere"
        )
    }
}

// MARK: - Helpers

/// Reference-typed mutable clock. `FixedClock` is a value type and the VM
/// captures the clock by value, so tests that advance the clock across
/// VM boundaries need a class-backed clock. File-scoped to avoid colliding
/// with the similarly-named helpers in other test files.
private final class TabataAutoLogClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

/// Records SetLogs routed through the push hook. Actor-isolated so the
/// main-actor `Task` closures can safely append without data-race warnings.
private actor AutoLogEnqueueRecorder {
    private(set) var setLogs: [SetLog] = []

    func append(_ log: SetLog) {
        setLogs.append(log)
    }
}

/// Records `LocalCompletionWriter` invocations. Actor-isolated for the
/// same reason as `AutoLogEnqueueRecorder`.
private actor AutoLogCompletionRecorder {
    struct Call {
        let workout: Workout
        let setLogs: [SetLog]
    }
    private(set) var calls: [Call] = []

    func record(workout: Workout, setLogs: [SetLog]) {
        calls.append(Call(workout: workout, setLogs: setLogs))
    }
}
