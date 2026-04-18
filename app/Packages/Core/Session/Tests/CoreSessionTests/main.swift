// main.swift — entry point for `swift run CoreSessionTests`.
//
// Covers every mutation in SessionMutation against the rules in
// app/README.md § "Autoregulation"/"Tap-to-edit"/"Swap"/"Persistence"
// and docs/prescription.md § "Autoregulation · Edits don't retrigger".

import Foundation
import CoreSession
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

let itemA = UUID()
let itemB = UUID()
let workoutID = UUID()
let exerciseAlt = UUID()

func pristineSets(loadKg: Double = 100.0, reps: Int = 5, count: Int = 3) -> [SetPlan] {
    (1...count).map { i in
        SetPlan(setIndex: i, loadKg: loadKg, reps: reps, done: false, adjust: nil, rir: nil)
    }
}

/// Build a baseline state with two items (itemA, itemB), each with 3 sets,
/// all pending, route=today, cursor at (0, 0, 1). Tests layer on top.
func makeBaselineState() -> SessionState {
    SessionState(
        workoutID: workoutID,
        route: .today,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets()),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets()),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]]
        )
    )
}

// ---------------------------------------------------------------------------
// 1. start: today → active
// ---------------------------------------------------------------------------
runCase("start · today → active") {
    let s0 = makeBaselineState()
    try expectEqual(s0.route, .today)
    let s1 = SessionReducer.reduce(s0, .start)
    try expectEqual(s1.route, .active)
    // Cursor unchanged (already at first set by construction).
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
}

// ---------------------------------------------------------------------------
// 2. logSet · marks target set done=true with reps+rir; other sets untouched.
// ---------------------------------------------------------------------------
runCase("logSet · target set done=true, reps+rir set; other sets unchanged") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: itemA, setIndex: 2, loggedReps: 4, loggedRir: 1)
    )

    let setsA = s1.items.first(where: { $0.itemID == itemA })!.sets
    try expectEqual(setsA[0].done, false)
    try expectEqual(setsA[0].reps, 5)
    try expectEqual(setsA[0].rir, nil)
    try expectEqual(setsA[1].done, true)
    try expectEqual(setsA[1].reps, 4)
    try expectEqual(setsA[1].rir, 1)
    try expectEqual(setsA[2].done, false)
    try expectEqual(setsA[2].rir, nil)

    // itemB entirely untouched.
    let setsB = s1.items.first(where: { $0.itemID == itemB })!.sets
    try expectEqual(setsB, pristineSets())
}

runCase("logSet · rir nil is preserved (user skipped picker)") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: nil)
    )
    let setsA = s1.items.first(where: { $0.itemID == itemA })!.sets
    try expectEqual(setsA[0].done, true)
    try expectEqual(setsA[0].reps, 5)
    try expectEqual(setsA[0].rir, nil)
}

// ---------------------------------------------------------------------------
// 3. editPastSet · preserves done=true, updates fields, sets adjust=.manual.
// ---------------------------------------------------------------------------
runCase("editPastSet · done=true preserved, fields updated, adjust=.manual") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    s = SessionReducer.reduce(
        s,
        .editPastSet(
            itemID: itemA,
            setIndex: 1,
            loadKg: 105.0,
            reps: 6,
            rir: 3
        )
    )
    let set = s.items.first(where: { $0.itemID == itemA })!.sets[0]
    try expectEqual(set.done, true)
    try expectEqual(set.loadKg, 105.0)
    try expectEqual(set.reps, 6)
    try expectEqual(set.rir, 3)
    try expectEqual(set.adjust, .manual)
}

// ---------------------------------------------------------------------------
// 4. editPastSet · leaves adjust=.manual if already .manual.
// ---------------------------------------------------------------------------
runCase("editPastSet · adjust stays .manual when already .manual") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    // First edit stamps .manual
    s = SessionReducer.reduce(
        s,
        .editPastSet(itemID: itemA, setIndex: 1, loadKg: 110.0, reps: nil, rir: nil)
    )
    try expectEqual(s.items[0].sets[0].adjust, .manual)
    // Second edit — adjust stays .manual (idempotent)
    s = SessionReducer.reduce(
        s,
        .editPastSet(itemID: itemA, setIndex: 1, loadKg: nil, reps: 7, rir: nil)
    )
    try expectEqual(s.items[0].sets[0].adjust, .manual)
    try expectEqual(s.items[0].sets[0].loadKg, 110.0)
    try expectEqual(s.items[0].sets[0].reps, 7)
}

// ---------------------------------------------------------------------------
// 5. editPendingSet · non-done set, updates fields, marks .manual.
// ---------------------------------------------------------------------------
runCase("editPendingSet · non-done set updated, adjust=.manual") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .editPendingSet(itemID: itemA, setIndex: 2, loadKg: 102.5, reps: 6)
    )
    let set = s.items[0].sets[1]
    try expectEqual(set.done, false)
    try expectEqual(set.loadKg, 102.5)
    try expectEqual(set.reps, 6)
    try expectEqual(set.adjust, .manual)
}

// ---------------------------------------------------------------------------
// 6. applyAutoregProposal · flips .up/.down, preserves .manual and done.
//    (Re-tests CoreAutoreg.apply via the reducer.)
// ---------------------------------------------------------------------------
runCase("applyAutoregProposal · flips non-manual non-done; preserves .manual + done") {
    // Build an item with explicit set shapes: [done=true .up, pending nil,
    // pending .manual, pending nil].
    let sets = [
        SetPlan(setIndex: 1, loadKg: 100.0, reps: 5, done: true,  adjust: .up,     rir: 2),
        SetPlan(setIndex: 2, loadKg: 100.0, reps: 5, done: false, adjust: nil,     rir: nil),
        SetPlan(setIndex: 3, loadKg: 110.0, reps: 5, done: false, adjust: .manual, rir: nil),
        SetPlan(setIndex: 4, loadKg: 100.0, reps: 5, done: false, adjust: nil,     rir: nil),
    ]
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2),
        items: [SessionState.ItemLog(itemID: itemA, sets: sets)],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(itemsPerBlock: [1], setsPerItem: [[4]])
    )
    let proposal = AutoregProposal(
        direction: .down,
        newLoadKg: 97.5,
        reason: .undershootReps(prescribed: 5, actual: 3, threshold: 2)
    )
    let s1 = SessionReducer.reduce(
        s0,
        .applyAutoregProposal(itemID: itemA, proposal: proposal)
    )
    let out = s1.items[0].sets
    // done stays, adjust stays .up, load unchanged
    try expectEqual(out[0].done, true)
    try expectEqual(out[0].adjust, .up)
    try expectEqual(out[0].loadKg, 100.0)
    // pending nil → .down, load bumped
    try expectEqual(out[1].adjust, .down)
    try expectEqual(out[1].loadKg, 97.5)
    // .manual preserved
    try expectEqual(out[2].adjust, .manual)
    try expectEqual(out[2].loadKg, 110.0)
    // pending nil → .down
    try expectEqual(out[3].adjust, .down)
    try expectEqual(out[3].loadKg, 97.5)
}

// ---------------------------------------------------------------------------
// 7. holdAutoreg · sets autoregHeld=true; Core/Session stores the flag and
//    still applies a proposal if one is dispatched (the decision to skip
//    Autoreg.propose lives in Features layer — documented behavior).
// ---------------------------------------------------------------------------
runCase("holdAutoreg · sets flag; idempotent; applyAutoregProposal still mutates") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))
    try expectEqual(s.items[0].autoregHeld, true)
    try expectEqual(s.items[1].autoregHeld, false, "other item unaffected")

    // Idempotent.
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))
    try expectEqual(s.items[0].autoregHeld, true)

    // Core/Session does not block `applyAutoregProposal` on held — the
    // Features layer is expected to never propose when held. If the
    // caller does dispatch one anyway, the reducer applies it.
    let proposal = AutoregProposal(
        direction: .up,
        newLoadKg: 102.5,
        reason: .overshoot(rirLogged: 4, targetRir: 2, threshold: 2)
    )
    s = SessionReducer.reduce(s, .applyAutoregProposal(itemID: itemA, proposal: proposal))
    try expectEqual(s.items[0].sets[0].loadKg, 102.5)
    try expectEqual(s.items[0].sets[0].adjust, .up)
}

// ---------------------------------------------------------------------------
// 8. swap · sets performedExerciseID on target; other items unchanged;
//    does not reset autoregHeld; does not modify logged sets.
// ---------------------------------------------------------------------------
runCase("swap · target item gets performedExerciseID; other untouched; held preserved; logs preserved") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )

    let s1 = SessionReducer.reduce(s, .swap(itemID: itemA, toExerciseID: exerciseAlt))
    try expectEqual(s1.items[0].performedExerciseID, exerciseAlt)
    try expectEqual(s1.items[0].autoregHeld, true, "hold preserved across swap")
    // Logged set preserved.
    try expectEqual(s1.items[0].sets[0].done, true)
    try expectEqual(s1.items[0].sets[0].reps, 5)
    try expectEqual(s1.items[0].sets[0].rir, 2)
    // Other item untouched.
    try expectEqual(s1.items[1].performedExerciseID, nil)
}

// 8b. swap + overrides · non-done sets pick up load/reps, logged set
//     preserved, target_rir lands on ItemLog.overrides for the driver.
runCase("swap+overrides · remaining sets updated; logged set preserved; target_rir stored") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    let overrides = AlternativeOverrides(reps: 8, loadKg: 70, targetRir: 3)
    let s1 = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    try expectEqual(s1.items[0].performedExerciseID, exerciseAlt)
    try expectEqual(s1.items[0].overrides?.reps, 8)
    try expectEqual(s1.items[0].overrides?.loadKg, 70)
    try expectEqual(s1.items[0].overrides?.targetRir, 3)
    // Logged set untouched.
    try expectEqual(s1.items[0].sets[0].done, true)
    try expectEqual(s1.items[0].sets[0].reps, 5)
    try expectEqual(s1.items[0].sets[0].loadKg, 100.0)
    // Remaining sets carry the override.
    try expectEqual(s1.items[0].sets[1].reps, 8)
    try expectEqual(s1.items[0].sets[1].loadKg, 70.0)
    try expectEqual(s1.items[0].sets[2].reps, 8)
    try expectEqual(s1.items[0].sets[2].loadKg, 70.0)
    // Other item entirely untouched.
    try expectEqual(s1.items[1].overrides, nil)
}

// 8c. swap with empty-overrides payload is equivalent to a pure swap —
//     the overrides field stays nil so drivers don't branch.
runCase("swap+empty overrides · overrides field stays nil") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    let empty = AlternativeOverrides()
    s = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: empty)
    )
    try expectEqual(s.items[0].performedExerciseID, exerciseAlt)
    try expectEqual(s.items[0].overrides, nil)
    // Sets unchanged.
    try expectEqual(s.items[0].sets[0].loadKg, 100.0)
    try expectEqual(s.items[0].sets[0].reps, 5)
}

// 8d. swap+overrides · a .manual set is preserved (user's edit wins).
runCase("swap+overrides · manual set preserved, other remaining sets overridden") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    // User manually edited set 2.
    s = SessionReducer.reduce(
        s,
        .editPendingSet(itemID: itemA, setIndex: 2, loadKg: 90.0, reps: nil)
    )
    try expectEqual(s.items[0].sets[1].loadKg, 90.0)
    try expectEqual(s.items[0].sets[1].adjust, .manual)
    let overrides = AlternativeOverrides(loadKg: 70)
    let s1 = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    // Set 1: non-manual, non-done → overridden.
    try expectEqual(s1.items[0].sets[0].loadKg, 70.0)
    // Set 2: manual → preserved.
    try expectEqual(s1.items[0].sets[1].loadKg, 90.0)
    try expectEqual(s1.items[0].sets[1].adjust, .manual)
    // Set 3: non-manual, non-done → overridden.
    try expectEqual(s1.items[0].sets[2].loadKg, 70.0)
}

// ---------------------------------------------------------------------------
// 9. enterRest · sets restEndsAt = now + durationSec.
// ---------------------------------------------------------------------------
runCase("enterRest · sets restEndsAt = now + 180") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s = SessionReducer.reduce(s, .enterRest(durationSec: 180, now: now))
    try expectEqual(s.route, .rest)
    try expectEqual(s.restEndsAt, now.addingTimeInterval(180))
}

// ---------------------------------------------------------------------------
// 10. advanceFromRest · last set of last item of last block → complete,
//     restEndsAt = nil.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · last-set-last-item-last-block → .complete, restEndsAt=nil") {
    // Build a one-block, one-item, one-set state with cursor on that set
    // and restEndsAt set.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2)]
            )
        ],
        restEndsAt: now.addingTimeInterval(60),
        note: "",
        structure: SessionState.Structure(itemsPerBlock: [1], setsPerItem: [[1]])
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.route, .complete)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 11. advanceFromRest · intermediate set → cursor advances, route=.active,
//     restEndsAt=nil.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · intermediate set → cursor.setIndex advances, route=.active") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s.route = .rest
    s.restEndsAt = now.addingTimeInterval(60)
    // cursor is (0, 0, 1) — advance should go to (0, 0, 2)
    let s1 = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s1.route, .active)
    try expectEqual(s1.cursor.setIndex, 2)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.restEndsAt, nil)
}

runCase("advanceFromRest · last set of current item → next item, setIndex=1") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s.route = .rest
    s.restEndsAt = now.addingTimeInterval(60)
    // move cursor to last set of first item (item 0, set 3)
    s.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 3)
    let s1 = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 1)
    try expectEqual(s1.cursor.setIndex, 1)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.route, .active)
}

// ---------------------------------------------------------------------------
// 12. save · returns pristine state with route=.today, sets un-done.
// ---------------------------------------------------------------------------
runCase("save · returns pristine state with route=.today, note cleared, sets fresh") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    s = SessionReducer.reduce(s, .appendNote("felt good"))
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))

    let freshItems = [
        SessionState.ItemLog(itemID: itemA, autoregHeld: false, sets: pristineSets()),
        SessionState.ItemLog(itemID: itemB, autoregHeld: false, sets: pristineSets()),
    ]
    let freshStructure = SessionState.Structure(
        itemsPerBlock: [2],
        setsPerItem: [[3, 3]]
    )
    let s1 = SessionReducer.reduce(
        s,
        .save(freshItems: freshItems, freshStructure: freshStructure)
    )

    try expectEqual(s1.route, .today)
    try expectEqual(s1.note, "")
    try expectEqual(s1.restEndsAt, nil)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
    try expectEqual(s1.workoutID, workoutID, "workoutID preserved")
    try expectEqual(s1.items[0].sets[0].done, false, "fresh sets un-done")
    try expectEqual(s1.items[0].autoregHeld, false, "hold cleared")
}

// ---------------------------------------------------------------------------
// 13. appendNote · concatenates with newline separator.
// ---------------------------------------------------------------------------
runCase("appendNote · first append replaces empty; subsequent appends add newline") {
    var s = makeBaselineState()
    try expectEqual(s.note, "")
    s = SessionReducer.reduce(s, .appendNote("felt strong"))
    try expectEqual(s.note, "felt strong")
    s = SessionReducer.reduce(s, .appendNote("left shoulder twinge"))
    try expectEqual(s.note, "felt strong\nleft shoulder twinge")
}

runCase("appendNote · empty input is a no-op") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .appendNote("start"))
    s = SessionReducer.reduce(s, .appendNote(""))
    try expectEqual(s.note, "start")
}

// ---------------------------------------------------------------------------
// 14. Unknown-item mutations are no-ops.
// ---------------------------------------------------------------------------
runCase("no-op · logSet with unknown itemID leaves state unchanged") {
    let unknown = UUID()
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: unknown, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    try expectEqual(s0, s1)
}

runCase("no-op · logSet with unknown setIndex leaves state unchanged") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: itemA, setIndex: 99, loggedReps: 5, loggedRir: 2)
    )
    try expectEqual(s0, s1)
}

runCase("no-op · holdAutoreg / swap / editPendingSet with unknown itemID unchanged") {
    let unknown = UUID()
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(s0, .holdAutoreg(itemID: unknown))
    try expectEqual(s0, s1)
    let s2 = SessionReducer.reduce(s0, .swap(itemID: unknown, toExerciseID: exerciseAlt))
    try expectEqual(s0, s2)
    let s3 = SessionReducer.reduce(
        s0,
        .editPendingSet(itemID: unknown, setIndex: 1, loadKg: 50, reps: 5)
    )
    try expectEqual(s0, s3)
}

// ---------------------------------------------------------------------------
// Bonus: editPastSet on a pending set is a no-op (wrong mutation path);
//        editPendingSet on a done set is a no-op.
// ---------------------------------------------------------------------------
runCase("no-op · editPastSet on pending set unchanged") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .editPastSet(itemID: itemA, setIndex: 1, loadKg: 999, reps: 99, rir: 5)
    )
    try expectEqual(s0, s1)
}

runCase("no-op · editPendingSet on done set unchanged") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    let s1 = SessionReducer.reduce(
        s,
        .editPendingSet(itemID: itemA, setIndex: 1, loadKg: 999, reps: 99)
    )
    try expectEqual(s, s1)
}

// ---------------------------------------------------------------------------
// 15. complete · route → .complete; state otherwise preserved.
// ---------------------------------------------------------------------------
runCase("complete · route flips to .complete, log preserved") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2)
    )
    let s1 = SessionReducer.reduce(s, .complete)
    try expectEqual(s1.route, .complete)
    try expectEqual(s1.items[0].sets[0].done, true)
    try expectEqual(s1.items[0].sets[0].reps, 5)
}

// ---------------------------------------------------------------------------
// 16. advanceFromRest · last set of a work block → next block is zero-item
//     (standalone rest) → cursor LANDS on the rest block (blockIndex+1,
//     itemIndex=0, setIndex=1). The view model reroutes to `.rest` on
//     arrival — the reducer itself sets route=.active here. This matches
//     the Decision A1 cursor model documented in `RestBlockDriver`.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · last set of work block → cursor lands on zero-item rest block") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Work block (1 item, 2 sets) → rest block (zero items) → work block
    // (1 item, 2 sets). Cursor on block 0 last set.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [
                    SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2),
                    SetPlan(setIndex: 2, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2),
                ]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [
                    SetPlan(setIndex: 1, loadKg: 60, reps: 8, done: false, adjust: nil, rir: nil),
                    SetPlan(setIndex: 2, loadKg: 60, reps: 8, done: false, adjust: nil, rir: nil),
                ]
            ),
        ],
        restEndsAt: now.addingTimeInterval(60),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 0, 1],
            setsPerItem: [[2], [], [2]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    // Lands on the rest block (b=1), not skipped.
    try expectEqual(s1.cursor.blockIndex, 1)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
    // The reducer does not know about "rest block" — it sets route=.active
    // on every advance that produces a new cursor. The ExecutionViewModel
    // re-flips to `.rest` on zero-item landings (see `RestBlockDriver`).
    try expectEqual(s1.route, .active)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 17. advanceFromRest · FROM a zero-item rest block → next work block.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · from zero-item rest block → next block, setIndex=1") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Same 3-block structure; cursor is currently on the rest block.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 1, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2)]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [SetPlan(setIndex: 1, loadKg: 60, reps: 8, done: false, adjust: nil, rir: nil)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 0, 1],
            setsPerItem: [[1], [], [1]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 2)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
    try expectEqual(s1.route, .active)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 18. advanceFromRest · FROM a zero-item rest block that is the LAST block
//     → complete.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · from trailing zero-item rest block → .complete") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 1, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 0],
            setsPerItem: [[1], []]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.route, .complete)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 19. advanceFromRest · round-robin mode — after logging an item, cursor
//     moves to the NEXT item in the same round (setIndex unchanged).
//     Used by circuit / superset / amrap / emom / forTime / tabata.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · round-robin: (item 0, round 1) → (item 1, round 1)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // 3 items × 3 rounds circuit. Cursor at item 0, round 1.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [3],
            setsPerItem: [[3, 3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.cursor.itemIndex, 1, "next item in same round")
    try expectEqual(s1.cursor.setIndex, 1, "same round")
    try expectEqual(s1.route, .active)
}

// ---------------------------------------------------------------------------
// 20. advanceFromRest · round-robin mode — last item of round N → first
//     item of round N+1 (setIndex bumps).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · round-robin: (last item, round N) → (item 0, round N+1)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // 2 items × 3 rounds superset. Cursor at item 1 (last), round 2.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 2),
        items: [
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(120),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 0, "wrap to first item")
    try expectEqual(s1.cursor.setIndex, 3, "bump round")
    try expectEqual(s1.route, .active)
}

// ---------------------------------------------------------------------------
// 21. advanceFromRest · round-robin mode — last item of last round →
//     complete (no next block).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · round-robin: last item of last round → .complete") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 3),
        items: [
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.route, .complete)
}

// ---------------------------------------------------------------------------
// 22. advanceFromRest · set-major preserves legacy straight-sets walk
//     (item 0 set 1 → item 0 set 2, ..., item 0 set N → item 1 set 1).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · set-major: (item 0, set N) → (item 1, set 1)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s.route = .rest
    s.restEndsAt = now.addingTimeInterval(60)
    s.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 3)
    // makeBaselineState defaults to `.setMajor` via the structure
    // default; verify by leaving advancementByBlock unspecified.
    let s1 = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 1)
    try expectEqual(s1.cursor.setIndex, 1)
}

// ---------------------------------------------------------------------------
// 23. advanceFromRest · blockEndsAt / workEndsAt cleared on block change.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · blockEndsAt+workEndsAt cleared on block change") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Two blocks — block 0 (1 item, 1 set) with both timers set, then
    // block 1 (1 item, 1 set). After advancing from block 0's last set,
    // the cursor should land on block 1 and both timers should be cleared.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: true, adjust: nil, rir: nil)]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: false, adjust: nil, rir: nil)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        blockEndsAt: now.addingTimeInterval(600),
        workEndsAt: now.addingTimeInterval(20),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 1],
            setsPerItem: [[1], [1]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 1, "landed on next block")
    try expectEqual(s1.blockEndsAt, nil, "blockEndsAt cleared on block change")
    try expectEqual(s1.workEndsAt, nil, "workEndsAt cleared on block change")
}

// ---------------------------------------------------------------------------
// 24. enterRest · clears workEndsAt (Tabata's 20s window ended).
// ---------------------------------------------------------------------------
runCase("enterRest · clears workEndsAt") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s.workEndsAt = now.addingTimeInterval(20)
    s = SessionReducer.reduce(s, .enterRest(durationSec: 10, now: now))
    try expectEqual(s.workEndsAt, nil)
    try expectEqual(s.restEndsAt, now.addingTimeInterval(10))
}

reportAndExit()
