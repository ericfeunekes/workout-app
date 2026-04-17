# WorkoutDB v2 — Architecture Spec

**Date:** 2026-04-15 (accepted 2026-04-17)
**Status:** Accepted — this is the target architecture. v1 (current Python CLI + YAML + Google Calendar) is legacy-in-transition.

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

---

## Data model

### Core principle: composition with timing

Everything is blocks. A block has a timing mode and contains exercises (or nested blocks). The app's job is to read the timing mode and drive the appropriate timer UI.

### Entities

#### `exercise`

An atomic movement. Minimal metadata — the app doesn't reason about exercises, it just displays them.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Stable across sync. **Claude owns the ID namespace** — Claude pushes `{id, name}` and is responsible for reusing an existing ID when the same exercise recurs across conversations. The server does not canonicalize on name. |
| `name` | String | Display name ("Back Squat", "400m Run") |
| `notes` | String? | Brief cue or form reminder, pushed by Claude |
| `demo_url` | String? | Optional link to a video demo |

No muscle groups, movement patterns, or modality on the exercise itself. That knowledge lives in conversation. If Claude wants the app to display a muscle tag for context, it goes in `notes` or `metadata_json`.

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
| `notes` | String? | |

**Timing modes** (the key feature):

| Mode | `timing_config_json` keys | App behavior |
|---|---|---|
| `straight_sets` | `rest_between_sets_sec`, `rest_between_exercises_sec` | Set counter + rest timer between sets |
| `superset` | `rest_between_rounds_sec` | Cycle through exercises, rest after each round |
| `circuit` | `rest_between_exercises_sec`, `rest_between_rounds_sec` | Same as superset but more exercises |
| `emom` | `interval_sec` (typically 60) | Minute timer, new exercise each minute |
| `amrap` | `time_cap_sec` | Countdown timer, count rounds + reps |
| `for_time` | `time_cap_sec` (optional) | Stopwatch, optional cap |
| `intervals` | `work_sec` OR `work_distance_m`; `rest_sec` OR `rest_distance_m`; optional `target_pace_sec_per_km` | Work/rest alternating timer; distance- or time-based |
| `tabata` | (fixed: work=20, rest=10, rounds=8) | Tabata timer |
| `continuous` | `target_duration_sec?`, `target_distance_m?`, `target_pace_sec_per_km?` | Running clock, optional targets |
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
| `prescription_json` | String | What to do — mode-dependent (see below) |

**`prescription_json` by context:**

- Strength: `{"sets": 3, "reps": 8, "load_kg": 80, "rpe_target": 7}`
- Reps-only: `{"sets": 4, "reps": 12}`
- Time-based: `{"duration_sec": 45}` (e.g. plank hold within a circuit)
- Distance: `{"distance_m": 400, "target_pace_sec_per_km": 270}`
- Rep range: `{"sets": 3, "reps_min": 8, "reps_max": 12, "load_kg": 70}`
- Per-side: `{"sets": 3, "reps": 10, "per_side": true}`
- Percentage-based: `{"sets": 5, "reps": 3, "percent_1rm": 0.85}` — app resolves from user_parameters
- Tempo (eccentric-bottom-concentric-top): `{"sets": 4, "reps": 5, "load_kg": 80, "tempo": "3-0-1-0"}`
- Per-set variation (pyramids, wave loading): `{"sets_detail": [{"reps": 12, "load_kg": 60}, {"reps": 10, "load_kg": 65}, {"reps": 8, "load_kg": 70}, {"reps": 6, "load_kg": 75}]}` — when `sets_detail` is present, flat `sets/reps/load` are ignored
- Drop sets: `{"sets_detail": [{"reps": 10, "load_kg": 20}, {"reps": "amrap", "load_kg": 15, "drop": true}, {"reps": "amrap", "load_kg": 10, "drop": true}]}` — `drop: true` tells the app to collapse the group under one rest timer
- Cluster sets / rest-pause / myo-reps: `{"sets": 4, "reps": 5, "load_kg": 100, "sub_sets": 4, "intra_set_rest_sec": 15}` — each of the 4 top-level sets = 4 sub-sets of 5 reps with 15s rest between sub-sets; `rest_between_sets_sec` still applies between top-level sets

Keeping this as JSON means new prescription shapes don't require schema changes.

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
| `completed_at` | Timestamp? | |
| `tags_json` | String? | JSON array of free-form tags Claude attaches for analysis grouping, e.g. `["hypertrophy_block_2", "week_3", "pull_day", "deload_pending"]`. App ignores; used for querying. |

#### `set_log`

What actually happened. One row per set performed.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `workout_item_id` | UUID | FK |
| `set_index` | Int | 1-based |
| `reps` | Int? | |
| `weight` | Float? | |
| `weight_unit` | Enum | `kg`, `lb` |
| `duration_sec` | Float? | |
| `distance_m` | Float? | |
| `rpe` | Float? | Perceived effort (6–10 scale) |
| `is_warmup` | Bool | |
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
| `key` | String | e.g. `1rm_back_squat_kg`, `resting_hr_bpm`, `5k_pr_sec`, `training_age_years`, `preference_rep_range`, `bodyweight_kg`, `sleep_hours_7d_avg` |
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

**Sync mechanics:**
- App pulls plans on refresh (manual pull-to-refresh or on app open).
- App pushes results when a workout is completed (or on next connectivity if offline).
- UUIDs everywhere — no auto-increment IDs. Makes merge trivial.
- `updated_at` on every record. Last-write-wins within each flow direction.
- Sync state tracked per-entity: `last_synced_at` on device.

**Offline behavior:**
- App works fully offline with whatever plans were last pulled.
- Results queue locally and push on next sync.
- No push notifications needed in v1. App pulls when opened.

### Future: push signal

If we want real-time "new workout available" notifications later, options:
- WebSocket from home server (simple, requires connectivity)
- Apple Push Notification via a thin relay
- Local network Bonjour discovery (if on same WiFi as server)

Not needed for v1. Pull-on-open is fine.

---

## API contract (home server)

### Endpoints

All JSON. Auth: simple bearer token (single-user system, doesn't need more).

**Plans (Claude → Server → App):**

```
POST   /api/workouts                          — Create a workout (with nested blocks, items, alternatives)
PUT    /api/workouts/:id                      — Update a workout
GET    /api/workouts                          — List workouts. Filters: ?status=planned&after=2026-04-15&tag=hypertrophy_block_2
GET    /api/workouts/:id                      — Get full workout with blocks, items, alternatives

POST   /api/exercises                         — Create/upsert exercises (Claude-owned UUIDs)
GET    /api/exercises                         — List all exercises

POST   /api/user-parameters                   — Append user parameter rows (batch). Never updates; always inserts.
GET    /api/user-parameters?latest=true       — Latest-per-key for a user (app uses this to resolve prescriptions)
GET    /api/user-parameters?key=X&since=Y     — Full history for a key since timestamp (Claude uses this for trend analysis)
```

**Results (App → Server):**

```
POST   /api/sync/results       — Push completed workout data (set_logs, status changes)
                                 Body: array of workout results with nested set_logs
                                 Idempotent (UUIDs prevent duplicates)
```

**Sync (App pull):**

```
GET    /api/sync/pull?since=<timestamp>  — Get everything changed since last sync
                                          Returns: workouts, exercises, alternatives,
                                          user_parameters updated after timestamp
```

---

## What Claude pushes vs what the app decides

| Concern | Who decides | How |
|---|---|---|
| Which exercises this week | Claude | Pushes workout plans to server |
| Sets, reps, load targets | Claude | In `prescription_json` |
| Alternatives if something's unavailable | Claude | Pre-computed in `exercise_alternative` |
| User maxes, rep ranges, preferences | Claude | Pushes to `user_parameters` |
| Percentage-based load resolution | App | Reads `percent_1rm` from prescription, resolves against `user_parameters` |
| Timer behavior | App | Reads `timing_mode` + `timing_config_json`, drives UI |
| Logging what happened | App | Writes `set_log` rows |
| Swapping to an alternative mid-workout | User (in app) | Taps alternative, app swaps exercise on the item |
| Adjusting reps/load on the fly | User (in app) | Edits prescription locally, logs actual |
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

## Watch integration (v1 in-scope)

The WatchKit companion app is part of `app/` scope for v1.

**In-scope for v1:**
- Start/stop sets from the watch (writes `started_at`, `completed_at`).
- Haptic buzz on timer transitions (rest end, EMOM tick, interval transitions).
- Record HR into `set_log` via `HKLiveWorkoutBuilder` (`hr_avg_bpm`, `hr_max_bpm`).
- Record cadence silently during runs into `cadence_avg_spm` (no live target display in v1).

**Deferred to v1.1+:**
- Pushing cardio workouts to the Apple Fitness app via `WorkoutKit` (native pace/HR alert UX). v1 runs everything in our app.
- Live cadence / pace target display on Watch.
- Tempo haptic pulses cueing eccentric/bottom/concentric/top phases during tempo lifts. Feasibility unknown; worth spiking when tempo work is actually being programmed. If it works, it fits the existing `tempo` prescription field — no schema change needed.
- Raw accelerometer / gyroscope capture during sets (for bar-speed, bar-path, power-graph analysis). Schema reserves `set_log.motion_samples_ref` for when this lands. v1 doesn't capture; when it does, samples can be stored on the server as blobs referenced from that field. "Collect broadly, analyze in conversation" — the app never interprets raw motion.

## Build order suggestion

1. **Data model** — Define SwiftData models in Swift and SQLAlchemy/Pydantic models in Python. Keep them mirroring each other.
2. **Home server** — Python, FastAPI, SQLite. CRUD endpoints + sync. Dead simple. Claude needs this to push/pull.
3. **App shell** — SwiftData store, sync manager (pull plans, push results), basic workout list view.
4. **Timer engine** — The core feature. Read `timing_mode`, drive the right timer UI. This is where most of the app complexity lives and where Eric's UX instincts matter.
5. **Workout execution view** — Show current exercise, prescription, timer, log button. Alternatives accessible via swipe or tap.
6. **Polish** — whatever Eric wants.

Steps 1–2 are shared work (Eric builds, Claude specs and tests the API). Steps 3–6 are pure Eric.
