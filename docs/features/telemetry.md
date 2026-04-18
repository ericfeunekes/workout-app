---
title: telemetry
status: living
purpose: Behavioral contract + QA scenarios for the structured event log.
covers:
  - app/Packages/Core/Telemetry/
  - app/Packages/Persistence/Sources/Persistence/TelemetryEmitterImpl.swift
  - app/Packages/Sync/Sources/Sync/PushQueue.swift (.events case)
  - server/workoutdb_server/api/telemetry.py
  - server/db/migrations/005_event_log.sql
---

# telemetry

## What it does

Every significant app action (start, logSet, autoreg proposal, save, network request, error) emits a structured `Event` record to a local SwiftData ring buffer (10k cap) AND enqueues it into the push queue. When the queue flushes, events POST to `/api/telemetry/events` and land in the server's `event_log` table. The whole loop is fire-and-forget — emitters never block the UI.

Why: when Eric reports "something didn't work at the gym," the telemetry event log answers "what actually happened, in order." Before this, diagnostics meant rooting through SwiftData containers and server access logs.

## State surface

- **Inputs:** `Event` value — `id`, `timestamp`, `sessionID` (stable per app launch), `kind` (`"state" | "network" | "timer" | "error"`), `name` (e.g. `"execution.logSet"`), optional `data_json`, optional `workoutID` / `setLogID`.
- **Outputs:** `EventModel` rows in SwiftData; `PushItem.Payload.events([Event])` queue entries; `POST /api/telemetry/events` server-side; `event_log` table rows keyed by user_id.
- **State transitions:** Emit → local insert (+ ring-buffer trim if > 10k) → enqueue → flush (every ~60s foreground or on kick). 2xx → remove from queue. 5xx/network fail → retry next flush. 401 → same auth path as set_log push.

## What it deliberately doesn't do

- Block on emit. Every `emit(_:)` is sync + fire-and-forget (`Task.detached` inside the impl actor).
- Batch multiple events per push item. One event = one queue item = one HTTP call. The ~60s cadence coalesces time-wise; batching would add complexity for marginal bytes-on-wire savings.
- Ship to a third-party analytics service. Single-user app; the event log lives on Eric's home server.
- Surface in-app (no debug overlay). Deferred to v1.1+ (`docs/open-questions.md`).
- Sample / rate-limit. 10k ring buffer handles bursts; beyond that, oldest events drop.
- Carry PII. Events reference `workoutID` / `setLogID`; server stores them under the authenticated user only.

## Edge cases handled in code

- `TelemetrySession.id` is generated once per app launch — same `sessionID` across all events from one run.
- Cross-tenant POST rejected server-side (`user_id` always from bearer token; caller-sent IDs never resolve to another user).
- Duplicate push (same Event UUID re-enqueued): server upserts by id, idempotent.
- App kill mid-flight: queue is SwiftData-durable; events survive across relaunch.
- Empty batch (`events: []`): server accepts as no-op.

## Known issues / gaps

- **Emit coverage is partial.** Wired in: `AppBootstrap`, `TodayViewModel.start`, `ExecutionViewModel.session_mutation` (start / logSet / advance / save), `execution.autoreg_proposed / _accepted / _undo`, `execution.past_set_edited` (bug-017), `history.past_set_edited` (bug-015), `SyncAPI.network.*`. NOT wired in: History tab switches / filter taps, FirstRun events, Settings (when it exists).
- **No export / share from Settings.** Deferred to v1.1+.
- **No debug overlay** — to see events you query the server's `event_log` table directly.
- **Server caps batches at 500 events per POST** (bug-033, `TelemetryEventsPayload.events` `Field(max_length=500)`). 501+ → 422 at the Pydantic validator, zero writes. Client drains one event per `PushItem` so this is never breached in normal flow; it bounds blast radius from a misbehaving client.

## QA scenarios

### S1. Emit → local insert → push → server
- **setup:** fresh app install, connected to test server
- **steps:** start app → FirstRun succeeds → app enters `.ready` → log one set → save & done
- **expected:** server `event_log` rows include `bootstrap.start`, `bootstrap.ready`, `today.start_tap`, `execution.session_mutation (start)`, `execution.session_mutation (logSet)`, `network.pull_latest`, `network.response`
- **notes:** query with `sqlite3 /tmp/workoutdb_e2e/workout.db "SELECT name, ts FROM event_log ORDER BY ts"`

### S2. Offline emits queue up, flush on reconnect
- **setup:** airplane mode on, app running
- **steps:** log 5 sets offline → check push queue count (SwiftData container) — non-zero events for each mutation. Turn airplane mode off → wait ~60s for flush
- **expected:** all queued events reach server in order. `EventModel` rows removed from push queue (kept in local ring buffer as history)

### S3. Same sessionID across all events in one launch
- **setup:** single app session
- **steps:** emit at least 5 events across different kinds (state, network, autoreg)
- **expected:** all have identical `sessionID`. Kill + relaunch → new sessionID for subsequent events

### S4. Ring buffer caps at 10k
- **setup:** synthesize 10,001 events programmatically (integration test, not E2E)
- **steps:** emit 10k+1 events
- **expected:** `EventModel` table has exactly 10k rows; oldest event trimmed

### S5. 401 handling
- **setup:** rotate server bearer token after app is running
- **steps:** trigger any emit → queue tries to push → server 401
- **expected:** `tokenRejected` flag set; push pauses; Shell routes to FirstRun. Events remain on disk until re-auth.

### S6. Cross-tenant isolation
- **setup:** two distinct tokens / users on the test server
- **steps:** post an Event with `user_id` set (or implicitly via first bearer) → GET `/api/telemetry/events` as the other user
- **expected:** second user sees zero of the first user's events. Covered by `test_api_telemetry.py::test_cross_tenant_isolation`.

### S7. Idempotent re-push
- **setup:** push an event; simulate a retry by re-enqueuing the same UUID
- **steps:** POST `/api/telemetry/events` twice with the same batch
- **expected:** second POST is a no-op (upsert by id). `event_log` has exactly one row.

### S8. Event payload structure
- **setup:** live MCP-driven workout
- **steps:** log a set with RIR 4 (triggers autoreg overshoot) → check server event_log
- **expected:** row `execution.autoreg_proposed` with `data_json` containing `{"reason": "overshoot", "rir": 4, "newLoadKg": 105.0}` (shape-check; exact keys may evolve). `workoutID` + `setLogID` populated.

### S9. Persona QA event diff
- **setup:** run a persona scenario (see `scratch/e2e/personas/*`) end-to-end
- **steps:** capture telemetry during the run; compare to the persona's expected event stream
- **expected:** the event log is a replayable script of what the persona did. Any anomaly (missing event, duplicated event, out-of-order event) = a bug.
