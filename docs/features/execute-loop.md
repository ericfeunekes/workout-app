---
title: execute-loop
status: living
purpose: Behavioral contract + QA scenarios for execute-loop
covers:
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Persistence.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Push.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ActiveView.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/RestView.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/RestView+Banner.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/CompleteView.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/CompleteView+Ledger.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Sheets/LogSetSheet.swift
  - app/Packages/Core/Session/Sources/CoreSession/SessionReducer.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/SessionSeeder.swift
---

# execute-loop

## What it does
Once `SessionState.route` flips out of `.today`, `ExecutionView` renders the active/rest/complete router. `ExecutionViewModel` wraps the pure `SessionReducer`, owns a `SessionState` (seeded by `SessionSeeder` from each item's prescription), and mutates via a single `apply(_:)` funnel that persists to `SessionStore` as fire-and-forget JSON. Active screen: exercise name, "SET N OF M · REST mm:ss", progress pips, hero load + reps display, last-time chip, "log set N" button → opens a combined `LogSetSheet` (reps numpad + RIR row + inline "log" key — bug-023 fix) → `viewModel.logSet(reps:rir:)`. `logSet` asks the current driver (resolved from `block.timingMode`) for an autoreg outcome against the *pre-log* state, applies `[.logSet, .applyAutoregProposal?, .enterRest | .advanceFromRest, outcome.mutations...]` in order, enqueues the SetLog for push, and stores the proposal for the banner (accept-by-default — Undo reverts). Rest screen: `TimelineView(.periodic(by: 0.25))` drives a `DSRing` countdown against the absolute `state.restEndsAt`; three tap-editable "just did" pills (load / reps / RIR); autoreg banner with Undo; "next" → `advance()` → `.advanceFromRest` → next set / next item / next block / `.complete`. Complete screen: per-item ledger ("NxR @ kg · RIR n" or "N sets" when non-uniform); "save & done" → `saveAndDone()` emits terminal `status_update`, writes the completion into the local cache, dispatches `.save` with empty items (shell flips route back to Today), and fires `sessionStore.clear()`.

## State surface
- **Inputs:** `WorkoutContext` (workout + blocks + itemsByBlock + exercise catalog + lastPerformed); `SessionStore`; `DriverRegistry`; `ExecutionPushHooks` (`onSetLogged`, `onStatusChanged`, `onPushKick`); `LocalCompletionWriter`; `TelemetryEmitter`; `Clock`.
- **Outputs / side effects:** (1) reducer-driven `SessionState`; (2) `sessionStore.save(data)` JSON bytes on every mutation; (3) enqueue one `SetLog` per `logSet`; (4) enqueue one terminal `status_update(completed, completedAt)` on `complete` and again on `saveAndDone`; (5) kick push flush after completion; (6) local-cache `Workout` + `[SetLog]` write on `saveAndDone`; (7) telemetry events per intent.
- **State transitions (`SessionState.Route`):** `.today → .active` (start); `.active → .rest` (logSet with rest > 0); `.active → .active next set` (logSet with rest == 0 — `advanceFromRest` fires directly — see `ExecutionViewModel.swift:262-268`); `.rest → .active` (advance); `.rest → .complete` (advance past last set); `.active → .complete` (explicit End button); `.complete → .today` (saveAndDone clears state).

## What it deliberately doesn't do
- Does not compute programming / periodization / progression — Claude owns that (`CLAUDE.md` invariant).
- Does not auto-apply autoreg — reducer logs the set; the `.applyAutoregProposal` mutation is dispatched separately as accept-by-default, Undo available (`SessionMutation.swift:18-22`, `ExecutionViewModel.swift:257-260`).
- Does not retrigger autoreg on `editPastSet` (corrective edits mark `.manual`, don't nudge) (`SessionReducer+Handlers.swift:81-101`).
- Does not reset `autoregHeld` on swap — hold is session-scoped (`SessionReducer+Handlers.swift:128-131`).
- Does not await persistence / enqueue / local-cache writes before UI updates — all fire-and-forget (`ExecutionViewModel+Persistence.swift:37-54`, `+Push.swift:73-76`).
- Does not mutate the workout template on `editPendingSet` — session-local only (`SessionMutation.swift:83-88`).
- Does not expire stale sessions — `docs/open-questions.md` § "Stale session expiry" (decide-next).

## Edge cases handled in code
- **Progress-dot contract (bug-037).** `ActiveView` gates both the progress-dot row and the meta line's "OF M" denominator on `content.totalSets > 0`. Drivers for unbounded time-capped modes (AMRAP → `AMRAPDriver.unboundedRoundsCount == 0`) pass `totalSets = 0` to declare "no bound"; the view collapses the dot row and the meta line reads `ROUND N · REST mm:ss`. Bounded modes (StraightSets = sets count, Circuit/Superset = rounds, Tabata = 8, ForTime = rounds, EMOM = intervals, Continuous = 1) pass their real count and render the dots. If a future mode goes unbounded, seed `totalSets = 0` — do NOT reach for a large-integer sentinel (a prior AMRAP sentinel of 999 rendered 999 dots off-screen at x = -5797). Pinned by `AMRAPDriverBug037Tests` + `ActiveViewMetaLineTests`.
- Unknown itemID / setIndex is a silent no-op (`SessionReducer.swift:6-8`, `SessionReducer+Handlers.swift:164-178`).
- `rest_sec == 0` collapses rest entirely and advances directly (`ExecutionViewModel.swift:262-268`).
- Rest timer survives backgrounding: `restEndsAt` is an absolute `Date`, the `TimelineView` re-reads current time each tick (`RestView.swift:113-134`). Resolved per `docs/open-questions.md` § "In-flight rest timer persistence".
- Bodyweight item: `SessionSeeder` seeds `loadKg = 0`; `StraightSetsDriver` renders "BW" and passes `loadKg: nil` to the numpad so the sheet doesn't prefill a load (`StraightSetsDriver.swift:68-83`).
- Past-set edit always marks `.manual` and preserves `done` (`SessionReducer+Handlers.swift:85-100`).
- Pending-set edit silently drops on done sets (`SessionReducer+Handlers.swift:65-77`).
- Zero-item blocks (standalone `rest`) LAND on the cursor `(blockIndex, 0, 1)`; `ExecutionViewModel.enterRestIfZeroItemBlock` flips route to `.rest` with the `RestBlockDriver`'s `restDuration`. Same helper runs from `start()` AND `advance()`, so a rest block at position 0 (bug-034) enters `.rest` directly on `start` without ever landing on a dead `.active` screen. Advancing FROM a zero-item block jumps straight to the next block (`SessionReducer+Handlers.swift` § `nextCursor`). See `docs/features/timing-modes.md` § "`rest`".
- Autoreg is NOT proposed on the last set of an item (no remaining sets to adjust) (`StraightSetsDriver.swift:164-169`).
- Logged reps/RIR overwrite prescribed reps on the SetPlan; `rir` may be nil (user skipped the RIR sheet) (`SessionReducer+Handlers.swift:43-54`, `ActiveView.swift:79-89`).
- `saveAndDone` now enqueues `status_update` before wiping in-memory state (fix this session; `ExecutionViewModel.swift:365-371`).
- `.complete` reachable via `.advanceFromRest` (auto-advance) without going through explicit `complete()` (`SessionReducer+Handlers.swift:200-213`).

## Known issues / gaps
- Session detail displays set indexes "2..N" instead of "1..N" — downstream formatter bug, not execute-loop's (`docs/open-questions.md` § "Session detail renders 2..N").
- `holdAutoreg` uses a workaround in `undoAutoreg` — revert path uses `editPendingSet` which tags sets `.manual` (`ExecutionViewModel.swift:314-322`). Cosmetic: hold flag makes this moot for the session.
- `percent_1rm` prescriptions seed with `loadKg = 0` in v0 (`SessionSeeder.swift:105-109`); resolver deferred.
- Only `straight_sets` driver is wired in `DriverRegistry.init` default (`ExecutionViewModel.swift:430-438`); all other modes fall back to it silently. See `timing-modes.md`.
- `amrapToken` / `empty` prescriptions seed zero sets — `[]` returned from `SessionSeeder.setsFor` (`SessionSeeder.swift:114-118`).
- `docs/open-questions.md` § "Multiple active workouts" — starting workout B while A is `active` is not handled.

## QA scenarios

### S1. Happy path — full straight_sets workout
- **setup:** one block, one item, 3 sets, `rest_between_sets_sec: 90`.
- **steps:** start → log set 1 (reps 5, RIR 2, single `LogSetSheet`) → rest ticks down → tap next → active set 2 → log → rest → next → active set 3 → log → rest → next → complete → save & done.
- **expected:** three SetLog enqueues; one `status_update(completed)` on saveAndDone; route returns to Today; SessionStore is cleared.
- **notes:** logging collapses reps + RIR into a single `LogSetSheet` (bug-023 fix) — the prior three-screen chain (tap "log" → NumPad sheet → RIR sheet → rest) is gone on this flow. Past-set edit sheets on Rest still use the individual NumPad / Rir primitives since those are single-field corrections.

### S2. Boundary — `rest_sec = 0`
- **setup:** `rest_between_sets_sec: 0`.
- **steps:** log set 1.
- **expected:** route goes `.active → .active` (next set), skipping `.rest`. No rest screen shown. (`ExecutionViewModel.swift:266-268`)

### S3. Boundary — log last set
- **setup:** 3-set item, already on set 3 of only block.
- **steps:** log set 3 → rest → tap next.
- **expected:** route = `.complete`; `advanceFromRest` bypasses next-set/next-item/next-block and flips to `.complete` (`SessionReducer+Handlers.swift:200-213`).

### S4. Boundary — RIR skip (tested: `LogSetSheetTests.testCommitWithRirUntouchedFiresNilRir`)
- **setup:** any active set.
- **steps:** type reps → leave the RIR row untouched → tap the inline "log" key on the keypad.
- **expected:** `viewModel.logSet(reps: N, rir: nil)` fires; `SetLog.rir == nil`; rest starts; SetLog enqueue happens with `rir: nil`. Tapping a RIR row and then tapping it again also clears the selection (`LogSetSheetTests.testTappingSameRirClearsIt`).

### S5. Autoreg — overshoot triggers proposal
- **setup:** item has `target_rir: 2`, `autoreg.overshoot_at: 2`, `overshoot_step_kg: 2.5`, prescribed `100 kg × 5`; currently on set 1 of 3.
- **steps:** log reps 5, RIR 4.
- **expected:** enter rest; banner shows "next set: 102.5 kg · rir 4 > target 2"; remaining sets' loadKg now 102.5, `adjust = .up`.
- **notes:** accept-by-default — proposal is already applied. Undo reverts.

### S6. Autoreg — undo
- **setup:** continue from S5.
- **steps:** tap "undo".
- **expected:** remaining non-done sets revert to 100 kg; `autoregHeld = true` on the item; banner dismissed; subsequent logs this session won't propose (`ExecutionViewModel.swift:285-330`).
- **notes:** reverted sets end up with `adjust = .manual` (cosmetic; documented in `ExecutionViewModel.swift:311-322`).

### S7. Autoreg — hitFailure (RIR 0)
- **setup:** straight_sets with target_rir 2.
- **steps:** log reps 3 (of prescribed 5), RIR 0.
- **expected:** banner reads "hit failure · target rir 2"; load reduced on remaining sets (`RestView+Banner.swift` reason format).

### S8. Autoreg — no proposal on last set
- **setup:** 3-set item, on set 3.
- **steps:** log set 3 with RIR 4.
- **expected:** no banner; `DriverLogOutcome.proposal == nil` (`StraightSetsDriver.swift:164-169`).

### S9. Rest timer — background and return
- **setup:** rest ticking, `restEndsAt = now + 60s`.
- **steps:** background app for 30s; foreground.
- **expected:** ring shows ~30s remaining (absolute timestamp preserved; re-read on TimelineView tick). (`RestView.swift:177-182`)

### S10. Tap-to-edit — numpad edit of pending set
- **setup:** on Active set 2; set 2's load is 100 kg prescribed.
- **steps:** (via future UX hook or test harness) dispatch `editPendingSet(loadKg: 95, reps: nil)`.
- **expected:** set 2's load = 95, `adjust = .manual`; subsequent `logSet` on set 2 records 95.
- **notes:** UI entry point for editing pending sets from Active is not built in v0; edit of the "just logged" set is wired via the Rest tap-pills → sheets path (`RestView.swift:142-164` + `RestView+Sheets.swift`).

### S11. Tap-to-edit — rest pill edits just-logged set
- **setup:** just logged set 1 (reps 5, 100 kg, RIR 2); on rest screen.
- **steps:** tap the `REPS` pill → sheet → change to 6 → commit.
- **expected:** dispatches `.editPastSet(reps: 6)`; set 1's reps now 6, `adjust = .manual`, `rir` preserved.

### S12. Chaos — log set twice
- **setup:** any set.
- **steps:** log set, then re-dispatch `logSet` on the same setIndex.
- **expected:** `applyLogSet` overwrites — reps/rir updated, `done` stays true. Enqueues another SetLog with a new UUID (duplicate push row). Not idempotent by design — the in-memory state converges but the push queue accrues rows.

### S13. Force-complete mid-workout
- **setup:** 3-set workout, on set 2.
- **steps:** tap "End" (navbar).
- **expected:** route = `.complete`, ledger shows the one logged set; `status_update(completed)` enqueued (`ExecutionViewModel.swift:344-348`); tapping save & done enqueues status again (redundant but tolerated per push semantics).

### S14. Save & done — auto-advance path (regression watch)
- **setup:** last set logged → rest → tap next → `.complete` reached via `.advanceFromRest` (NOT via End button).
- **steps:** tap "save & done".
- **expected:** `enqueueStatusCompleted` fires (fix this session); server workout row transitions to `completed`. Watchlist per `docs/open-questions.md` § "Save & done didn't enqueue status_update".

### S15. Persistence — cold restore
- **setup:** mid-workout state saved to `SessionStore`.
- **steps:** kill app → relaunch → `restoreIfPossible()` runs.
- **expected:** route/cursor/logged sets restored. A corrupt payload silently returns the seeded state (`ExecutionViewModel+Persistence.swift:14-27`).

### S16. Bodyweight item
- **setup:** `bodyweight` prescription `{sets: 3, reps: 10}`.
- **steps:** land on Active.
- **expected:** hero shows "BW"; numpad initial load is nil; log commits with `loadKg = 0` in SetPlan; SetLog enqueue pushes `weight = nil, weight_unit = nil` (`ExecutionViewModel+Push.swift:60-71`).

### S17. Swap mid-item
- **setup:** item A on block 1; valid alternative exercise.
- **steps:** dispatch `.swap(itemID, toExerciseID)` mid-set.
- **expected:** exercise name updates via `performedExerciseID`; logged sets preserved; `autoregHeld` NOT reset. UI entry for swap is not built in v0; mutation path is wired.

### S18. Same exercise twice in one workout
- **setup:** two items with the same `exerciseID`.
- **steps:** walk through both.
- **expected:** each item has its own ItemLog + autoregHeld flag; proposals are per-item; last-time chip is identical on both (map keyed by exerciseID).

### S19. Rest-block at position 0 (bug-034)
- **setup:** workout whose block[0] is a standalone `rest` block (`itemsPerBlock[0] == 0`, `timingMode == .rest`, `timing_config_json = {"duration_sec": 45}`), and block[1] is a work block.
- **steps:** Today → start.
- **expected:** route goes straight to `.rest`, NOT `.active`. `restEndsAt = now + 45s`, cursor = `(0, 0, 1)`. Advance from rest → cursor bumps to `(1, 0, 1)`, route = `.active`. No dead "Active screen with no items" render.
- **notes:** `ExecutionViewModel.start()` dispatches `.start` then runs `enterRestIfZeroItemBlock()`, which detects `itemsPerBlock[0] == 0` and fires `.enterRest(durationSec:now:)`. Pinned by `testStartOnZeroItemFirstBlockEntersRest` and the pre-existing `testRestBlockAtStartPositionEntersRestOnStart`.
