---
title: save-and-done
status: living
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
On the `.complete` route the user sees a per-exercise ledger, an optional body-weight field, an optional note field, and a single "save & done" button (`CompleteView.swift`). Tapping it calls `ExecutionViewModel.saveAndDone(note:bodyweightKg:)`, which does five things in order: (1) enqueues a terminal `status_update` with `completedAt = clock.now` via `enqueueStatusCompleted` (wires to `syncAPI.pushStatus` + a push-flush kick), (2) writes the completed Workout (with the note on `Workout.notes` if non-empty) + all `done` SetLogs to the local `WorkoutCache` via `localCompletionWriter` so the History tab sees them immediately (`ExecutionViewModel+Push.swift` § `writeCompletionToLocalCache`), (3) if the user typed a body weight, fires the `onUserParameterChanged` hook with a fresh `UserParameter{key:"bodyweight_kg",source:.appLog}` — Shell wires that to `WorkoutCache.saveUserParameter` + `SyncAPI.pushUserParameter` which enqueues `POST /api/user-parameters` (bug-011 fix), (4) dispatches `.save(freshItems:, freshStructure:)` through the reducer which flips route → `.today` and empties the log, and (5) fire-and-forgets `sessionStore.clear()` so next launch won't resume.

**Note dictation is deferred** — the `saveAndDone` doc comment carries a TODO linking the open question. The TextField is the minimum UI that unblocks bug-012; the mic affordance is a polish item.

**Ledger rhythm & font pairing** — each ledger row renders inside a `DSCard(padding: 0)` with its own 16pt horizontal / 12pt vertical padding (`CompleteView.swift`, bug-028 fix). Exercise text no longer butts against the card edge, and the row rhythm stays uniform across cards. The uniform "Nxr @ L kg · RIR n" summary routes the weight + unit through `DSWeightLabel` (`CompleteView+Ledger.swift` → `ledgerSummaryView`, bug-027 fix) so the "kg" shares the same mono family + weight as the digits; BW-only and "N sets" summaries render plain.

## State surface
- **Inputs:** `viewModel.state` (all logged sets), `viewModel.context.workout` (template id/name/tags), `clock.now`.
- **Outputs / side effects:**
  - `onStatusChanged(workoutID, .completed, completedAt)` enqueued to the push queue (`ExecutionViewModel+Push.swift:88`).
  - `onPushKick()` fires so the flusher drains immediately (`AppBootstrap.swift:198`).
  - `localCompletionWriter(workout, setLogs)` writes to `WorkoutCache` via `saveWorkout` + `saveSetLogs` (`WorkoutCache+History.swift:150`, `:132`).
  - `SessionState` → route `.today`, `items == []`, `structure` empty.
  - `SessionStore` row deleted (`SessionStore.swift:56`).
  - Telemetry event `execution.session_mutation` with `{"mutation":"save"}`.
- **State transitions:** `.complete` → `.today` (via `.save`). Shell's `RootTabView` re-reads `executionVM.state.route` and flips back to Today.

## What it deliberately doesn't do
- Does NOT offer dictation-mic capture on the note (bug-012 TODO — tracked as a polish item).
- Does NOT confirm before wiping the session — the tap is immediate.
- Does NOT await any network or disk write — all side effects are fire-and-forget `Task`s.
- Does NOT validate that every prescribed set was logged — an early "End" button path can reach `.complete` with partial logs.
- Does NOT write the note back up to the server yet — it lands on the local-cache workout row only. The server's `Workout.notes` column already exists; the push path will be wired when we revisit the workout-completion sync protocol.

## Edge cases handled in code
- Auto-advance path vs explicit End button both route through `saveAndDone` for the server status update (R2.5, `docs/open-questions.md:282`). Before the fix, the auto-advance path left the server's workout row `planned` forever. `complete()` itself no longer enqueues — the terminal push is owned exclusively by `saveAndDone` so force-complete + save-and-done no longer double-pushes (`ExecutionViewModel.swift:393-405`).
- Re-entrancy guard on `saveAndDone` (R2.11 — `ExecutionViewModel+SaveAndDone.swift`): a rapid double-tap or a SwiftUI re-render that fires the tap action twice is dropped on the floor. First call sets an `@MainActor`-isolated in-flight marker (weak-to-strong `NSMapTable`); subsequent calls see the marker and return silently. Without this, a duplicate bodyweight `UserParameter` row would land in the append-only `user_parameters` table forever. Views also bind `.disabled(viewModel.saveAndDoneInFlight)` as belt-and-suspenders.
- `localCompletionWriter` is `nil` in the pure-offline test path (`ExecutionViewModel.swift:163`) — `writeCompletionToLocalCache` returns early (`ExecutionViewModel+Push.swift:109`).
- `SetLog` is only emitted for sets with `set.done == true` (`ExecutionViewModel+Push.swift:127`).
- Each cache-write SetLog is stamped with the deterministic `setLogID(itemID:setIndex:)` UUID (`ExecutionViewModel+Push.swift:584`) — same derivation used by the per-set push enqueue, so local-cache ids MATCH push-queue ids for the same `(itemID, setIndex)` (R1.3b-v2 — see `ExecutionViewModel+Push.swift:45`).
- Push enqueuer (`syncAPI.pushStatus`) is wrapped in `try?` (`AppBootstrap.swift:196`) — network errors are swallowed; the persistent push queue will retry.
- Local cache writes are wrapped in `try?` (`AppBootstrap.swift:207-208`) — a failed local write just means History waits for the next pull.

## Known issues / gaps
- **Body-weight capture**: wired on the Complete screen (S11). Client-owned deterministic id (MD5 of `userID|key|observedAt`) + server tenant guard (403 on duplicate id across users) close the replay-idempotency hole (bug-044). Re-entrancy guard on `saveAndDone` collapses double-tap into a single pipeline run.
- **Workout note server push**: now wired. The `.statusUpdate` push payload carries the trimmed workout note; server persists it on `Workout.notes` (previously pulls overwrote it with the planned-template note). Regression covered by server status-push note-persistence test.
- **Dictation-mic on the note TextField**: deferred (polish item, documented in the `saveAndDone` TODO comment).
- SetLog id divergence between per-set push enqueue and batch local-cache write is **closed** — both paths derive the id deterministically from `(itemID, setIndex)` via `setLogID(...)` (R1.3b-v2 / bug-040). Pinned by `ExecutionViewModelTests` § local-cache-deterministic-setLogID assertions.

## QA scenarios

### S1. Happy path — auto-advance → save & done
- **setup:** Seeded push workout, offline-capable build.
- **steps:** Log every prescribed set; after the last set, cursor auto-advances through `.rest` → `.complete`. Tap "save & done".
- **expected:** Route flips to `.today`; workout appears in History list immediately (local cache write); push queue drains a `status_update` + flush kick; `SessionStore` row cleared.
- **notes:** This is the regression path for the fix in `docs/open-questions.md:282`.

### S2. Happy path — explicit End button → save & done
- **setup:** Mid-workout (some sets logged, some not), push stack available.
- **steps:** Tap End from the nav bar to force `.complete`; tap save & done.
- **expected:** `complete()` flips the route to `.complete` but does NOT enqueue a `status_update` (that responsibility moved to `saveAndDone` exclusively — `ExecutionViewModel.swift:393-405`). `saveAndDone()` then enqueues the single terminal `status_update`. Ledger reflects only the logged sets.
- **notes:** Prior to R2.5, both `complete()` and `saveAndDone()` enqueued on the End path — double-push. The current invariant is "exactly one `status_update` per completed workout, sourced from `saveAndDone`."

### S3. Save & done with zero sets logged
- **setup:** User taps Start, never logs a set, reaches `.complete` via the End button.
- **steps:** Tap save & done.
- **expected:** `status_update = completed` still enqueues; `writeCompletionToLocalCache` writes the workout row (status completed, `completedAt = now`) but ZERO SetLogs (`ExecutionViewModel+Push.swift:127` skips non-done sets). History shows the workout with no exercise cards.
- **notes:** Confirm the Workout row appears in History list with the correct empty-state rendering; `SessionDetail.durationSeconds` returns nil (no set timestamps).

### S4. Save & done offline (Tailscale unreachable)
- **setup:** Airplane mode or cable pulled; at least one completed set.
- **steps:** Tap save & done.
- **expected:** Route flips instantly. `status_update` enqueues to the persistent push queue. `onPushKick` fires but the flusher fails silently. Local cache write succeeds. History tab shows the workout.
- **notes:** Next time connectivity returns, `PushFlusher` drains and server catches up.

### S5. Rapid double-tap on save & done (R2.11)
- **setup:** Normal completion.
- **steps:** Tap save & done twice within ~100ms.
- **expected:** First tap flips `saveAndDoneInFlight` to `true` and runs the full path; the second tap hits the re-entrancy guard (`ExecutionViewModel+SaveAndDone.swift`) and returns silently. Exactly one `status_update`, exactly one bodyweight `UserParameter`, exactly one local-cache write.
- **notes:** The guard is the correctness check; `.disabled(viewModel.saveAndDoneInFlight)` on the button is belt-and-suspenders. The flag is a per-VM stored `Bool` (`saveAndDoneInFlightStorage`) — the shell rebuilds a fresh VM per workout via `AppBootstrap+Hooks.makeCompletionWriter`, so the flag is naturally reset between workouts (qa-002 / qa-003 fix).

### S6. Server returns 404 on status_update (stale workoutID)
- **setup:** Force the server to 404 the status push.
- **steps:** Complete + save & done.
- **expected:** `try? await syncAPI.pushStatus(...)` swallows the error (`AppBootstrap.swift:196`). Local cache still reflects completed. Push queue behavior on 404 is outside this feature's surface — see push-queue.md.
- **notes:** Validate the user sees no error surface; History remains correct locally.

### S7. Local cache write fails (SwiftData error)
- **setup:** Force a SwiftData error in `saveWorkout` (e.g., model-context invalidation).
- **steps:** save & done.
- **expected:** `try?` swallow (`AppBootstrap.swift:207`). Route still flips. Next `syncAPI.pullLatest` backfills History. No user-visible error.
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
- **setup:** save & done → kill the app process before `sessionStore.clear()` completes.
- **steps:** Relaunch.
- **expected:** `SessionStore` row may still exist (clear was fire-and-forget). `restoreIfPossible` would load it and restore `.today` route (since `.save` already mutated the in-memory state before the persist kicked off). The fire-and-forget `persist()` after `.save` writes an empty state; if that won, there's nothing to restore.
- **notes:** Race between `persist()` (empty state) and `sessionStore.clear()` is fine — either outcome reaches Today.

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
