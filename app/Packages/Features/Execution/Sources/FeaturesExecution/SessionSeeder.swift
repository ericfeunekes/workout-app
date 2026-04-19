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
    ///
    /// Tabata collapse: per `docs/prescription.md` § "tabata" the mode is
    /// strictly single-item ("one exercise"). Authors cannot compose a
    /// multi-item tabata — the driver + cursor pair disagree on per-item
    /// vs global rounds and the active screen ends up out of sync with
    /// what just got auto-logged. When the pulled context carries > 1 item
    /// for a tabata block, we collapse to item[0]: only the first item is
    /// seeded (SetPlan rows + ItemLog), `itemsPerBlock[blockIndex] == 1`,
    /// and extras are dropped. Paired fix in `TabataDriver.activeContent`
    /// always resolves `blockItems[0]` so the render matches the seed.
    /// Callers that care about the collapse (the VM, to emit telemetry)
    /// use `seedWithNormalization` instead.
    public static func seed(
        context: WorkoutContext,
        parser: PrescriptionParser = PrescriptionParser()
    ) -> SessionState {
        seedWithNormalization(context: context, parser: parser).state
    }

    /// Same seed as `seed(context:)`, but also returns a manifest of any
    /// normalization drops (e.g. a multi-item tabata collapsed to its
    /// first item). The VM uses this variant so it can emit telemetry
    /// for each drop at init time — the pure `seed(context:)` path stays
    /// side-effect-free for test callers that don't care about drops.
    public static func seedWithNormalization(
        context: WorkoutContext,
        parser: PrescriptionParser = PrescriptionParser()
    ) -> SeedResult {
        var accum = SeedAccumulator()
        for (bi, rawBlockItems) in context.itemsByBlock.enumerated() {
            accum.append(seedBlock(
                rawBlockItems: rawBlockItems,
                blockIndex: bi,
                block: context.block(at: bi),
                parser: parser
            ))
        }
        let state = SessionState(
            workoutID: context.workout.id,
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: accum.items,
            restEndsAt: nil,
            note: "",
            structure: SessionState.Structure(
                itemsPerBlock: accum.itemsPerBlock,
                setsPerItem: accum.setsPerItem,
                advancementByBlock: accum.advancementByBlock
            )
        )
        // Debug-only defense: the paired fix in `TabataDriver.activeContent`
        // depends on `itemsPerBlock[bi] == 1` after a collapse. Release
        // builds omit the assert; authoring regressions still surface
        // through the telemetry event.
        assert(
            accum.collapses.allSatisfy { state.structure.itemsPerBlock[$0.blockIndex] == 1 },
            "tabata collapse must leave exactly one seeded item per affected block"
        )
        return SeedResult(state: state, tabataCollapses: accum.collapses)
    }

    /// Seed one block: normalize its items, produce ItemLogs + set counts,
    /// and emit any collapse record. Extracted so `seedWithNormalization`
    /// stays under SwiftLint's `function_body_length`.
    private static func seedBlock(
        rawBlockItems: [WorkoutItem],
        blockIndex: Int,
        block: Block?,
        parser: PrescriptionParser
    ) -> BlockSeed {
        let blockItems = normalizeBlockItems(rawBlockItems, block: block)
        let collapse = tabataCollapseRecord(
            rawBlockItems: rawBlockItems,
            normalizedItems: blockItems,
            blockIndex: blockIndex,
            block: block
        )
        let (itemLogs, perBlock) = seedItems(blockItems, block: block, parser: parser)
        return BlockSeed(
            itemLogs: itemLogs,
            perBlock: perBlock,
            itemsInBlock: blockItems.count,
            advancement: advancement(for: block, itemCount: blockItems.count),
            collapse: collapse
        )
    }

    /// Apply mode-specific validity constraints to the context's items for a
    /// block before they are seeded. Currently just the Tabata single-item
    /// collapse — see the `seed(context:)` doc-comment for the rationale.
    /// Returns the items that should be seeded for this block (possibly a
    /// strict prefix of the raw list).
    private static func normalizeBlockItems(
        _ rawBlockItems: [WorkoutItem],
        block: Block?
    ) -> [WorkoutItem] {
        if block?.timingMode == .tabata, rawBlockItems.count > 1 {
            return Array(rawBlockItems.prefix(1))
        }
        return rawBlockItems
    }

    // `tabataCollapseRecord`, `TabataCollapse`, `SeedResult` live in
    // `SessionSeeder+Accumulator.swift` so the seeder enum body stays
    // under SwiftLint's `type_body_length` cap.

    /// Seed ItemLogs + per-item set counts for one block. Extracted so
    /// `seed(context:)` stays under SwiftLint's `function_body_length`.
    private static func seedItems(
        _ blockItems: [WorkoutItem],
        block: Block?,
        parser: PrescriptionParser
    ) -> (items: [SessionState.ItemLog], perBlock: [Int]) {
        var items: [SessionState.ItemLog] = []
        var perBlock: [Int] = []
        for item in blockItems {
            let sets = setRowsForBlock(block: block, item: item, parser: parser)
            items.append(SessionState.ItemLog(
                itemID: item.id,
                autoregHeld: false,
                sets: sets,
                performedExerciseID: nil
            ))
            perBlock.append(sets.count)
        }
        return (items, perBlock)
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
        // Use the autoreg-tolerant parse so an unsupported `apply_to`
        // value (or any other autoreg-inner parse failure) doesn't wipe
        // the whole item's base reps/load. When the base prescription
        // parses cleanly, autoreg is dropped silently and the set seed
        // carries the authored load/reps. When the base prescription is
        // itself malformed, we still fall back to the zero-row
        // placeholder — there's nothing to recover from.
        switch parser.parseTolerantOfAutoreg(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            return setsFor(prescription: p)
        case .failure:
            // Graceful fallback — one placeholder set so the UI doesn't
            // hand the user an empty item. The parse error already ate
            // the authored values; we can't recover them. Unit defaults
            // to .lb per R2.10 — matches the pound-first default applied
            // when a prescription parses but omits `weight_unit`. Load
            // is nil (loadless) so the placeholder doesn't claim a
            // real numeric 0 that would render as "0 lb".
            return [SetPlan(setIndex: 1, loadKg: nil, unit: .lb, reps: 0, done: false, adjust: nil)]
        }
    }

    // MARK: - Private

    private static func setsFor(prescription: Prescription) -> [SetPlan] {
        switch prescription {
        case .straightSets(let sets, let reps, let loadKg, let unit, _, _, _, _):
            return seedStraightSets(sets: sets, reps: reps, loadKg: loadKg, unit: unit)
        case .bodyweight(let sets, let reps, _):
            // Bodyweight carries no load; unit is moot. Seed loadKg: nil
            // so the row's loadless-ness travels end-to-end: drivers
            // render "BW", push writes `SetLog.weight = nil`, History
            // renders "BW" — not "0 lb".
            return seedUniform(sets: sets, loadKg: nil, unit: .lb, reps: reps)
        case .repRange(let sets, _, let repsMax, let loadKg, let unit, _, _):
            // Seed with the upper end of the range — authors pick the
            // range with the ceiling as the stretch goal. Authored-nil
            // load stays nil (loadless variant).
            return seedUniform(sets: sets, loadKg: loadKg, unit: unit, reps: repsMax)
        case .setsDetail(let details, let unit, _, _):
            return seedSetsDetail(details: details, unit: unit)
        case .percentOf1RM(let sets, let reps, _, _):
            // v0 does not resolve percent → kg here. The percent-of-1RM
            // slice will layer a resolver on top. Seed loadKg: nil until
            // the 1RM resolver lands with a real number; UI still shows
            // the set counter. Unit defaults to .lb until the resolver
            // lands with its own unit plumb.
            return seedUniform(sets: sets, loadKg: nil, unit: .lb, reps: reps)
        case .cluster(let sets, let reps, let loadKg, let unit, _, _, _):
            return seedUniform(sets: sets, loadKg: loadKg, unit: unit, reps: reps)
        case .warmup(let sets, let reps, let loadKg, let unit):
            // Authored-nil load stays nil (warm-up bodyweight shapes).
            return seedUniform(sets: sets, loadKg: loadKg, unit: unit, reps: reps)
        case .amrapToken(let loadKg, let unit, _):
            // AMRAP token — "as many reps as possible, open numeric
            // entry" (docs/prescription.md § "amrap_token"). Seeds a
            // single open-entry SetPlan row that preserves the authored
            // load and unit so a weighted AMRAP token (e.g. "kettlebell
            // snatch @ 24 kg, AMRAP") renders and logs with the correct
            // load. `reps=0` is the open-entry sentinel: the user enters
            // the actual rep count at log time. A nil `load_kg` seeds
            // loadKg: nil so drivers / push / History all render "BW".
            return [SetPlan(
                setIndex: 1,
                loadKg: loadKg,
                unit: unit,
                reps: 0,
                done: false,
                adjust: nil
            )]
        case .empty:
            // `{}` can legitimately appear inside set-major blocks
            // (straight_sets / custom) where the segment describes the
            // work. A zero-row seed strands the cursor on `(b, i, 1)`
            // with no matching SetPlan: the driver renders nothing and
            // the reducer never advances past the item. Seed a single
            // manual placeholder so the driver can render "set 1 of 1"
            // and the user can log-or-skip to move the cursor forward.
            return [manualPlaceholder]
        }
    }

    /// Single 1-row placeholder for `.empty` prescriptions inside set-major
    /// blocks. Keeps the cursor's (b, i, 1) position matched by a real
    /// SetPlan so `logSet` lands and `advanceCursor` walks on. `loadKg`
    /// is nil (loadless) so the placeholder flows as BW through display
    /// and push — never as a fabricated "0 lb". The sibling `.amrapToken`
    /// case seeds its own row that preserves authored load/unit, since
    /// AMRAP-token is semantically distinct — see `setsFor` above.
    static let manualPlaceholder = SetPlan(
        setIndex: 1,
        loadKg: nil,
        unit: .lb,
        reps: 0,
        done: false,
        adjust: nil
    )

    private static func seedStraightSets(
        sets: Int?,
        reps: RepCount?,
        loadKg: Double?,
        unit: WeightUnit
    ) -> [SetPlan] {
        let n = sets ?? 1
        let repCount = reps.flatMap { rc -> Int? in
            if case .count(let r) = rc { return r }
            return nil
        } ?? 0
        // Authored-nil load stays nil — a `straight_sets` shape without
        // load_kg is a bodyweight / loadless variant (circuit station,
        // pull-up block) and must render as "BW", not "0 lb".
        return (1...max(n, 1)).map {
            SetPlan(setIndex: $0, loadKg: loadKg, unit: unit, reps: repCount, done: false, adjust: nil)
        }
    }

    static func seedUniform(
        sets: Int,
        loadKg: Double?,
        unit: WeightUnit,
        reps: Int
    ) -> [SetPlan] {
        (1...max(sets, 1)).map {
            SetPlan(setIndex: $0, loadKg: loadKg, unit: unit, reps: reps, done: false, adjust: nil)
        }
    }

    private static func seedSetsDetail(details: [SetDetail], unit: WeightUnit) -> [SetPlan] {
        details.enumerated().map { i, d in
            let reps: Int
            if case .count(let n) = d.reps { reps = n } else { reps = 0 }
            // Per-set `load_kg` on a SetDetail: authored-nil stays nil,
            // so a mixed-load `sets_detail` (warm-up BW → weighted) can
            // carry nil on the loadless rows.
            return SetPlan(
                setIndex: i + 1,
                loadKg: d.loadKg,
                unit: unit,
                reps: reps,
                done: false,
                adjust: nil
            )
        }
    }
}
