---
title: Sync, connectivity, and first-run
status: accepted
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
| Workouts (plans) | Server → App | Claude | `workout`, `block`, `workout_item` |
| Exercises | Server → App | Claude | `exercise` |
| Alternatives | Server → App | Claude | `exercise_alternative` |
| User parameters | Server → App | Claude | `user_parameters` (latest-per-key) |
| `last_performed` summary | Server → App | Derived | Piggybacked on `/api/sync/pull` |
| Set logs (results) | App → Server | App | `set_log` |
| Workout status changes | App → Server | App | `workout.status`, `workout.completed_at` |
| Body weight at completion | App → Server | App | `user_parameters` row with key `bodyweight_kg` |

**No field is written from both sides.** If a field would be bi-directional (e.g., "preferred rest interval"), it lives in `user_parameters` and Claude owns writes; the app reads.

---

## Cadence

The app pulls and pushes on three triggers:

1. **App open.** On every foregrounding, the app issues `GET /api/sync/pull?since=<last_server_time>`.
2. **After a log write.** When the user completes a set (or a workout), the app issues `POST /api/sync/results` with the new rows. Push is fire-and-forget from the UI's perspective — failure is queued silently.
3. **Gentle retry while foregrounded.** Every ~60s while the app is in foreground, the retry queue is flushed (one attempt per pending batch). No exponential backoff needed at single-user scale.

**No aggressive polling.** No WebSocket. Push notifications are not in scope for v1 — the user will have opened the app by the time a new plan matters.

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
  "workouts": [ /* full workouts with nested blocks, items, alternatives */ ],
  "exercises": [ /* all known exercises */ ],
  "user_parameters_latest": { /* latest-per-key map */ },
  "last_performed": { /* per-exercise most recent set_logs + prescription snapshot */ }
}
```

**Filter on `workout.updated_at`** — the server uses `updated_at`, not `created_at`, so PUT edits are picked up. The returned `server_time` is what the app sends as the next `since`.

**`last_performed` includes swap targets.** When a workout item has alternatives, the alternative exercises' history is also included — otherwise swapping mid-workout would show "no data" for the substitute.

---

## Push protocol

```
POST /api/sync/results
  Authorization: Bearer <token>
  Body: { "set_logs": [...], "status_updates": [...] }
```

Each `set_log` row carries the UUID the app assigned. Re-pushing the same UUID updates in place (idempotent). `status_updates` flip `workout.status` (planned → active → completed / skipped) and bump `workout.updated_at` so a subsequent pull sees the change.

**Batching.** The app sends pending results in whatever size is convenient — per set after each log write is fine; batches at workout completion are also fine. There is no server-side minimum or maximum.

---

## Conflict rules

| Situation | Resolution |
|---|---|
| New prescription arrives mid-session | Live session is frozen. New prescription applies to the next occurrence of that workout. |
| Server has a newer `workout.updated_at` than the app's cached version | Server version wins. App refreshes on next pull (this is the common case). |
| App has a set_log the server doesn't | Push on next connectivity (queued). |
| App has a set_log the server already has (same UUID) | Idempotent update — server accepts and overwrites. |
| User edits a completed set_log locally | Updated row pushes like any other; server overwrites on UUID. |
| User deletes a set_log locally | Out of scope for v1 — the app does not offer delete. |
| Workout status transitions | Only `planned → active`, `planned → skipped`, `active → completed`, `active → skipped`, `completed → active` (reopen). Illegal transitions (e.g., `completed → planned`) are rejected server-side. |
| Exercise renamed while live session cached | Live session uses the cached exercise snapshot (name, notes) for display. On next pull, the updated row replaces the cached one and subsequent sessions render the new name. Historical set_logs render the name that was current when they were logged (cached at log time). |
| Swap mid-workout (user taps an alternative) | Swap is session-local. `set_log.workout_item_id` still references the original item; the app writes the actually-performed `exercise_id` onto the log row so history is truthful. The workout template is not mutated. |

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
2. **Connecting.** On submit, the app calls `GET /api/version` with the provided token. On 200, the token and URL are persisted to the keychain (token) and `UserDefaults` (URL). On 401/failure, show "Couldn't reach the server — check the address and try again."
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

## Watch sync

The Apple Watch companion is part of the app in v1 for HR, haptics, and start/end-set. It does **not** talk to the server directly. The watch talks to the iPhone via WatchConnectivity; the iPhone is the single point of contact with the server.

Pairing the watch is handled by iOS (WatchConnectivity auto-discovers the companion). From the user's perspective, once the watch app is installed on the paired watch, it works. No per-device server configuration.

The watch face grammar (widget-based faces for set / rest / superset / EMOM / AMRAP / for-time / intervals / cardio) is deferred to **v1.1+**. See `docs/design/src/watch-grammar.jsx` and `docs/design/src/watch-hifi-v2.jsx` for the target shape when we promote it.

---

## Open items

- **Sync triggers on the watch.** Currently the phone is the only sync actor. If the watch ever writes set_logs independently (not in v1), we'll need a watch → phone → server reconciliation step.
- **Deletion semantics.** The v1 app does not delete set_logs. If that becomes a user request later, we'll need to decide between soft-delete (a `deleted_at` column) and hard-delete (push a tombstone). Revisit when the request appears.
- **Multiple active workouts.** The spec allows a user to mark multiple workouts `active`, but the app UX assumes one active workout at a time. Behavior if a second workout is started before the first is completed is undefined; we'd need to decide whether "start workout" auto-completes the prior one or refuses.
