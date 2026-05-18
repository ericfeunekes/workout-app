---
title: Sync, connectivity, and first-run
status: accepted
last_reviewed: 2026-05-17
purpose: How data flows between Claude, the home server, and the app; how the app behaves when the network is unavailable; how a device is connected for the first time. This is the detail layer behind the "Sync model" section of the v2 spec.
covers:
  - server/workoutdb_server/api/sync.py
  - app/ (sync manager, first-run, offline UX)
---

# Sync, connectivity, first-run

## Invariants

1. **The app works offline by default, not as an error state.** Cellular at the gym, travel, and hotel WiFi all fail. "Offline" is a neutral condition, not a warning.
2. **Direction-based sync, no conflict resolution.** Plans flow server → app; results flow app → server. No field is written from both sides.
3. **The live session is frozen.** Once a workout has started executing on the device, a fresh prescription arriving from the server does not rewrite the in-flight session. The new prescription applies to the *next* occurrence of that workout.
4. **Server address is the identity.** There is no login surface. The user configures a server URL (and bearer token) once; changing it is equivalent to switching users.
5. **UUIDs everywhere.** Every entity has a Claude- or app-assigned UUID. Re-pushing a row with a known UUID is idempotent.

---

## Directionality

| Data | Flows | Owner | Entity |
|---|---|---|---|
| Workouts (plans) | Server → App | Claude | `workout.primitive_blocks` plus legacy bridge projections where still needed |
| Exercises | Server → App | Claude | `exercise` |
| User parameters | Server → App | Claude | `user_parameters` (latest-per-key) |
| `last_performed` summary | Server → App | Derived | Piggybacked on `/api/sync/pull` |
| Primitive result rows | App → Server | App | `primitive_set_log` via `/api/sync/results` |
| Workout status changes | App → Server | App | `workout.status`, `workout.completed_at` |
| Workout completion record | App → Server / future publisher | App | Local `WorkoutCompletionRecord` published as grouped primitive result rows + completed status today |
| Body weight at completion | App → Server | App | `user_parameters` row with key `bodyweight_kg` |

**No field is written from both sides.** If a field would be bi-directional (e.g., "preferred rest interval"), it lives in `user_parameters` and Claude owns writes; the app reads.

---

## Cadence

The app pulls and pushes on three triggers:

1. **App open.** On every foregrounding, the app issues `GET /api/sync/pull?since=<last_server_time>`.
2. **After a log write.** When the user completes a set (or a workout), the app issues `POST /api/sync/results` with the new rows. Push is fire-and-forget from the UI's perspective — failure is queued silently.
3. **Gentle retry while foregrounded.** While the app is in foreground, the
   retry queue is flushed on a bounded cadence. The current push loop uses
   backoff after failures; the lifecycle contract is still foreground-owned,
   not background-owned.

**No aggressive polling.** No WebSocket. Push notifications are not in scope for v1 — the user will have opened the app by the time a new plan matters.

---

## App sync ownership and foreground lifecycle

Sync is now a domain behavior, not just a transport helper. The app needs one
app-level owner for "make local data current and keep outbound writes moving"
so foreground sync, manual refresh, token recovery, and any later background
sync path do not grow separate policies.

### Ownership boundary

The boundary is:

- `Sync` owns transport mechanics: `PullService`, `PushQueue`,
  `ConnectionManager`, DTO mapping, HTTP requests, queue flushing, backoff,
  idempotent enqueue, and connection-state events.
- `Persistence` owns durable local stores: workout cache, push queue storage,
  token store, sync metadata, telemetry storage, and session snapshots.
- The app-sync owner coordinates app policy across those packages: when to pull,
  where pulled data is written, when to start or stop push flushing, how token
  rejection routes back to connection recovery, and which telemetry marks the
  lifecycle.
- Feature view models request refresh or enqueue domain writes. They do not own
  foreground/background sync policy.
- `Shell` owns app lifecycle and cross-feature composition. The current
  implementation lives in `Shell` as `AppSyncCoordinator` because Shell
  already composes `Sync` and `Persistence`. If the coordinator becomes a stable
  domain with enough surface to justify its own package, promote it later to a
  named app-sync package. Do not create an empty package before the boundary
  proves itself.

This keeps `Sync` transport-focused. It must not import `Persistence` just to
become the app's lifecycle coordinator.

### Foreground lifecycle contract

When the app becomes active with a saved connection, the app-sync owner must:

1. Run `GET /api/sync/pull?since=<last_server_time>` through `SyncAPI`.
2. Save successful pull results into `WorkoutCache` and related read models.
3. Persist the returned `server_time` as the next `lastSyncAt`.
4. Start or restart the foreground push flusher idempotently.
5. Leave any in-flight live workout frozen: pulled prescription changes update
   the local cache for future sessions, not the active `ExecutionViewModel`.
6. Preserve offline-first behavior: transport failures fall back to cached data
   and queued writes remain durable.

On background, the app-sync owner must define one explicit posture for the
foreground push flusher. The current target is foreground-owned sync: stop or
park the foreground flusher on background, then restart it on the next
foreground transition. Background delivery is a separate capability, not an
implicit side effect of this foreground lifecycle work.

### Token rejection contract

A 401 from pull or push is auth rejection, not offline. The app-sync owner must
surface one recovery path:

- Pull 401 clears or invalidates the saved connection and routes back to
  FirstRun / connection entry.
- Push 401 stops push flushing and leaves queued writes durable. The next
  recovery action must route through the same connection entry path rather than
  silently retrying forever.
- No sync path should continue normal network attempts while
  `ConnectionManager` is in token-rejected state.

### Telemetry requirements

Foreground sync must be observable enough to answer "did the app try, what did
it do, and where did it stop?" without replaying a simulator video. The
app-sync owner should emit stage-level telemetry for:

- foreground sync requested
- pull started, succeeded, failed offline/server/decode, or token-rejected
- cache/writeback started and succeeded or failed
- push flusher started, stopped, restarted, token-rejected, or manually kicked
- lifecycle transition handled: active, background, inactive if needed
- manual refresh started and completed

Telemetry must avoid sensitive payload content. Current app-sync lifecycle
events include the trigger, final outcome, error class/description when present,
`since` presence, and pulled workout count when the event follows a pull.
Server identity and queued item counts are still part of `TELEM-GAP-005` until
the app has a cheap redacted server label and queue-count read path.

### Acceptance criteria

`APP-SYNC-A1. Single app-sync owner.` A third party can identify one app-level
owner for foreground pull, cache writeback, push flusher lifecycle, and token
rejection routing. `RootView` / app target code remains a thin lifecycle caller;
feature view models do not directly decide foreground/background sync policy.

`APP-SYNC-A2. Foreground refresh is deterministic.` On foreground with a saved
connection, the app runs a pull using stored `lastSyncAt`, saves successful
results, updates `lastSyncAt`, refreshes visible Today state while preserving
an active workout session, and starts/restarts push flushing idempotently.
Proof follows `docs/TESTING.md` foreground/background lifecycle expectations:
package or app-hosted tests for the app-root path, plus simulator QA for the
visible foreground behavior.

`APP-SYNC-A3. Background posture is explicit.` Backgrounding stops or parks the
foreground-owned flusher according to the selected posture, and foregrounding
restarts it without duplicate loops or lost queued writes. This criterion does
not require true iOS background delivery.

`APP-SYNC-A4. Token rejection has one recovery route.` Pull and push 401s stop
normal sync attempts, preserve queued outbound writes, and route to the
connection recovery surface. Silent retry loops after 401 fail this criterion.

`APP-SYNC-A5. Lifecycle telemetry is sufficient for proof.` The sync lifecycle
emits the stage events above so tests, logs, or local event readbacks can prove
where a foreground sync attempt stopped. Simulator video is not accepted as the
only proof for cache, queue, token, or server-side claims.

### Non-goals

- No true background upload/download capability in this slice.
- No CloudKit or Cloudflare transport change.
- No new conflict-resolution model.
- No change to the directionality rule: plans flow server → app; results flow
  app → server.
- No feature-owned sync policy hidden in Today, Execution, History, or Settings.

---

## Pull protocol

```
GET /api/sync/pull?since=<ISO8601>
  Authorization: Bearer <token>
```

Returns (schema owned by `server/workoutdb_server/api/sync.py` and mirrored in `schema/openapi.json`):

```jsonc
{
  "server_time": "2026-04-17T19:04:22Z",
  "workouts": [ /* full primitive workouts with primitive_blocks */ ],
  "exercises": [ /* all known exercises */ ],
  "user_parameters_latest": { /* latest-per-key map */ },
  "last_performed": { /* per-exercise most recent primitive result summary */ }
}
```

**Filter on `workout.updated_at`** — the server uses `updated_at`, not `created_at`, so PUT edits are picked up. The returned `server_time` is what the app sends as the next `since`.

**`last_performed` is a history summary, not an authoring payload.** The
primitive workout tree carries the current prescription. History summaries are
derived from result rows and are used for display/context only.

---

## Push protocol

```
POST /api/sync/results
  Authorization: Bearer <token>
  Body: {
    "primitive_set_logs": [...],
    "status_updates": [...],
    "workout_resets": [...]
  }
```

Each `primitive_set_log` row carries the UUID the app assigned. Re-pushing the
same UUID updates in place (idempotent). Rows are role-scoped:

- `slot` rows identify `block_id`, `set_id`, and `slot_id`, and may carry
  exercise-specific metrics. `set_index` is required and must match the slot's
  ordinal inside the authored set.
- `set_result` rows identify `block_id` and `set_id`, use `set_index = 0` as
  their aggregate sentinel, and cannot carry `slot_id` or exercise IDs.
- `block_result` rows identify only `block_id`, use `set_index = 0` and
  `set_repeat_index = 0` as aggregate sentinels, and cannot carry `set_id`,
  `slot_id`, or exercise IDs.

The server validates every row against the persisted primitive tree before
writing it. Unsupported swaps fail closed today: `performed_exercise_id` may be
omitted or equal the planned slot exercise, but arbitrary alternate exercise
IDs wait for the primitive alternatives wire shape.

`status_updates` flip `workout.status` (planned → active → completed / skipped)
and bump `workout.updated_at` so a subsequent pull sees the change.

`workout_resets` is the same-day History escape hatch: the app deletes local
logs immediately, queues `{workout_id}`, and the server deletes primitive
result rows tied to that workout, clears `completed_at`, and returns the
workout to `planned`. Without this server-side reset, the next pull would
resurrect the completed workout the user just reset locally.

**Completion atomicity.** During execution, individual primitive results may
still queue as single-result pushes. Save & Done builds one app-owned local
`WorkoutCompletionRecord` from the completed workout and its final result rows.
The current REST publisher durably replaces any still-pending single-log /
completed-status rows with one grouped queue item, then serializes that record
as one `/api/sync/results` body with both primitive result rows and a completed
`status_update`; future publishers such as CloudKit should consume the same
local record rather than reconstructing completion from separate queue rows.

**Batching.** The app sends pending results in whatever size is convenient. At
workout completion, the final primitive result rows and completed status must
publish as one grouped completion result. There is no server-side minimum or
maximum.

---

## Conflict rules

| Situation | Resolution |
|---|---|
| New prescription arrives mid-session | Live session is frozen. New prescription applies to the next occurrence of that workout. |
| Server has a newer `workout.updated_at` than the app's cached version | Server version wins. App refreshes on next pull (this is the common case). |
| App has a primitive result row the server doesn't | Push on next connectivity (queued). |
| App has a primitive result row the server already has (same UUID) | Idempotent update — server accepts and overwrites. |
| User edits a completed primitive result locally | Native primitive History correction is not active yet. History edit affordances are disabled unless a push hook is explicitly wired. |
| User deletes a result locally | Out of scope for v1 — the app does not offer delete. |
| Workout status transitions | Only `planned → active`, `planned → skipped`, `active → completed`, `active → skipped`, `completed → active` (reopen). Illegal transitions (e.g., `completed → planned`) are rejected server-side. |
| Exercise renamed while live session cached | Live session uses the cached exercise snapshot (name, notes) for display. On next pull, the updated row replaces the cached one and subsequent sessions render the new name. Historical result rows render through the available exercise cache. |
| Swap mid-workout (user taps an alternative) | Primitive swaps are fail-closed until alternatives exist on the active primitive wire schema. A slot result may omit `performed_exercise_id` or repeat the planned exercise ID; arbitrary alternate IDs are rejected server-side. |

**Rule of thumb:** prescriptions are server-owned; logs are app-owned. Inside the live session, nothing external reaches in.

---

## First-run UX

The app on first launch has no cached data. It cannot execute a workout until it is pointed at a server.

### Connection string

The user provides a single "connection string" that encodes both the server URL and the bearer token. Two surfaces, same data:

- **Paste** a URL: `https://<tailnet-host>/?t=<token>`
- **Scan a QR** that encodes the same URL

There is no login form. There is no account creation. There are no usernames or passwords. The bearer token *is* the credential; the server URL *is* the identity.

### First-launch flow

1. **Welcome.** "Point at your server to begin." Text input for URL + "Scan QR" button.
2. **Connecting.** On submit, the app calls `GET /api/version` with the provided token. On 200, the full connection pair (URL + token) is persisted to Keychain so same-device reinstalls do not require re-entry. `UserDefaults` keeps a URL mirror only for compatibility/diagnostics. On 401/failure, show "Couldn't reach the server — check the address and try again."
3. **First sync.** Call `GET /api/sync/pull` (no `since`). Show a progress indicator with metadata as it arrives — "4 weeks · 14 sessions · 42 exercises."
4. **Ready.** Land on Today.

### If the user is offline on first launch

They cannot proceed. There is nothing in the local database yet. The welcome screen offers a retry but no "skip." After the first successful sync, offline is fine forever.

### First-sync crash recovery

If the app is killed mid-first-sync, the first sync is **all-or-nothing**. On relaunch, any partial cache is cleared and the app retries `GET /api/sync/pull` (no `since`) from scratch. The connection string persists — the user does not need to re-enter it. This keeps "is the local DB trustworthy?" a single bit, not a partial-state question.

Subsequent (non-first) syncs are not all-or-nothing — an interrupted pull leaves the last successful `since` in place and the next pull resumes from there.

### Changing servers

`Settings → Change server` is destructive. Changing the server URL is equivalent to switching to a different user's data, so it wipes the local cache before the next sync. A confirmation dialog ("CHANGING SERVERS WIPES LOCAL DATA") guards the action.

---

## Offline behavior

### Surface

A **neutral pill** near the status bar reads `· offline` (no color, no banner, no modal). When sync is actively retrying, the pill flips to `↻ syncing…` briefly. After extended offline (>1h, optional), the pill can append elapsed time: `· offline · 2h`. There is no manual "go online" button — the app retries on its own cadence.

### During a workout

The workout executes fully from the local cache. Logs write locally and queue for push. The user sees no difference between online and offline execution. If the user completes a workout while offline, everything works normally; the queue flushes on the next successful connection.

### Wrong or unreachable server

If the configured URL fails DNS or times out, the app stays offline (no crash, no modal). The user can navigate to `Settings → Server` to update the URL or re-scan a QR. Typical cause: Tailscale disconnected on one end.

---

## Auth posture

- **RIR-only, no RPE.** The wire protocol carries `rir` (Int 0–5) on `set_log`. The system has no RPE scale, no conversion layer, no legacy mode. (Noted here alongside auth because both are system-identity claims that have to stay true across every surface.)
- **Bearer token over Tailscale.** The tailnet handles network-layer trust; the bearer distinguishes app traffic from other tailnet traffic. See ADR-2026-04-17-ux-scope for the full reasoning.
- **One token per `app_user`.** Adding a second user is creating another `app_user` row and issuing another token. No invite flow, no OAuth, no Apple Sign In.
- **Token rotation.** Not automated. If a token needs rotation, Claude (or the server operator) generates a new one; the user re-scans a QR on the device.
- **401 handling.** A 401 on any request is treated as "token rejected" — distinct from a transient network failure. The app surfaces a dedicated prompt ("Token rejected — re-scan QR or paste a new connection string") and pauses the push queue until the user re-authenticates. Silent retry loops do not apply to 401.
- **No public exposure.** The server is not reachable from the public internet. Alternatives (Cloudflare Zero Trust, etc.) remain open options if Tailscale becomes inconvenient — the app does not care, as long as the URL reaches the server and the bearer passes.

---

## Future replication and endpoint directions

The current REST-over-private-network sync path remains the implemented
contract. CloudKit was investigated as a possible Apple-device replication
substrate, but is **not** part of the current sync architecture.

### CloudKit decision

Decision: do not use CloudKit for the current sync architecture. Keep REST as
the canonical Claude authoring and readback path, and keep SwiftData as the
app's permanent offline execution store.

Why:

- The app already needs a backend because Claude authors plans and needs
  history readback. Once that backend exists, CloudKit mostly becomes a second
  sync system rather than a replacement.
- A headless REST service should not be planned as a durable direct writer into
  each user's private CloudKit database. Apple's server-to-server key path is
  public-database oriented; private user access depends on user-authenticated
  web tokens, which is a different operating model.
- CloudKit background delivery is indeterminate. Explicit `CKSyncEngine`
  send/fetch operations can support foreground user-driven attempts and tests,
  but CloudKit should not replace REST for timing-sensitive "plan now" or
  "result readback now" flows unless a later real-device/account probe proves
  the latency and recovery contract.
- Native SwiftData/CloudKit mirroring hides too much sync/outbox policy for
  WorkoutDB's current proof requirements: durable completion publication,
  retry classification, token/account recovery, conflict visibility, and
  state readback.
- CloudKit sharing is a collaboration feature, not the default multi-user
  account model. Future other-user support should keep REST accounts/service
  identity as the user boundary, with CloudKit limited to same-user
  Apple-device replication unless a product requirement explicitly asks for
  user-managed shared workouts.

What could change this decision:

- Same-user Apple-device replication becomes important enough that REST alone
  is awkward, for example iPhone/iPad/Mac/Watch need to exchange app state when
  the backend is unreachable.
- A real-device/account probe proves explicit CloudKit send/fetch can meet a
  concrete latency and recovery target for a named user flow.
- Product direction shifts toward user-managed shared workouts where
  CloudKit's owner/participant model is the feature, not an implementation
  detail.
- The backend becomes a narrow bridge rather than the canonical store, and the
  app can remain the authoritative importer/publisher for all private CloudKit
  data without losing Claude readback.

If one of those changes occurs, the next CloudKit spike should be narrow:
prove one app-mediated bridge slice using explicit zones/change state, account
availability handling, offline behavior, conflict rules, manual send/fetch, and
the REST Claude authoring/readback path. Non-goal: replacing the server before
the authority model is proven.

Future sync work should investigate two separate lanes rather than treating
them as one generic replacement:

1. **Apple-device replication lane.** CloudKit is the likely first candidate
   for iPhone/iPad/Mac/Watch data replication because it syncs app-owned
   records through the user's iCloud account. This is not just a transport swap:
   it changes record ownership, conflict behavior, account dependency,
   background-delivery expectations, and possibly the local data model. The
   only viable future planning assumption is REST canonical plus explicit
   CloudKit bridge: SwiftData remains the app's permanent offline execution
   store; REST remains the immediate Claude authoring and readback channel; a
   future CloudKit bridge publishes/consumes selected app-owned records for
   same-user Apple-device replication.
   A CloudKit path should use app data records, zones, and sync state, not
   iCloud Drive files as the primary database. iCloud Drive may be useful for
   explicit import/export artifacts, but file sync should not become the source
   of truth for workout state unless a spike proves CloudKit cannot cover the
   required app data.
2. **External/private service lane.** Cloudflare Tunnel + Cloudflare Access are
   candidates for exposing selected local endpoints to non-Apple clients,
   callbacks, or future app families without opening the origin publicly. The
   local examples in `/Users/ericfeunekes/coding/oauth-callback` and
   `/Users/ericfeunekes/coding/personal-mcp-gateway` show the intended security
   posture: loopback-only origins, Cloudflare Access as the external trust
   boundary, narrow named capabilities, local secrets, and audit logs that avoid
   sensitive content.

State authority must stay explicit regardless of transport:

- Claude/server remains the plan author unless a later requirement explicitly
  moves authoring elsewhere.
- The app remains authoritative for completed workout results it records.
- CloudKit may become a replication substrate for app-owned records; it should
  not silently create a second planner or conflict resolver.
- If CloudKit proceeds, assume a hybrid record shape: coarse authored workout
  records where that remains under record limits, plus normalized app-owned
  completion/result and sync-state records. Avoid one giant database blob and
  avoid fully normalized CloudKit records before the first bridge proves it.
- Cloudflare-protected endpoints may expose narrow APIs or callback receivers;
  they should not become a broad generic write proxy into personal data.

Open decisions before implementation:

- `SYNC-GAP-003`: Whether Cloudflare Access identity maps to app users, service capabilities,
  or both.
- Whether the general endpoint should live inside this repo, beside the
  existing OAuth callback service, or as a separate personal gateway.

Spike contract if the Cloudflare lane is reopened:

- **Cloudflare Access endpoint spike:** expose one narrow loopback-only
  endpoint through Tunnel + Access, prove identity headers/JWT validation,
  audit logging, and capability boundaries. Non-goal: a broad generic write
  proxy into workout or personal data.

---

## Watch sync

The Watch has two possible execution paths:

- **WorkoutKit handoff:** Apple's Workout app owns the live Watch workout.
  Setmark does not own HR slots, haptics, start/end-set actions, or event replay
  in this lane. The iPhone exports eligible workouts and imports only proven
  completion/result facts.
- **Custom Setmark Watch app:** the later watch-primary path owns HR, haptics,
  start/end-set, custom metric views, and offline event replay.

Neither path talks to the server directly from the Watch. The iPhone remains
the single point of contact with the server.

Pairing the watch is handled by iOS (WatchConnectivity auto-discovers the companion). From the user's perspective, once the watch app is installed on the paired watch, it works. No per-device server configuration.

The watch face grammar (widget-based faces for set / rest / superset / EMOM / AMRAP / for-time / intervals / cardio) is deferred to **v1.1+**. See `docs/design/src/watch-grammar.jsx` and `docs/design/src/watch-hifi-v2.jsx` for the target shape when we promote it.

---

## Open items

- `SYNC-GAP-001`: **Stale live-session expiry.** A live session is frozen, but
  the app has no selected behavior for returning to an unfinished workout days
  later after newer prescriptions may have arrived. Pick explicit expiry,
  refuse/resume, or never-expire behavior before changing execution/sync around
  long-lived active sessions.
- **Sync triggers on the watch.** Currently the phone is the only sync actor. If the watch ever writes primitive result rows independently (not in v1), we'll need a watch → phone → server reconciliation step.
- **Result deletion scope.** v1 only deletes primitive result rows through `workout_resets` for same-day accidental workout logs. Arbitrary historical result deletion/edit provenance remains out of scope unless the user asks for audit-grade history later.
- **Multiple active workouts.** The spec allows a user to mark multiple workouts `active`, but the app UX assumes one active workout at a time. Behavior if a second workout is started before the first is completed is undefined; we'd need to decide whether "start workout" auto-completes the prior one or refuses.
