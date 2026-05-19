---
title: Setmark v2 architecture spec
status: accepted — primitives are the active data contract
date: 2026-04-15
last_reviewed: 2026-05-18
purpose: System-level architecture for the dumb-app/smart-conversation workout system. The active workout data contract is primitive-only; older timing-mode/prescription sections are retained as historical context for bridge code only.
covers:
  - docs/specs/primitives-data-model.md
  - docs/prescription.md
  - docs/sync.md
  - server/
  - app/
---

# Setmark v2 — Architecture Spec

**Date:** 2026-04-15 (accepted 2026-04-17)
**Status:** Accepted. The former v1 Python CLI / YAML / Google Calendar path
is gone; this repo is the active v2 system. The active workout data contract is
the primitive Block > Set > Slot model in
`docs/specs/primitives-data-model.md`.

---

## Philosophy: dumb app, smart conversation

The app does three things: show the workout, time it, log what happened. That's it.

All intelligence lives outside the app, in conversation with Claude:
- Workout programming and periodization
- Exercise selection and muscle group targeting
- Progression decisions (load, volume, intensity)
- Alternatives and substitutions (pre-computed, pushed as data)
- Recovery and readiness assessment
- Body composition tracking (photos, measurements discussed in conversation)

The app doesn't need to know what a muscle group is. It doesn't need substitution logic. It doesn't need to infer stimulus. It receives a fully composed workout with everything it needs to run the session, including pre-computed alternatives and user-specific parameters.

Future read-only taxonomy, capability, or external-mapping data may be added
when a concrete history, export, or sync behavior requires it. That data must
not turn the app into the programming authority: primitive execution stays
vendor-neutral, and adapter-specific WorkoutKit, Strava, HealthKit, or exercise
similarity decisions belong in separate taxonomy or adapter-profile layers.

---

## Data model

> **Status (2026-05-18):** The primitive-only contract is the active contract.
> `docs/specs/primitives-data-model.md` and its aspect docs are canonical for
> the Block > Set > Slot authoring shape, primitive result roles, runtime
> legality, QA-data reset, and adapter-readiness rules. The older
> timing-mode/block-item description below is **non-authoritative historical
> context** for bridge surfaces that still project primitives into existing app
> execution code during the cutover.
>
> The durable wire contract is primitive-only: workout create/update/read and
> sync pull expose `primitive_blocks`, and result pushes use
> `primitive_set_logs`.

### Historical pre-primitives model (non-authoritative)

The rest of this Data model section, until `## Persistence architecture`, is
the superseded timing-mode / `workout_item` / `set_log` model. It must not be
used to author new requirements. Use it only to understand remaining legacy
projection code that has not yet been replaced by primitive-native execution
and history correction.

#### Former core principle: composition with timing

Everything is blocks. A block has a timing mode and contains exercises (or nested blocks). The app's job is to read the timing mode and drive the appropriate timer UI.

#### Former entities

#### `exercise`

An atomic movement. Minimal metadata — the app doesn't reason about exercises, it just displays them.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Stable across sync. **Claude owns the ID namespace** — Claude pushes `{id, name}` and is responsible for reusing an existing ID when the same exercise recurs across conversations. The server does not canonicalize on name. |
| `name` | String | Display name ("Back Squat", "400m Run") |
| `notes` | String? | Brief cue or form reminder, pushed by Claude |
| `demo_url` | String? | Optional link to a video demo |
| `default_prescription_json` | String? | Library-level prescription defaults (typically `target_rir` + `autoreg`) merged into every `workout_item` that references this exercise unless the item overrides. See `docs/decisions/ADR-2026-04-18-smart-defaults.md`. |
| `default_alternatives_json` | String? | Library-level alternatives — a JSON array matching the `exercise_alternative` shape minus the `workout_item_id` pointer. Items that omit alternatives inherit this list. |

No muscle groups, movement patterns, or modality on the exercise itself in the
former pre-primitives baseline. That knowledge lives in conversation. If
Claude wants the app to display a muscle tag for context, it goes in `notes` or
`metadata_json`. A later exercise taxonomy may add structured relationships or
external mappings, but only as read-only data for named history/export/sync
behaviors, not as app-side programming logic.

**ID management:** Claude lists existing exercises via `GET /api/exercises` at the start of a conversation, then reuses UUIDs for recurring exercises. Pushing a new exercise with a fresh UUID creates a new row — the server doesn't deduplicate. This keeps the server dumb and gives Claude explicit control over history continuity.

#### `exercise_alternative`

Pre-computed swap options attached to a specific exercise within a specific workout. Claude decides these, not the app.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `workout_item_id` | UUID | FK — which item in which workout this alternative applies to |
| `exercise_id` | UUID | FK — the alternative exercise |
| `reason` | String | Why this is a good swap ("machine taken", "endurance variant", "lower back fatigue") |
| `parameter_overrides_json` | String? | If the alternative needs different sets/reps/load than the original |

The app shows 2–3 alternatives per exercise. User taps one, it swaps in. No app-side logic needed.

#### `block`

A group of exercises with a timing contract. Blocks nest.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `workout_id` | UUID | FK to workout |
| `parent_block_id` | UUID? | Null = top-level block; non-null = nested inside another block |
| `position` | Int | Order within parent |
| `name` | String? | "Warm-up", "Main lift", "Metcon", etc. |
| `timing_mode` | Enum | See timing modes below |
| `timing_config_json` | String | Mode-specific config |
| `rounds` | Int? | Number of times through this block (null = 1) |
| `rounds_rep_scheme_json` | String? | JSON array for block-level descending/ascending rep schemes such as `[21,15,9]`. |
| `notes` | String? | |
| `intent` | String? | Freeform coach-authored purpose for the block. Null means the app renders no intent copy. |

**Timing modes** (the key feature):

| Mode | `timing_config_json` keys | App behavior |
|---|---|---|
| `straight_sets` | `rest_between_sets_sec`, `rest_between_exercises_sec` | Set counter + rest timer between sets |
| `superset` | `rest_between_rounds_sec` | Cycle through exercises, rest after each round |
| `circuit` | `rest_between_exercises_sec`, `rest_between_rounds_sec` | Same as superset but more exercises |
| `emom` | `interval_sec` (typically 60) | Minute timer, new exercise each minute |
| `amrap` | `time_cap_sec` | Countdown timer; each `next` records the completed station, then finish asks for partial reps on the current station only |
| `for_time` | `time_cap_sec` (optional) | Stopwatch, optional cap |
| `intervals` | `work_sec` OR `work_distance_m`; `rest_sec` OR `rest_distance_m`; optional `target_pace_sec_per_km` | Work/rest alternating timer; distance- or time-based |
| `tabata` | (fixed: work=20, rest=10, rounds=8) | Tabata timer |
| `continuous` | `target_duration_sec?`, `target_distance_m?`, `target_pace_sec_per_km?` | Running clock, optional targets |
| `accumulate` | `target_duration_sec?`, `target_reps?`, `target_distance_m?` | Free-rest bouts accumulated toward one total target |
| `custom` | `segments: [{type: "work"|"rest", duration_sec, label?}]` | Arbitrary sequence of timed segments |
| `rest` | `duration_sec` | Countdown rest block between other blocks (e.g., between metcons) |

**Block-level rep scheme (chippers, ladders):**

When reps descend or ascend across rounds (e.g., 21-15-9, 100-80-60-40-20, 1-2-3-…-10), the block carries the scheme instead of each workout_item:

```json
{
  "timing_mode": "for_time",
  "rounds": 3,
  "rounds_rep_scheme": [21, 15, 9],
  "workout_items": [ /* exercises; reps omitted when rounds_rep_scheme is present */ ]
}
```

This covers everything from "3×8 bench press with 90s rest" to "21-15-9 Fran" to "5K easy run" to "30/30 intervals × 10" to "10×400m @ 5K pace."

#### `workout_item`

An exercise placed inside a block.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `block_id` | UUID | FK |
| `position` | Int | Order within block |
| `exercise_id` | UUID | FK |
| `prescription_json` | String | Resolved "what to do" — server merges the exercise's `default_prescription_json` into whatever the client sent at ingest. Immutable once stored; library mutations don't rewrite history. See `docs/decisions/ADR-2026-04-18-smart-defaults.md`. |
| `prescription_json_raw` | String? | The original sparse payload the client sent, preserved when the server's merge changed something. Null when the client sent a fully-resolved prescription. Diagnostic / re-merge aid only — the app reads only `prescription_json`. |

**`prescription_json` by context:**

- Strength: `{"sets": 3, "reps": 8, "load_kg": 80, "target_rir": 2, "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5, "undershoot_at": 2, "undershoot_step_kg": 2.5, "apply_to": "remaining" }}` — `target_rir` + the `autoreg` subobject drive the app's load-adjustment rules on remaining sets. Server does not interpret; the app applies. See `docs/prescription.md` for the full vocabulary and `docs/decisions/ADR-2026-04-17-rir-autoreg-sync.md` for the decision record.
- Reps-only: `{"sets": 4, "reps": 12}`
- Time-based: `{"duration_sec": 45}` (e.g. plank hold within a circuit)
- Distance: `{"distance_m": 400, "target_pace_sec_per_km": 270}`
- Rep range: `{"sets": 3, "reps_min": 8, "reps_max": 12, "load_kg": 70}`
- Unilateral: author left/right variants as separate exercise/workout items when
  actuals matter, with `load_kg` interpreted as per-implement load; see
  `docs/prescription.md`.
- Percentage-based: `{"sets": 5, "reps": 3, "percent_1rm": 0.85}` — app resolves from user_parameters
- Tempo (eccentric-bottom-concentric-top): `{"sets": 4, "reps": 5, "load_kg": 80, "tempo": "3-0-1-0"}`
- Per-set variation (pyramids, wave loading): `{"sets_detail": [{"reps": 12, "load_kg": 60}, {"reps": 10, "load_kg": 65}, {"reps": 8, "load_kg": 70}, {"reps": 6, "load_kg": 75}]}` — when `sets_detail` is present, flat `sets/reps/load` are ignored
- Drop sets: `{"sets_detail": [{"reps": 10, "load_kg": 20}, {"reps": "amrap", "load_kg": 15, "drop": true}, {"reps": "amrap", "load_kg": 10, "drop": true}]}` — `drop: true` tells the app to collapse the group under one rest timer
- Cluster sets / rest-pause / myo-reps: `{"sets": 4, "reps": 5, "load_kg": 100, "sub_sets": 4, "intra_set_rest_sec": 15}` — each of the 4 top-level sets = 4 sub-sets of 5 reps with 15s rest between sub-sets; `rest_between_sets_sec` still applies between top-level sets
- Cluster stations in round-based blocks may omit `sets`; the block `rounds` supplies the top-level count while the station keeps `sub_sets` and `intra_set_rest_sec`.

Keeping this as JSON meant new pre-primitives prescription shapes did not
require schema changes. This is no longer the active authoring contract.
Primitive authoring lives in `docs/specs/primitives-data-model.md`; any
remaining `prescription_json` readers are bridge/projection surfaces only.

#### `workout`

A complete session ready to execute.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `user_id` | UUID | FK |
| `name` | String | "Tuesday Pull Day", "5K Tempo Run" |
| `scheduled_date` | Date? | When it's planned for |
| `status` | Enum | `planned`, `active`, `completed`, `skipped` |
| `source` | String | `claude` (pushed by conversation), `manual` (created in app) |
| `notes` | String? | Session-level notes from Claude |
| `created_at` | Timestamp | |
| `updated_at` | Timestamp | Server-managed. Bumped on create, on PUT `/api/workouts/:id` (including nested block replacement), and on status transitions via POST `/api/sync/results`. `/api/sync/pull?since=X` filters on this. |
| `completed_at` | Timestamp? | |
| `tags_json` | String? | JSON array of free-form tags Claude attaches for analysis grouping, e.g. `["hypertrophy_block_2", "week_3", "pull_day", "deload_pending"]`. App ignores; used for querying. |

#### `set_log`

What actually happened. One row per set performed.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `workout_item_id` | UUID | FK — the planned item. Never changes; swaps are recorded via `performed_exercise_id`, not by rewriting this FK. |
| `performed_exercise_id` | UUID? | The exercise actually performed. Null = the item's default exercise was performed as planned. Non-null = the user swapped to an alternative mid-workout (the alternative's `exercise_id`). Session-local swap is lossless on the log; the workout template is not mutated. |
| `set_index` | Int | 1-based |
| `reps` | Int? | |
| `weight` | Float? | |
| `weight_unit` | Enum | `kg`, `lb` |
| `duration_sec` | Float? | |
| `distance_m` | Float? | |
| `rir` | Int? | Reps in Reserve (0–5 scale). 0 = failure, 5 = very easy. See `docs/prescription.md` § "RIR" for the full scale and `docs/decisions/ADR-2026-04-17-rir-autoreg-sync.md` for why this replaced RPE. |
| `is_warmup` | Bool | |
| `skipped` | Bool | True when the user explicitly skipped the planned work unit. Existing/migrated rows default false. |
| `side` | Enum | `left`, `right`, or `bilateral`. Existing/migrated rows default `bilateral`. This is a shipped/reserved round-trip field, not the active unilateral authoring model; app UX and analytics must not infer left/right grouping from it unless a later taxonomy phase explicitly promotes the field. |
| `started_at` | Timestamp? | When the user tapped "start set" or the timed set began (watch) |
| `completed_at` | Timestamp | |
| `hr_avg_bpm` | Integer? | Average HR during the set (from HealthKit) |
| `hr_max_bpm` | Integer? | Peak HR during the set |
| `cadence_avg_spm` | Integer? | Average cadence during the set (running/cycling) |
| `motion_samples_ref` | String? | Optional reference to raw accelerometer/gyro samples captured during the set. Reserved for future power/bar-speed analysis; capture not required in v1. |
| `notes` | String? | |

#### `user_parameters`

User-specific data that Claude pushes so the app can resolve things like percentage-based loading and display personalized targets. **Append-only log** — every push inserts a new row. The latest value for a given key is `MAX(updated_at) WHERE key = ?`. History is preserved for trend analysis, correlations between lifestyle parameters and performance, and longitudinal experiments.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `user_id` | UUID | FK |
| `key` | String | e.g. `one_rep_max_<exercise_id>_kg`, `resting_hr_bpm`, `5k_pr_sec`, `training_age_years`, `preference_rep_range`, `bodyweight_kg`, `sleep_hours_7d_avg`. The app pushes `bodyweight_kg` on workout completion when the user records it — body weight is a user_parameter, not a column on `workout`. |
| `value` | String | Stored as string, interpreted by context |
| `updated_at` | Timestamp | |
| `source` | String | `claude`, `app_log`, `manual` |

This is a key-value log, not a fixed schema. Claude can push any parameter, any number of times. The app reads latest-per-key via `GET /api/user-parameters?latest=true` to resolve `percent_1rm` prescriptions and display personalized targets. Claude can query history with `GET /api/user-parameters?key=X&since=Y` for analysis. Unknown keys are stored but ignored by the app until it's taught to use them.

**Why append-only:** overwriting is irreversible. If next week Claude updates `bodyweight_kg`, this week's value must survive — otherwise trend analysis becomes impossible. The cost (linear growth, a few thousand rows per year per user) is trivial; the loss from upsert semantics is permanent.

#### `app_user`

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | |
| `created_at` | Timestamp | |

---

## Persistence architecture

### On-device: SwiftData (SQLite)

- Source of truth during a workout.
- Full offline capability. App never crashes or degrades without network.
- All entities above live in SwiftData with the same schema.

### Home server: Python + SQLite

- Lightweight FastAPI (or similar) service running on Eric's home server.
- Same schema as the app (SQLite, mirrored tables).
- REST API for CRUD + sync.
- This is how Claude interacts with the system — reads results, writes workout plans.
- Also the exchange layer for sharing with friends/family.

### Sync model

**Direction is clear — no conflict resolution needed:**

| Data | Flows | Owner |
|---|---|---|
| Workouts (plans) | Server → App | Claude (via server) |
| Exercises | Server → App | Claude (via server) |
| Alternatives | Server → App | Claude (via server) |
| User parameters | Server → App | Claude (via server) |
| Set logs (results) | App → Server | App (was there when the work happened) |
| Workout status changes | App → Server | App (started, completed, skipped) |
| Body weight at completion | App → Server | App (pushed as a `user_parameters` row with key `bodyweight_kg`) |

**Sync mechanics (summary — see `docs/sync.md` for the deep version):**
- App pulls on every foregrounding (`GET /api/sync/pull?since=<last_server_time>`).
- App pushes results after each log write; failures queue silently.
- Gentle ~60s foreground retry flushes the queue.
- UUIDs everywhere. Re-pushing a known UUID is idempotent.
- `updated_at` on every record. Filter uses `workout.updated_at` so PUT edits are picked up.

**Conflict rules:**
- Server wins for prescriptions; app wins for logs.
- Live session is frozen: a new prescription arriving mid-session applies to the *next* occurrence of that workout, not the one currently executing.
- Swaps mid-workout are session-local — the workout template is not mutated; the actually-performed `exercise_id` is recorded on the primitive result row.

**Offline behavior:**
- Offline is the default assumption, not an error state. Neutral "offline" pill, no alarm colors.
- App executes a fully-pulled workout with zero network calls (load-bearing invariant).
- Results queue locally and push on next connectivity.
- No push notifications in v1.

**First-run UX:** single connection string (URL + bearer token) via paste or QR; no login form. Full detail in `docs/sync.md` § "First-run UX".

See `docs/sync.md` for cadence details, conflict-case enumeration, and the first-run flow.

### Future: push signal

If we want real-time "new workout available" notifications later, options:
- WebSocket from home server (simple, requires connectivity)
- Apple Push Notification via a thin relay
- Local network Bonjour discovery (if on same WiFi as server)

Not needed for v1. Pull-on-open is fine.

---

## API contract (home server)

### Endpoints

All JSON. Auth: simple bearer token (single-user system, doesn't need more). Per
ADR-2026-04-17, the token maps to an `app_user` row; routes resolve `user_id`
from the token — no endpoint accepts `user_id` in a query param or body.

**Plans (Claude → Server → App):**

```
POST   /api/workouts                          — Create a primitive workout (`primitive_blocks`)
PUT    /api/workouts/:id                      — Update a primitive workout (`primitive_blocks`)
GET    /api/workouts                          — List workouts. Filters: ?status=planned&after=2026-04-15&tag=hypertrophy_block_2
GET    /api/workouts/:id                      — Get full primitive workout (`primitive_blocks`)

POST   /api/exercises                         — Create/upsert exercises (Claude-owned UUIDs)
GET    /api/exercises                         — List all exercises

POST   /api/user-parameters                   — Append user parameter rows (batch). Never updates; always inserts.
GET    /api/user-parameters?latest=true       — Latest-per-key for a user (app uses this to resolve prescriptions)
GET    /api/user-parameters?key=X&since=Y     — Full history for a key since timestamp (Claude uses this for trend analysis)
```

**Results (App → Server):**

```
POST   /api/sync/results       — Push completed workout data or same-day reset requests
                                 Body: { primitive_set_logs: [...],
                                         status_updates: [...],
                                         workout_resets: [...] }
                                 Each primitive_set_log MUST carry the UUID the app assigned;
                                 re-pushing the same id updates in place (idempotent).
                                 Slot, set_result, and block_result rows must reference IDs
                                 that belong to the pushed workout's primitive tree.
                                 Status updates bump
                                 workout.updated_at so a subsequent /api/sync/pull sees them.
                                 Workout resets delete the workout's primitive_set_logs and return it
                                 to planned so accidental same-day logs can be started over.

POST   /api/health/archive     — Upload selected normalized HealthKit archive records
                                 and tombstones for the personal archive lane.
                                 Body carries request_set_key, server_namespace,
                                 descriptor_fingerprint, next_cursor, records, and
                                 tombstones. The server idempotently upserts records
                                 by (user, descriptor_id, external_id), stores
                                 tombstones, and acknowledges the cursor only after
                                 the upload is committed.
```

**Sync (App pull):**

```
GET    /api/sync/pull?since=<timestamp>
                                — Get everything changed since last sync. user_id is
                                  resolved from the bearer token (ADR-2026-04-17).
                                  Returns workouts with primitive_blocks,
                                  the full exercise library, and latest-per-key user_parameters
                                  whose newest row is after `since`. Omit `since` for a full pull.
                                  The response's `server_time` is what the app should send
                                  as the next `since`. Filtering uses `workout.updated_at`, not
                                  `created_at`, so PUT /api/workouts/:id edits are picked up.
                                  `last_performed` covers exercises referenced both directly
                                  and via alternatives (swap targets must carry their own history).
```

---

## What Claude pushes vs what the app decides

| Concern | Who decides | How |
|---|---|---|
| Which exercises this week | Claude | Pushes workout plans to server |
| Sets, reps, duration, distance, rounds, and load targets | Claude | In `primitive_blocks[].sets[].slots[].work_target` and `load` |
| Target RIR per exercise | Claude | Slot/set/block `stimuli` in the primitive tree |
| Autoregulation rules | Claude | Attached to the relevant primitive stimulus; the app applies only documented runtime rules |
| Load step / equipment granularity | Claude | Authored as primitive load/autoreg metadata; no per-exercise app default |
| Alternatives if something's unavailable | Claude | Pre-computed primitive slot alternatives |
| User maxes, rep ranges, preferences | Claude | Pushes to `user_parameters` |
| Percentage-based load resolution | App | Resolves primitive relative load against latest local `user_parameters` at seed time |
| Timer behavior | App | Reads primitive timing/traversal/repeat cells, drives UI |
| Autoreg application (propose + apply to remaining sets) | App | Reads primitive stimulus/autoreg metadata, proposes on rest screen, applies on accept |
| Hold-autoreg (session-scoped) | User (in app) | "Undo" on proposal sets local `autoregHeld` for the session; cleared on complete |
| Logging what happened | App | Writes `primitive_set_logs` rows with `slot`, `set_result`, or `block_result` role |
| Body weight at completion | App → user_parameters | Optional prompt at completion writes a `bodyweight_kg` row |
| Swapping to an alternative mid-workout | User (in app) | Taps alternative; session-local; primitive log carries `performed_exercise_id` |
| Editing a past logged result | User (in app) | Primitive correction path is required before server-backed history correction is re-enabled |
| Editing a pending set | User (in app) | Tap load/reps cell; marks `adjust: "manual"` |
| Progression decisions | Claude | Reads results from server, adjusts next week's plans |
| "How are you feeling" / readiness | Conversation | Eric tells Claude, Claude adjusts plans before pushing |
| Body photos, measurements | Conversation | Discussed here, not in app |

---

## What's NOT in this spec (by design)

- **UI/UX.** Eric builds whatever interface he wants against this data model.
- **Workout programming logic.** Lives in conversation, not in code.
- **Muscle group / movement pattern taxonomy.** Claude knows this; the app doesn't need to.
- **Equipment modeling.** Removed from v2. If a machine is taken, the alternative is already attached.
- **Stimulus inference.** Claude does this in conversation from the logged data.
- **Social features.** Friends get the same app pointed at Eric's server (or their own). Sharing = pushing workouts to their user account on the server.

---

## Watch integration

Watch delivery now has two separate lanes:

1. **Early WorkoutKit handoff.** `docs/features/watch-workoutkit-handoff.md`
   is the shorter path for getting eligible Setmark workouts onto Apple Watch.
   The iPhone maps a narrow subset of Setmark workouts into WorkoutKit plans,
   then schedules or hands them off through the platform path proven by the
   WorkoutKit spike. Apple's Workout app owns the live Watch experience in this
   lane; Setmark remains the authoring, planning, history, and analysis
   surface. Completion/result reconciliation is a separate future lane, not a
   requirement of WorkoutKit push.
2. **Later custom watch-primary execution.**
   `docs/features/watch-primary-execution.md` and `docs/watch-metrics.md`
   remain the target for Setmark-owned Watch execution: custom Watch UI,
   haptics, HR slots, watch-side set logging, offline event replay, and
   phone/watch authority handoff.

The Watch never talks to the server directly in either lane. In the WorkoutKit
handoff lane, the iPhone performs the push/open/schedule work. Any later
result import or reconciliation is a separate module. In the custom
watch-primary lane, the Watch talks to the iPhone through a versioned
WatchBridge protocol and the iPhone pushes results through the existing sync
queue.

Do not mix these lanes during implementation planning. WorkoutKit handoff is
not a partial implementation of the custom Watch UI, and the custom Watch docs
must not be treated as proof that Apple's Workout app can display Setmark's
metric slots, haptics, double-tap actions, or per-set strength logging.

Deferred custom-watch capabilities include:

- Live Setmark cadence / pace target display on Watch.
- Tempo haptic pulses cueing eccentric/bottom/concentric/top phases during
  tempo lifts.
- Raw accelerometer / gyroscope capture during sets. Schema reserves
  `primitive_set_logs.motion_samples_ref` or an equivalent primitive result
  artifact reference for when this lands. When it does, samples can
  be stored on the server as blobs referenced from that field. "Collect
  broadly, analyze in conversation" — the app never interprets raw motion.

## Build order suggestion

1. **Data model** — Define SwiftData models in Swift and SQLAlchemy/Pydantic models in Python. Keep them mirroring each other.
2. **Home server** — Python, FastAPI, SQLite. CRUD endpoints + sync. Dead simple. Claude needs this to push/pull.
3. **App shell** — SwiftData store, sync manager (pull plans, push results), basic workout list view.
4. **Timer engine** — The core feature. Read primitive timing/traversal/repeat cells, drive the right timer UI. This is where most of the app complexity lives and where Eric's UX instincts matter.
5. **Workout execution view** — Show current exercise, prescription, timer, log button. Alternatives accessible via swipe or tap.
6. **Polish** — whatever Eric wants.

Steps 1–2 are shared work (Eric builds, Claude specs and tests the API). Steps 3–6 are pure Eric.
