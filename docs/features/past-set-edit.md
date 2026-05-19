---
title: past-set-edit
status: built
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for past-set-edit
covers:
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Push.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/RestView+Sheets.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/NumPadSheet.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/RirSheet.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistorySessionDetailView.swift
  - app/Packages/Core/Session/Sources/CoreSession/SessionReducer+Handlers.swift
---

# past-set-edit

## Target behavior

Past-set edit is the corrective path for logged work. The target surface is the
shared `docs/set-edit-sheet.md` contract, with field availability determined by
the source prescription and log row.

Any past correction marks the row manual, updates the existing logical set log,
and never retriggers autoreg.

Active-session correction remains available. Completed-workout History
correction is disabled in production during the primitive cutover until a
primitive-native edit/push contract is wired.

## Current implementation
Correctively edit a logged set's load, reps, or RIR. **In active session** (RestView): tap the corresponding `DSPill` in the "JUST LOGGED" row. Load and reps open `NumPadSheet`; RIR opens `RirSheet` (`RestView+Sheets.swift:17-87`). Only the `lastLoggedSet` is editable here — `RestView.swift:144` reads `viewModel.lastLoggedSet` and the pills dispatch to the sheet for that single set. Commit calls `viewModel.editPastSet(...)` which dispatches the `.editPastSet` reducer mutation AND — after the apply — republishes the corresponding primitive `.slot` row through `onPrimitiveSetLogged` using the deterministic primitive log coordinate from the active `ExecutionPlan` (`ExecutionViewModel.swift:editPastSet` → `ExecutionViewModel+Push.swift:handlePastSetEditSideEffects` → `enqueueEditedSet`). Reducer updates load/reps/rir, stamps `adjust=.manual`, never fires autoreg (`SessionReducer+Handlers.swift:81-101`, comment: "Corrective — does NOT retrigger autoreg"). **In History** (`HistorySessionDetailView`): production rows are read-only during the primitive cutover because the shell does not wire `onSetLogEdited`. Package tests still cover the legacy hook-backed cache edit behavior, but it is not an active production affordance.

## State surface
- **Inputs (active session, Rest screen):** tap on load pill → `NumPadSheet(step: 2.5, allowsDecimal: true)` (`RestView+Sheets.swift:28-48`). Tap reps pill → `NumPadSheet(step: 1, allowsDecimal: false)` (`:50-70`). Tap RIR pill → `RirSheet(initialValue: set.rir)` (`:72-87`). All sheets subtitle "correcting log · no autoreg".
- **Inputs (History tab):** production set rows are read-only while
  `onSetLogEdited` is nil. If a test or future shell wires the hook, tapping a
  set row opens `EditSetSheet` with labels per source `weightUnit`, reps capped
  at 999, RIR clear via explicit-clear enum, and row fields for duration,
  distance, skipped/performed state, side round-trip, and notes where present.
- **Outputs / side effects:** `.editPastSet` dispatched. Reducer: `adjust → .manual`, load/reps/rir updated where non-nil (nil = leave unchanged), `done` preserved (`SessionReducer+Handlers.swift:86-100`). Session persisted via `persist()` (`ExecutionViewModel+Persistence.swift:37-54`). Post-apply: `enqueueEditedSet` republishes the primitive `.slot` result through `onPrimitiveSetLogged` when the active context has an `ExecutionPlan`, and `emitPastSetEdited` fires `execution.past_set_edited` on the telemetry emitter.
- **State transitions:** purely a set-log mutation. No route change. No autoreg trigger. Push fires (fire-and-forget, same UUID as original log).

## What it deliberately doesn't do
- Does not re-fire autoreg (`SessionMutation.swift:90-100`, `SessionReducer+Handlers.swift:85-101`). Matches `docs/prescription.md` § "Edits don't retrigger".
- Does not change `done` — a past-set edit is by definition on a logged set; `applyEditPastSet` returns unchanged state when `old.done == false` (`SessionReducer+Handlers.swift:88-90`).
- Does not scope — no "this set / remaining" toggle. `NumPadSheet` comment flags the future scoped variant (`NumPadSheet.swift:10-14`).
- Does not allow editing anything but the **last-logged set** from RestView. There's no active-screen past-set picker in v0.
- RestView edits push primitive slot rows when the active context carries a
  primitive execution plan. History-screen edits are disabled in production
  during the primitive cutover; hook-backed legacy cache behavior remains
  package-tested but is not a shipped affordance today.

## Edge cases handled in code
- Nil load/reps/rir in the mutation → "leave unchanged" (`SessionReducer+Handlers.swift:94-98` uses `?? old.loadKg` etc.).
- Edit of a non-done set via `.editPastSet` → no-op guard (`:88-90`). The Rest screen guards this naturally by only exposing pills when `lastLoggedSet != nil`.
- `adjust` always forced to `.manual` on past-set edit (`:97`), overwriting `.up` / `.down` / prior `.manual` — matches `docs/prescription.md` § "Autoreg + manual edit".
- Unknown itemID or setIndex → silent no-op via `updateSet` guards (`SessionReducer+Handlers.swift:170-175`).
- `NumPadSheet` primes its buffer from `initialValue`; integer-valued doubles render without decimal (`NumPadSheet.swift:115-123`).
- RirSheet "skip" returns without committing (`:85`) — intended behavior for RIR-only edits that the user opens then abandons.
- `adjustGlyph` renders `✎` for `.manual` on `ActiveView.swift:154-156`. The "adjusted" glyph shows in the active hero block.

## Current gaps

- `PASTEDIT-GAP-001`: Active-session past correction is limited to the
  last-logged set. There is no active-screen picker for older logged rows.
- `SETEDIT-GAP-001`: Active-session and History corrections still use different
  visual surfaces. The remaining unification work is preview/active visual
  parity and apply scope.
- `SETEDIT-GAP-002`: Apply-to-remaining/future-set scope is target behavior for
  selected preview or active setup edits, but it is not part of completed
  past-log correction.
- `HISTORY-GAP-002`: Past corrections overwrite the existing logical set-log
  row. `set_log.updated_at`, field-diff telemetry, and durable History edit log
  are separate future provenance work.

## QA scenarios

### S1. Happy path: edit load after log
- **setup:** active session, log set 1 @ 100 kg × 5, land on Rest.
- **steps:** tap load pill → NumPadSheet opens at 100, change to 95, tap "save".
- **expected:** pill flips to "95 KG". `state.items[i].sets[0].loadKg == 95`, `adjust == .manual`. Banner (if any from autoreg) is unaffected. Back on Active for set 2, the `adjustGlyph` on set 1 would render `✎` if revisited.

### S2. Happy path: edit reps
- **setup:** Rest screen, last logged set 5 reps.
- **steps:** tap reps pill, change to 4, save.
- **expected:** pill shows 4. Reducer writes `reps=4, adjust=.manual`. No autoreg retrigger (confirm: `currentProposal` unchanged).

### S3. Happy path: edit RIR
- **setup:** last logged rir=2.
- **steps:** tap RIR pill, pick 1.
- **expected:** pill shows 1. `sets[0].rir == 1`, `adjust=.manual`.

### S4. RIR "skip"
- **setup:** RIR pill tapped.
- **steps:** tap "skip".
- **expected:** sheet closes, rir unchanged (`RestView+Sheets.swift:85`).

### S5. Edit does not re-fire autoreg
- **setup:** log set 1 with RIR 4, autoreg up fires, banner visible, remaining sets bumped.
- **steps:** tap RIR pill, change to 2.
- **expected:** remaining sets' loads unchanged (still at the bumped value). No new banner. Reducer's `.editPastSet` path never calls `Autoreg.propose` (confirmed: only `StraightSetsDriver.onSetLogged` calls it, invoked only from `logSet`).

### S6. Clearing reps to 0
- **setup:** edit reps, type 0, save.
- **expected:** `sets[0].reps == 0`. No floor. Display shows "0 REPS". Accept this is a legal state (the user skipped after a failure).

### S7. Edit a bodyweight set
- **setup:** item parsed as `.bodyweight`; logged set shows "BW / 10 REPS".
- **steps:** tap load pill.
- **expected — code behavior:** `RestView+Sheets.loadSheet` opens with `initialValue: set.loadKg` which is `0` for bodyweight rows (seeded to 0 per `StraightSetsDriver.swift:70-74, 232-240`). NumPad shows "0". Saving any value writes that load to the set. No UI hides the load pill for BW rows today — **cosmetic / minor bug** (user could accidentally set a nonzero load on a BW set). Flag.

### S8. Multiple edits — latest wins (locally)
- **setup:** edit load 100 → 95 → 97.5.
- **expected:** final state `loadKg == 97.5`. `adjust` stays `.manual`. No history of intermediate values.

### S9. Edit after Undo autoreg
- **setup:** autoreg down fires on set 1, tap Undo (loads revert, `.manual` stamped, `autoregHeld=true`).
- **steps:** tap reps pill, edit reps.
- **expected:** reps update, `adjust` already `.manual` from the revert, stays `.manual`.

### S10. Edit enqueues a push with the same UUID as the original log (tested: `testEditPastSetEnqueuesSameUUIDAsOriginalLog`, `testEditPastSetEnqueuesWithUpdatedValues`, `testMultipleEditsOfSameSetAllUseSameUUID`)
- **setup:** push hook wired; log a set (enqueue fires once).
- **steps:** edit load / reps / rir via the pill.
- **expected:** a SECOND `onPrimitiveSetLogged` call fires carrying the POST-edit primitive `.slot` row, using the SAME deterministic primitive coordinate as the original row from the active `ExecutionPlan`. The server upserts the existing primitive row in place; no second row is created. Repeated edits all share the one primitive log UUID; the final state wins.

### S11. History-screen edit disabled in production
- **setup:** History tab → session detail for a completed workout.
- **steps:** tap any set row.
- **expected:** No edit sheet opens in the production shell while
  `onSetLogEdited` is nil; no local mutation, telemetry, or push occurs.
  Hook-backed legacy edit behavior is package-tested only.

### S12. Session detail set indexes render 1..N
- **setup:** Session detail for a workout with N sets on an exercise.
- **expected:** rendered indexes start at 1 and follow the stored 1-based `setIndex` (bug-020 closed). Cosmetic display only; keep as a regression guard.

### S13. NumPad decimal / step controls
- **setup:** load sheet opened.
- **steps:** tap "+ 2.5" → 102.5. Tap "− 2.5" twice → 97.5. Enter 100.25 via keypad.
- **expected:** buffer accepts decimals (`NumPadSheet.swift:142-146`, `allowsDecimal=true` for load). Step buttons nudge exactly. Rounded via `rounded(toPlaces: 2)` (`:148-156`).

### S14. NumPad reps disallows decimal
- **setup:** reps sheet.
- **steps:** attempt to type `.`.
- **expected:** keypad doesn't expose the `.` key — `NumPadSheet` constructs `DSKeypad(onDecimal: allowsDecimal ? pressDecimal : nil)` (`:39-43`), and reps sheet passes `allowsDecimal: false`.

### S15. Edit then advance
- **setup:** edit load post-log.
- **steps:** tap "next" to leave Rest.
- **expected:** `advance()` runs; `currentProposal` clears (moot); state persists the edit (`persist()` ran on apply). `lastLoggedSet` now points to a different setIndex as the cursor moves — the just-edited set is no longer exposed via the pills.

### S16. Unknown itemID / setIndex
- **setup:** hand-craft `editPastSet` with stale itemID or nonexistent setIndex.
- **expected:** silent no-op in `updateSet` (`SessionReducer+Handlers.swift:170-175`). State unchanged.

### S17. Edit of a non-done set
- **setup:** (synthetic) dispatch `.editPastSet` against a setIndex that has not been logged (`done == false`).
- **expected:** reducer guard returns state unchanged (`:88-90`). In practice the UI never exposes this path; the `editPendingSet` mutation is the correct vocabulary for that case.

### S18. `adjust` tag precedence
- **setup:** set 1 has `adjust=.up` from autoreg. (To reach this from a past-set-edit POV, set 1 was done earlier with an autoreg bump applied.)
- **steps:** (synthetic) edit set 1 via `.editPastSet`.
- **expected:** `adjust` overwritten to `.manual` (`SessionReducer+Handlers.swift:97`). The `adjust` field is append-of-precedence: past-set edits always manualize.

### S19. Persistence survives reload
- **setup:** edit a pill. Background and re-launch the app.
- **expected:** edited value persists. `persist()` serialized `SessionState` to `SessionStore`; `restoreIfPossible` rehydrates on next bootstrap (`ExecutionViewModel+Persistence.swift:16-26`).

### S20. Edit AFTER save & done
- **setup:** save the workout.
- **steps:** re-open History → session detail → tap a set row.
- **expected:** History edit sheet (S11) shipped — the tap opens `EditSetSheet` and pushes the corrected `SetLog` with the same deterministic UUID so the server upserts the existing row (bug-015 / bug-051 / Phase 6). Marking a row skipped clears performance metrics and removes skipped-only rows from by-exercise aggregation.

### S_HISTORY_IDEMPOTENT. History edit upserts the server row in place (bug-040, fixed)
- **setup:** log a set on Active; save & done; server + local cache both carry the same deterministic `setLogID(itemID, setIndex)`. Open History → session detail → tap the set row → EditSetSheet → change reps → save.
- **expected:** the push hook receives a `SetLog` with `id` EQUAL to the existing cached/server id (not a freshly generated UUID). Server `sync_results` UPDATEs the row in place. No duplicate row. Root cause of the pre-fix duplicate was `writeCompletionToLocalCache` stamping a fresh `UUID()` on the local cache row while the push path used a deterministic id — the two sides carried different ids for the same logical set, so the History edit pushed an id the server had never seen. Fix aligned the local cache with the push path (same deterministic id on both sides). Covered by `testSaveAndDoneLocalCacheUsesDeterministicSetLogID` (FeaturesExecutionTests) and `testHistoryEditUsesExistingSetLogIdForIdempotentUpsert` (FeaturesHistoryTests).

### S21. Adjusted glyph + telemetry (tested: `testEditPastSetEmitsTelemetry`)
- **setup:** wired session; edit a set via a pill.
- **expected:** `adjustGlyph == .manual` renders as "✎" on the active hero block (`ActiveView.swift:137-141, 152-158`). A single `execution.past_set_edited` event fires on the telemetry emitter, tagged with `workoutID` and the deterministic `setLogID`, and carrying `{"itemID": "...", "setIndex": N, "setLogID": "..."}` in `data_json`. Downstream analysis joins the event back to the mutated set_log by id.
