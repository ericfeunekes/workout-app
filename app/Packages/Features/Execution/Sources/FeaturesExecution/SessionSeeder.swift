// SessionSeeder.swift
//
// Bootstrap a live `SessionState` from a `WorkoutContext`. Core/Session
// is pure — it does not know how to read a prescription blob. This is
// Features/Execution's job: parse each item's prescription once and
// materialize the per-item `SetPlan` rows that the reducer operates on.
//
// The seeder is also what `.save` uses to produce "fresh items" when the
// user finishes and wants a pristine state. For v0 save clears state
// entirely (the shell flips back to Today); we still expose the seeder
// here so a future "next workout in the same session" flow can reuse it.
//
// Seeding rules:
//   - `straight_sets` / rep_range / sets_detail / bodyweight / warmup /
//     cluster / percent_1rm — read `sets` from the per-item prescription.
//     This is the "set-major" shape: walk all sets of item 0, then item 1.
//   - `circuit` / `superset` / `for_time` — seed `block.rounds` SetPlan
//     rows per item. Item prescriptions typically carry `{reps, load_kg}`
//     (no top-level `sets` — the block carries the rounds). The seeder
//     pulls rounds from the Block directly via the private helper below.
//   - `tabata` — 8 rounds, hardcoded (spec § "tabata").
//   - `intervals` — `interval_count` rows for the single item (parsed from
//     block timing config).
//   - `continuous` — 1 row (single long effort).
//   - `amrap` / `emom` — 1 sentinel row per item. Rounds are unbounded at
//     authoring time; the block's wall-clock cap terminates execution.
//     The drivers surface setIndex as the "round" counter regardless of
//     how many rows are seeded.
//   - `rest` — zero items, so no SetPlan rows.
//
// Per-block advancement policy is computed alongside the set counts and
// stored on `SessionState.Structure.advancementByBlock`. The reducer reads
// it to pick `nextCursor` semantics (set-major vs round-robin). Keeping
// the policy on state means the reducer stays pure — no CoreDomain import,
// no WorkoutContext dependency inside SessionReducer.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public enum SessionSeeder {

    /// Sentinel row count for unbounded modes (AMRAP / EMOM). The wall
    /// clock terminates execution, not a set count; we seed a generous
    /// cap so the cursor never walks off the end before the time cap
    /// expires. 100 rounds × 60s = ~100 minutes — far longer than any
    /// realistic AMRAP or EMOM. The VM's `enterBlockTimerIfNeeded` and
    /// `tickBlockTimer` own the time-cap dispatch (route → `.complete`);
    /// these seeded rows exist purely so the round-robin cursor keeps
    /// walking until the clock terminates the block.
    public static let unboundedRoundsSentinel: Int = 100

    /// Produce the initial `SessionState` for a workout. Route is
    /// `.today`; cursor is (0, 0, 1); items are seeded per prescription.
    public static func seed(
        context: WorkoutContext,
        parser: PrescriptionParser = PrescriptionParser()
    ) -> SessionState {
        var items: [SessionState.ItemLog] = []
        var setsPerItem: [[Int]] = []
        var itemsPerBlock: [Int] = []
        var advancementByBlock: [SessionState.BlockAdvancement] = []

        for (bi, blockItems) in context.itemsByBlock.enumerated() {
            let block = context.block(at: bi)
            var perBlock: [Int] = []
            for item in blockItems {
                let sets = setRowsForBlock(
                    block: block,
                    item: item,
                    parser: parser
                )
                items.append(SessionState.ItemLog(
                    itemID: item.id,
                    autoregHeld: false,
                    sets: sets,
                    performedExerciseID: nil
                ))
                perBlock.append(sets.count)
            }
            setsPerItem.append(perBlock)
            itemsPerBlock.append(blockItems.count)
            advancementByBlock.append(advancement(for: block, itemCount: blockItems.count))
        }

        let structure = SessionState.Structure(
            itemsPerBlock: itemsPerBlock,
            setsPerItem: setsPerItem,
            advancementByBlock: advancementByBlock
        )

        return SessionState(
            workoutID: context.workout.id,
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: items,
            restEndsAt: nil,
            note: "",
            structure: structure
        )
    }

    /// Build per-item SetPlan rows from a prescription. All rows start
    /// with `done=false`, `adjust=nil`, `rir=nil`.
    ///
    /// Mode-aware block/item seeding lives in
    /// `SessionSeeder+RoundBased.swift` (`setRowsForBlock`,
    /// `itemRepsAndLoad`, `intervalCount`, `advancement`). The two
    /// entry points compose: `seed(context:)` calls `setRowsForBlock`,
    /// which falls through to this prescription-reader for set-major
    /// modes.
    public static func seedSets(
        for item: WorkoutItem,
        parser: PrescriptionParser = PrescriptionParser()
    ) -> [SetPlan] {
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            return setsFor(prescription: p)
        case .failure:
            // Graceful fallback — one placeholder set so the UI doesn't
            // hand the user an empty item. The parse error already ate
            // the authored values; we can't recover them.
            return [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: false, adjust: nil)]
        }
    }

    // MARK: - Private

    private static func setsFor(prescription: Prescription) -> [SetPlan] {
        switch prescription {
        case .straightSets(let sets, let reps, let loadKg, _, _, _, _):
            return seedStraightSets(sets: sets, reps: reps, loadKg: loadKg)
        case .bodyweight(let sets, let reps, _):
            return seedUniform(sets: sets, loadKg: 0, reps: reps)
        case .repRange(let sets, _, let repsMax, let loadKg, _, _):
            // Seed with the upper end of the range — authors pick the
            // range with the ceiling as the stretch goal.
            return seedUniform(sets: sets, loadKg: loadKg ?? 0, reps: repsMax)
        case .setsDetail(let details, _, _):
            return seedSetsDetail(details: details)
        case .percentOf1RM(let sets, let reps, _, _):
            // v0 does not resolve percent → kg here. The percent-of-1RM
            // slice will layer a resolver on top. Seed at loadKg=0 so
            // the UI at least shows the set counter.
            return seedUniform(sets: sets, loadKg: 0, reps: reps)
        case .cluster(let sets, let reps, let loadKg, _, _, _):
            return seedUniform(sets: sets, loadKg: loadKg, reps: reps)
        case .warmup(let sets, let reps, let loadKg):
            return seedUniform(sets: sets, loadKg: loadKg ?? 0, reps: reps)
        case .amrapToken, .empty:
            // Nothing structurally to seed — these items rely on the
            // block-level timing for their set count, which v0 does
            // not model.
            return []
        }
    }

    private static func seedStraightSets(
        sets: Int?,
        reps: RepCount?,
        loadKg: Double?
    ) -> [SetPlan] {
        let n = sets ?? 1
        let repCount = reps.flatMap { rc -> Int? in
            if case .count(let r) = rc { return r }
            return nil
        } ?? 0
        let load = loadKg ?? 0
        return (1...max(n, 1)).map {
            SetPlan(setIndex: $0, loadKg: load, reps: repCount, done: false, adjust: nil)
        }
    }

    static func seedUniform(
        sets: Int,
        loadKg: Double,
        reps: Int
    ) -> [SetPlan] {
        (1...max(sets, 1)).map {
            SetPlan(setIndex: $0, loadKg: loadKg, reps: reps, done: false, adjust: nil)
        }
    }

    private static func seedSetsDetail(details: [SetDetail]) -> [SetPlan] {
        details.enumerated().map { i, d in
            let reps: Int
            if case .count(let n) = d.reps { reps = n } else { reps = 0 }
            return SetPlan(
                setIndex: i + 1,
                loadKg: d.loadKg ?? 0,
                reps: reps,
                done: false,
                adjust: nil
            )
        }
    }
}
