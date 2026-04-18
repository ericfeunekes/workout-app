---
title: push-queue
status: living
purpose: Behavioral contract + QA scenarios for push-queue
covers:
  - app/Packages/Sync/Sources/Sync/PushQueue.swift
  - app/Packages/Sync/Sources/Sync/PushQueueStore.swift
  - app/Packages/Persistence/Sources/Persistence/PushQueueStoreImpl.swift
  - app/Packages/Shell/Sources/Shell/PushFlusher.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Push.swift
---

# push-queue

## What it does
Durable SwiftData-backed FIFO queue for outbound writes. Three payload shapes: `setLogs([SetLog])`, `statusUpdate(workoutID, status, completedAt)`, `events([TelemetryEvent])`. Set logs and status updates POST to `/api/sync/results`; telemetry events POST to `/api/telemetry/events` (`PushQueue.swift:205-212`). `PushFlusher` is an actor that owns a detached `Task.sleep`-based loop at 60s cadence; it calls `SyncAPI.flushPushQueue()` which pulls `bearerToken` from `tokenProvider`, peeks up to `batchSize=32` oldest items, posts each, and on 2xx removes. On 401 it stops the loop (`PushFlusher.swift:66-71`). `ExecutionViewModel` enqueues via fire-and-forget `Task { @MainActor in await hook(...) }`; never awaits from the UI path. On workout `complete` the VM calls `onPushKick` → `flushNow()` so the terminal payload hits the server in seconds not minutes. See `docs/sync.md` § "Push protocol" and "Cadence".

## State surface
- **Inputs:** enqueue calls from `ExecutionViewModel+Push`, `TelemetryEmitterImpl`, `tokenProvider` closure
- **Outputs / side effects:** HTTP POST to `/api/sync/results` or `/api/telemetry/events`; `PushItemModel` rows in SwiftData; `ConnectionManager` state transitions (`.pushSucceeded`, `.networkFailed`, `.tokenRejected`)
- **State transitions:** per-item `attempts` counter bumps on each non-2xx outcome (`PushQueue.swift:173, 179, 188, 195`). Items removed only on 2xx (`:185`)

## What it deliberately doesn't do
- No exponential backoff — fixed 60s foreground cadence (`PushFlusher.swift`, `docs/sync.md` § "Cadence")
- No background flushing — loop runs only while `Task` is alive; app backgrounding eventually kills it
- No dead-letter queue — items retry forever until 2xx or user action (`open-questions.md` has no entry for this; not built)
- No retention cap on local queue (`PushQueueStoreImpl` — no pruning)
- No priority ordering — strict FIFO by `enqueuedAt` (`PushQueueStoreImpl.swift:48`). Telemetry and set_logs interleave by insert time.
- Does not delete telemetry events after successful push from the `EventModel` store — see `open-questions.md` § "Telemetry ring buffer is durable but un-pruned beyond the cap"
- PushFlusher does NOT fire an immediate flush on `start()` — sleeps first (`PushFlusher.swift:52-61`)

## Edge cases handled in code
- 2xx → remove item, return `.pushed` (`PushQueue.swift:184-186`)
- 401 → bump attempts, return `.tokenRejected`, short-circuit rest of batch (`:187-189, :124`)
- 5xx and non-401 4xx → bump attempts, return `.networkFailed`, continue batch (`:190-197`)
- Network throw (SyncError) → bump attempts, classify tokenRejected vs networkFailed (`:172-180`)
- Idempotent enqueue: duplicate `PushItemID` replaces existing row (`PushQueueStoreImpl.swift:29-43`)
- Idempotent server: same `SetLog.id` upserts — safe to re-push (per `docs/sync.md` § "Push protocol")
- `PushFlusher.start()` is idempotent — second call no-ops if task exists (`PushFlusher.swift:46-47`)
- `PushFlusher.stop()` is safe to call multiple times (`:97-100`)
- `flushNow()` swallows all errors — UI callers never await for correctness (`:86-94`)
- FIFO by `enqueuedAt` ascending (`PushQueueStoreImpl.swift:48`)
- Telemetry events UUID-lowercased at encode time (`PushQueue.swift:243, :245, :249, :250`)

## Known issues / gaps
- Fixed this session: `/api/sync/results` rejected all set_log pushes with 404 "workout_item not found" due to UUID case mismatch (Swift emits UPPERCASE, server stored lowercase). Fixed via `_UuidNormalizingBase` Pydantic mixin lowercasing all `id`/`*_id` fields. See `open-questions.md` § "Server FK lookup was UUID-case-sensitive".
- Fixed this session: `saveAndDone()` did NOT enqueue the workout `status_update` on the auto-advance-to-complete path — server workout stayed `planned` forever. Fixed: `saveAndDone()` now calls `enqueueStatusCompleted(at:)` before `.save` wipes local state. Needs regression test. See `open-questions.md` § "Save & done didn't enqueue status_update".
- Telemetry pipeline added this session — routes through this queue via `enqueueEvents`. In-flight work; narrow emit surface documented in `open-questions.md` § "Telemetry emit surface is narrow by design".
- Open: `docs/sync.md` § "Offline completion atomicity" — set_logs and status_update are separate items; partial flush can leave server in "logs against active workout" state.
- Open: no background-push — if user logs a set, locks phone, set never gets pushed until next foreground.

## QA scenarios

### S1. Happy path: log a set, flush drains it
- **setup:** `.ready`, online, queue empty
- **steps:** start workout, log one set, wait ≤60s (or trigger `flushNow` via complete)
- **expected:** `PushItemModel` row appears on enqueue, `POST /api/sync/results` fires, 2xx, row removed. `ConnectionManager` emits `.pushSucceeded`.

### S2. Happy path: complete + save & done pushes status
- **setup:** `.ready`, workout near end
- **steps:** log final set (auto-advances to `.complete`), tap "save & done"
- **expected:** one set_log enqueue, one status_update enqueue, `flushNow` kick, both drain to server. Server's workout row transitions `planned → completed` with `completed_at` set.
- **notes:** regression guard for the `saveAndDone` fix from this session

### S3. Status push on explicit complete button
- **setup:** mid-workout
- **steps:** tap "End" button → `ExecutionViewModel.complete()`
- **expected:** status_update enqueued via `enqueueStatusCompleted`. Same as S2 but via the manual path (`ExecutionViewModel+Push.swift:85-93`).

### S4. Offline → queue grows → reconnect
- **setup:** airplane mode, `.ready` (cached)
- **steps:** log 5 sets, wait 2 minutes (flusher ticks twice, both fail silently), disable airplane mode, wait ≤60s
- **expected:** 5 `PushItemModel` rows persisted across airplane mode. On reconnect, flusher drains them in FIFO order. Attempt counters reflect prior failures.
- **notes:** `attempts` bumps per failure — verifiable by peeking DB

### S5. 5xx retry with attempt counter
- **setup:** server returns 500 on first POST, 200 on second
- **steps:** log a set
- **expected:** first flush attempt → row stays, `attempts=1`, `.networkFailed`. Next flush → 200, row removed.

### S6. 2xx pushed, then server amnesia (duplicate re-push)
- **setup:** set pushed, 2xx, removed. User force-re-enqueues same set with same UUID (hypothetical; normal flow doesn't do this)
- **steps:** re-enqueue, flush
- **expected:** server upserts on UUID — 2xx. Idempotent per `docs/sync.md` § "Push protocol".

### S7. 401 during push → loop stops
- **setup:** `.ready`, server rotates token mid-session
- **steps:** log a set, wait for flush
- **expected:** flush returns `tokenRejected`, `ConnectionManager` emits `.tokenRejected`, `PushFlusher` loop exits and clears its `task` (`PushFlusher.swift:66-71`). Queue items stay on disk. Shell does not auto-route to FirstRun from push 401 — waits for next explicit pull or Settings action.
- **notes:** verify the shell's behavior separately; push 401 does NOT itself trigger FirstRun routing

### S8. UUID case regression
- **setup:** server running pre-fix code
- **steps:** log a set, push
- **expected:** on pre-fix server, 404. On fixed server (`_UuidNormalizingBase`), 2xx. Regression guard: every set push from the app returned 404 before this session's fix.

### S9. Telemetry event routing
- **setup:** `.ready`, telemetry emitter wired
- **steps:** trigger any emit point (e.g. start a workout → `execution.session_mutation`)
- **expected:** event lands in local store, eventually enqueued via `PushQueue.enqueueEvents`, POSTed to `/api/telemetry/events` (separate path from set_logs — `PushQueue.swift:208-211`)

### S10. Telemetry failure doesn't block set_logs
- **setup:** `/api/telemetry/events` returns 500, `/api/sync/results` returns 200
- **steps:** log a set, trigger a telemetry event
- **expected:** set_log drains (2xx, removed). Telemetry item stays, `attempts` bumps. Flusher continues batch — `.networkFailed` is per-item, doesn't short-circuit.
- **notes:** 401 DOES short-circuit; 5xx does not (`PushQueue.swift:124`)

### S11. Rapid log taps during flush
- **setup:** `.ready`, flusher mid-flight
- **steps:** log 3 sets in <1s
- **expected:** all three enqueue via `Task { @MainActor in await onSetLogged(log) }`. Enqueue order matches tap order because MainActor serializes the tasks.
- **notes:** `PushQueue` itself is an actor so internal operations are serialized regardless

### S12. App kill mid-push
- **setup:** flush in flight, POST sent but response not received
- **steps:** force-quit app, relaunch
- **expected:** item was not removed (removal is after 2xx), so it's in the queue. On next flush, re-POST. Server upserts — idempotent.

### S13. Background during flush
- **setup:** flush loop running
- **steps:** background the app
- **expected:** `Task.sleep` eventually throws on suspension or task is cancelled by iOS. No explicit backgroundTask handling in `PushFlusher`. On foreground return, `start()` may need to be re-invoked by the shell — unclear from code whether shell does this.
- **notes:** unclear — no explicit `scenePhase` wiring visible in `WorkoutDBApp.swift`; review Shell wiring

### S14. FIFO ordering with mixed payloads
- **setup:** queue empty, enqueue: set_logA (t=0), status_update (t=1), set_logB (t=2), event (t=3)
- **steps:** flush
- **expected:** posted in insert order. Each `pushOne` routes to the correct path per `PushQueue.swift:205-212`. Two different endpoints interleave.

### S15. `PushFlusher.start()` called twice
- **setup:** any
- **steps:** call `start()`, then `start()` again
- **expected:** second call no-ops (`if task != nil { return }`, `PushFlusher.swift:46-47`). One loop, not two.

### S16. `flushNow()` during periodic tick
- **setup:** flush loop in the middle of posting
- **steps:** invoke `flushNow()` (e.g., user taps "save & done")
- **expected:** both enter `SyncAPI.flushPushQueue()` which is on the `PushQueue` actor — serialized. No double-POST for the same item since `remove` is gated on 2xx.

### S17. Very large queue (>32 items)
- **setup:** offline for a long session, 100+ items queued
- **steps:** reconnect
- **expected:** each flush drains up to `batchSize=32`. At 60s cadence that's ~32/min. `flushNow` from complete also helps. No retention cap — all items eventually drain.

### S18. Queue item for a deleted workout
- **setup:** status_update enqueued for workout X, server deletes workout X before flush (shouldn't happen in v1 but hypothetical)
- **steps:** flush
- **expected:** 404 from server → treated as `networkFailed` (non-401 4xx path, `PushQueue.swift:190-197`) → attempts bumps, item retries forever.
- **notes:** not built: dead-letter path
