---
title: past-set-edit
status: living
purpose: Behavioral contract + QA scenarios for past-set-edit
covers:
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Push.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/RestView+Sheets.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/PastSetSheet.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/NumPadSheet.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/RirSheet.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistorySessionDetailView.swift
  - app/Packages/Core/Session/Sources/CoreSession/SessionReducer+Handlers.swift
---

# past-set-edit

## What it does
Correctively edit a logged set's load, reps, or RIR. **In active session** (RestView): tap the corresponding `DSPill` in the "JUST LOGGED" row. Load and reps open `NumPadSheet`; RIR opens `RirSheet` (`RestView+Sheets.swift:17-87`). Only the `lastLoggedSet` is editable here — `RestView.swift:144` reads `viewModel.lastLoggedSet` and the pills dispatch to the sheet for that single set. Commit calls `viewModel.editPastSet(...)` which dispatches the `.editPastSet` reducer mutation AND — after the apply — enqueues the corrected `SetLog` through `onSetLogged` with the SAME deterministic UUID as the original log push so the server upserts the existing row in place (`ExecutionViewModel.swift:editPastSet` → `ExecutionViewModel+Push.swift:handlePastSetEditSideEffects` → `enqueueEditedSet`). The shared UUID is derived by `ExecutionViewModel.setLogID(itemID:setIndex:)` via `Insecure.MD5` of `"\(itemID)|\(setIndex)"` fed into `UUID(uuid:)` — deterministic, so the original log and every edit push always carry the same id. Reducer updates load/reps/rir, stamps `adjust=.manual`, never fires autoreg (`SessionReducer+Handlers.swift:81-101`, comment: "Corrective — does NOT retrigger autoreg"). **In History** (`HistorySessionDetailView`): set rows are tappable but the sheet is stubbed — tap animates a brief highlight and calls `handleSetRowTap` which only toggles `highlightedSetID` (`HistorySessionDetailView.swift:88-125`, TODO at line 89). The push path is now available for the History-screen sheet to call into once it's built (bug-015).

## State surface
- **Inputs (active session, Rest screen):** tap on load pill → `NumPadSheet(step: 2.5, allowsDecimal: true)` (`RestView+Sheets.swift:28-48`). Tap reps pill → `NumPadSheet(step: 1, allowsDecimal: false)` (`:50-70`). Tap RIR pill → `RirSheet(initialValue: set.rir)` (`:72-87`). All sheets subtitle "correcting log · no autoreg".
- **Inputs (History tab):** tap on a set row in `HistorySessionDetailView` — **sheet stubbed** (`HistorySessionDetailView.swift:89-92`).
- **Outputs / side effects:** `.editPastSet` dispatched. Reducer: `adjust → .manual`, load/reps/rir updated where non-nil (nil = leave unchanged), `done` preserved (`SessionReducer+Handlers.swift:86-100`). Session persisted via `persist()` (`ExecutionViewModel+Persistence.swift:37-54`). Post-apply: `enqueueEditedSet` fires a `SetLog` through `onSetLogged` (same deterministic UUID as the original log → server upserts in place) and `emitPastSetEdited` fires `execution.past_set_edited` on the telemetry emitter.
- **State transitions:** purely a set-log mutation. No route change. No autoreg trigger. Push fires (fire-and-forget, same UUID as original log).

## What it deliberately doesn't do
- Does not re-fire autoreg (`SessionMutation.swift:90-100`, `SessionReducer+Handlers.swift:85-101`). Matches `docs/prescription.md` § "Edits don't retrigger".
- Does not change `done` — a past-set edit is by definition on a logged set; `applyEditPastSet` returns unchanged state when `old.done == false` (`SessionReducer+Handlers.swift:88-90`).
- Does not scope — no "this set / remaining" toggle. `NumPadSheet` comment flags the future scoped variant (`NumPadSheet.swift:10-14`).
- Does not allow editing anything but the **last-logged set** from RestView. There's no active-screen past-set picker in v0.
- Does not route to server on History-screen edits — because History-screen edits aren't wired (see bug-015). RestView edits DO push as of bug-010's fix; the History sheet will call the same `editPastSet` path once built.
- `PastSetSheet.swift` is a dispatcher type that's not actually used — `RestView+Sheets.swift` inlines the dispatch. Dead code kept for a future caller (`PastSetSheet.swift:8-11`).

## Edge cases handled in code
- Nil load/reps/rir in the mutation → "leave unchanged" (`SessionReducer+Handlers.swift:94-98` uses `?? old.loadKg` etc.).
- Edit of a non-done set via `.editPastSet` → no-op guard (`:88-90`). The Rest screen guards this naturally by only exposing pills when `lastLoggedSet != nil`.
- `adjust` always forced to `.manual` on past-set edit (`:97`), overwriting `.up` / `.down` / prior `.manual` — matches `docs/prescription.md` § "Autoreg + manual edit".
- Unknown itemID or setIndex → silent no-op via `updateSet` guards (`SessionReducer+Handlers.swift:170-175`).
- `NumPadSheet` primes its buffer from `initialValue`; integer-valued doubles render without decimal (`NumPadSheet.swift:115-123`).
- RirSheet "skip" returns without committing (`:85`) — intended behavior for RIR-only edits that the user opens then abandons.
- `adjustGlyph` renders `✎` for `.manual` on `ActiveView.swift:154-156`. The "adjusted" glyph shows in the active hero block.

## Known issues / gaps
- **History-screen edit stubbed** (bug-015). `docs/open-questions.md` § "Editing a completed, synced set from history" says "allowed, and push. UUIDs make it idempotent" as the assumption. The UI is still a flash-highlight placeholder, but the push path is now available — the sheet only needs to call `viewModel.editPastSet(...)` once it's built.
- `docs/open-questions.md:22-24` flags lack of `set_log.updated_at` on the server — no provenance for edits.
- `docs/open-questions.md:285-287` — **session detail set indexes render "2..N" instead of "1..N"** (cosmetic watchlist).
- Bugs fixed this session that touch History's path into this feature: `HistoryRow` Button-in-NavigationLink (now flattened); server naive datetime; `/api/sync/results` UUID case mismatch; `saveAndDone` missing status_update. See `docs/open-questions.md`.

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
- **expected:** a SECOND `onSetLogged` call fires carrying the POST-edit `reps`, `weight`, and `rir`, using the SAME deterministic UUID as the original log — derived from `(itemID, setIndex)` via `ExecutionViewModel.setLogID`. The server upserts the existing set_log row in place; no second row is created. Repeated edits all share the one UUID; the final state wins.

### S11. History-screen edit (stubbed)
- **setup:** History tab → session detail for a completed workout.
- **steps:** tap any set row.
- **expected:** brief accent-color flash via `highlightedSetID` animation (`HistorySessionDetailView.swift:93-106`). No sheet. No mutation. **Not built** — TODO at `:89-92` and `docs/open-questions.md:182-185`.

### S12. Session detail set indexes render 2..N (watchlist)
- **setup:** Session detail for a workout with N sets on an exercise.
- **expected:** rendered indexes start at 2, not 1 (`docs/open-questions.md:285-287`). Cosmetic; doesn't affect list/summary math. Flag as observed.

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
- **expected:** stubbed (S11). Until the History edit sheet ships, there is no path to correct a completed workout's sets from the client. Server has no endpoint for set_log edits today either (would be a `PUT /api/sync/results` with same UUID — infrastructure assumed but not verified in this audit).

### S_HISTORY_IDEMPOTENT. History edit upserts the server row in place (bug-040, fixed)
- **setup:** log a set on Active; save & done; server + local cache both carry the same deterministic `setLogID(itemID, setIndex)`. Open History → session detail → tap the set row → EditSetSheet → change reps → save.
- **expected:** the push hook receives a `SetLog` with `id` EQUAL to the existing cached/server id (not a freshly generated UUID). Server `sync_results` UPDATEs the row in place. No duplicate row. Root cause of the pre-fix duplicate was `writeCompletionToLocalCache` stamping a fresh `UUID()` on the local cache row while the push path used a deterministic id — the two sides carried different ids for the same logical set, so the History edit pushed an id the server had never seen. Fix aligned the local cache with the push path (same deterministic id on both sides). Covered by `testSaveAndDoneLocalCacheUsesDeterministicSetLogID` (FeaturesExecutionTests) and `testHistoryEditUsesExistingSetLogIdForIdempotentUpsert` (FeaturesHistoryTests).

### S21. Adjusted glyph + telemetry (tested: `testEditPastSetEmitsTelemetry`)
- **setup:** wired session; edit a set via a pill.
- **expected:** `adjustGlyph == .manual` renders as "✎" on the active hero block (`ActiveView.swift:137-141, 152-158`). A single `execution.past_set_edited` event fires on the telemetry emitter, tagged with `workoutID` and the deterministic `setLogID`, and carrying `{"itemID": "...", "setIndex": N, "setLogID": "..."}` in `data_json`. Downstream analysis joins the event back to the mutated set_log by id.
