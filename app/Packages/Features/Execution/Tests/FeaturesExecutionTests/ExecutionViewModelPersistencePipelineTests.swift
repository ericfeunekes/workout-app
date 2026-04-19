// ExecutionViewModelPersistencePipelineTests.swift
//
// Regression coverage for the persistence pipeline + restore-normalization
// work (the two P0 correctness bugs surfaced by Codex review):
//
//   Bug A — unordered session-store writes racing with clear.
//     * `testPersistOrderingRejectsStaleWrite`
//     * `testClearFollowsInFlightSave`
//
//   Bug B — `restoreIfPossible()` skipping normalization.
//     * `testRestoreNormalizesZeroItemFirstBlock`
//     * `testRestoreNormalizesTabataWorkWindow`
//
// Shared scaffolding:
//   - `SlowSessionStore` introduces a configurable per-op delay so tests
//     can enqueue multiple writes in flight and observe the pipeline's
//     ordering / rejection behavior without relying on racing fire-and-
//     forget Tasks.

import XCTest
import CoreDomain
import CorePrescription
import CoreSession
import Persistence
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelPersistencePipelineTests: XCTestCase {

    // MARK: - Context builders

    /// Straight-sets, one block, one item, N sets.
    private func makeStraightSetsContext(sets: Int = 2, restSec: Int = 60)
        -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Pipeline",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":\#(sets),"reps":5,"load_kg":100}"#
        )
        return WorkoutContext(
            workout: workout, blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")],
            lastPerformed: [:]
        )
    }

    /// Zero-item rest block at position 0, then a straight-sets work block.
    private func makeZeroItemFirstContext(restDurationSec: Int = 45)
        -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let bRest = UUID()
        let bWork = UUID()
        let exW = UUID()
        let itemW = UUID()
        let workout = Workout(
            id: workoutID, userID: userID, name: "ZeroFirst",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let restBlock = Block(
            id: bRest, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .rest,
            timingConfigJSON: #"{"duration_sec":\#(restDurationSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let workBlock = Block(
            id: bWork, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        return WorkoutContext(
            workout: workout, blocks: [restBlock, workBlock],
            itemsByBlock: [
                [],
                [WorkoutItem(id: itemW, blockID: bWork, position: 0,
                             exerciseID: exW,
                             prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#)],
            ],
            exercises: [exW: Exercise(id: exW, name: "Bench")]
        )
    }

    /// Tabata single-block context so we can assert the work-window
    /// normalization path.
    private func makeTabataContext() -> WorkoutContext {
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
        return WorkoutContext(
            workout: workout, blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Air Squats")],
            lastPerformed: [:]
        )
    }

    // MARK: - Bug A · ordering + stale rejection

    /// Two persist() calls are issued in chronological order 1 then 2,
    /// but the store is slow and the pipeline serializes them. Asserts
    /// the final payload on disk corresponds to the LATEST state — the
    /// intermediate state is superseded, not left behind. The pipeline's
    /// FIFO actor guarantees this ordering.
    func testPersistOrderingRejectsStaleWrite() async throws {
        let store = RecordingSessionStore()
        let ctx = makeStraightSetsContext(sets: 2)
        let vm = ExecutionViewModel(context: ctx, sessionStore: store)
        defer { vm.resetPersistencePipelineForTesting() }

        // State A: start → .active.
        vm.start()
        let stateA = vm.state

        // State B: log a set → .rest.
        vm.logSet(reps: 5, rir: 2)
        let stateB = vm.state

        // Drain both fire-and-forget persist() tasks.
        try await Task.sleep(nanoseconds: 100_000_000)

        // At minimum two distinct states must have been written.
        XCTAssertNotEqual(stateA.route, stateB.route)

        // Final bytes on disk must decode to state B (the last persist()).
        let loaded = try await store.load()
        let decoded = try JSONDecoder().decode(
            SessionStateCodable.self, from: XCTUnwrap(loaded)
        )
        XCTAssertEqual(decoded.state.route, stateB.route)
        XCTAssertEqual(
            decoded.state.items.first?.sets.filter(\.done).count,
            stateB.items.first?.sets.filter(\.done).count
        )

        // Additionally: simulate an explicitly-out-of-order write. We
        // enqueue a save at a stale revision AFTER the most recent one
        // and assert the pipeline rejects it.
        let pipeline = try XCTUnwrap(vm.persistencePipelineHandle())
        let staleSnapshot = SessionStateCodable(state: stateA)
        let staleData = try JSONEncoder().encode(staleSnapshot)
        // Revision 1 is well below the counter's current value (bumped
        // twice by the two persist() calls above and once by start's
        // helper). The pipeline must drop this op without writing.
        await pipeline.enqueue(op: .save(staleData), revision: 1)

        let afterStaleEnqueue = try await store.load()
        let decodedAfter = try JSONDecoder().decode(
            SessionStateCodable.self, from: XCTUnwrap(afterStaleEnqueue)
        )
        // Final bytes are still state B — the stale save was rejected.
        XCTAssertEqual(decodedAfter.state.route, stateB.route)
    }

    /// `.save` followed immediately by `clearPersistedSession()` must leave
    /// the store empty on restore. Previously the save was a detached Task
    /// and the clear was a separate detached Task — either could land
    /// last. With the serial pipeline, the clear is guaranteed to land
    /// AFTER the save (FIFO), so restore reads `nil`.
    func testClearFollowsInFlightSave() async throws {
        let store = SlowSessionStore(delayNanos: 20_000_000)
        let ctx = makeStraightSetsContext(sets: 1)
        let vm = ExecutionViewModel(context: ctx, sessionStore: store)
        defer { vm.resetPersistencePipelineForTesting() }

        // Drive persist() → a save is in-flight inside the slow store.
        vm.start()
        vm.logSet(reps: 5, rir: 2)

        // Immediately enqueue the clear — no deliberate sleep in between.
        // The pipeline must preserve FIFO order: save resolves first,
        // then clear wipes the row.
        vm.clearPersistedSession()

        // Wait long enough for ALL ops (persist from start, persist from
        // logSet, clear) to drain through the slow store. The slow store
        // adds 20ms per op; three ops serialized = ~60ms; a generous
        // 500ms wait absorbs scheduler jitter without making the test
        // flaky.
        try await Task.sleep(nanoseconds: 500_000_000)

        let loaded = try await store.load()
        XCTAssertNil(loaded, "clear must land after save — restore should read nil")
    }

    // MARK: - Bug B · restore normalization

    /// A raw snapshot that says `.active` on a zero-item block 0 must NOT
    /// be restored verbatim — normalization flips it to `.rest` with a
    /// populated `restEndsAt`. This guards against a kill-then-relaunch
    /// mid-session where the on-disk bytes reflect a pre-normalization
    /// state (e.g. before a bug fix, or from a race where `.start()`
    /// ran but the helper call was interrupted).
    func testRestoreNormalizesZeroItemFirstBlock() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 3_000_000))
        let ctx = makeZeroItemFirstContext(restDurationSec: 45)
        let store = RecordingSessionStore()

        // Handcraft a raw snapshot: route = .active, no restEndsAt. This
        // mimics the "kill-then-relaunch on a zero-item block 0 before
        // normalization ran" corner case.
        let seed = SessionSeeder.seed(context: ctx)
        var rawState = seed
        rawState.route = .active
        rawState.restEndsAt = nil
        let rawData = try JSONEncoder().encode(SessionStateCodable(state: rawState))
        try await store.save(rawData)

        let vm = ExecutionViewModel(context: ctx, clock: fixed, sessionStore: store)
        defer { vm.resetPersistencePipelineForTesting() }
        await vm.restoreIfPossible()

        // Post-normalization: route is .rest, restEndsAt reflects the
        // block's duration_sec.
        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 45
        )

        // And the normalized state was persisted back — a fresh decode
        // of the store's bytes matches the normalized in-memory state.
        try await Task.sleep(nanoseconds: 50_000_000)
        let reloaded = try await store.load()
        let decoded = try JSONDecoder().decode(
            SessionStateCodable.self, from: XCTUnwrap(reloaded)
        )
        XCTAssertEqual(decoded.state.route, .rest)
        XCTAssertEqual(
            decoded.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 45
        )
    }

    /// A restored snapshot on a zero-item block that ALREADY has
    /// `route = .rest` + `restEndsAt` set must NOT be re-stamped by
    /// normalization. The previous bug unconditionally dispatched
    /// `.enterRest` on every restore, which reset `restEndsAt = now +
    /// duration` — turning every kill/relaunch mid-rest into a timer
    /// extension. The `restEndsAt == nil` guard in
    /// `enterRestIfZeroItemBlock()` makes the helper idempotent.
    func testRestoreIsIdempotentForZeroItemRest() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 4_000_000))
        let ctx = makeZeroItemFirstContext(restDurationSec: 45)
        let store = RecordingSessionStore()

        // Craft a live mid-rest snapshot: route = .rest, restEndsAt set
        // somewhere in the future (we picked `now + 10s` to represent
        // "rest has 10 seconds left when the app was killed"). The key
        // property: restEndsAt is populated, NOT nil.
        let seed = SessionSeeder.seed(context: ctx)
        var rawState = seed
        rawState.route = .rest
        let preExistingRestEnd = fixed.now.addingTimeInterval(10)
        rawState.restEndsAt = preExistingRestEnd
        let rawData = try JSONEncoder().encode(SessionStateCodable(state: rawState))
        try await store.save(rawData)

        let vm = ExecutionViewModel(context: ctx, clock: fixed, sessionStore: store)
        defer { vm.resetPersistencePipelineForTesting() }
        await vm.restoreIfPossible()

        // Route stays .rest — nothing flipped it.
        XCTAssertEqual(vm.state.route, .rest)
        // restEndsAt is IDENTICAL to the restored value. If the guard
        // were missing, the helper would have re-dispatched `.enterRest`
        // and `restEndsAt` would now equal `fixed.now + 45`.
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            preExistingRestEnd.timeIntervalSince1970
        )
        // And explicitly: it is NOT the re-stamped value.
        XCTAssertNotEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 45
        )
    }

    /// A restored snapshot on an active Tabata block that ALREADY has
    /// `workEndsAt` set must NOT be re-stamped. The previous bug
    /// unconditionally called `state.workEndsAt = now + 20s` on every
    /// restore, so every kill/relaunch mid-work-window extended the
    /// window by another full 20s. The `workEndsAt == nil` guard in
    /// `enterTabataWorkWindowIfNeeded()` makes the helper idempotent.
    func testRestoreIsIdempotentForActiveTabata() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 6_000_000))
        let ctx = makeTabataContext()
        let store = RecordingSessionStore()

        // Craft a live mid-work-window snapshot: route = .active,
        // workEndsAt populated (we picked `now + 8s` — 8 seconds left
        // in the 20s work window when the app was killed). blockEndsAt
        // is also already set so the `enterBlockTimerIfNeeded` path
        // doesn't re-derive it either.
        let seed = SessionSeeder.seed(context: ctx)
        var rawState = seed
        rawState.route = .active
        let preExistingWorkEnd = fixed.now.addingTimeInterval(8)
        let preExistingBlockEnd = fixed.now.addingTimeInterval(200)
        rawState.workEndsAt = preExistingWorkEnd
        rawState.blockEndsAt = preExistingBlockEnd
        let rawData = try JSONEncoder().encode(SessionStateCodable(state: rawState))
        try await store.save(rawData)

        let vm = ExecutionViewModel(context: ctx, clock: fixed, sessionStore: store)
        defer { vm.resetPersistencePipelineForTesting() }
        await vm.restoreIfPossible()

        // Route stays .active.
        XCTAssertEqual(vm.state.route, .active)
        // workEndsAt is IDENTICAL to the restored value — not re-stamped
        // to `fixed.now + 20s`.
        XCTAssertEqual(
            vm.state.workEndsAt?.timeIntervalSince1970,
            preExistingWorkEnd.timeIntervalSince1970
        )
        XCTAssertNotEqual(
            vm.state.workEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + TabataDriver.workSec
        )
        // blockEndsAt also untouched.
        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            preExistingBlockEnd.timeIntervalSince1970
        )
    }

    /// A raw snapshot on an `.active` Tabata block with no `workEndsAt`
    /// must be normalized to carry `workEndsAt = now + 20s`. Without
    /// normalization the `tickBlockTimer` view-side path would never
    /// auto-log the placeholder rep on the first round after a restart,
    /// because `workEndsAt` would stay nil forever.
    func testRestoreNormalizesTabataWorkWindow() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 5_000_000))
        let ctx = makeTabataContext()
        let store = RecordingSessionStore()

        // Handcraft a snapshot on .active for the Tabata block with NO
        // workEndsAt. Mirrors a mid-work-window kill before the helper
        // stamped the 20s window.
        let seed = SessionSeeder.seed(context: ctx)
        var rawState = seed
        rawState.route = .active
        rawState.workEndsAt = nil
        rawState.blockEndsAt = nil
        let rawData = try JSONEncoder().encode(SessionStateCodable(state: rawState))
        try await store.save(rawData)

        let vm = ExecutionViewModel(context: ctx, clock: fixed, sessionStore: store)
        defer { vm.resetPersistencePipelineForTesting() }
        await vm.restoreIfPossible()

        // Work window stamped at `clock.now + 20s`.
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(
            vm.state.workEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + TabataDriver.workSec
        )
        // Block cap also stamped (defensive: 8 × 30s = 240s).
        XCTAssertNotNil(vm.state.blockEndsAt)
    }
}

// MARK: - Test stores

/// Records the most recent payload. No artificial delay — useful when a
/// test needs to observe the final persisted bytes but doesn't need the
/// pipeline to visibly serialize multiple in-flight ops.
private actor RecordingSessionStore: SessionStore {
    private var payload: Data?

    func load() async throws -> Data? { payload }
    func save(_ payload: Data) async throws { self.payload = payload }
    func clear() async throws { payload = nil }
}

/// Introduces a configurable per-op delay. When multiple ops are
/// enqueued in rapid succession, the delay exposes any ordering bug: a
/// fire-and-forget Task design would let the fastest op complete first,
/// while the pipeline guarantees FIFO.
private actor SlowSessionStore: SessionStore {
    private let delayNanos: UInt64
    private var payload: Data?

    init(delayNanos: UInt64) {
        self.delayNanos = delayNanos
    }

    func load() async throws -> Data? { payload }

    func save(_ newPayload: Data) async throws {
        try await Task.sleep(nanoseconds: delayNanos)
        self.payload = newPayload
    }

    func clear() async throws {
        try await Task.sleep(nanoseconds: delayNanos)
        self.payload = nil
    }
}
