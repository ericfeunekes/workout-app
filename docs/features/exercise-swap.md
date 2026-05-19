---
title: exercise-swap
status: built
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for exercise-swap
covers:
  - app/Packages/Core/Session/Sources/CoreSession/SessionReducer+Handlers.swift
  - app/Packages/Core/Session/Sources/CoreSession/SessionMutation.swift
  - app/Packages/Core/Domain/Sources/CoreDomain/ExerciseAlternative.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/WorkoutContext.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ActiveView.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/SwapSheet.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/StraightSetsDriver.swift
  - app/Packages/Core/Prescription/Sources/CorePrescription/AlternativeOverrides.swift
---

# exercise-swap

## What it does
Long-press on the Active screen's card fires a medium haptic + opens `SwapSheet`, which lists the pre-computed `ExerciseAlternative` rows for the current item. Tapping a row commits the swap via `ExecutionViewModel.swap(itemID:, alternativeID:)` — the reducer sets `performedExerciseID = alt.exerciseID` on the item, parses the alternative's `parameter_overrides_json` into an `AlternativeOverrides`, mirrors reps / load onto the remaining non-done `SetPlan` rows, and stores the struct on `SessionState.ItemLog.overrides`. `StraightSetsDriver.onSetLogged` reads `itemLog.overrides?.targetRir` and prefers it over the prescription's authored `target_rir` for its autoreg path. `SwapSheet` surfaces each alternative's `reason` + a "LAST · …" summary pulled from `WorkoutContext.lastPerformed`. Cancel is an explicit ghost button; drag-down and tap-outside both dismiss without swapping. Empty-alternatives case renders a "no alternatives" DSCard placeholder. Telemetry: `execution.exercise_swap` carries `{item_id, from_exercise_id, to_exercise_id, had_overrides}`. Closes bug-008 + bug-009.

## State surface
- **Inputs (UI):** long-press (~0.4s) on the Active-card scroll region opens `SwapSheet`. Tapping a row calls `ExecutionViewModel.swap(itemID:, alternativeID:)`.
- **Inputs (code):** any caller can dispatch `.swap(itemID:, toExerciseID:, overrides:)` through `ExecutionViewModel.apply(_:)`; the `overrides:` associated value defaults to `nil`.
- **Outputs / side effects:** `itemLog.performedExerciseID` is set; `itemLog.overrides` carries the parsed `AlternativeOverrides` when non-empty; remaining non-done `SetPlan` rows pick up the override's `reps` / `load_kg` (`.manual` rows preserved). Subsequent `logSet` calls produce primitive slot rows with `performedExerciseID` populated. The workout template is **not** mutated — re-pulling the workout shows the original exercise. Telemetry emits `execution.exercise_swap`.
- **State transitions:** exactly one reducer branch — `applySwap` (`SessionReducer+Handlers.swift`).

## What it deliberately doesn't do
- Does not reset `autoregHeld` (`SessionReducer+Handlers.swift` — cites `docs/prescription.md` § "Hold scope").
- Does not mutate logged sets (comment: "preserves history", `SessionMutation.swift`). Pre-swap primitive slot rows retain `performedExerciseID=nil` (meaning "planned exercise performed").
- Does not write to the workout row — next session still shows the original exercise.
- Does not overwrite `.manual` edits. Any pending set the user edited before the swap keeps its user-chosen load/reps; only non-manual pending sets pick up the alternative's override values.
- Does not validate that the alternative's shape matches the block's timing_mode — flagged in `docs/open-questions.md:41` ("no validation that the override produces a shape the block's timing_mode can execute").
- Does not apply autoreg step / threshold overrides to the driver's autoreg path. `AlternativeOverrides` now parses the full target override key set (`sets`, `reps`, `load_kg`, `weight_unit`, `target_rir`, `autoreg`) and stores parsed fields on `SessionState.ItemLog.overrides`, but the v0 driver still reads only `targetRir` — the `autoreg` step-override struct is parsed-but-inert until the driver wiring lands.
- Does not honour a `sets` override on a round-robin block (superset, circuit, AMRAP, EMOM, Tabata, for_time). The app drops the `sets` portion of the override — the block's per-item row counts are a shared `rounds` invariant — and emits `execution.swap_sets_override_rejected` so the rejection is visible. Other override fields still apply on those blocks.

## Edge cases handled in code
- Unknown itemID in `.swap` → silent no-op (`SessionReducer+Handlers.swift:123-125`).
- Post-save state is cleared; a swap mutation against a stale `itemID` is a silent no-op (same guard).
- Display fallback: missing exercise in `context.exercises` renders as `"(unknown exercise)"` (`WorkoutContext.swift:76`).
- `CompleteView.swift:102` surfaces `performedExerciseID` in the completion ledger so a swap is visible at session's end.
- `WorkoutCache+History.swift:93-114` uses `performedExerciseID` for per-exercise history aggregation — swaps count toward the alternative's history, not the planned item's.

## Current gaps

- `SWAP-GAP-001`: Swap is item-scoped. A "swap just this set" behavior is not
  in the reducer vocabulary.
- `SWAP-GAP-002`: Cross-block swap is not supported. Alternatives are attached
  to a specific `workoutItemID`; moving work between blocks remains out of
  scope until a concrete workflow needs it.
- `SWAP-GAP-003`: Swap has no undo path. The only way back is to swap to the
  original exercise id through another authored alternative row.
- `SWAP-GAP-004`: Alternative override shape is not validated against the
  block's `timing_mode` (`docs/open-questions.md`).
- `SWAP-GAP-005`: `autoreg` override values land on `ItemLog.overrides`, but
  drivers do not yet consume step/threshold overrides.

## QA scenarios

### S1. Happy path (reducer-only)
- **setup:** seeded session with item A (Bench), item B (Row). Pre-computed alternative for A: DB Bench (different `exerciseID`).
- **steps:** dispatch `.swap(itemID: A, toExerciseID: dbBenchID)` via a test harness or debug path.
- **expected:** `state.items[0].performedExerciseID == dbBenchID`. `ActiveView` renders "Dumbbell Bench" via `WorkoutContext.exerciseName`. Item B unchanged.

### S2. Long-press opens SwapSheet
- **setup:** running app, Active screen showing Bench, alternatives authored on the item.
- **steps:** long-press anywhere on the active-card scroll area (~0.4s).
- **expected:** medium haptic fires, `SwapSheet` presents with a DSCard per alternative. Tap cancels via ghost button or drag-down. **Wired** (`ActiveView.swift` `.onLongPressGesture` + `openSwapSheet`).

### S3. Swap preserves logged sets
- **setup:** 3 sets prescribed. Log set 1 of Bench as 5/RIR 2.
- **steps:** dispatch `.swap(itemID, dbBenchID)`.
- **expected:** `state.items[0].sets[0]` still has the logged reps/rir. Its `performedExerciseID` is **not** retroactively applied to logged sets — primitive slot rows already created from that logged state carry `performedExerciseID=nil` (the set was logged before the swap). Only **subsequent** `logSet` calls receive the new id through primitive slot publication.

### S4. Swap preserves autoregHeld
- **setup:** Bench item with `autoregHeld=true` after an earlier Undo.
- **steps:** dispatch swap.
- **expected:** `state.items[0].autoregHeld == true` post-swap (`SessionReducer+Handlers.swift:128-130`). No new proposals will fire for this item.

### S5. Swap mid-set
- **setup:** Active screen, set 2 of 3.
- **steps:** long-press → SwapSheet → tap alternative → return to active.
- **expected — code behavior:** pending set 2's `loadKg` and `reps` are unchanged (swap doesn't reseed — non-manual rows pick up the override's values, but set 2 is the current cursor). Only the display name flips. Logging set 2 produces a primitive slot row with `performedExerciseID` set to the alternative.

### S6. Empty alternatives list
- **setup:** item with `alternatives[]=[]` in the pulled workout.
- **steps:** long-press.
- **expected:** `SwapSheet` opens and renders a "no alternatives" DSCard placeholder instead of a row list. Tap / drag-down dismisses without mutation.

### S7. Swap to same exercise (no-op)
- **setup:** alternative's `exerciseID == item.exerciseID`.
- **steps:** dispatch `.swap(itemID, sameID)`.
- **expected — code behavior:** `performedExerciseID` is set to `sameID`, which now masks the underlying `item.exerciseID`. `exerciseName` resolution short-circuits on the same id. Functional no-op, but the state now carries a redundant override — it'll show in primitive slot `performedExerciseID` for subsequent logs. Cosmetically fine; semantically an authoring oddity.

### S8. Swap affects only this item
- **setup:** three items A, B, C in the same block.
- **steps:** swap A.
- **expected:** only `items[indexOfA].performedExerciseID` changes. B and C untouched (`SessionReducer+Handlers.swift:123-127` indexes by itemID).

### S9. Subsequent items unaffected across blocks
- **setup:** swap A in block 0; advance to block 1 containing item D.
- **expected:** D's display name, prescription, autoreg all come from D's own `workout_item`. No cross-item contamination.

### S10. `performedExerciseID` lands on primitive slot log
- **setup:** swap Bench → DB Bench. Log set 2.
- **steps:** inspect the `PrimitiveSetLog` handed to `onPrimitiveSetLogged`.
- **expected:** `primitiveSetLog.performedExerciseID == dbBenchID`. The primitive slot ID stays the original authored slot/item coordinate.

### S11. History aggregation follows the swap
- **setup:** swap logged, completion saved.
- **steps:** open History → by-exercise view for DB Bench.
- **expected:** the swapped sets appear under DB Bench's history, not Bench's — `WorkoutCache+History.swift:93-114` uses `performedExerciseID` when present. Bench's history for this session is empty (or just the pre-swap sets).

### S12. Completion ledger shows the swap
- **setup:** swap mid-workout, complete workout.
- **steps:** open CompleteView.
- **expected:** `CompleteView.swift:102` reads `log.performedExerciseID` and renders the alternative's name. The ledger reflects what was actually performed.

### S13. Unknown `toExerciseID` (missing from catalog)
- **setup:** swap to a UUID not in `context.exercises`.
- **expected:** reducer still sets the field (it doesn't validate). `exerciseName` returns `"(unknown exercise)"` (`WorkoutContext.swift:76`). No crash; display degrades.

### S14. Autoreg config after swap
- **setup:** Bench item with autoreg (target_rir=2); alternative DB Bench with `parameter_overrides_json = {"target_rir": 4}`.
- **steps:** swap, then log a set at RIR 4.
- **expected:** autoreg uses the override's `target_rir = 4`, so RIR 4 is not an overshoot (needs RIR ≥ target + 2 = 6). Without the override, the same log would fire `.up`. `autoreg.step_kg` overrides are still deferred (see S18) — the struct reads only `reps` / `load_kg` / `target_rir`. Verified by `testSwapTargetRirOverrideShadowsPrescription` + `testSwapWithoutTargetRirOverrideRetainsPrescriptionBehavior`.

### S15. Next session shows the original
- **setup:** swap today; save & done.
- **steps:** re-launch tomorrow; pull a new workout that happens to include the same template.
- **expected:** new workout renders the original exercise. The swap was session-local; `items[i].performedExerciseID` is cleared on `.save` (fresh `ItemLog` from caller, `SessionMutation.swift:56-58`).

### S16. Swap then Undo autoreg — item scope intersection
- **setup:** swap Bench → DB Bench. Log a set that fires autoreg. Tap Undo.
- **expected:** `autoregHeld=true` is set on the **same** `ItemLog` (the one carrying `performedExerciseID`). Further logs on this item don't propose. Swap survives the Undo.

### S17. Post-save stale swap mutation
- **setup:** mid-workout swap applied; save & done; session cleared; dispatch another `.swap` with the old itemID.
- **expected:** silent no-op (item not found in `state.items`, `SessionReducer+Handlers.swift:123-125`). No crash.

### S18. Shape mismatch on alternative's parameter_overrides_json
- **setup:** alternative has `parameter_overrides_json` that would change a straight_sets item into a bodyweight item (e.g. authors omit `load_kg` + add a shape discriminator).
- **expected:** **not handled.** `AlternativeOverrides.parse` now reads `sets` / `reps` / `load_kg` / `weight_unit` / `target_rir` / `autoreg`, but unknown keys are still ignored and there is no validation that the override produces a shape the block's `timing_mode` can execute. Flagged in `docs/open-questions.md:41`. A malformed override (wrong-type value on any recognised key) is rejected wholesale — the swap still happens with `overrides == nil`, not a partial accept.

### S19. DTO round-trip through sync
- **setup:** server pushes a workout with alternatives; client pulls.
- **steps:** verify `DTOMapping+Block.swift:21-42` and `DTOMapping+Exercise.swift:32-42` route alternatives into `CoreDomain.ExerciseAlternative` and `WorkoutCache+Upserts.upsertAlternative`.
- **expected:** alternatives persisted; `attachAlternativeToItem` links them to their `workoutItemID` (`WorkoutCache+Upserts.swift:90`). Ready for a future UI.

### S20. Swap fires telemetry
- **setup:** wired session; alternative authored.
- **steps:** call `ExecutionViewModel.swap(itemID:, alternativeID:)`.
- **expected:** a single `execution.exercise_swap` event (kind = `state`) tagged with the current `workoutID`. `dataJSON` carries `item_id`, `from_exercise_id`, `to_exercise_id`, and `had_overrides: true|false`. Verified by `testSwapEmitsTelemetry` + `testSwapWithoutOverridesReportsHadOverridesFalse`.
