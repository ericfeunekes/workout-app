---
title: push-queue
status: built
last_reviewed: 2026-05-17
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
Durable SwiftData-backed FIFO queue for outbound writes. Result payloads are `primitiveSetLogs([PrimitiveSetLog])`, `statusUpdate(workoutID, status, completedAt)`, `completionResults(workoutID, completedAt, notes, primitiveSetLogs)`, `workoutReset(workoutID)`, and `userParameter(...)`; telemetry uses `events([TelemetryEvent])`. Result payloads POST to `/api/sync/results` except user parameters, which POST to `/api/user-parameters`; telemetry events POST to `/api/telemetry/events`. `PushFlusher` is an actor that owns a detached `Task.sleep`-based loop at 60s cadence; it calls `SyncAPI.flushPushQueue()` which pulls `bearerToken` from `tokenProvider`, peeks up to `batchSize=32` oldest items, posts each, and on 2xx removes. On 401 it stops the loop (`PushFlusher.swift:66-71`). Normal set logging enqueues primitive slot rows via fire-and-forget hooks. Save & Done is stricter: the VM builds a local `WorkoutCompletionRecord`, awaits REST's durable grouped enqueue, then writes that same record to local history before clearing the live session. See `docs/sync.md` § "Push protocol" and "Cadence".

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
- **Priority-weighted FIFO** (bug-056): `peek` sorts by `(priority, enqueuedAt)`. `results` (PrimitiveSetLog / status / UserParameter) are priority 0; `telemetry` is priority 1. Telemetry backlog can't starve primitive result pushes. perf-002 persisted `priority` on `PushItemModel` (V4) so SwiftData resolves the sort against a SQLite index with `fetchLimit: batchSize` instead of decoding every row on every flush.
- **Logical dedup** (bug-055): dedup on `PrimitiveSetLog.id` / `(workoutID, status)` / `UserParameter.id`. Idempotent enqueue also still replaces by `PushItemID`. perf-002 persisted `dedupKey: String?` on `PushItemModel` (V4) so dedup resolves via a scoped `FetchDescriptor` predicate — one scoped fetch per enqueue, not a full-table peek + decode.
- **Atomic completion publication**: Save & Done queues `completionResults`, a single logical item that encodes final primitive set logs and completed status together. The queue store removes older single-log rows for the same `PrimitiveSetLog.id`, older completed status rows for the workout, and older grouped completion rows for the same workout in the same durable mutation that inserts the grouped replacement. A 2xx removes the grouped item; a 5xx/transport failure keeps logs and status together for retry.
- **Tolerant peek**: one unknown envelope kind (forward-versioned row) is skipped instead of throwing. Startup sweep via `pruneUndecodableRows()` removes anything the decoder consistently rejects.

## Edge cases handled in code
- 2xx → remove item, return `.pushed` (`PushQueue.swift:184-186`)
- 401 → bump attempts, return `.tokenRejected`, short-circuit rest of batch (`:187-189, :124`)
- 5xx and non-401 4xx → bump attempts, return `.networkFailed`, continue batch (`:190-197`)
- Network throw (SyncError) → bump attempts, classify tokenRejected vs networkFailed (`:172-180`)
- Idempotent enqueue: duplicate `PushItemID` replaces existing row (`PushQueueStoreImpl.swift:29-43`)
- Idempotent server: same `PrimitiveSetLog.id` upserts — safe to re-push (per `docs/sync.md` § "Push protocol")
- `PushFlusher.start()` is idempotent — second call no-ops if task exists (`PushFlusher.swift:46-47`)
- `PushFlusher.stop()` is safe to call multiple times (`:97-100`)
- `flushNow()` returns `tokenRejected` for 401s so Shell can route auth
  recovery; transient failures remain non-blocking for UI callers.
- `(priority, enqueuedAt)` sort + `fetchLimit: max` (`PushQueueStoreImpl.swift` `peek(max:)`) — server-side order, no whole-queue decode
- Telemetry events UUID-lowercased at encode time (`PushQueue.swift:243, :245, :249, :250`)

## Current gaps

- `PUSH-GAP-002`: No background push path exists. If the user logs a set and
  locks the phone before a foreground flush, push waits until the app resumes.
  Foreground flusher start/restart, background stop posture, and push-token
  recovery now belong to `AppSyncCoordinator`; this gap is only true background
  delivery.
- Inbound server-nudged workout delivery is not part of this outbound queue.
  That future APNs/silent-push sync lane is tracked separately as
  `SYNC-GAP-004` in `docs/sync.md`.

## QA scenarios

### S1. Happy path: log a set, flush drains it
- **setup:** `.ready`, online, queue empty
- **steps:** start workout, log one set, wait ≤60s (or trigger `flushNow` via complete)
- **expected:** `PushItemModel` row appears on enqueue, `POST /api/sync/results` fires, 2xx, row removed. `ConnectionManager` emits `.pushSucceeded`.

### S2. Happy path: complete + save & done pushes grouped completion
- **setup:** `.ready`, workout near end
- **steps:** log final set (auto-advances to `.complete`), tap "save & done"
- **expected:** one `completionResults` queue item replaces pending single-log rows for that workout's final logs, `flushNow` kicks, and one `/api/sync/results` body carries both `primitive_set_logs` and `status_updates`. Server persists the final logs and transitions the workout to `completed` atomically.
- **notes:** regression guard for completion atomicity; covered by Sync, Shell, and server atomicity tests.

### S3. Explicit End button does not publish until Save & Done
- **setup:** mid-workout
- **steps:** tap "End" button → `ExecutionViewModel.complete()`
- **expected:** route flips to `.complete`, no terminal push is enqueued yet. Tapping Save & Done then publishes the same grouped completion result as S2.

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
- **expected:** flush returns `tokenRejected`, `ConnectionManager` emits `.tokenRejected`, `PushFlusher` loop exits and clears its `task`, and `AppSyncCoordinator` routes Shell through the same FirstRun recovery path used for pull 401. Queue items stay on disk.
- **notes:** app-root routing is owned by the Shell coordinator; `PushFlusher` only reports the terminal outcome.

### S8. UUID case regression
- **setup:** server running pre-fix code
- **steps:** log a set, push
- **expected:** on pre-fix server, 404. On fixed server (`_UuidNormalizingBase`), 2xx. Regression guard: every set push from the app returned 404 before this session's fix.

### S9. Telemetry event routing
- **setup:** `.ready`, telemetry emitter wired
- **steps:** trigger any emit point (e.g. start a workout → `execution.session_mutation`)
- **expected:** event lands in local store, eventually enqueued via `PushQueue.enqueueEvents`, POSTed to `/api/telemetry/events` (separate path from primitive result payloads)

### S10. Telemetry failure doesn't block primitive results
- **setup:** `/api/telemetry/events` returns 500, `/api/sync/results` returns 200
- **steps:** log a set, trigger a telemetry event
- **expected:** primitive result drains (2xx, removed). Telemetry item stays, `attempts` bumps. Flusher continues batch — `.networkFailed` is per-item, doesn't short-circuit.
- **notes:** 401 DOES short-circuit; 5xx does not (`PushQueue.swift:124`)

### S11. Rapid log taps during flush
- **setup:** `.ready`, flusher mid-flight
- **steps:** log 3 sets in <1s
- **expected:** all three primitive slot rows enqueue via `Task { @MainActor in await onPrimitiveSetLogged(log) }`. Enqueue order matches tap order because MainActor serializes the tasks.
- **notes:** `PushQueue` itself is an actor so internal operations are serialized regardless

### S12. App kill mid-push
- **setup:** flush in flight, POST sent but response not received
- **steps:** force-quit app, relaunch
- **expected:** item was not removed (removal is after 2xx), so it's in the queue. On next flush, re-POST. Server upserts — idempotent.

### S13. Background during flush
- **setup:** flush loop running
- **steps:** background the app
- **expected:** Shell tells `AppSyncCoordinator` to stop the foreground flusher on background. On foreground return, the coordinator refreshes, preserves any active workout session, and restarts the flusher idempotently.
- **notes:** package tests pin the coordinator behavior; `TEST-GAP-004` remains for simulator/app-root proof that the running `scenePhase` path invokes it.

### S14. Priority FIFO ordering with mixed payloads
- **setup:** queue empty, enqueue: telemetry event (t=0), primitiveSetLogA (t=1), completionResults (t=2), event (t=3)
- **steps:** flush
- **expected:** result payloads drain before telemetry because priority 0 sorts ahead of priority 1; FIFO holds within each priority class. Each `pushOne` routes to the correct endpoint.

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
- **expected:** 404 from server → treated as `networkFailed` (non-401 4xx path) → attempts bumps, and after 5 consecutive non-401 4xx rejections the item dead-letters (`execution.push_item_dead_lettered` with correlation id) instead of retrying forever (bug-060).
