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
- No background flushing — loop runs only while `Task` is alive; app backgrounding eventually kills it.
- No retention cap on local queue beyond dead-letter. `PushQueueStoreImpl` prunes undecodable rows on startup (bug-055) but doesn't trim by age.
- Does not delete telemetry events after successful push from the `EventModel` store — see `open-questions.md` § "Telemetry ring buffer is durable but un-pruned beyond the cap".
- PushFlusher does NOT fire an immediate flush on `start()` — sleeps first.

## What it does have now (bug-060)
- **Exponential backoff** via `PushBackoff.schedule = [10, 30, 60, 120, 300]`s. `PushFlusher` consults the schedule against the consecutive-failure counter.
- **Dead-letter after 5 consecutive non-401 4xx.** Drops the item and emits `execution.push_item_dead_lettered` with `setLogID` / `workoutID` / `userParameterID` correlation id so the event can be joined to the dropped payload.
- **Priority-weighted FIFO** (bug-056): `peek` sorts by `(priority, enqueuedAt)`. `results` (SetLog / status / UserParameter) are priority 0; `telemetry` is priority 1. Telemetry backlog can't starve set_log pushes. perf-002 persisted `priority` on `PushItemModel` (V4) so SwiftData resolves the sort against a SQLite index with `fetchLimit: batchSize` instead of decoding every row on every flush.
- **Logical dedup** (bug-055): dedup on `SetLog.id` / `(workoutID, status)` / `UserParameter.id`. Idempotent enqueue also still replaces by `PushItemID`. perf-002 persisted `dedupKey: String?` on `PushItemModel` (V4) so dedup resolves via a scoped `FetchDescriptor` predicate — one scoped fetch per enqueue, not a full-table peek + decode.
- **Tolerant peek**: one unknown envelope kind (forward-versioned row) is skipped instead of throwing. Startup sweep via `pruneUndecodableRows()` removes anything the decoder consistently rejects.

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
- `(priority, enqueuedAt)` sort + `fetchLimit: max` (`PushQueueStoreImpl.swift` `peek(max:)`) — server-side order, no whole-queue decode
- Telemetry events UUID-lowercased at encode time (`PushQueue.swift:243, :245, :249, :250`)

## Known issues / gaps
- Closed: `/api/sync/results` UUID case mismatch (bug-004 / bug-030 / bug-031 / bug-045). Every outbound UUID routes through `UUID.wireID` (lowercase); server accepts only lowercase on input.
- Closed: saveAndDone status_update (bug-005 / bug-006) with re-entrancy guard (bug-044).
- Closed: unbounded retry / no priority ordering / no dedup / no backoff — all shipped in bug-060 + bug-056 + bug-055 + bug-044. See "What it does have now" above.
- Closed: `peek` decoded the whole queue on every flush and every dedup pass (perf-002). `PushItemModel` V4 persists `priority` + `dedupKey` so `peek` uses a `(priority, enqueuedAt)` sort + `fetchLimit`, and dedup uses `removeMatchingDedupKey` with a scoped predicate.
- Closed: `.userParameter` idempotency (bug-044) — client-owned deterministic id (MD5 of `userID|key|observedAt`); server enforces tenant guard (403 on duplicate id from different user).
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
