---
title: autoreg
status: living
last_reviewed: 2026-04-26
purpose: Behavioral contract + QA scenarios for autoreg
covers:
  - app/Packages/Core/Autoreg/Sources/CoreAutoreg/Autoreg.swift
  - app/Packages/Core/Autoreg/Sources/CoreAutoreg/AutoregProposal.swift
  - app/Packages/Core/Autoreg/Sources/CoreAutoreg/SetPlan.swift
  - app/Packages/Core/Prescription/Sources/CorePrescription/Autoreg.swift
  - app/Packages/Core/Prescription/Sources/CorePrescription/PrescriptionParser+Autoreg.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/StraightSetsDriver.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
---

# autoreg

## What it does
Client-side load adjustment computed per set-log against **per-item** prescription config. On `logSet`, `StraightSetsDriver.onSetLogged` reads `autoreg` + `target_rir` from the current item's `prescriptionJSON` (`StraightSetsDriver.swift:149-158`), calls `Autoreg.propose` (`Autoreg.swift:107`), and — **accept-by-default** — the view model immediately dispatches `.applyAutoregProposal` which rewrites remaining non-done, non-manual sets' loads (`ExecutionViewModel+Persistence.swift:74-75`). A banner on the Rest screen shows the proposal with an "undo" affordance; Undo reverts the loads and sets `autoregHeld=true` on *that* item for the rest of the session (`ExecutionViewModel.swift:260-305`). Three trigger rules: overshoot (`loggedRir >= targetRir + overshoot_at`), undershoot-reps (`prescribed - logged >= undershoot_at`), hit-failure (`loggedRir == 0 && targetRir > 0`). Precedence: undershoot-reps > hit-failure > overshoot (`Autoreg.swift:111-151`).

## State surface
- **Inputs:** per-set `logSet(reps, rir)`; per-item prescription carries its own `autoreg` sub-object with `target_rir`, `overshoot_at`, `overshoot_step_kg`, `undershoot_at`, `undershoot_step_kg`, `apply_to` (`Prescription/Autoreg.swift:16-42`). Defaults fill in: `overshoot_at=2`, unit-aware step defaults (`5.0` when `weight_unit` is `lb`, `1.25` when `weight_unit` is `kg`), `undershoot_at=2`, `apply_to=remaining` (`PrescriptionParser+Autoreg.swift:79-94`). `target_rir` is **required** when the `autoreg` sub-object is present (`PrescriptionParser+Autoreg.swift:60-62`).
- **Outputs / side effects:** remaining non-done non-manual `SetPlan` rows have `loadKg` overwritten + `adjust` set to `.up` or `.down` (`Autoreg.swift:176-187`). `currentProposal` + `currentProposalItemID` on the view model feed the banner. `autoregHeld` flag flips per-item on Undo. A `execution.autoreg_proposed` / `_accepted` / `_undo` telemetry event fires.
- **State transitions:** `.logSet` → (optional) `.applyAutoregProposal` → `.enterRest` / `.advanceFromRest`, all in one `apply(_:)` batch (`ExecutionViewModel+Persistence.swift:65-87`). Undo emits `[editPendingSet×N, holdAutoreg]` (`ExecutionViewModel.swift:292-301`). Accept is a no-op on state — the apply already happened inline.

## What it deliberately doesn't do
- Autoreg is proposed only by `StraightSetsDriver` for straight-set-adjacent prescription shapes: `.straightSets`, `.repRange`, and top-level `.cluster`. All 12 timing modes have dedicated drivers in `DriverRegistry`; round-robin, scored, interval, continuous, accumulate, custom, and rest modes do not propose autoreg unless their driver explicitly adds support later.
- No cross-exercise downscaling. `apply_to` enum has **only `.remaining`** (`Prescription/Autoreg.swift:24-26`); "next" / "all-future" are reserved-unimplemented.
- No proposal fires on the last set of an item — `hasRemaining` guard in `StraightSetsDriver.swift:167-170` (comment: "mirrors the JSX prototype `hasRemaining = si + 1 < block.sets`").
- Does not consume `bodyweight_kg` — noted in `docs/open-questions.md` § "Body weight freshness".
- Does not round loads — "kilogram math is exact for the step sizes documented" (`Autoreg.swift:40-46`).
- Does not clamp to a floor: `prescribed - step` can go negative. No guard in `Autoreg.propose` (flag: see below).
- Does not re-trigger on `editPastSet` by design (`SessionReducer+Handlers.swift:86-101`, comment: "Corrective — does NOT retrigger autoreg").

## Edge cases handled in code
- `autoregHeld==true` short-circuits `propose` → returns nil (`Autoreg.swift:108-109`).
- RIR nil: overshoot and hit-failure cannot fire (both guarded by `let rir = input.loggedRir`); undershoot-reps still fires on rep miss (`Autoreg.swift:133, 141`).
- Unknown itemID or unknown setIndex in `.applyAutoregProposal` → silent no-op (`SessionReducer+Handlers.swift:110-112`).
- `.manual` and `done` sets are preserved on apply (`Autoreg.swift:182-186`).
- Swap preserves `autoregHeld` — hold is session-scoped (`SessionReducer+Handlers.swift:128-130`, cites spec).
- Missing `autoreg` sub-object → `parseAutoreg` returns `.success(nil)` (`PrescriptionParser+Autoreg.swift:22`); driver bails at `StraightSetsDriver.swift:160-162` with empty `DriverLogOutcome`.
- `autoreg` present but `target_rir` missing → parse failure `.missingKey("target_rir", ...)` (`PrescriptionParser+Autoreg.swift:60-62`); driver's parse branch returns `(nil, nil)`, no proposal.
- Undo's revert-then-hold: reverting sets uses `editPendingSet` which stamps `.manual`. Comment acknowledges the tag is a side-effect made moot by the hold (`ExecutionViewModel.swift:283-291`).

## Known issues / gaps
- Negative-load floor closed (bug-013): `max(0.0, newLoad)` clamp in `Autoreg.propose`. Regression tests: "clamp · undershoot on prescribed=2.5" + "clamp · hit-failure on prescribed=4.0".
- Autoreg step defaults per unit: `5.0` for `.lb`, `1.25` for `.kg` (bug-059). The legacy "default 2.5" is gone.
- `apply_to` parse failure no longer degrades the whole item to `0 kg / 0 reps` — `parseTolerantOfAutoreg` isolates autoreg parse errors from the base prescription, and the server rejects unknown `apply_to` values at ingest (bug-052).
- `execution.autoreg_proposed` telemetry carries a typed `Encodable` payload with `step_kg` + canonical reason tokens (bug-060).
- **Settings vs prescription precedence unresolved** (`docs/open-questions.md` § "Autoreg defaults — Settings vs prescription"). Current assumption: per-item wins; Settings are display-only.
- **Pyramid / tempo ambiguity** — `sets_detail` and tempo-heavy shapes return `(nil, nil)` from `autoregAndTarget` so no proposal fires; top-level cluster is supported as a single composed set and proposes only after the top-level set logs.
- Undo's `.manual` stamp on reverted sets means a subsequent hold-lift wouldn't re-enable autoreg on those rows. Documented trade-off.
- No per-item proposal history / audit trail. `currentProposal` clears on advance/accept/undo; prior proposals leave no evidence beyond the `adjust` glyph.

## QA scenarios

### S1. Happy path: overshoot → up
- **setup:** Bench item with `target_rir=2`, `overshoot_at=2`, `overshoot_step_kg=2.5`, `undershoot_step_kg=2.5`, 3 sets prescribed at 100 kg × 5.
- **steps:** log set 1 as 5 reps / RIR 4.
- **expected:** banner "↑ next set: 102.5 kg" with reason "rir 4 > target 2". Sets 2 and 3 show 102.5 with `↑` glyph. `adjust=.up`.

### S2. Happy path: undershoot-reps → down
- **setup:** Squat item `target_rir=2`, `undershoot_at=2`, `undershoot_step_kg=5.0`, 3 sets @ 140 kg × 5.
- **steps:** log set 1 as 3 reps / RIR 0.
- **expected:** banner "↓ next set: 135 kg" with reason "missed 2 reps" (NOT hit-failure — undershoot-reps wins precedence, `Autoreg.swift:111-131`). Sets 2 and 3 drop to 135 with `↓`.

### S3. Happy path: hit-failure → down
- **setup:** Row item `target_rir=2`, 3 sets @ 80 kg × 8.
- **steps:** log set 1 as 8 reps / RIR 0.
- **expected:** banner "↓ next set: 77.5 kg" with reason "hit failure · target rir 2". Reps met target, so undershoot-reps doesn't fire; hit-failure carries.

### S4. Per-exercise variance (TOP PRIORITY)
- **setup:** workout with Bench (`overshoot_step_kg=2.5`, target 2) followed by Squat (`overshoot_step_kg=5.0`, target 2).
- **steps:** log bench set 1 as 5 reps / RIR 4, advance, accept, finish bench, log squat set 1 as 5 reps / RIR 4.
- **expected:** bench proposal bumps by **2.5**; squat proposal bumps by **5.0**. Each proposal reads its **own item's** `prescriptionJSON` via `StraightSetsDriver.autoregAndTarget`.

### S5. Different target_rir per item
- **setup:** Bench target_rir=2, OHP target_rir=1, both `overshoot_at=2`, same workout.
- **steps:** log bench set 1 as RIR 3 → no proposal (3 < 2+2). Log OHP set 1 as RIR 3 → proposal up (3 ≥ 1+2).
- **expected:** same observed RIR, one fires, the other doesn't — thresholds are per-item.

### S6. Missing autoreg block on one item
- **setup:** Bench has full autoreg; Row's prescription omits the entire `autoreg` sub-object (still parses fine, `parseAutoreg` → nil).
- **steps:** log row set 1 as RIR 4 / reps missed.
- **expected:** no proposal, no banner, no error. Bench unaffected — next day's bench items still propose normally.

### S7. autoregHeld is per-item
- **setup:** workout with Bench then Squat, both with autoreg.
- **steps:** on bench set 1, log RIR 4, banner appears, tap **Undo**. Complete bench. Start squat, log RIR 4.
- **expected:** bench no longer proposes (held). Squat proposes normally — `autoregHeld` lives on `ItemLog`, not session (`SessionState.swift:60`).

### S8. RIR matrix (target_rir=2, thresholds default to 2)
- **setup:** item target 2, defaults (`overshoot_at=2`, `undershoot_at=2`).
- **steps:** six runs, logging prescribed reps in full with RIR ∈ {0, 1, 2, 3, 4, 5}.
- **expected:** RIR 0 → down (hitFailure). RIR 1, 2, 3 → no proposal (in tolerance / at target / in tolerance). RIR 4 → up (overshoot). RIR 5 → up (same class). `Autoreg.swift:141` uses `>=` so 4 and 5 both qualify.

### S9. Undershoot-reps threshold boundary
- **setup:** prescribed 5 reps, `undershoot_at=2`.
- **steps:** two runs: log 3 reps / RIR 2 (delta 2), and log 4 reps / RIR 2 (delta 1).
- **expected:** first → down proposal (`delta ≥ threshold`). Second → no proposal.

### S10. Precedence collision — RIR 0 AND reps missed by 2
- **setup:** prescribed 5 reps, target 2, both thresholds 2.
- **steps:** log 3 reps / RIR 0.
- **expected:** banner reason is **undershoot-reps** (`missed 2 reps`), not hit-failure — `Autoreg.swift:121-131` is checked before the hit-failure branch. Direction and step are identical (`undershoot_step_kg`), so load is the same; only the reason string differs.

### S11. Proposal on last set is suppressed
- **setup:** 3 sets prescribed, autoreg active.
- **steps:** log sets 1 and 2 normally (accept any proposals). Log set 3 with RIR 5 or 0/reps missed.
- **expected:** no banner, no load change. `StraightSetsDriver.swift:167-170` guards `remaining == false`.

### S12. Negative load floor (audit)
- **setup:** prescribed 2.5 kg, `undershoot_step_kg=5.0`, 3 sets.
- **steps:** log set 1 with 0 reps (undershoot fires).
- **expected — code behavior:** proposal `newLoadKg = -2.5`. Remaining sets render as "-2.5 kg" with `↓`. No clamp in `Autoreg.swift:124`. **Flag as defect** if product requires non-negative.

### S13. Nil autoreg sub-object on item
- **setup:** prescription has `target_rir` but no `autoreg` object.
- **steps:** log any set with any rir/reps.
- **expected:** `parseAutoreg` returns `.success(nil)`; `StraightSetsDriver` returns empty outcome (`:160-162`). No banner, no error.

### S14. Nil RIR (skip picker) — overshoot cannot fire
- **setup:** target 2, prescribed 5 × 100 kg.
- **steps:** log set 1 with 5 reps; on the RIR picker tap **skip**.
- **expected:** no overshoot proposal. If reps are full, no undershoot either — no banner. If reps missed by ≥ threshold, undershoot still fires.

### S15. Manual edit wins — autoreg skips `.manual` sets
- **setup:** 3 sets @ 100 kg. Before logging set 1, tap set 3's load pill (pending-edit path) and change it to 95. This stamps `.manual` on set 3.
- **steps:** log set 1 with RIR 4 (overshoot fires).
- **expected:** set 2's load becomes 102.5 with `↑`. Set 3 stays at 95 with `✎` (`Autoreg.swift:184`, `SetPlan.swift:16-20`). The `ActiveView.adjustGlyph(.manual) == "✎"` (`ActiveView.swift:154-156`).

### S16. Autoreg + swap interaction
- **setup:** Bench item swapped mid-workout to DB Bench (via `.swap` mutation). Bench's own `autoreg` config is on the **item**, not the exercise.
- **steps:** after the swap, log next bench set with RIR 4.
- **expected:** proposal fires using the **original item's** autoreg config — `performedExerciseID` overrides display only; `StraightSetsDriver` reads `item.prescriptionJSON` which is unchanged by `.swap` (`SessionReducer+Handlers.swift:216-275`). If the chosen alternative carries a non-empty `parameter_overrides_json`, R2.8 applies those reps / load / unit overrides to remaining non-done `SetPlan` rows AND stashes the full overrides on `ItemLog.overrides` for drivers that read per-side / `target_rir` / nested `autoreg`. R2.8b narrowed the `sets` sub-override: it is only honored on **set-major** blocks (straight sets). Round-robin blocks (superset / circuit / AMRAP / EMOM / Tabata / forTime) drop the `sets` portion and apply the rest of the override — rewriting one item's row count in a round-robin structure would skew the cursor walk or silently collapse peer items (`SessionReducer+Handlers.swift:236-268`, `SessionReducer+SwapOverrides.swift`). The dropped `sets` override emits telemetry event `execution.swap_sets_override_rejected` (NOT `swap.sets_override_rejected` — the event is scoped under the `execution.` family; see `ExecutionViewModel+Swap.swift:138`).

### S17. Autoreg only in straight-set-adjacent execution
- **setup:** workout with a block whose `timing_mode` is something other than `straight_sets`.
- **expected:** dedicated non-straight drivers do not propose autoreg. Unsupported parsed prescription shapes (e.g. `.setsDetail`, `.amrapToken`, `.bodyweight`, `.warmup`, `.empty`) return `(nil, nil)` from `autoregAndTarget` in `StraightSetsDriver`. Cluster is the exception: when authored with `autoreg`, it proposes only after the top-level composed set logs, never per sub-set.

### S18. Across workouts — no carry-over
- **setup:** yesterday's bench undershot heavily; today's bench is a freshly-pulled workout.
- **steps:** start today's bench.
- **expected:** today's prescribed loads come from the pulled `prescription_json`, not a running tally from yesterday. Autoreg is session-scoped; nothing persists across workouts.

### S19. Undo round-trip
- **setup:** 3 sets, overshoot fires on set 1 (banner up).
- **steps:** tap **Undo** on banner. Observe sets 2 and 3.
- **expected:** loads revert to originals (from `SessionSeeder.seedSets(for: item)`). Adjust glyph becomes `✎` (manual, a known side-effect — `ExecutionViewModel.swift:283-291`). `autoregHeld=true` — subsequent logs on this item propose nothing.

### S20. Accept is a no-op on state
- **setup:** banner visible after set 1 log.
- **steps:** tap somewhere to dismiss (or wait and tap "next"). Observe set 2.
- **expected:** set 2 load is already updated (apply happened inline with logSet, `ExecutionViewModel+Persistence.swift:72-76`). No re-render on dismiss.

### S21. Advance clears the banner
- **setup:** banner visible.
- **steps:** tap "next".
- **expected:** `advance` nils out `currentProposal` and `currentProposalItemID` (`ExecutionViewModel.swift:311-315`). Banner gone on the next active screen.

### S22. Telemetry events
- **setup:** autoreg wired.
- **steps:** trigger a proposal → emits `execution.autoreg_proposed`. Dismiss with next → fires nothing explicit (accept is passive). Tap Undo → emits `execution.autoreg_undo`. Explicit accept call (if ever wired) → `execution.autoreg_accepted`.
- **expected:** event names match `ExecutionViewModel.swift:242, 253, 263`. All tagged with workout_id.

### S23. Unknown itemID on proposal apply
- **setup:** hand-craft a `.applyAutoregProposal` with a stale itemID (e.g., post-save state).
- **expected:** silent no-op (`SessionReducer+Handlers.swift:110-112`). State unchanged.

### S24. Parser: autoreg present but target_rir missing
- **setup:** authored prescription has the `autoreg` sub-object but no `target_rir` at the item level.
- **expected:** parse fails with `.missingKey("target_rir", inShape: "autoreg(<shape>)")` (`PrescriptionParser+Autoreg.swift:60-62`). In StraightSetsDriver, parse failure branch sets `autoregConfig=nil`; no proposal, no crash (`:155-158`).

### S25. Parser: unknown apply_to value
- **setup:** authored `"apply_to": "next"` (reserved-unimplemented).
- **expected:** parse fails with `.wrongType(key: "apply_to", expected: "\"remaining\"")` (`PrescriptionParser+Autoreg.swift:110-113`). Prescription load fails; no autoreg. Authoring error, not a runtime chaos case.
