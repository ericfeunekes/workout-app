---
title: Prescription vocabulary
status: accepted — legacy projection/reference surface
last_reviewed: 2026-05-17
purpose: Legacy per-timing-mode prescription vocabulary retained for residual bridge/reference work. Active workout authoring uses docs/specs/primitives-data-model.md.
covers:
  - schema/Sources/WorkoutDBSchema/*.swift
  - server/workoutdb_server/api/schemas.py
  - app/ (execution)
---

# Prescription vocabulary

> **Status (2026-05-18):** This is no longer the active workout authoring
> contract. It remains only as a legacy projection/reference surface while
> residual bridge code exists. Active primitive work uses
> `docs/specs/primitives-data-model.md` and its aspect docs.

Claude authors workouts. The server stores them. The app executes them. This doc tells you what Claude must put into a workout so the app knows what to do.

Scope:
- **RIR scale** and **autoregulation** — how the app adapts load mid-session.
- **Per-mode prescriptions** — what keys each of the 12 timing modes reads.
- **Parametric shapes** — reusable shapes (percent_1rm, tempo, drop, cluster, unilateral/per-implement load conventions, ranges, per-set variation) that layer onto any mode.

See also:
- `docs/specs/v2-architecture.md` for the entity schema.
- `docs/workout-taxonomy.md` for the target block archetypes and domain lenses.
- `docs/workout-execution-requirements.md` for target athlete-facing timer, transition, logging, and summary behavior.
- `docs/watch-metrics.md` for the target watchOS slot contract, metric windows, sensor fallbacks, and phone/watch lifecycle.
- `docs/sync.md` for how prescriptions reach the app and what wins on conflict.
- `docs/design/RULES.md` (in the design bundle) for the underlying app-behavior rules.

---

## Authoring shape: sparse overrides on library defaults

Claude does not have to re-send every prescription field on every item. Each
`Exercise` row carries two optional library defaults — `default_prescription_json`
and `default_alternatives_json` — that the server merges into whatever the
client sends when a workout is POSTed or PUT.

**Rules of the merge** (see `docs/decisions/ADR-2026-04-18-smart-defaults.md`):

- Top-level scalar keys on the item win; library values fill in gaps.
- The `autoreg` sub-object merges field-by-field; item wins on conflict. When
  the item omits `autoreg`, the library's `autoreg` block is used wholesale.
- Alternatives: if the item sends any, they replace the library defaults
  wholesale (no element-level merge). If the item omits alternatives and the
  library has defaults, the library list is materialized into stored rows.

**Snapshot behavior.** The merge runs once, at ingest. The resolved form is
stored in `workout_item.prescription_json` and is immutable thereafter — if
Claude later rewrites the exercise's `default_prescription_json`, already-
stored workouts keep their original resolved shape. The client's raw sparse
payload is preserved in `workout_item.prescription_json_raw` whenever the
merge changed something (null when the client sent a fully-resolved form).

A typical bench item drops from ~30 lines to three:

```jsonc
// Exercise.default_prescription_json (library)
{ "target_rir": 2,
  "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
               "undershoot_at": 2, "undershoot_step_kg": 2.5,
               "apply_to": "remaining" } }

// workout_item.prescription_json (what Claude sends)
{ "sets": 4, "reps": 5, "load_kg": 102.5 }

// workout_item.prescription_json (what the server stores)
{ "sets": 4, "reps": 5, "load_kg": 102.5,
  "target_rir": 2,
  "autoreg": { ... } }
```

Because the merge is a no-op on items that already carry every field, Claude's
existing fully-shaped workouts continue to work without change. There is no
feature flag and no deprecation period — adopt defaults as you go.

---

## Conventions

- **snake_case keys everywhere on the wire.** The design bundle's JSX uses camelCase (`targetRir`, `overshootAt`); our JSON is snake_case (`target_rir`, `overshoot_at`). The app is the translation boundary — Swift Codable keys map to snake_case via `CodingKeys`. When authoring or reviewing, assume snake_case.
- **Units.** Every prescription that carries a load also declares `weight_unit ∈ {"kg", "lb"}`. The key `load_kg` keeps its historical name even when the value is pounds — the *unit* is the source of truth, the field name is a spelling compromise (ADR R2.10). Default is `"lb"` when the key is omitted: Eric trains in pounds, and every prescription that makes it to the app must resolve to a stamp-able unit. The server's `prescription_merge` fills `weight_unit: "lb"` at ingest if neither the library default nor the item authored one, so the app never sees a unit-less strength prescription. On the log side, `set_log` carries `(weight, weight_unit)` — the SetLog's `weight_unit` is stamped from the matching `SetPlan.unit`. No unit conversion happens on the wire; the app renders whatever unit the prescription declared.
- **`rounds` default.** A block with `rounds: null` or omitted means one round. `rounds: 0` and negatives are invalid.
- **Timing config is strict.** The app reads only the keys documented per mode. Extraneous keys in `timing_config_json` are ignored — no error, but Claude should avoid littering.

## Work targets

Every executable item has a primary work target. Reps, duration, and distance are the same concept at the authoring layer:

```jsonc
{ "target": { "kind": "reps", "value": 12, "unit": "reps" } }
{ "target": { "kind": "duration", "value": 2, "unit": "min" } }
{ "target": { "kind": "distance", "value": 200, "unit": "ft" } }
```

Use this shape whenever the item is not ordinary reps, or whenever the display unit matters. The app keeps the authored unit for the active screen (`2 min`, `200 ft`) and logs canonical analytics fields:

| Target kind | Display units | Canonical log field |
|---|---|---|
| `reps` | `reps` | `set_log.reps` |
| `duration` | `sec`, `min` | `set_log.duration_sec` |
| `distance` | `m`, `km`, `ft`, `yd`, `mi` | `set_log.distance_m` |

Loaded duration/distance work carries load beside the target:

```jsonc
{
  "target": { "kind": "distance", "value": 200, "unit": "ft" },
  "load_kg": 53,
  "weight_unit": "lb"
}
```

That represents a 200 ft loaded carry at 53 lb. The active face shows the distance as the primary work target and the load as the secondary load target. The pushed log has `reps = null`, `distance_m = 60.96`, `weight = 53`, and `weight_unit = "lb"`.

Flat scalar authoring (`reps`, `duration_sec`, `distance_m`, plus `duration_unit` / `distance_unit` when needed) is still parsed, but new workout generation should prefer `target.kind/value/unit` because it prevents duration and distance stations from collapsing into fake `0 reps` rows.

## Block intent

`block.intent` is the freeform qualitative purpose of a block. It explains why
the block exists: heavy strength, hypertrophy volume, tempo pacing, skill
practice, recovery, or another human-readable training intent.

Authoring rules:

- New Claude-authored blocks should populate `block.intent`.
- The server accepts `null` indefinitely for old workouts, imports, and cases
  where Claude deliberately punts.
- The app may display intent where it helps orientation, but it must render no
  placeholder when intent is null.
- Intent is not an enum and not app-side classification. Structured goals,
  targets, timers, and autoreg rules stay in `timing_config_json` and
  `workout_item.prescription_json`.

## Invariants

1. **The app is a renderer + logger.** It does not compute prescriptions. Everything downstream of "read `prescription_json`" is display + timing + logging.
2. **`prescription_json` is opaque by convention.** The server does not validate its shape — Claude and the app agree on a shape per timing mode. New shapes don't require schema migrations. Shape drift between app and Claude is caught at the first missing or surprising key at execution time; add shapes here before relying on them.
3. **Timing and prescription are separable.** `block.timing_mode` + `block.timing_config_json` tell the app *how to drive time*. `workout_item.prescription_json` tells the app *what to do inside that time*. A straight-sets block times rest; a superset block alternates items; the prescription in each case is what the item itself looks like.
4. **One item per exercise.** A single block has N `workout_item`s. Straight-sets blocks have N=1. Supersets/circuits have N≥2. Conditioning modes (amrap, for_time, etc.) have as many items as the WOD has exercises.
5. **Autoreg is advisory and session-scoped.** The app applies it to remaining sets and can be "held" by the user for the rest of the session. Past-set edits never retrigger it. See `app/README.md` § "Autoregulation" for UX semantics.
6. **Current vs target behavior must be explicit.** `docs/features/*.md` describe target feature behavior and carry `Current gaps` for anything unimplemented or unproven. If this file names a target shape before the app supports it, mark it as a current gap rather than implying it is shipped.

---

## RIR (Reps In Reserve)

**Scale:** integer `0–5`. Lower = closer to failure.

| RIR | Meaning |
|---|---|
| `0` | Failure. Could not have done another rep. |
| `1` | Grinder. One more rep possible, but it would have been ugly. |
| `2` | Hard. Two more reps possible. |
| `3` | Moderate. Three more reps possible. |
| `4` | Easy. Four more reps possible. |
| `5` | Very easy. Warm-up effort. |

**Not RPE.** The server's `set_log.rir` field is `Int?`, range `0–5`. Do not introduce RPE 6–10 anywhere in user-facing copy, prescriptions, or analysis. If Claude wants to talk about effort out of conversation, "RIR 2" is the language.

**Half-steps:** not supported in v1. If that ever bites, revisit.

**RIR is logged, not prescribed-for-the-log.** The prescription carries a `target_rir` (what Claude wants); the set log carries `rir` (what actually happened). They don't have to match — the difference is the signal autoreg reads.

**Scope:** RIR is primarily for strength, hypertrophy, and load-bearing skill work. Author `target_rir` on exercises/sets where proximity to failure is meaningful. Do not force RIR onto metcon, running, mobility, or sensor-scored work unless the author intentionally wants that signal.

---

## Autoregulation

Autoreg is a client-side rule that nudges load on remaining sets when the user overshoots or undershoots the target RIR. Claude authors the rules per item. The app applies them.

### Configuration shape

Attached to a `workout_item.prescription_json`:

```jsonc
{
  "target_rir": 2,
  "autoreg": {
    "overshoot_at": 2,
    "overshoot_step_kg": 2.5,
    "undershoot_at": 2,
    "undershoot_step_kg": 2.5,
    "apply_to": "remaining"
  }
}
```

| Key | Type | Meaning |
|---|---|---|
| `target_rir` | Int, 0–5 | The RIR Claude wants the user to hit on this exercise. |
| `autoreg.overshoot_at` | Int ≥1 | If `set.rir >= target_rir + overshoot_at`, load was too light. Default `2`. |
| `autoreg.overshoot_step_kg` | Float | How much to bump load on remaining sets when overshoot fires. Default `2.5`. |
| `autoreg.undershoot_at` | Int ≥1 | If `prescribed_reps − actual_reps >= undershoot_at`, load was too heavy. Default `2`. |
| `autoreg.undershoot_step_kg` | Float | How much to drop load on remaining sets when undershoot fires. Default `2.5`. |
| `autoreg.apply_to` | Enum | `"remaining"` only in v1. Reserved: `"next"`, `"all-future"`. |

Omit the `autoreg` subobject on items that shouldn't autoadjust (warm-ups, conditioning inside a strength block, anything where Claude explicitly wants the prescription held constant).

### Trigger rules

**Overshoot** (load too light): `set.rir >= target_rir + autoreg.overshoot_at`
- Example: `target_rir=2`, `overshoot_at=2`. User logs RIR 4 → fires. App proposes `next_load = current_load + overshoot_step_kg`, bumps remaining sets.

**Undershoot** (load too heavy): either is sufficient:
- `(prescribed_reps − actual_reps) >= autoreg.undershoot_at`
- `set.rir == 0 && target_rir > 0` (hit failure when target wasn't zero)
- App proposes `next_load = current_load − undershoot_step_kg`, drops remaining sets.

**Comparison is against the set's *current* prescribed reps/load, not the item's original values.** If autoreg already bumped a set, the next set compares against the bumped prescription. This avoids cascading adjustments from each set.

### Hold scope

If the user "Undos" an autoreg proposal on the rest screen, the app sets `autoregHeld = true` on the item for the rest of the session. No further autoreg proposals fire for that item in that session. The hold does **not** persist across workouts — next session, autoreg is live again. Claude can always change the prescription or the autoreg config on the next push.

**Undo semantics:** Undo reverts the autoreg's effect on **not-yet-touched remaining sets**. If the user manually edited a remaining set after the autoreg bumped it, the manual value wins and is preserved by the Undo (the hold applies forward; nothing retroactive).

### Autoreg + manual edit

Manual edits to pending sets always win over autoreg.

- If autoreg bumped set 3 (`adjust="up"`) and the user then manually edits set 3's load, the manual value overwrites. `adjust` becomes `"manual"`.
- Autoreg still applies to sets 4+ unless held.
- The per-set `adjust` precedence: `"manual"` > `"up"` / `"down"`. Once an adjust is `"manual"`, subsequent autoreg passes do not overwrite that set.

### Edits don't retrigger

Editing a past set (from the rest ledger, completion screen, or history detail) is **corrective** — it changes the record but does not run autoreg again. The per-set `adjust` field is preserved; manual edits mark it `"manual"` if it wasn't already `"up"` or `"down"`.

**Boundary rule:** a set counts as "past" once it has `done=true`. Corrections to a set before it's been logged (while it's still the pending target) mark it `"manual"` and do not retrigger autoreg from earlier sets.

### RIR nullable in set_log

`set_log.rir` is nullable. The app does not force an RIR pick — the user can tap "skip" on the RIR picker and the set logs with `rir=null`.

Autoreg behavior when RIR is null:
- **Overshoot cannot fire** (no RIR value to compare).
- **Undershoot can still fire** on the reps-missed condition.
- **Hit-failure detection** (`rir==0`) obviously can't fire.

In practice, skipping RIR turns off overshoot detection for that set but leaves undershoot detection intact.

### When autoreg applies

| Timing mode | Autoreg applies? |
|---|---|
| `straight_sets` | Yes; current implementation and target behavior are aligned. |
| `superset` | Target behavior: yes when authored on strength-like stations, applying to remaining rounds. Current implementation gap: round-robin autoreg is not fully supported yet. |
| `circuit` | Target behavior: yes only when authored on strength-like stations. Current implementation gap: round-robin autoreg is not fully supported yet. |
| `emom` | No (conditioning) |
| `amrap` | No |
| `for_time` | No |
| `intervals` | No |
| `tabata` | No |
| `continuous` | No |
| `accumulate` | No by default; reps/duration accumulation is logged as chunks, not autoregulated set progression. |
| `custom` | Avoid by default. If a stricter load-bearing archetype fits, use that instead. |
| `rest` | N/A |

Rule of thumb: autoreg is for load-bearing strength work where the user has a number of remaining sets that a bump/drop can still reach.

### Load step and equipment

The `overshoot_step_kg` / `undershoot_step_kg` values encode the equipment's granularity. The *numeric value* is always in the SetPlan's unit — the `_kg` suffix on the key is historical (ADR R2.10). Claude picks the step per block based on what's realistic at the gym:

| Equipment | Pounds (`weight_unit: "lb"`) | Kilograms (`weight_unit: "kg"`) |
|---|---|---|
| Barbell, full plates (default) | `5.0` | `2.5` |
| Dumbbells (pairs) | `5.0` | `2.5` |
| Dip belt / loaded bodyweight | `5.0` | `2.5` |
| Machine stack | whatever the stack step is | whatever the stack step is |
| Fractional plates available | `1.25` | `1.0` / `1.25` |

**Defaults when the parser fills them in:** `5.0` for `"lb"`, `1.25` for `"kg"`. These are the smallest reasonable loadable increments (one pair of 2.5 lb plates for pounds, one pair of 0.625 kg fractional plates for kilograms). Explicit authoring always wins — when Claude provides `overshoot_step_kg`, the parser uses that value verbatim.

There is no per-exercise default in the schema — the authoritative answer lives in the prescription. Claude sets it with equipment knowledge that doesn't fit in a database column.

---

## Per-timing-mode prescription shapes

Each section below is the authoring contract for that mode: what `timing_config_json` on the block carries, what `prescription_json` on each item carries, and what the app displays and logs.

### `straight_sets`

Canonical strength: N sets of one exercise with a common rest between sets.

**Block `timing_config_json`:**
```jsonc
{ "rest_between_sets_sec": 180,
  "rest_between_exercises_sec": 180 }
```

Both fields are independently optional. When only one is authored, the missing field defaults to the value of the present one (authoring just `rest_between_sets_sec` is the common case for a single-exercise block). When neither is authored, both default to `0` and no rest screen is shown. Authoring both is still preferred when the between-exercises value should genuinely exceed the between-sets value — e.g. several heavy singles followed by a back-off exercise where Claude wants a longer transition.

**Item `prescription_json`:**
```jsonc
{ "sets": 4,
  "reps": 5,
  "load_kg": 102.5,
  "target_rir": 2,
  "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
               "undershoot_at": 2, "undershoot_step_kg": 2.5,
               "apply_to": "remaining" } }
```

Active face shows load × reps × set counter. Rest screen shows ring countdown + autoreg proposal if fired. Logs per set: `reps`, `weight`, `rir`.

### `superset`

Two or more exercises performed back-to-back with one shared rest.

**Block `timing_config_json`:**
```jsonc
{ "rest_between_rounds_sec": 120,
  "logging_mode": "batch_at_round_rest" } // optional; this is the default
```

**Block:** carries `rounds` (total times through the pair/group).

**Items:** one per exercise. Each has its own prescription, including its own `target_rir` and (optionally) `autoreg`.

```jsonc
{ "reps": 10, "load_kg": 60, "target_rir": 2, "autoreg": { ... } }
```

Active face shows NOW (current exercise) + THEN (next in the superset, muted). User does not log mid-round — `next station` advances through the round, and logging happens on the shared rest screen for all items of that round. `finish round` on the final round commits before completion because there is no shared rest screen. Logs per round per item: `reps`, `weight`, `rir`.

### `circuit`

N exercises in a loop, possibly with a short between-exercise rest and a longer between-rounds rest.

**Block `timing_config_json`:**
```jsonc
{ "rest_between_exercises_sec": 0,
  "rest_between_rounds_sec": 120,
  "logging_mode": "station_by_station" } // optional; this is the default
```

**Block:** carries `rounds`.

**Items:** one per exercise.

```jsonc
{ "reps": 12, "load_kg": 20 }             // reps-based station
{ "duration_sec": 45 }                    // time-based station (plank, row)
{ "reps": "amrap" }                       // as many as possible at this station
```

Active face shows a numbered list of stations with the current one highlighted. Logs per round per station: `reps` (or `duration_sec`), optionally `rir` if load-based.

### `emom` (Every Minute on the Minute)

Perform the prescribed reps within each minute; rest the remainder of the minute; auto-advance.

**Block `timing_config_json`:**
```jsonc
{ "interval_sec": 60,
  "total_minutes": 12 }
```

**Items:** one or more exercises. If multiple, they rotate per minute in the listed order.

```jsonc
{ "reps": 10, "load_kg": 95 }             // 10 Power Cleans @ 95 kg each minute
```

Active face shows interval countdown + warn tone under ~15s left. Strength-style EMOM work still requires `Set Start` before `Done` can log the set, even though the interval clock is already running. If the scheduled boundary passes before the user logs, the app advances to the next interval without creating a fake completed `0 reps` set; a first-class missed/partial row is a future data-model addition. Logs per completed round: `reps`, `weight`, `completed_at` (used to derive "finish time" within the minute). No autoreg.

### `amrap` (As Many Rounds As Possible)

Fixed time cap; rotate through a defined circuit and record completed stations plus any partial station at the buzzer.

**Block `timing_config_json`:**
```jsonc
{ "time_cap_sec": 900 }
```

**Items:** the round definition — list of exercise × reps tuples.

```jsonc
{ "reps": 10 }   // item for Pull-ups
{ "reps": 15 }   // item for Push-ups
{ "reps": 20 }   // item for Air Squats
```

Active face shows the cap timer, current station, round count, and a single `next` action. Each `next` logs the current station as completed and advances to the next station in the round. At the buzzer, the app presents a partial picker: completed prior stations are checkmarked, the current station accepts extra reps, and later stations are locked. Logs are normal station-level `set_log` rows — one per completed station tap, plus one for the partial station if any. No autoreg.

### `for_time`

Complete a prescribed body of work as fast as possible; log the time it took.

**Block `timing_config_json`:**
```jsonc
{ "time_cap_sec": 1200 }    // optional cap
```

**Block:** can use `rounds_rep_scheme` for chippers (e.g., 21-15-9).

```jsonc
{
  "timing_mode": "for_time",
  "rounds": 3,
  "rounds_rep_scheme": [21, 15, 9],
  "workout_items": [ /* thruster, pull-up — rep counts come from the scheme */ ]
}
```

**Items:** exercise refs; when `rounds_rep_scheme` is present, the rep count per round is read from the scheme. Otherwise each item carries `reps`.

Active face shows elapsed time + grouped rep×exercise list with the current group highlighted. Logs: `total_duration_sec`, per-group completion (no per-rep logging). No autoreg.

### `intervals`

Alternating work/rest phases, auto-advance, usually cardio.

**Block `timing_config_json`:**
```jsonc
{ "work_sec": 30, "rest_sec": 30, "interval_count": 10,
  "target_pace_sec_per_km": 270 }
```

Or distance-based:
```jsonc
{ "work_distance_m": 400, "rest_distance_m": 200, "interval_count": 10,
  "target_pace_sec_per_km": 270 }
```

**Items:** usually a single cardio exercise (run, bike, row).

Active face shows a countdown for time-based work/rest phases and elapsed time for distance-based phases until GPS/sensor detection exists. Target pace / HR zone is guidance, not completion logic. Logs per interval: `duration_sec`, `distance_m`, `hr_avg_bpm`, `cadence_avg_spm` where available. No autoreg.

### `tabata`

Fixed 8 rounds of 20s work / 10s rest. Configuration locked.

**Block `timing_config_json`:**
```jsonc
{}    // no keys required; 20/10/8 is the definition
```

**Items:** one exercise.

Active face shows 8 pips + current phase timer. Haptic on every transition. Logs per round: `reps`, `hr_avg_bpm`. No autoreg.

**Execution scope:** Tabata supports both strength-shaped and cardio-shaped work. Strength-shaped rows keep the reps path so the user's reps count survives; if the work window expires before the user logs, the app enters rest without writing a fake `0 reps` completion. Loadless/cardio rows render a 20s work window and auto-log `duration_sec` because duration is clock-detectable.

### `continuous`

One long piece at a target zone/pace. Z2 ride, easy run, row.

**Block `timing_config_json`:**
```jsonc
{ "target_duration_sec": 3600,
  "target_distance_m": null,
  "target_pace_sec_per_km": 360,
  "target_hr_zone": 2 }
```

**Items:** one exercise.

Active face shows elapsed + avg HR + zone + distance. Duration targets show a `TARGET` countdown; at zero, standalone efforts offer `complete` or `continue`, while composed detectable efforts route into the next block. Distance targets stay manual until sensor-derived distance exists. Logs once: `duration_sec`, `distance_m`, `hr_avg_bpm`, `hr_max_bpm`, `cadence_avg_spm`. No autoreg.

### `accumulate`

Free-rest bouts toward one accumulated target. Examples: `100 push-ups`, `2:00 total dead hang`, or `100 ft loaded carry`.

**Block `timing_config_json`:**
```jsonc
{ "target_duration_sec": null,
  "target_reps": 100,
  "target_distance_m": null }
```

Exactly one target key should be authored. Priority if multiple are present is duration, then reps, then distance.

**Items:** one exercise. The item prescription can carry the per-bout default, such as `{ "reps": 25 }` or `{ "load_kg": 24, "weight_unit": "kg" }`.

Active face shows accumulated progress (`25 / 100`, `1:17 / 2:00`, `50 m / 100 m`). The user taps `set start` before each bout; `break` / `log chunk` records the chunk and returns to a ready state for free rest. The app completes the block once the accumulated target is met or exceeded, routing to the next block when the workout is composed. Distance accumulation is representable, but without sensor/manual distance entry UI it currently needs a richer metric-entry sheet to be useful for carries.

### `custom`

Catch-all for mixed-segment sessions that do not fit a stricter mode. Prefer `intervals`, `continuous`, `for_time`, `amrap`, or composed blocks when they can express the workout. For example, threshold repeats should usually be authored as intervals or composed continuous blocks, not `custom`, unless the structure genuinely exceeds the stricter modes.

**Block `timing_config_json`:**
```jsonc
{ "segments": [
    { "type": "work", "duration_sec": 300, "label": "Z4 threshold", "target_hr_zone": 4 },
    { "type": "rest", "duration_sec": 120, "label": "easy" },
    { "type": "work", "duration_sec": 300, "label": "Z4 threshold", "target_hr_zone": 4 },
    { "type": "rest", "duration_sec": 120, "label": "easy" },
    { "type": "work", "duration_sec": 300, "label": "Z4 threshold", "target_hr_zone": 4 }
  ] }
```

**Items:** depends — often one cardio exercise; for a mixed strength+cardio piece, multiple items with segment-level bindings (future; not in v1).

Active face advances through segments on user tap or timer, depending on segment `type`. Logs per segment: `duration_sec`, `hr_avg_bpm`, optional `reps`. No autoreg by default; add explicitly per item if a segment is load-based.

### `rest` (standalone rest block)

A prescribed rest window between workout blocks — e.g., 3 minutes between an upper-body block and a lower-body block in a long session.

**Block `timing_config_json`:**
```jsonc
{ "duration_sec": 180 }
```

**Items:** none. A rest block is an item-less block.

Active face shows a big countdown + preview of the next block. "Start early" advances immediately. Logs: the actual rest duration taken (derivable from `started_at` / `completed_at`).

**Distinction from inter-set rest:** inter-set rest is carried by the *surrounding* block's `timing_config_json` (e.g., `rest_between_sets_sec` on a `straight_sets` block). A standalone `rest` block is something Claude schedules at the workout level because the user should explicitly sit down and wait.

---

## Parametric prescription shapes

Shapes that layer onto any mode with the right item keys.

### Percentage-based load

```jsonc
{ "sets": 5, "reps": 3, "percent_1rm": 0.85, "target_rir": 1 }
```

App resolves the load by reading the latest `one_rep_max_<exercise_id>_kg` user_parameter and multiplying. If the parameter is missing, the current execution UI treats the set as loadless (`BW`) and leaves manual load entry blank; the entered value is logged on the set.

### Rep range

```jsonc
{ "sets": 3, "reps_min": 8, "reps_max": 12, "load_kg": 70, "target_rir": 1 }
```

App displays "8–12 reps @ 70 kg". Autoreg undershoot triggers on `actual < reps_min − undershoot_at`; overshoot triggers as usual on RIR.

### Unilateral / per-implement load work

```jsonc
{ "sets": 3, "reps": 10, "load_kg": 20 }
```

Author unilateral work as separate exercise/workout items when left and right
actuals matter, for example `DB Row (Left)` and `DB Row (Right)`. The app then
logs each side as its own explicit work item instead of hiding asymmetry inside
one ambiguous set row.

**`load_kg` is per-implement** — for unilateral work the number is what each
hand, foot, dumbbell, or side-specific implement carries, not the sum across
sides. A 20 kg dumbbell single-arm row means `load_kg: 20` for that side; total
work across left and right may be 40 kg, but each authored item carries the
per-implement value. Logs `reps` as the performed count for that authored item, not a
doubled aggregate.

`per_side: true` is still accepted as a legacy/display hint and may appear in
fixtures or alternative overrides. It does not make one authored item expand
into left/right logs. New Claude-authored work should prefer separate
left/right exercise items when side-specific actuals matter.

`set_log.side` exists as a shipped/reserved round-trip field with values
`left`, `right`, and `bilateral`; `bilateral` is the default for normal
both-sides-together work. It is not the active authoring model, and analytics
must not infer left/right grouping from it unless a later taxonomy phase
explicitly promotes the field.

See `docs/modifier-equipment.md` for the broader modifier/equipment vocabulary:
when to use separate exercise identity, notes/display metadata,
`prescription_json`, alternatives, or tags.

### Bodyweight and weighted bodyweight

Load convention:

- **Bodyweight only** (unloaded push-up, unloaded dip, air squat): omit `load_kg` entirely. App displays "BW".
- **Weighted bodyweight** (weighted dip, weighted pull-up): `load_kg` is the *added* weight. A dip with +20 kg is `{"load_kg": 20}`. App displays "BW + 20 kg".
- **External load** (barbell, dumbbell, machine): `load_kg` is the total implement load as usual.

`load_kg` is never the user's body weight itself. Body weight lives in `user_parameters` under key `bodyweight_kg`.

If a future shape needs "percent of body weight" (e.g. a row at 0.5 × BW), use a dedicated key rather than overloading `load_kg`. Not in v1.

### Tempo

```jsonc
{ "sets": 4, "reps": 5, "load_kg": 80, "tempo": "3-0-1-0" }
```

Four-digit tempo (eccentric-bottom-concentric-top). App displays the tempo string; watch haptics cueing phases are a v1.1+ feature. Logs unchanged.

### Per-set variation (pyramid / wave)

```jsonc
{ "sets_detail": [
    { "reps": 12, "load_kg": 60 },
    { "reps": 10, "load_kg": 65 },
    { "reps": 8,  "load_kg": 70 },
    { "reps": 6,  "load_kg": 75 }
  ],
  "target_rir": 2,
  "autoreg": { /* applies per set's prescribed load */ } }
```

When `sets_detail` is present, flat `sets/reps/load` keys are ignored. Each element is one set with its own load and reps. Autoreg (if present) adjusts remaining sets from the point of trigger forward, respecting each set's original prescribed values.

### Drop sets

```jsonc
{ "sets_detail": [
    { "reps": 10, "load_kg": 20 },
    { "reps": "amrap", "load_kg": 15, "drop": true },
    { "reps": "amrap", "load_kg": 10, "drop": true }
  ] }
```

`drop: true` tells the app to collapse this set under the previous set's rest — the drop happens immediately, no rest. Autoreg is typically omitted on drop-set items.

### Cluster sets / rest-pause / myo-reps

```jsonc
{ "sets": 4, "reps": 5, "load_kg": 100,
  "sub_sets": 4, "intra_set_rest_sec": 15,
  "target_rir": 1,
  "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 5,
               "undershoot_at": 2, "undershoot_step_kg": 5,
               "apply_to": "remaining" } }
```

Each top-level set is 4 sub-sets of 5 reps with 15s between sub-sets. The block's `rest_between_sets_sec` applies between top-level sets only. Intended logging shape: one `set_log` per top-level set, with total reps summed and `duration_sec` covering the cluster.

When a cluster appears as a station inside a round-based block such as a superset or circuit, `sets` may be omitted; the block's `rounds` supplies the top-level set count. The station still logs one top-level row per round with `reps * sub_sets` total reps.

Autoreg, when authored, fires only after the top-level composed set is logged. Sub-sets never trigger autoreg. RIR is the athlete's final-effort RIR for the composed set, and undershoot compares actual total reps against `reps * sub_sets`.

**Current app status:** parsing, Today summary rendering, live slot execution, intra-set rest timing, top-level duration logging, and top-level cluster autoreg are supported for `straight_sets`; cluster stations also execute with slots inside round-based superset/circuit blocks. Expanded per-slot actual editing remains a later enhancement.

### AMRAP token

```jsonc
{ "reps": "amrap" }
```

The literal string `"amrap"` in a `reps` field means "as many as possible at this station / set." The app switches the log input to an open numeric entry. Valid in `circuit` stations, `drop` set terminals, and similar patterns. Distinct from the `amrap` timing mode, which is time-capped rounds.

**Autoreg on `amrap` sets:** reps-based undershoot cannot fire (no rep target to compare). RIR-based overshoot / failure still applies if the set carries `target_rir`.

### Warm-ups

Mark warm-up sets so the app excludes them from autoreg triggers and from history aggregates.

Per-set flag inside `sets_detail`:
```jsonc
{ "sets_detail": [
    { "reps": 8, "load_kg": 40, "warmup": true },
    { "reps": 5, "load_kg": 60, "warmup": true },
    { "reps": 5, "load_kg": 80, "warmup": true },
    { "reps": 5, "load_kg": 102.5 }
  ],
  "target_rir": 2,
  "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
               "undershoot_at": 2, "undershoot_step_kg": 2.5,
               "apply_to": "remaining" } }
```

Whole-item flag for a separate warm-up item:
```jsonc
{ "warmup": true, "sets": 3, "reps": 5, "load_kg": 40 }
```

`warmup: true` sets `set_log.is_warmup = true` on log write. Warm-up sets:
- Are skipped by autoreg triggers (don't cause overshoot/undershoot).
- Don't contribute to history top-set or avg-RIR displays.
- Still count for the session's total time.

### Alternative prescription (overrides)

`exercise_alternative.parameter_overrides_json` carries a shallow override onto the item's `prescription_json` when the user swaps. Any prescription key can be overridden.

```jsonc
// Original item: 4 × 5 barbell bench @ 102.5 kg
// Alternative: dumbbell bench press — higher reps, lower per-implement load
{
  "exercise_id": "<dumbbell-bench-uuid>",
  "reason": "bench platform taken",
  "parameter_overrides_json": {
    "sets": 3, "reps": 10, "load_kg": 32.5,
    "target_rir": 2
  }
}
```

On swap, the app merges the override onto the original prescription (override keys win). `autoreg` can be overridden too — if the alternative wants different steps (machine → stack-based), set `autoreg` in the override.

**`sets` override scope (R2.8).** The `sets` key is honored only for blocks whose advancement is **set-major** — `straight_sets`, `custom`, `intervals`, `continuous`. Round-robin blocks (`superset`, `circuit`, `amrap`, `emom`, `tabata`, `for_time`) replicate a single `rounds` count across every item, so rewriting one item's row count would either skew the cursor walk or silently collapse the whole block. `accumulate` also drops `sets` because target completion, not row count, owns the exit. On those blocks the app **drops** the `sets` portion of the override and applies the rest of the keys (`reps`, `load_kg`, `weight_unit`, `target_rir`, `autoreg`) unchanged. If Claude needs to change the round count for a round-robin block, edit the block's `rounds` in the next planned workout rather than smuggling it through an alternative's `sets` override. The drop is surfaced via the `execution.swap_sets_override_rejected` telemetry event so authoring drift is visible.

**Unit inheritance on overrides (R2.10).** Alternative overrides treat `weight_unit` as fully optional. When the override carries `weight_unit`, it wins; when it omits the key, the override's `load_kg` inherits the parent SetPlan's unit. This matches the real-world case: swapping a barbell bench (authored in lb) for a dumbbell bench press usually keeps the same unit. Claude should only declare `weight_unit` on an override when the alternative is fundamentally different equipment (e.g., a machine with a kg stack substituting for a pound-authored free-weight lift).

If the alternative has a fundamentally different shape (e.g., swap a load-based strength item for a bodyweight-reps item), the override replaces the whole strength prescription. For moves that aren't well-modeled as a swap (e.g., metcon ↔ strength), Claude should push a separate alternative on a different `workout_item` rather than force the shape onto one.

---

## Worked examples

### Push day — straight sets with autoreg

```jsonc
{
  "name": "Push A",
  "blocks": [
    {
      "name": "Main lift",
      "timing_mode": "straight_sets",
      "timing_config_json": { "rest_between_sets_sec": 180, "rest_between_exercises_sec": 180 },
      "rounds": 1,
      "workout_items": [
        {
          "exercise_id": "<bench-uuid>",
          "prescription_json": {
            "sets": 4, "reps": 5, "load_kg": 102.5,
            "target_rir": 2,
            "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
                         "undershoot_at": 2, "undershoot_step_kg": 2.5,
                         "apply_to": "remaining" }
          }
        }
      ]
    },
    {
      "name": "Accessories",
      "timing_mode": "straight_sets",
      "timing_config_json": { "rest_between_sets_sec": 120, "rest_between_exercises_sec": 120 },
      "rounds": 1,
      "workout_items": [
        { "exercise_id": "<row-uuid>", "prescription_json": {
            "sets": 3, "reps": 8, "load_kg": 80, "target_rir": 1,
            "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
                         "undershoot_at": 2, "undershoot_step_kg": 2.5,
                         "apply_to": "remaining" } } },
        { "exercise_id": "<ohp-uuid>", "prescription_json": {
            "sets": 3, "reps": 6, "load_kg": 55, "target_rir": 2,
            "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
                         "undershoot_at": 2, "undershoot_step_kg": 2.5,
                         "apply_to": "remaining" } } }
      ]
    }
  ]
}
```

### Fran — for_time with a rep scheme

```jsonc
{
  "name": "Fran",
  "blocks": [
    {
      "name": "Metcon",
      "timing_mode": "for_time",
      "timing_config_json": { "time_cap_sec": 600 },
      "rounds": 3,
      "rounds_rep_scheme": [21, 15, 9],
      "workout_items": [
        { "exercise_id": "<thruster-uuid>",
          "prescription_json": { "load_kg": 43 } },
        { "exercise_id": "<pullup-uuid>",
          "prescription_json": {} }
      ]
    }
  ]
}
```

### 10×400m at 5K pace

```jsonc
{
  "name": "10 × 400m",
  "blocks": [
    {
      "name": "Intervals",
      "timing_mode": "intervals",
      "timing_config_json": {
        "work_distance_m": 400,
        "rest_distance_m": 200,
        "interval_count": 10,
        "target_pace_sec_per_km": 270
      },
      "workout_items": [
        { "exercise_id": "<run-uuid>", "prescription_json": {} }
      ]
    }
  ]
}
```

### Pyramid squats

```jsonc
{
  "workout_items": [{
    "exercise_id": "<squat-uuid>",
    "prescription_json": {
      "sets_detail": [
        { "reps": 12, "load_kg": 60 },
        { "reps": 10, "load_kg": 70 },
        { "reps": 8,  "load_kg": 80 },
        { "reps": 6,  "load_kg": 90 }
      ],
      "target_rir": 1,
      "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5,
                   "undershoot_at": 2, "undershoot_step_kg": 2.5,
                   "apply_to": "remaining" }
    }
  }]
}
```

---

## Authoring checklist for Claude

Before pushing a workout to the server, confirm:

- [ ] Every block has a `timing_mode` and its required `timing_config_json` keys.
- [ ] Every `workout_item` has a `prescription_json` (possibly `{}` for trivial cases).
- [ ] Strength items carry `target_rir` + `autoreg`, or explicitly omit them when load should stay fixed.
- [ ] Load step (`overshoot_step_kg` / `undershoot_step_kg`) matches the equipment available.
- [ ] Percent-based prescriptions reference user_parameter keys that actually exist for this user.
- [ ] Rep schemes (chippers, ladders) use `rounds_rep_scheme` on the block, not per-item duplication.
- [ ] Alternatives are attached to `workout_item`s that need them, not to the block.
- [ ] The exercise IDs are reused from prior conversations when the same movement appears (no duplicate exercise rows).
