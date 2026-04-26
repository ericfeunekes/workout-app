// EMOMBackgroundCatchupTests.swift
//
// qa-047 regression coverage. Two failure modes documented in the bug
// report — both addressed by `ExecutionViewModel.tickBlockTimer`:
//
//   1. **Multi-interval catchup.** iOS suspends `Timer.publish` while
//      the app is backgrounded; on foreground return the publisher
//      fires ONCE regardless of how many minute boundaries elapsed.
//      Pre-fix: the single tick advanced the cursor by one interval
//      and stopped, leaving the user staring at interval N while the
//      wall clock was already inside N+1 / N+2 / etc.
//
//   2. **Cap-out termination.** Pre-fix: `blockEndsAt` elapse
//      unconditionally dispatched `.complete` — workout-terminal,
//      ignoring any remaining blocks after the capped one. A 10-minute
//      EMOM as block 3 of 12 dropped blocks 4-11 entirely.
//
// Post-fix: `catchUpEMOMBoundaries` walks every overdue boundary in a
// single tick; `routeOutOfCappedBlock` advances to the next block if
// one exists, routing to `.complete` only when the capped block is
// trailing.
//
// Kept separate from `EMOMBoundaryTests.swift` so the parent file
// stays under SwiftLint's `file_length` / `type_body_length` caps.

import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class EMOMBackgroundCatchupTests: XCTestCase {

    // MARK: - Fixtures

    /// Two-item EMOM fixture, copied from `EMOMBoundaryTests` to keep
    /// this file self-contained (shared fixtures live in the other
    /// file; duplicating here is simpler than exporting a helper).
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
                exerciseAID: Exercise(id: exerciseAID, name: "KB Swing"),
                exerciseBID: Exercise(id: exerciseBID, name: "Push Press"),
            ]
        )
        return (ctx, itemA: itemAID, itemB: itemBID)
    }

    /// Single-item EMOM fixture for the trailing-cap-out case.
    private func makeEMOMContext(totalMinutes: Int) -> WorkoutContext {
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
            timingConfigJSON: #"{"interval_sec":60,"total_minutes":\#(totalMinutes)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":10,"load_kg":24}"#
        )
        return WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "KB Swing")]
        )
    }

    /// Two-block fixture: a short EMOM followed by a straight-sets
    /// block. Used to prove the cap-out advances into the next block
    /// rather than terminating the workout.
    private func makeTwoBlockWorkoutEMOMThenStraightSets()
        -> (WorkoutContext, straightSetsItem: UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let emomBlockID = UUID()
        let ssBlockID = UUID()
        let emomExerciseID = UUID()
        let ssExerciseID = UUID()
        let emomItemID = UUID()
        let ssItemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "emom-then-ss",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let emomBlock = Block(
            id: emomBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":60,"total_minutes":2}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let ssBlock = Block(
            id: ssBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let emomItem = WorkoutItem(
            id: emomItemID, blockID: emomBlockID, position: 0,
            exerciseID: emomExerciseID,
            prescriptionJSON: #"{"reps":10,"load_kg":24}"#
        )
        let ssItem = WorkoutItem(
            id: ssItemID, blockID: ssBlockID, position: 0,
            exerciseID: ssExerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [emomBlock, ssBlock],
            itemsByBlock: [[emomItem], [ssItem]],
            exercises: [
                emomExerciseID: Exercise(id: emomExerciseID, name: "KB Swing"),
                ssExerciseID: Exercise(id: ssExerciseID, name: "Bench Press"),
            ]
        )
        return (ctx, straightSetsItem: ssItemID)
    }

    /// Count of all completed (done) SetPlan rows across every item.
    private func totalLoggedSets(_ state: SessionState) -> Int {
        state.items.reduce(0) { acc, item in
            acc + item.sets.filter { $0.done }.count
        }
    }

    // MARK: - Tests

    /// qa-047 — multi-interval catchup in a single tick. Jump the clock
    /// 150s (past boundaries at 60 and 120) and fire the tick exactly
    /// once: the cursor must walk through BOTH boundaries, not just
    /// one. Missed intervals advance the schedule without writing fake
    /// 0-rep completed sets.
    func testEMOMTickCatchesUpMultipleIntervalsAfterBackground() {
        let start = Date(timeIntervalSince1970: 11_000_000)
        let clock = MutableCatchupClock(now: start)
        // 12-minute EMOM so the catchup leaves plenty of block runway
        // — block cap is t=720, far beyond t=150.
        let (ctx, itemA, itemB) = makeTwoItemEMOMContext(totalMinutes: 12)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        XCTAssertEqual(vm.state.route, .active)

        // 150s elapsed → boundaries 1 (60s) and 2 (120s) have both
        // passed; the cursor walks through BOTH in one tick.
        clock.now = start.addingTimeInterval(150)
        vm.tickBlockTimer()

        // A 2-item EMOM cursor path: (0, 0, 1) → (0, 1, 1) → (0, 0, 2),
        // i.e. interval 3 is authored as item 0, round 2. Interval 3's
        // boundary is at t=180 — past `now` at t=150, so the loop
        // stops there.
        XCTAssertEqual(vm.state.cursor.itemIndex, 0,
            "after catching up 2 boundaries, cursor wraps round-robin to item 0 of round 2")
        XCTAssertEqual(vm.state.cursor.setIndex, 2,
            "after catching up 2 boundaries, setIndex bumps to round 2")
        XCTAssertEqual(vm.state.route, .active,
            "advance lands on .active for the next interval")
        // No logs are fabricated for skipped intervals. Interval 1 →
        // item A and interval 2 → item B both remain pending.
        XCTAssertEqual(totalLoggedSets(vm.state), 0,
            "missed EMOM boundaries advance without fake completed sets")
        let logA = vm.state.items.first { $0.itemID == itemA }
        let logB = vm.state.items.first { $0.itemID == itemB }
        XCTAssertEqual(logA?.sets.filter { $0.done }.count, 0,
            "interval 1 remains pending")
        XCTAssertEqual(logB?.sets.filter { $0.done }.count, 0,
            "interval 2 remains pending")
    }

    /// qa-047 — round-robin correctness across catchup. Each advance
    /// in the catchup loop goes through `nextCursor`, which reads
    /// `structure.advancementByBlock` and picks round-robin for EMOM.
    /// Pre-fix observation: "setIndex bumped 1→2→3, itemIndex stayed
    /// 0" would mean the walk used `setMajor` semantics. Post-fix: the
    /// cursor alternates items across the round-robin walk.
    func testEMOMMultiItemAlternatesOnEachBoundaryTick() {
        let start = Date(timeIntervalSince1970: 12_000_000)
        let clock = MutableCatchupClock(now: start)
        let (ctx, _, _) = makeTwoItemEMOMContext(totalMinutes: 8)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // Jump 4 full intervals — the cursor should walk
        // (0, 0, 1) → (0, 1, 1) → (0, 0, 2) → (0, 1, 2) → (0, 0, 3).
        // Clock at t=240 means boundaries 1, 2, 3, 4 all elapsed;
        // boundary 5 is at t=300, so the walk stops at interval 5's
        // cursor position: ordinal 5 → setIndex 3, itemIndex 0.
        clock.now = start.addingTimeInterval(240)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.cursor.setIndex, 3,
            "catchup walked 4 boundaries; cursor lands on interval 5 (round 3)")
        XCTAssertEqual(vm.state.cursor.itemIndex, 0,
            "round 3 starts at item 0 — round-robin correctness across catchup")
        XCTAssertEqual(totalLoggedSets(vm.state), 0,
            "4 skipped intervals advance without fake completed sets")
    }

    /// qa-047 — an EMOM block cap expiring with remaining blocks must
    /// advance the cursor into the NEXT block, not terminate the
    /// workout. Pre-fix: `apply([.complete])` fired unconditionally on
    /// cap elapse, dropping every block after the EMOM. Post-fix:
    /// `routeOutOfCappedBlock` checks for a next block and jumps the
    /// cursor to its first position; `.complete` only fires on a
    /// trailing capped block.
    func testEMOMCapDoesNotJumpToNextBlocksComplete() {
        let start = Date(timeIntervalSince1970: 13_000_000)
        let clock = MutableCatchupClock(now: start)
        let (ctx, ssItemID) = makeTwoBlockWorkoutEMOMThenStraightSets()
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // EMOM block entered: anchor stamped, blockEndsAt stamped.
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 120,
            "2-minute EMOM blockEndsAt = start + 120"
        )

        // Roll the clock past the 2-minute cap and tick.
        clock.now = start.addingTimeInterval(120)
        vm.tickBlockTimer()

        // Cursor must land on the first position of block 1, NOT on
        // `.complete`. The workout has a straight_sets block waiting
        // behind the setup transition.
        XCTAssertEqual(vm.state.route, .transition,
            "cap-out must land on transition for the next block, not .complete")
        XCTAssertEqual(vm.state.cursor.blockIndex, 1,
            "cursor advances from block 0 (EMOM) into block 1 (straight_sets)")
        XCTAssertEqual(vm.state.cursor.itemIndex, 0,
            "cursor enters the new block at item 0")
        XCTAssertEqual(vm.state.cursor.setIndex, 1,
            "cursor enters the new block at set 1")
        vm.beginBlockTransition()
        XCTAssertEqual(vm.state.route, .active)

        // Timer anchors for the capped block are cleared; straight_sets
        // is not time-capped so `blockEndsAt` stays nil.
        XCTAssertNil(vm.state.blockEndsAt,
            "straight_sets block is not time-capped — blockEndsAt must be cleared")
        XCTAssertNil(vm.state.intervalAnchorAt,
            "intervalAnchorAt cleared on block transition")

        // Sanity: the straight_sets item has its seeded pending sets,
        // none logged yet.
        let ssLog = vm.state.items.first { $0.itemID == ssItemID }
        XCTAssertNotNil(ssLog,
            "straight_sets block's ItemLog is visible now that cursor moved in")
        XCTAssertEqual(ssLog?.sets.count, 3,
            "straight_sets item seeded 3 pending sets")
        XCTAssertTrue(ssLog?.sets.allSatisfy { !$0.done } ?? false,
            "no logs in the new block yet — the user hasn't touched it")
    }

    /// qa-047 companion — the trailing-block cap-out path. When the
    /// capped block is the LAST block, `routeOutOfCappedBlock` must
    /// still dispatch `.complete`; there's nowhere else to go. Pins
    /// the branch so a future refactor of the cap-out logic doesn't
    /// drop the workout-terminal case.
    func testEMOMCapRoutesToCompleteWhenNoNextBlock() {
        let start = Date(timeIntervalSince1970: 13_500_000)
        let clock = MutableCatchupClock(now: start)
        let ctx = makeEMOMContext(totalMinutes: 2)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertEqual(vm.state.cursor.blockIndex, 0)

        clock.now = start.addingTimeInterval(120)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .complete,
            "trailing EMOM block cap-out routes to .complete — no next block to roll into")
    }
}

// MARK: - Helpers

/// Reference-typed mutable clock, file-local to avoid colliding with
/// the similarly-named helper in `EMOMBoundaryTests.swift`.
private final class MutableCatchupClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
