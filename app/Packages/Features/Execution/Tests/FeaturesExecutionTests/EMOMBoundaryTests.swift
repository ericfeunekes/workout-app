// EMOMBoundaryTests.swift
//
// Regression for the EMOM minute-boundary semantics. Spec intent (per
// `docs/prescription.md` § "emom"): "finish the work inside the minute,
// rest the remainder, advance to next work window on boundary tick."
//
// Pre-fix: `EMOMDriver` returned `interval_sec` from `restDuration`, so
// the VM stamped `restEndsAt = logTime + interval_sec`. A log at 0:15
// inside interval 1 would rest until 1:15 — 15s late. Drift compounded
// over the block's duration.
//
// Post-fix: the VM stamps `intervalAnchorAt` on EMOM block entry. Rest
// anchors to `intervalAnchorAt + cursor.setIndex * interval_sec`, NOT
// log-time. `tickBlockTimer` auto-advances when the boundary elapses.
//
// Tests:
//   1. `testEMOMBoundaryAdvanceOnMinuteMark` — log at 0:15, clock → 1:00,
//      tick, assert cursor is on interval 2 (not interval 1 + rest).
//   2. `testEMOMBoundaryAnchorsFromBlockStartNotLogTime` — log at 0:15,
//      then log interval 2 at 1:30, clock → 2:00, tick, assert cursor
//      advances to interval 3 — boundary is clock time, not
//      log-time-plus-interval.
//   3. `testEMOMCompletesAtTotalMinutes` — seed 2-minute EMOM, clock →
//      2:00, assert `.complete`.
//   4. `testEMOMRestoreNormalizesAfterKill` — persist mid-EMOM, restore
//      on clock ahead of block cap, assert `.complete` (uses restore
//      normalization).

import XCTest
import CoreDomain
import CoreSession
import Persistence
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class EMOMBoundaryTests: XCTestCase {

    // MARK: - Fixtures

    private func makeEMOMContext(
        totalMinutes: Int,
        intervalSec: Int = 60
    ) -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "emom",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":\#(intervalSec),"total_minutes":\#(totalMinutes)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":10,"load_kg":24}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "KB Swing")]
        )
        return (ctx, itemID)
    }

    /// Two-item EMOM fixture. Models the qa-005 scenario — an 8-minute
    /// EMOM with 2 items rotating per minute. Returned `itemIDs` carry
    /// (rowItem, pushItem) so tests can attribute logs back to the right
    /// item in the round-robin walk.
    private func makeTwoItemEMOMContext(
        totalMinutes: Int,
        intervalSec: Int = 60
    ) -> (WorkoutContext, itemA: UUID, itemB: UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseAID = UUID()
        let exerciseBID = UUID()
        let itemAID = UUID()
        let itemBID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "emom-2",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":\#(intervalSec),"total_minutes":\#(totalMinutes)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let itemA = WorkoutItem(
            id: itemAID, blockID: blockID, position: 0,
            exerciseID: exerciseAID,
            prescriptionJSON: #"{"reps":15,"load_kg":0}"#
        )
        let itemB = WorkoutItem(
            id: itemBID, blockID: blockID, position: 1,
            exerciseID: exerciseBID,
            prescriptionJSON: #"{"reps":10,"load_kg":43}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[itemA, itemB]],
            exercises: [
                exerciseAID: Exercise(id: exerciseAID, name: "Row Erg Calories"),
                exerciseBID: Exercise(id: exerciseBID, name: "Push Press"),
            ]
        )
        return (ctx, itemA: itemAID, itemB: itemBID)
    }

    /// Count of all completed (done) SetPlan rows across every item in the
    /// session state — the test-level mirror of `set_log` rows on the
    /// server. qa-005 manifested as 7 such rows for an 8-minute / 2-item
    /// EMOM; the post-fix expectation is 8.
    private func totalLoggedSets(_ state: SessionState) -> Int {
        state.items.reduce(0) { acc, item in
            acc + item.sets.filter { $0.done }.count
        }
    }

    // MARK: - Tests

    /// A log at 0:15 inside interval 1 must rest until 1:00, not 1:15.
    /// Advancing the clock to 1:00 and calling `tickBlockTimer()` must
    /// auto-advance the cursor to interval 2 on the minute mark.
    func testEMOMBoundaryAdvanceOnMinuteMark() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableBoundaryClock(now: start)
        let (ctx, _) = makeEMOMContext(totalMinutes: 3)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // Interval grid anchor stamped at block entry.
        XCTAssertEqual(
            vm.state.intervalAnchorAt?.timeIntervalSince1970,
            start.timeIntervalSince1970,
            "EMOM block entry must stamp intervalAnchorAt = now"
        )
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        // User logs at 0:15 inside interval 1.
        clock.now = start.addingTimeInterval(15)
        vm.logSet(reps: 10, rir: nil)
        XCTAssertEqual(vm.state.route, .rest)

        // Rest must end at boundary (1:00), NOT at log + interval (1:15).
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 60,
            "restEndsAt must anchor to boundary, not log-time + interval_sec"
        )

        // Advance clock to 1:00 (the boundary). Tick auto-advances cursor.
        clock.now = start.addingTimeInterval(60)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.cursor.setIndex, 2,
            "cursor must advance to interval 2 on the minute boundary")
        XCTAssertEqual(vm.state.route, .active)
    }

    /// Each interval's boundary is derived from the block start, not the
    /// previous log. A log at 0:15 in interval 1, then a log at 1:30 in
    /// interval 2, should still boundary at 2:00 — clock-anchored.
    func testEMOMBoundaryAnchorsFromBlockStartNotLogTime() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let clock = MutableBoundaryClock(now: start)
        let (ctx, _) = makeEMOMContext(totalMinutes: 5)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // Log interval 1 at 0:15.
        clock.now = start.addingTimeInterval(15)
        vm.logSet(reps: 10, rir: nil)
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 60,
            "interval 1 boundary = start + 60"
        )

        // Auto-advance at 1:00.
        clock.now = start.addingTimeInterval(60)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.state.cursor.setIndex, 2)

        // User starts interval 2 immediately and logs late — at 1:30.
        clock.now = start.addingTimeInterval(90)
        vm.logSet(reps: 10, rir: nil)
        // Rest until 2:00 (boundary = anchor + 2*60 = start + 120), NOT
        // log + interval (would be 2:30).
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 120,
            "interval 2 boundary = start + 120, independent of log time"
        )

        // Advance clock to 2:00. Tick must auto-advance to interval 3.
        clock.now = start.addingTimeInterval(120)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.state.cursor.setIndex, 3,
            "cursor must advance to interval 3 at the 2:00 boundary")
    }

    /// A 2-minute EMOM must complete when the clock hits total_minutes,
    /// regardless of interval logging. The block cap and the interval
    /// boundary share the same wall clock.
    func testEMOMCompletesAtTotalMinutes() {
        let start = Date(timeIntervalSince1970: 3_000_000)
        let clock = MutableBoundaryClock(now: start)
        let (ctx, _) = makeEMOMContext(totalMinutes: 2)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 120,
            "2-minute EMOM blockEndsAt = start + 120"
        )

        // Fast-forward to the block cap.
        clock.now = start.addingTimeInterval(120)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.state.route, .complete,
            "EMOM must complete when total_minutes elapses")
    }

    /// A pre-R2.1 persisted payload decodes with `intervalAnchorAt == nil`
    /// (the field didn't exist yet). Without backfill, the restore path's
    /// `enterBlockTimerIfNeeded` would see a nil anchor on an EMOM block
    /// and re-stamp it to `clock.now`, sliding every future minute boundary
    /// forward to relaunch-time and destroying the original minute grid.
    ///
    /// Post-fix: the restore normalizer derives `intervalAnchorAt` from
    /// `blockEndsAt - total_minutes * 60` — the block cap was stamped at
    /// block entry as `anchor + total_minutes * 60`, so that subtraction
    /// recovers the original anchor deterministically.
    func testRestoreBackfillsEMOMAnchorFromBlockEndsAt() async throws {
        let originalStart = Date(timeIntervalSince1970: 5_000_000)
        let totalMinutes = 3
        let totalSeconds: TimeInterval = Double(totalMinutes) * 60
        let store = InMemorySessionStore()
        let (ctx, _) = makeEMOMContext(totalMinutes: totalMinutes)

        // Craft a pre-R2.1 payload: blockEndsAt reflects the original
        // block-entry clock + 3 minutes; intervalAnchorAt is nil (the
        // field didn't exist before R2.1). Any mid-block route works;
        // we pick `.active` to prove the backfill runs before the
        // normalizer's other helpers.
        let seed = SessionSeeder.seed(context: ctx)
        var rawState = seed
        rawState.route = .active
        rawState.blockEndsAt = originalStart.addingTimeInterval(totalSeconds)
        rawState.intervalAnchorAt = nil
        let rawData = try JSONEncoder().encode(SessionStateCodable(state: rawState))
        try await store.save(rawData)

        // Relaunch on a clock 90s into the original block (well past
        // where `enterBlockTimerIfNeeded` would stamp `clock.now` as a
        // fresh anchor if the backfill weren't running).
        let relaunch = originalStart.addingTimeInterval(90)
        let clock = MutableBoundaryClock(now: relaunch)
        let vm = ExecutionViewModel(context: ctx, clock: clock, sessionStore: store)
        await vm.restoreIfPossible()

        // Anchor backfilled from blockEndsAt, NOT re-stamped at relaunch.
        XCTAssertEqual(
            vm.state.intervalAnchorAt?.timeIntervalSince1970,
            originalStart.timeIntervalSince1970,
            "restore must backfill intervalAnchorAt = blockEndsAt - total*60, "
                + "preserving the original minute grid"
        )
        // Explicitly NOT the relaunch clock — that's the pre-fix bug.
        XCTAssertNotEqual(
            vm.state.intervalAnchorAt?.timeIntervalSince1970,
            relaunch.timeIntervalSince1970,
            "pre-R2.1 back-compat must not slide the minute grid to relaunch time"
        )
    }

    /// The rest ring's total (the denominator for progress math) must be
    /// the REAL rest window — `restEndsAt - log_time` — not the raw
    /// `interval_sec`. A log at 0:15 inside a 60s EMOM interval has a 45s
    /// rest window; using `interval_sec` as the total would render the
    /// ring already 25% depleted at log-time (elapsed = 60 - 45 = 15 →
    /// 15/60), which is the pre-fix bug. The VM tracks the rest-window
    /// start via the `.enterRest` mutation's `now` and exposes the real
    /// window through `restDurationSeconds` (EMOM branch).
    func testEMOMRestRingTotalIsLogAwareNotIntervalSec() {
        let start = Date(timeIntervalSince1970: 6_000_000)
        let clock = MutableBoundaryClock(now: start)
        let (ctx, _) = makeEMOMContext(totalMinutes: 3)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // Log at 0:15 — 45s of real rest remaining until the 1:00 boundary.
        clock.now = start.addingTimeInterval(15)
        vm.logSet(reps: 10, rir: nil)
        XCTAssertEqual(vm.state.route, .rest)

        // Ring total = real window (45s), NOT interval_sec (60s).
        XCTAssertEqual(
            vm.restDurationSeconds, 45,
            "EMOM rest ring total must be the log-to-boundary window, not interval_sec"
        )
        XCTAssertNotEqual(
            vm.restDurationSeconds, 60,
            "interval_sec as ring total is the pre-fix bug — ring starts depleted"
        )

        // Boundary clears the window-start tracker so a stale value
        // doesn't leak into the next interval's rest.
        clock.now = start.addingTimeInterval(60)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.state.route, .active)
    }

    /// A persisted mid-EMOM session restored on a clock past the block
    /// cap must normalize to `.complete`. The restore path runs the same
    /// `enterBlockTimerIfNeeded` as `start()` (so anchors are re-stamped
    /// defensively via the nil-guard) and the first `tickBlockTimer` call
    /// on a clock beyond `blockEndsAt` trips the complete route. This
    /// pins the invariant that a kill-then-relaunch after the block cap
    /// expired can't leave the VM mid-interval.
    func testEMOMRestoreNormalizesAfterKill() async throws {
        let start = Date(timeIntervalSince1970: 4_000_000)
        let clock = MutableBoundaryClock(now: start)
        let store = InMemorySessionStore()
        let (ctx, _) = makeEMOMContext(totalMinutes: 2)

        // First launch: start, log interval 1 mid-window, let persistence
        // land the state on the "disk".
        let vm1 = ExecutionViewModel(context: ctx, clock: clock, sessionStore: store)
        vm1.start()
        clock.now = start.addingTimeInterval(20)
        vm1.logSet(reps: 10, rir: nil)
        XCTAssertEqual(vm1.state.route, .rest)

        // Give the persistence pipeline a moment to drain.
        try await Task.sleep(nanoseconds: 30_000_000)

        // Kill + relaunch. The clock has advanced past the 2-minute block
        // cap while the app was gone.
        clock.now = start.addingTimeInterval(150)
        let vm2 = ExecutionViewModel(context: ctx, clock: clock, sessionStore: store)
        await vm2.restoreIfPossible()

        // `intervalAnchorAt` survives the round-trip.
        XCTAssertEqual(
            vm2.state.intervalAnchorAt?.timeIntervalSince1970,
            start.timeIntervalSince1970,
            "intervalAnchorAt must round-trip through persistence"
        )

        // First tick on the restored VM (simulates the RestView's periodic
        // tick after cold launch) flips to complete — the block cap has
        // already elapsed.
        vm2.tickBlockTimer()
        XCTAssertEqual(vm2.state.route, .complete,
            "restoration on a clock past blockEndsAt must route to complete")
    }

    /// Regression for qa-005: an 8-minute EMOM with 2 items rotating must
    /// capture all 8 intervals, not 7. Pre-fix: the user taps log 7 times
    /// across minutes 1..7, reaches the 8th interval at t=420 on `.active`,
    /// and fails to tap log before the block cap fires at t=480 — the
    /// block-cap complete check commits `.complete` with the 8th interval
    /// silently dropped. Server shows 7 set_logs (4 of one item + 3 of the
    /// other). Post-fix: `tickBlockTimer` auto-logs a placeholder `(reps: 0,
    /// rir: nil)` for the in-progress EMOM interval before flipping to
    /// `.complete`, mirroring Tabata's work-window auto-log pattern
    /// ("capture the most user data" per timing-modes.md).
    func testEMOM8MinuteWorkoutLogs8Intervals() {
        let start = Date(timeIntervalSince1970: 7_000_000)
        let clock = MutableBoundaryClock(now: start)
        let (ctx, _, _) = makeTwoItemEMOMContext(totalMinutes: 8)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 480,
            "8-minute EMOM blockEndsAt = start + 480"
        )

        // User taps log 7 times across minutes 1..7 — roughly matching
        // the qa-005 run where the 8th interval was never reached before
        // the cap. We clock each log mid-minute then jump the clock to
        // the next minute boundary to fire the rest→active advance via
        // `tickBlockTimer`.
        for interval in 1...7 {
            let intervalStart = Double(interval - 1) * 60
            clock.now = start.addingTimeInterval(intervalStart + 10)
            vm.logSet(reps: 10, rir: nil)
            // Advance clock to this interval's boundary + tick. Only fires
            // boundary advance when we're on `.rest`; an inline advance on
            // log (late log) means no rest to tick out of.
            clock.now = start.addingTimeInterval(intervalStart + 60)
            vm.tickBlockTimer()
        }

        // 7 user-driven logs committed so far — that's the pre-fix floor.
        XCTAssertEqual(totalLoggedSets(vm.state), 7,
            "7 user-driven logs before the final tick")

        // Clock rolls to the block cap without the user logging interval 8.
        // Pre-fix: `.complete` fires here with 7 rows, dropping interval 8.
        // Post-fix: the auto-log placeholder commits interval 8 first.
        clock.now = start.addingTimeInterval(480)
        vm.tickBlockTimer()

        XCTAssertEqual(totalLoggedSets(vm.state), 8,
            "an 8-minute 2-item EMOM must log 8 intervals, not 7 (qa-005)")
        XCTAssertEqual(vm.state.route, .complete,
            "EMOM must complete when total_minutes elapses")
    }

    /// qa-005 regression, second angle: a user who logs at T=479.5s — 0.5s
    /// before the 8-minute cap — must land the 8th interval's log. Before
    /// the fix this was already fine (the log committed, then the cap
    /// fired on the next tick), but the test pins it so a future refactor
    /// of the cap / log ordering can't resurrect the drop.
    func testEMOMFinalIntervalLoggedAtCapBoundary() {
        let start = Date(timeIntervalSince1970: 8_000_000)
        let clock = MutableBoundaryClock(now: start)
        let (ctx, _, _) = makeTwoItemEMOMContext(totalMinutes: 8)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // Walk 7 logs at minute-pace cadence so the cursor lands on the
        // 8th interval's position before the cap fires.
        for interval in 1...7 {
            let intervalStart = Double(interval - 1) * 60
            clock.now = start.addingTimeInterval(intervalStart + 10)
            vm.logSet(reps: 10, rir: nil)
            clock.now = start.addingTimeInterval(intervalStart + 60)
            vm.tickBlockTimer()
        }

        XCTAssertEqual(totalLoggedSets(vm.state), 7)

        // User logs at 479.5s — 0.5s before the cap. The log must commit
        // (non-zero rest window until boundary at t=480). The 8th log is
        // user-driven here, not auto-placeholdered — this path was already
        // correct pre-fix, but we pin it so a future cap/log-order refactor
        // can't resurrect the drop.
        clock.now = start.addingTimeInterval(479.5)
        vm.logSet(reps: 10, rir: nil)

        XCTAssertEqual(totalLoggedSets(vm.state), 8,
            "a log at T=479.5s (inside the 8th interval) must commit; nothing dropped")

        // Cap tick lands .complete; the user's 8th log is already in state,
        // and the auto-log guard must not double-commit.
        clock.now = start.addingTimeInterval(480)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.state.route, .complete)
        XCTAssertEqual(totalLoggedSets(vm.state), 8,
            "completion tick must not re-trigger or drop the boundary log")
    }
}

// MARK: - Helpers

/// Reference-typed clock whose `now` is mutable across VM boundaries.
/// File-local (mirrors `MutableClock` in ExecutionViewModelTests).
private final class MutableBoundaryClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

/// Minimal in-memory `SessionStore` for the restore round-trip. Mirrors
/// the pattern used in `ExecutionViewModelPersistencePipelineTests` — no
/// disk, no Actor indirection beyond what `SessionStore` already provides.
private actor InMemorySessionStore: SessionStore {
    private var bytes: Data?

    func load() async throws -> Data? {
        bytes
    }

    func save(_ data: Data) async throws {
        bytes = data
    }

    func clear() async throws {
        bytes = nil
    }
}
