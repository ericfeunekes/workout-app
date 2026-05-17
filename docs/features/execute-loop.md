---
title: execute-loop
status: built
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for execute-loop
covers:
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Persistence.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Push.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionProjection.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionNextUpPresentation.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionTimerPresentation.swift
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

## Target behavior

Execution should make the next physical action obvious at every moment: current
exercise or station, current position, visible timer, available log/skip
actions, what remains in the current block, and what comes after the current
block. Active, rest, and transition surfaces should be information-dense without
filler copy.

The target loop supports skip persistence, explicit unilateral work where it is
authored as separate exercise/workout items, bodyweight edits,
carry/distance/duration logging, current-block "what's next," superset logging
at rest, and between-block setup through `block-transition.md`.

## Current implementation
Once `SessionState.route` flips out of `.today`, `ExecutionView` renders the active/rest/transition/complete router. `ExecutionViewModel` wraps the pure `SessionReducer`, owns a `SessionState` (seeded by `SessionSeeder` from each item's prescription), and mutates via a single `apply(_:)` funnel that persists to `SessionStore` as fire-and-forget JSON. Active screen: exercise name, mode-native metadata (`SET`, `ROUND`, `INTERVAL`, `SEGMENT`, or `CONTINUOUS`), bounded whole-block progress (`BLOCK n / m`, `N / M DONE`), one primary timer hero, progress pips when bounded, hero load + reps display, last-time chip, smaller next-up card, and a mode-aware primary action. Straight sets have an explicit boundary: Active first shows a `READY` count-up and `set start`; only after `set start` does `workStartedAt` stamp, the timer switch to `SET ELAPSED`, and the primary action become `done`. `done` opens the row-based `LogSetSheet` for actuals (load + reps as side-by-side cells, RIR as a quick row; keypad appears only for the selected numeric cell; inline "log" commit) → `viewModel.logSet(loadKg:reps:rir:)`. Eligible active row-based routes also expose a secondary `skip` action; skip completes the current row for cursor/rest progress but persists `skipped=true` with no performance metrics. AMRAP, For Time, standalone Rest, Accumulate, and round-robin batch logging do not expose this deliberate skip affordance because their completion semantics are block/score/target owned. AMRAP is mode-specific: the primary button says `next`, logs the completed station, and advances round-robin with zero rest; when the cap ends, the result sheet captures only extra reps on the current partial station while completed prior stations show as checkmarked and unreached stations stay locked; saving appends an `AMRAP result: N rounds + M reps` note before routing out. For Time's current M2 contract is finish-only: tapping `finish` immediately logs one total-duration result, while an expired cap does not auto-complete because cap-partial capture is deferred. `logSet` asks the current driver (resolved from `block.timingMode`) for an autoreg outcome against the *pre-log* state, applies `[.logSet, .applyAutoregProposal?, .enterRest | .advanceFromRest, outcome.mutations...]` in order, enqueues the SetLog for push, and stores the proposal for the banner (accept-by-default — Undo reverts). Rest screen: `TimelineView(.periodic(by: 0.25))` drives a `DSRing` countdown against the absolute `state.restEndsAt`; bounded work rests show a block progress grid under the timer with performed/skipped/pending dots and `N / M DONE`; strength rests show tap-editable "just did" pills (load / reps / RIR), skipped rows show `SKIPPED SET` with no editable metrics, and cardio rests suppress strength-only correction controls; smaller next-up card; autoreg banner with Undo; "next" → `advance()` → `.advanceFromRest` → next set / next item / next block / transition / `.complete`. Transition screen appears between real work blocks when the next block has setup value, shows the finished block, next block, timing mode, first task, timing setup, and all station setup lines, then `start block` enters the next active route without starting explicit-set work early. Complete screen: per-item ledger ("NxR @ kg · RIR n" or "N sets" when non-uniform); "save & done" → `saveAndDone()` builds one `WorkoutCompletionRecord`, durably queues grouped completion results, writes the same record into the local cache, dispatches `.save` with empty items (shell flips route back to Today), and clears `SessionStore`.

## State surface
- **Inputs:** `WorkoutContext` (workout + blocks + itemsByBlock + exercise catalog + lastPerformed); `SessionStore`; `DriverRegistry`; `ExecutionPushHooks` (`onSetLogged`, `onWorkoutCompleted`, `onPushKick`); `LocalCompletionWriter`; `TelemetryEmitter`; `Clock`.
- **Outputs / side effects:** (1) reducer-driven `SessionState`; (2) `sessionStore.save(data)` JSON bytes on every mutation; (3) enqueue one `SetLog` per `logSet`; (4) durably enqueue one grouped completion result on `saveAndDone` (`complete()` only flips route; terminal publication is owned exclusively by `saveAndDone`); (5) kick push flush after completion enqueue; (6) local-cache `Workout` + `[SetLog]` write on `saveAndDone`; (7) telemetry events per intent.
- **State transitions (`SessionState.Route`):** `.today → .active` (start); `.active → .rest` (logSet with rest > 0); `.active → .active next set` (logSet with rest == 0 and no block boundary); `.active/.rest → .transition` (next real work block needs setup); `.transition → .active` (`start block`); `.rest → .active` (advance within current setup); `.rest → .complete` (advance past last set); `.active → .complete` (explicit End button); `.complete → .today` (saveAndDone clears state).
- **Timer anchors:** `restEndsAt` (rest countdown), `blockEndsAt` (AMRAP / ForTime / EMOM / Tabata total cap), `workEndsAt` (Tabata / intervals / custom work window), `intervalAnchorAt` (EMOM boundary), `workReadyAt` (straight-set ready/prep count-up), and `workStartedAt` (active-set elapsed anchor). These anchors are state, not presentation; views should not independently infer timer labels from driver metadata.
- **Next-up read model:** Active and Rest derive next-up context from the current cursor and the loaded workout structure. It can label the next set, next exercise, next block, rest block, or workout completion. The compact card is tappable for a read-only preview sheet. This is display context only; it must not perform workout reorganization or programming logic.
- **Execution projection:** `ExecutionProjection` is the shared read-model seam for execution surfaces. Preview, Active/Rest, History correction, and Watch mapping should ask it for current task, remaining work, upcoming work, block progress, editability, and timer state rather than re-deriving cursor, driver, and timer rules from SwiftUI. This layer is view-neutral and watch-neutral: it may consume `WorkoutContext` and `SessionState`, but `FeaturesExecution` must not import Watch packages or sync/protocol DTOs. Unbounded modes such as AMRAP must not leak internal sentinel set counts into remaining/progress displays.
- **Interaction model:** timer surfaces own timer semantics; Active's exercise name / hero prescription is the long-press swap target; Rest's "just logged" load / reps / RIR pills are tap-to-correct controls. Hidden interactions need small visible cues because the gym context is sweaty, distracted, and usually one-handed.

## Timer boundary contract
Once the user taps `start workout`, every non-complete execution route must expose exactly one primary visible running timer. Internal ticking without a visible timer is not sufficient for gym use. This is implemented as a derived timer presentation on the view model. Active keeps set/round metadata structural and renders the timer once as a primary hero; Rest renders the rest countdown as the primary timer.

- **Rest route:** primary timer is `REST mm:ss` from `restEndsAt`; small `+30 sec` / `+1 min` controls are always available to extend `restEndsAt`.
- **Expired rest:** Rest flips to a red `OVER REST mm:ss` count-up while keeping the same add-time controls available.
- **Active route with `workEndsAt`:** primary timer is `WORK mm:ss` for the current work window.
- **Active route with an EMOM / interval boundary:** primary timer is `INTERVAL mm:ss` to the next boundary; total block cap can be secondary.
- **Active route with `blockEndsAt`:** primary timer is a mode-specific global block cap, e.g. `AMRAP CAP mm:ss`, `TIME CAP mm:ss`, or `EMOM CAP mm:ss`. This timer belongs to the whole block, not the current station.
- **Active straight-set route before Set Start:** primary timer is `READY mm:ss` from `workReadyAt`; `Done`/logging is unavailable and direct log attempts are ignored.
- **Active route with no countdown boundary after work starts:** primary timer is `SET ELAPSED mm:ss` from `workStartedAt`, so straight strength work is still never timerless.
- **Complete route:** no running timer is required; show final elapsed duration if useful.

Do not regress to the old pattern where Active renders `REST 0:00` while a block timer silently ticks elsewhere. Do not duplicate timer text in the meta line and the timer hero.

## What it deliberately doesn't do
- Does not compute programming / periodization / progression — Claude owns that (`CLAUDE.md` invariant).
- Does not auto-apply autoreg — reducer logs the set; the `.applyAutoregProposal` mutation is dispatched separately as accept-by-default, Undo available (`SessionMutation.swift:18-22`, `ExecutionViewModel.swift:257-260`).
- Does not retrigger autoreg on `editPastSet` (corrective edits mark `.manual`, don't nudge) (`SessionReducer+Handlers.swift:81-101`).
- Does not reset `autoregHeld` on swap — hold is session-scoped (`SessionReducer+Handlers.swift:128-131`).
- Does not await ordinary live-session persistence or per-set enqueue writes before UI updates. Save & Done does await completion enqueue and local completion write before clearing the session.
- Does not mutate the workout template on `editPendingSet` — session-local only (`SessionMutation.swift:83-88`).
- Does not expire stale sessions — `docs/open-questions.md` § "Stale session expiry" (decide-next).

## Edge cases handled in code
- **Progress-dot / meta-line contract (bug-037).** `ActiveView` gates progress dots on `content.totalSets > 0` and uses timing-mode language for the header line: straight strength = `SET`, round-based modes = `ROUND`, EMOM / intervals = `INTERVAL`, custom = `SEGMENT`, continuous = `CONTINUOUS`. Drivers for unbounded time-capped modes (AMRAP → `AMRAPDriver.unboundedRoundsCount == 0`) pass `totalSets = 0` to declare "no bound"; the view collapses the dot row and the meta line reads `ROUND N`. Bounded modes pass their real count and render the dots. If a future mode goes unbounded, seed `totalSets = 0` — do NOT reach for a large-integer sentinel (a prior AMRAP sentinel of 999 rendered 999 dots off-screen at x = -5797). Pinned by `AMRAPDriverBug037Tests` + `ActiveViewMetaLineTests`.
- **Active block-position strip.** `ActiveView` renders whole-block
  progress from `ExecutionProjection.blockProgress` when the block has a
  bounded positive `totalSets`. This is separate from exercise-local progress
  pips: the strip answers where the athlete is in the block, while pips answer
  the current item/set sequence. Pinned by
  `ActiveViewMetaLineTests.testBlockProgressStripRendersOnlyWhenBounded` and
  `testBlockProgressSummaryUsesCompletedOverTotal`.
- **Projection count contract.** `ExecutionProjection` treats AMRAP set counts as unbounded even if `SessionState` carries an internal cap for cursor advancement. Remaining/progress models should show no fake denominator for those blocks. Pinned by `ExecutionProjectionTests.testAMRAPProjectionKeepsUnboundedRoundsReadable`.
- Straight-set logging is guarded behind `startCurrentSet()`: workout start and rest advance land on Active with `workReadyAt` and nil `workStartedAt`; `Set Start` stamps `workStartedAt`; `logSet` / `logSet(loadKg:reps:rir:)` no-op until that stamp exists. This prevents fake/default actuals from entering push/autoreg while still keeping a visible prep timer.
- Deliberate skip uses `.skipSet`: the row becomes `done=true` and
  `skipped=true`, cursor/rest advancement treats it as complete, and push/local
  completion emit a `SetLog` with performance metrics empty. Rest displays it
  as `SKIPPED SET`, not as editable performed work. Pinned by
  `CoreSessionTests`, `ExecutionViewModelPushTests`,
  `ExecutionViewModelTests.testSaveAndDoneLocalCachePreservesSkippedWithoutPerformanceMetrics`,
  and `PostLogUnitDisplayTests.testSkippedSetDoesNotRenderPerformedMetricAffordances`.
- Rest block progress renders only for bounded work blocks with real rows.
  Standalone rest blocks, unbounded/sentinel modes (`amrap`, `emom`,
  `accumulate`), and round-robin batch-rest pre-commit states hide the grid so
  the UI does not invent progress. Set-major blocks order dots by item/set;
  round-robin blocks order dots by execution order. Skipped rows count as
  complete but render distinctly from performed rows. Pinned by
  `PostLogUnitDisplayTests.testRestProgressOrderFollowsSetMajorExecutionOrder`,
  `testRestProgressOrderFollowsRoundRobinExecutionOrder`,
  `testRestProgressGridSuppressesUnboundedTimingModes`, and
  `testRestProgressGridSuppressesRoundRobinBatchRoundRest`.
- Unknown itemID / setIndex is a silent no-op (`SessionReducer.swift:6-8`, `SessionReducer+Handlers.swift:164-178`).
- `rest_sec == 0` collapses rest entirely and advances directly (`ExecutionViewModel.swift:262-268`).
- Rest timer survives backgrounding: `restEndsAt` is an absolute `Date`, the `TimelineView` re-reads current time each tick (`RestView.swift:113-134`). Resolved per `docs/open-questions.md` § "In-flight rest timer persistence".
- Bodyweight item: `SessionSeeder` seeds `loadKg = 0`; `StraightSetsDriver` renders "BW" and passes `loadKg: nil` to the numpad so the sheet doesn't prefill a load (`StraightSetsDriver.swift:68-83`).
- Past-set edit always marks `.manual` and preserves `done` (`SessionReducer+Handlers.swift:85-100`).
- Pending-set edit silently drops on done sets (`SessionReducer+Handlers.swift:65-77`).
- Zero-item blocks (standalone `rest`) LAND on the cursor `(blockIndex, 0, 1)`; `ExecutionViewModel.enterRestIfZeroItemBlock` flips route to `.rest` with the `RestBlockDriver`'s `restDuration`. Same helper runs from `start()` AND `advance()`, so a rest block at position 0 (bug-034) enters `.rest` directly on `start` without ever landing on a dead `.active` screen. Advancing FROM a zero-item block jumps straight to the next block (`SessionReducer+Handlers.swift` § `nextCursor`). See `docs/features/timing-modes.md` § "`rest`".
- Autoreg is NOT proposed on the last set of an item (no remaining sets to adjust) (`StraightSetsDriver.swift:164-169`).
- Logged reps/RIR overwrite prescribed reps on the SetPlan; `rir` may be nil (user skipped the RIR sheet) (`SessionReducer+Handlers.swift:43-54`, `ActiveView.swift:79-89`).
- `saveAndDone` now publishes one grouped completion record before wiping in-memory state.
- `.complete` reachable via `.advanceFromRest` (auto-advance) without going through explicit `complete()` (`SessionReducer+Handlers.swift:200-213`).

## Current gaps

- `EXEC-GAP-001`: Primary CTA enabled/disabled contrast and tap targets need
  simulator proof.
- `EXEC-GAP-002`: Bodyweight editability must be proven through the shared edit
  surface.
- `EXEC-GAP-003`: Active/rest focal hierarchy and scrolling polish need proof
  across non-straight-set modes.
- `EXEC-GAP-004`: Rest timer continuity requires simulator or pinned UI proof.
- `EXEC-GAP-005`: Carry/distance/duration active logging exists, and History
  correction parity exists, but preview/active edit unification and broader
  mode-specific proof remain open.
- `EXEC-GAP-006`: ETA remaining remains later polish.
- `EXEC-GAP-007`: Starting workout B while workout A is active has no selected
  behavior.
- `EXEC-GAP-008`: Cluster/rest-pause expanded per-slot actual editing remains
  deferred; the current app logs one top-level row per composed set.
- `EXEC-GAP-009`: Numeric-entry flashes and log/rest transition flicker have
  been seen in visual QA but are not reproducible as deterministic defects.
  Capture simulator video before changing sheet/router code.
- `EXEC-GAP-010`: Active, Rest, and Complete need smaller SwiftUI component
  seams before adding more interactions. The seams must preserve
  `ExecutionProjection` ownership, timer ownership, and the no-app-programming
  invariant.
- `EXEC-GAP-012`: Timer and transition runtime claims need ETTrace-backed proof
  for the timer gauntlet before performance or smoothness is marked verified.

## QA scenarios

### S1. Happy path — full straight_sets workout
- **setup:** one block, one item, 3 sets, `rest_between_sets_sec: 90`.
- **steps:** start → READY timer appears → tap `set start` → SET ELAPSED timer appears → tap `done` → log set 1 (load if changed, reps 5, RIR 2, single row-based `LogSetSheet`) → rest ticks down → tap next → active set 2 in READY state → set start → done/log → rest → next → active set 3 → set start → done/log → rest → next → complete → save & done.
- **expected:** three SetLog enqueues during logging; one grouped completion result on saveAndDone; route returns to Today; SessionStore is cleared.
- **notes:** logging collapses load + reps + RIR into a compact row-based `LogSetSheet` (bug-023 plus log-time load correction) — the prior three-screen chain (tap "log" → NumPad sheet → RIR sheet → rest) is gone on this flow. Load and reps share one row so future superset/drop-set rows can stack without the sheet turning into a dashboard. Past-set edit sheets on Rest still use the individual NumPad / Rir primitives since those are single-field corrections.

### S2. Boundary — `rest_sec = 0`
- **setup:** `rest_between_sets_sec: 0`.
- **steps:** log set 1.
- **expected:** route goes `.active → .active` (next set), skipping `.rest`. No rest screen shown. (`ExecutionViewModel.swift:266-268`)

### S2A. Timer boundary — Active cannot start timerless
- **setup:** either a straight-set block with no countdown or one `for_time` block, 2 rounds, `time_cap_sec: 600`, first item has no rest.
- **steps:** start workout.
- **expected:** Active shows a visible primary timer immediately. Straight sets show `READY mm:ss` until `set start`, then `SET ELAPSED mm:ss`; capped modes show a visible primary global-cap countdown immediately, e.g. `TIME CAP 10:00` for For Time or `AMRAP CAP 10:00` for AMRAP. The meta line remains structural (`SET n OF m` or `ROUND n`). It must not show `REST 0:00` as the only timer-like metadata.
- **regression evidence:** simulator QA on 2026-04-24 reproduced the pre-fix failure on `UX Tomorrow Conditioning`; `ExecutionViewModelTickBlockTimerTests.testForTimeStartExposesCapTimerPresentationImmediately` now pins the fix.

### S2B. Next-up context — Active and Rest preview what comes next
- **setup:** workout has either another item in the current block, another set of the current item, or a following block.
- **steps:** start workout; inspect Active; log into Rest where applicable.
- **expected:** Active shows a compact next-up card beneath the current prescription; Rest shows the next block/set/exercise beneath the rest timer. Tapping either card opens a read-only "coming up" preview sheet. The card is informational only and does not mutate the plan.
- **regression evidence:** `ExecutionViewModelTickBlockTimerTests.testForTimeStartExposesNextExerciseContext`, `testStraightSetStartExposesNextSetContext`, and `testRestBlockStartExposesNextBlockContext` pin the read model.

### S3. Boundary — log last set
- **setup:** 3-set item, already on set 3 of only block.
- **steps:** log set 3 → rest → tap next.
- **expected:** route = `.complete`; `advanceFromRest` bypasses next-set/next-item/next-block and flips to `.complete` (`SessionReducer+Handlers.swift:200-213`).

### S4. Boundary — RIR skip (tested: `LogSetSheetTests.testCommitWithoutEditsFiresSeededLoadRepsAndNilRir`)
- **setup:** any active set.
- **steps:** for straight sets, tap `set start` then `done`; type reps → leave the RIR row untouched → tap the inline "log" key on the keypad.
- **expected:** `viewModel.logSet(loadKg: prescribedLoad, reps: N, rir: nil)` fires; `SetLog.rir == nil`; rest starts; SetLog enqueue happens with `rir: nil`. Tapping a RIR row and then tapping it again also clears the selection (`LogSetSheetTests.testTappingSameRirClearsIt`).

### S4A. Log-time load correction
- **setup:** weighted strength set is active.
- **steps:** tap `log set`; tap the load row; edit load with decimal keypad; tap `log`.
- **expected:** the pending `SetPlan.loadKg` is updated before `.logSet`, so Rest "just logged", completion ledger, local cache, and push all use the actual load. Bodyweight rows do not expose load editing.
- **regression evidence:** `LogSetSheetTests.testEditingLoadSupportsDecimalAndPreservesReps`, `LogSetSheetTests.testBodyweightRowsDoNotExposeLoadEditing`, and `ExecutionViewModelTests.testLogSetWithEditedLoadWritesActualLoadBeforeLogging`.

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

### S12A. Chaos — straight-set log before Set Start
- **setup:** straight-set block immediately after workout start or after advancing out of rest.
- **steps:** dispatch `logSet` or `logSet(loadKg:reps:rir:)` before `startCurrentSet()`.
- **expected:** no SetPlan is marked done, no SetLog is enqueued, no autoreg proposal is generated, and the UI remains in READY state with `set start` as the primary action.

### S13. Force-complete mid-workout
- **setup:** 3-set workout, on set 2.
- **steps:** tap "End" (navbar).
- **expected:** route = `.complete`, ledger shows the one logged set; `complete()` only transitions state — NO completion publication here. Tapping save & done publishes the grouped completion result (ownership moved to `saveAndDone` exclusively — see `save-and-done.md` S2).

### S14. Save & done — auto-advance path (regression watch)
- **setup:** last set logged → rest → tap next → `.complete` reached via `.advanceFromRest` (NOT via End button).
- **steps:** tap "save & done".
- **expected:** grouped completion publication fires; server workout row transitions to `completed` with final logs in the same results payload.

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
- **expected:** exercise name updates via `performedExerciseID`; logged sets preserved; `autoregHeld` NOT reset. UI entry for swap is wired via `ActiveView+Swap` long-press → `SwapSheet`; see `exercise-swap.md` for the full scenario set.

### S18. Same exercise twice in one workout
- **setup:** two items with the same `exerciseID`.
- **steps:** walk through both.
- **expected:** each item has its own ItemLog + autoregHeld flag; proposals are per-item; last-time chip is identical on both (map keyed by exerciseID).

### S19. Rest-block at position 0 (bug-034)
- **setup:** workout whose block[0] is a standalone `rest` block (`itemsPerBlock[0] == 0`, `timingMode == .rest`, `timing_config_json = {"duration_sec": 45}`), and block[1] is a work block.
- **steps:** Today → start.
- **expected:** route goes straight to `.rest`, NOT `.active`. `restEndsAt = now + 45s`, cursor = `(0, 0, 1)`. Advance from rest → cursor bumps to `(1, 0, 1)`, route = `.active`. No dead "Active screen with no items" render.
- **notes:** `ExecutionViewModel.start()` dispatches `.start` then runs `enterRestIfZeroItemBlock()`, which detects `itemsPerBlock[0] == 0` and fires `.enterRest(durationSec:now:)`. Pinned by `testStartOnZeroItemFirstBlockEntersRest` and the pre-existing `testRestBlockAtStartPositionEntersRestOnStart`.
