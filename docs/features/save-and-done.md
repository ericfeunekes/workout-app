---
title: save-and-done
status: built
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for save-and-done
covers:
  - app/Packages/Features/Execution/Sources/FeaturesExecution/CompleteView.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/CompleteView+Ledger.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Push.swift
  - app/Packages/Persistence/Sources/Persistence/WorkoutCache+History.swift
  - app/Packages/Shell/Sources/Shell/AppBootstrap.swift
---

# save-and-done

## What it does
On the `.complete` route the user sees a per-exercise ledger, an optional body-weight field, an optional note field, and a single "save & done" button (`CompleteView.swift`). Tapping it calls `ExecutionViewModel.saveAndDone(note:bodyweightKg:)`, which does five things in order: (1) builds one local `WorkoutCompletionRecord` from the completed `Workout` plus all `done` SetLogs, (2) publishes that record through `onWorkoutCompleted` so REST durably queues one grouped `completionResults` payload carrying both final `set_logs` and the completed `status_update`, then kicks the flusher, (3) awaits the local `WorkoutCache` writer for that same record so the History tab can see it immediately when the best-effort cache write succeeds, (4) if the user typed a body weight, fires the `onUserParameterChanged` hook with a fresh `UserParameter{key:"bodyweight_kg",source:.appLog}` — Shell wires that to `WorkoutCache.saveUserParameter` + `SyncAPI.pushUserParameter` which enqueues `POST /api/user-parameters` (bug-011 fix), and (5) only after the durable completion queue handoff succeeds, dispatches `.save(freshItems:, freshStructure:)` through the reducer which flips route → `.today` and empties the log, then clears `SessionStore` so next launch won't resume.

**Note dictation is deferred** — the `saveAndDone` doc comment carries a TODO linking the open question. The TextField is the minimum UI that unblocks bug-012; the mic affordance is a polish item.

**Ledger rhythm & font pairing** — each ledger row renders inside a `DSCard(padding: 0)` with its own 16pt horizontal / 12pt vertical padding (`CompleteView.swift`, bug-028 fix). Exercise text no longer butts against the card edge, and the row rhythm stays uniform across cards. The uniform "Nxr @ L kg · RIR n" summary routes the weight + unit through `DSWeightLabel` (`CompleteView+Ledger.swift` → `ledgerSummaryView`, bug-027 fix) so the "kg" shares the same mono family + weight as the digits; BW-only and "N sets" summaries render plain.

## State surface
- **Inputs:** `viewModel.state` (all logged sets), `viewModel.context.workout` (template id/name/tags), `clock.now`.
- **Outputs / side effects:**
  - `onWorkoutCompleted(WorkoutCompletionRecord)` enqueues one grouped completion result and `onPushKick()` fires so the flusher drains immediately.
  - `localCompletionWriter(WorkoutCompletionRecord)` attempts the same completed workout, legacy set logs, and primitive set logs in `WorkoutCache` via best-effort `saveWorkout` + `saveSetLogs` + `savePrimitiveSetLogs`.
  - `SessionState` → route `.today`, `items == []`, `structure` empty.
  - `SessionStore` row deleted (`SessionStore.swift:56`).
  - Telemetry proof events: `execution.completion_record_built`,
    `execution.completion_publish_finished`,
    `execution.completion_local_writer_completed`,
    `execution.completion_local_cache_write_succeeded/failed`, and
    `execution.session_mutation` with `{"mutation":"save"}`.
- **State transitions:** `.complete` → `.today` (via `.save`). Shell's `RootTabView` re-reads `executionVM.state.route` and flips back to Today.

## What it deliberately doesn't do
- Does NOT offer dictation-mic capture on the note (bug-012 TODO — tracked as a polish item).
- Does NOT confirm before wiping the session — the tap is immediate.
- Does NOT await the network flush. It does await durable completion enqueue before clearing the live session; the local cache writer is awaited but its SwiftData writes are best-effort.
- Does NOT validate that every prescribed set was logged — an early "End" button path can reach `.complete` with partial logs.
- Does NOT offer rich note capture or dictation yet. Plain text notes are
  carried through the grouped completion publication and persisted on
  `Workout.notes`.

## Edge cases handled in code
- Auto-advance path vs explicit End button both route through `saveAndDone` for the terminal completion publication (R2.5, `docs/open-questions.md:282`). Before the fix, the auto-advance path left the server's workout row `planned` forever. `complete()` itself no longer enqueues — the terminal push is owned exclusively by `saveAndDone` so force-complete + save-and-done no longer double-pushes (`ExecutionViewModel.swift:393-405`).
- Re-entrancy guard on `saveAndDone` (R2.11 — `ExecutionViewModel+SaveAndDone.swift`): a rapid double-tap or a SwiftUI re-render that fires the tap action twice is dropped on the floor. First call sets an `@MainActor`-isolated in-flight marker (weak-to-strong `NSMapTable`); subsequent calls see the marker and return silently. Without this, a duplicate bodyweight `UserParameter` row would land in the append-only `user_parameters` table forever. Views also bind `.disabled(viewModel.saveAndDoneInFlight)` as belt-and-suspenders.
- `localCompletionWriter` is `nil` in the pure-offline test path — `writeCompletionToLocalCache` returns early.
- `SetLog` is only emitted for sets with `set.done == true` (`ExecutionViewModel+Push.swift:127`).
- Each cache-write SetLog is stamped with the deterministic `setLogID(itemID:setIndex:)` UUID (`ExecutionViewModel+Push.swift:584`) — same derivation used by the per-set push enqueue, so local-cache ids MATCH push-queue ids for the same `(itemID, setIndex)` (R1.3b-v2 — see `ExecutionViewModel+Push.swift:45`).
- Completion publisher (`syncAPI.pushCompletion`) must succeed before the live session is cleared. The persistent push queue then owns retries of the grouped completion item.
- Local cache writes are wrapped in `try?` — a failed local write just means History waits for the next pull.

## Current gaps

- `SAVE-GAP-001`: Dictation or richer note capture is deferred. The current
  contract is plain text note entry on completion.
- `SAVE-GAP-002`: Save-and-done does not validate that every prescribed set was
  logged before completion. Early End can still save a partial workout.

## QA scenarios

### S1. Happy path — auto-advance → save & done
- **setup:** Seeded push workout, offline-capable build.
- **steps:** Log every prescribed set; after the last set, cursor auto-advances through `.rest` → `.complete`. Tap "save & done".
- **expected:** Route flips to `.today`; workout appears in History list immediately when the best-effort local cache writer succeeds; push queue drains a grouped `completionResults` payload with set logs and completed status; `SessionStore` row cleared.
- **notes:** This is the regression path for the fix in `docs/open-questions.md:282`.

### S2. Happy path — explicit End button → save & done
- **setup:** Mid-workout (some sets logged, some not), push stack available.
- **steps:** Tap End from the nav bar to force `.complete`; tap save & done.
- **expected:** `complete()` flips the route to `.complete` but does NOT enqueue a terminal push (that responsibility moved to `saveAndDone` exclusively — `ExecutionViewModel.swift:393-405`). `saveAndDone()` then publishes one grouped completion record. Ledger reflects only the logged sets.
- **notes:** Prior to R2.5, both `complete()` and `saveAndDone()` enqueued on the End path — double-push. The current invariant is "exactly one grouped completion publication per completed workout, sourced from `saveAndDone`."

### S3. Save & done with zero sets logged
- **setup:** User taps Start, never logs a set, reaches `.complete` via the End button.
- **steps:** Tap save & done.
- **expected:** grouped completion still enqueues with completed status and zero SetLogs; `localCompletionWriter` attempts the workout row (status completed, `completedAt = now`) but ZERO SetLogs. History shows the workout with no exercise cards when the best-effort cache write succeeds.
- **notes:** Confirm the Workout row appears in History list with the correct empty-state rendering; `SessionDetail.durationSeconds` returns nil (no set timestamps).

### S4. Save & done offline (Tailscale unreachable)
- **setup:** Airplane mode or cable pulled; at least one completed set.
- **steps:** Tap save & done.
- **expected:** Route flips after the grouped completion is durably enqueued to the persistent push queue and the local cache writer has been awaited. `onPushKick` fires but the flusher fails silently. History tab shows the workout if the best-effort local cache write succeeds; otherwise it catches up after a successful pull.
- **notes:** Next time connectivity returns, `PushFlusher` drains and server catches up.

### S5. Rapid double-tap on save & done (R2.11)
- **setup:** Normal completion.
- **steps:** Tap save & done twice within ~100ms.
- **expected:** First tap flips `saveAndDoneInFlight` to `true` and runs the full path; the second tap hits the re-entrancy guard (`ExecutionViewModel+SaveAndDone.swift`) and returns silently. Exactly one grouped completion publication, exactly one bodyweight `UserParameter`, exactly one local-cache writer invocation.
- **notes:** The guard is the correctness check; `.disabled(viewModel.saveAndDoneInFlight)` on the button is belt-and-suspenders. The flag is a per-VM stored `Bool` (`saveAndDoneInFlightStorage`) — the shell rebuilds a fresh VM per workout via `AppBootstrap+Hooks.makeCompletionWriter`, so the flag is naturally reset between workouts (qa-002 / qa-003 fix).

### S6. Server returns 404 on completion results (stale workoutID)
- **setup:** Force the server to 404 the grouped completion push.
- **steps:** Complete + save & done.
- **expected:** the durable enqueue has already succeeded, so the server 404 is handled later by push-queue dead-letter policy. Save & Done still routes through the local completion writer.
- **notes:** This scenario belongs primarily to push-queue.md; Save & Done owns creating and durably handing off the completion record.

### S7. Local cache write fails (SwiftData error)
- **setup:** Force a SwiftData error in `saveWorkout` (e.g., model-context invalidation).
- **steps:** save & done.
- **expected:** `try?` swallow in the local completion writer. Route still flips. Next `syncAPI.pullLatest` backfills History. No user-visible error.
- **notes:** Exercise the explicit do/catch/rollback in `WorkoutCache+History.swift:139` — partial inserts should not leak. See persistence.md S10.

### S8. History visible immediately after save & done
- **setup:** Normal completion.
- **steps:** save & done → navigate to History tab.
- **expected:** The just-completed workout is in the top week group with the correct program name and date.
- **notes:** This is the bug fix from `docs/open-questions.md` "save & done doesn't persist to local cache". Watch for: HistoryViewModel must `load()` on appear or the new row won't show until a restart.

### S9. History does NOT auto-refresh on Complete screen
- **setup:** History tab already loaded in a prior session.
- **steps:** Complete a new workout; save & done; tap History without any explicit refresh.
- **expected:** **Unclear from code** — `HistoryViewModel.load()` is called by the view's `.task`, which re-fires on tab appearance. If SwiftUI caches the view, the new row may not appear without a pull-to-refresh.
- **notes:** Likely real bug; needs a pin. See history.md S13.

### S10. Cold restart immediately after save & done
- **setup:** save & done → kill the app process after completion handoff but before `sessionStore.clear()` completes.
- **steps:** Relaunch.
- **expected:** The grouped completion is already durable in the push queue and the local cache writer has been attempted. `SessionStore` row may still exist until clear finishes; restore either finds no row or a post-save `.today` snapshot. If the best-effort local cache write failed, the push queue still owns the surviving completion artifact.
- **notes:** The unsafe window before this change was process death after clearing the session but before durable completion enqueue. Save & Done now orders the completion handoff before session clear.

### S11. Body weight capture (tested: `testSaveAndDoneEnqueuesBodyweightUserParameter`, `testSaveAndDoneNilBodyweightDoesNotFire`)
- **setup:** Normal completion.
- **steps:** Type a body weight into the decimal TextField (e.g. "82.5"); tap save & done.
- **expected:** A `UserParameter` with `key = "bodyweight_kg"`, `value = "82.5"`, `source = .appLog`, and `updatedAt = clock.now` fires through the `onUserParameterChanged` hook exactly once. Shell wires that to (a) `WorkoutCache.saveUserParameter` for immediate local reads, and (b) `PushQueue.enqueueUserParameter` which routes to `POST /api/user-parameters` on the next flush.
- **notes:** Empty string / unparseable text → no enqueue; save-path proceeds normally. Contract test `PushQueue — userParameter routes to /api/user-parameters` (SyncTests) pins the wire shape.

### S12. Workout note capture (tested: `testSaveAndDoneWritesNoteToCompletedWorkout`, `testSaveAndDoneEmptyNoteCollapsesToNil`)
- **setup:** Normal completion.
- **steps:** Type "felt strong" into the note TextField; tap save & done.
- **expected:** `localCompletionWriter` receives a `Workout` with `notes == "felt strong"`. Empty / whitespace-only notes collapse to `nil` via `ExecutionViewModel.normalizeNote` — the base template's `notes` stays untouched.
- **notes:** Dictation-mic is deferred; see the TODO in `ExecutionViewModel.saveAndDone` doc comment.

### S12a. Completion proof telemetry
- **setup:** Completed workout through the shell wiring, or a narrower
  `FeaturesExecution` package test when only VM-stage telemetry is under test.
- **steps:** Tap save & done, then inspect `ZEVENTMODEL`, `ZWORKOUTMODEL`,
  `ZSETLOGMODEL`, `ZPUSHITEMMODEL`, `ZSESSIONSNAPSHOTMODEL`, and the
  telemetry recorder used by tests.
- **expected:** Full shell/simulator proof includes the same `workout_id`,
  `set_log_count`, `primitive_set_log_count`, and `has_note` across
  record-build, publish, local-cache-write, and local-writer stages.
  `execution.session_mutation` with `{"mutation":"save"}` appears in the same
  Save & Done sequence. After the flow settles, `ZSESSIONSNAPSHOTMODEL` should
  have no active snapshot for that workout; during a crash-window probe, any
  surviving snapshot must be post-save `.today` state, not pre-handoff live
  workout state. VM package tests only assert record-build, publish, and
  local-writer-return events because the shell owns cache-write telemetry.
- **notes:** This is the debugging surface for "did Save & Done really hand
  off completion before clearing the live session?" UI video alone is not
  sufficient proof; event rows must match the actual cache, queue, and
  `ZSESSIONSNAPSHOTMODEL` state for the same workout.

### S13. Save & done when a proposal banner is still up
- **setup:** Log the last set; autoreg fires; reach `.complete` with `currentProposal != nil`.
- **steps:** save & done.
- **expected:** `.save` wipes state; proposal is irrelevant post-save. No crash.
- **notes:** Check there's no stale proposal flash during route flip.

### S14. Save & done under a clock skew (device time changed mid-workout)
- **setup:** Start workout, change device time forward by 1 hour, complete.
- **steps:** save & done.
- **expected:** `clock.now` at save time is the (skewed) wall clock. `completedAt` stored as whatever the device says. Server accepts UTC timestamps regardless.
- **notes:** Session duration in History will reflect the skew; not a bug but a known signal.

### S15. Save & done with a swapped exercise mid-workout
- **setup:** User swapped an item's exercise (`performedExerciseID != nil`).
- **steps:** Complete, save & done.
- **expected:** SetLogs carry `performedExerciseID` (`ExecutionViewModel+Push.swift:131`). Session detail in History shows the performed exercise name, not the planned one.
- **notes:** See history.md S8.
