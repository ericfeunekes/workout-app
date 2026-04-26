---
title: Data model exploration — composability across workout types
status: decisions-applied
date: 2026-04-17
purpose: "Stress-test the v2 schema against every workout style Eric composes, identify gaps, propose minimal additive extensions. Decisions from this exploration are merged into docs/specs/v2-architecture.md (2026-04-17)."
covers:
  - docs/specs/v2-architecture.md
  - server/
  - app/
---

> **Status note (2026-04-17):** Eric confirmed all seven gaps are real in his training. Extensions E1–E4, E7, E8 are merged into the v2 spec. Watch integration (HR, cadence, set start/stop) is v1-in-scope; tempo haptics and raw motion capture are v1.1+ with `motion_samples_ref` reserved in `set_log`. WorkoutKit push deferred. Exercise IDs are Claude-owned (no server canonicalization).

# Data model exploration — composability across workout types

## Purpose

The v2 spec defines `block` (with `timing_mode`), `workout_item` (with `prescription_json`), and `exercise_alternative`. Before we implement it, I want to test the shape against the full range of workout types I'd want Claude to compose. This doc runs that test, identifies the gaps, and proposes minimal additive extensions.

Ground rules:
1. **Composability > completeness.** We need primitives that combine, not a fixed vocabulary.
2. **JSON blobs absorb variation.** New prescription shapes don't need schema migrations.
3. **Additive only.** No rewrites of entities already in the spec.
4. **No semantic intelligence in the app.** If a new construct requires the app to reason, we defer it or push it into conversation.

---

## Workout taxonomy — what we need to compose

A tour of the main patterns I'd ask Claude to program, grouped by dominant training intent.

### Strength (heavy, low-rep, fully rested)

| Pattern | Example | Schema mapping |
|---|---|---|
| Straight sets | `Back Squat — 5×5 @ 100kg, 3min rest` | `straight_sets` block, one item, prescription `{sets, reps, load_kg}` ✓ |
| RPE-based | `Front Squat — 4×3 @ RPE 8, 4min rest` | prescription `{sets, reps, rpe_target}` ✓ |
| Percentage-based | `Deadlift — 5×3 @ 85% 1RM` | prescription `{sets, reps, percent_1rm}` ✓ (resolves via `user_parameters`) |
| Linear pyramid | `Bench — 12, 10, 8, 6 reps, adding load each set` | **GAP** — per-set variation |
| Wave loading | `Clean — 3×(3,2,1) with increasing load across waves` | **GAP** — nested per-set variation |
| Cluster sets | `Deadlift — 4×5 with 15s intra-set rest after reps 1,2,3,4` | **GAP** — intra-set rest |
| Tempo | `Squat — 4×5 @ 70%, tempo 3-0-1-0` | **GAP** — tempo notation |
| Complex | `Power clean + front squat + jerk — 3+3+3, 4 rounds` | Block (rounds=4) + 3 workout_items, each with own prescription ✓ |
| Max attempts | `Squat — work up to 1RM` | **GAP** — no explicit "max attempt" semantics; could live in prescription `{attempts: "build_to_1rm"}` |

### Hypertrophy (moderate-rep, intensity techniques)

| Pattern | Example | Schema mapping |
|---|---|---|
| Straight sets | `DB Row — 4×10, 90s rest` | `straight_sets` ✓ |
| Antagonist superset | `Bench 4×8 + Row 4×8, 60s between rounds` | `superset` block, 2 items ✓ |
| Tri-set / giant set | `Lateral raise + rear delt + front raise ×3 rounds` | `superset`/`circuit` ✓ |
| Drop set | `Curl — 10 reps @ 20kg, drop to 15kg AMRAP, drop to 10kg AMRAP` | **GAP** — explicit drop notation |
| Rest-pause | `Press — 1 set of 10 reps, rest 15s, AMRAP, rest 15s, AMRAP` | **GAP** — intra-set rest + sub-sets |
| Myo-reps | `Leg press — 15 activation reps, then 5 mini-sets of 5 with 5 deep breaths between` | Covered by rest-pause variant |
| Mechanical drop set | `DB incline press → DB flat press → DB decline press, no rest, 8 reps each` | `superset` with `rest_between_rounds_sec=0` and 3 items ✓ |
| Unilateral | `Bulgarian split squat — 3×10 per side` | left/right variants as explicit exercise/workout items when side-level actuals matter; `load_kg` remains per-implement ✓ |

### CrossFit / GPP / Metcon

| Pattern | Example | Schema mapping |
|---|---|---|
| AMRAP | `10 min AMRAP: 5 pull-ups, 10 push-ups, 15 air squats` | `amrap` block, 3 items, `time_cap_sec=600` ✓ |
| EMOM | `10 min EMOM: odd = 10 cal row, even = 5 burpees` | `emom` block, 2 items with `position` alternating ✓ |
| For Time | `21-15-9 thrusters + pull-ups` | **GAP** — rep scheme descends across rounds (21, 15, 9) |
| Chipper | `100-80-60-40-20: row cal, air squats, situps` | Same GAP as 21-15-9 |
| Couplet/triplet | `5 rounds for time: 400m run, 15 KB swings, 10 burpees` | `for_time` block, 3 items, rounds=5 ✓ |
| Tabata | `Tabata push-ups, 8 rounds 20/10` | `tabata` block ✓ |
| Density | `10 min max effort bench press @ 60kg` | Can encode as `amrap` with 1 item + time_cap ✓ |
| KB complex | `Clean + press + squat + swing — 5 reps each, 3 rounds` | `superset`/`circuit` ✓ |
| Partner / "You go, I go" | n/a | Out of scope (single-user) |

### Running / Endurance

| Pattern | Example | Schema mapping |
|---|---|---|
| Easy continuous | `45 min easy` | `continuous` block, `target_duration_sec=2700` ✓ |
| Easy with distance | `10 km easy` | `continuous`, `target_distance_m=10000` ✓ |
| Tempo | `30 min @ threshold pace (4:30/km)` | `continuous`, `target_duration_sec + target_pace_sec_per_km` ✓ |
| Progression run | `60 min — last 20 min at tempo pace` | **GAP** — multi-segment within one block (or: use 2 continuous blocks) |
| Time-based intervals | `8×3 min hard / 2 min easy` | `intervals`, `work_sec=180, rest_sec=120`, rounds=8 ✓ |
| Distance-based intervals | `10×400m @ 5K pace with 90s jog recovery` | **GAP** — `intervals` only has `work_sec/rest_sec` |
| Hill repeats | `6×90s uphill hard, walk down recovery` | Time-based intervals ✓ (rest description is soft) |
| Fartlek | `45 min with 6–10 hard pushes of 30–90s, freestyle` | **GAP** — semi-structured, could be `continuous` with notes |
| Strides | `4×20s at mile pace, full recovery` | Time intervals ✓ |
| Long run | `2 hr easy` | `continuous` ✓ |

### Mixed modality / hybrid

| Pattern | Example | Schema mapping |
|---|---|---|
| Strength + metcon | `A: 5×5 squat. B: 15-min AMRAP.` | Two blocks in sequence ✓ |
| Skill + WOD + accessory | `Skill: double-unders 10 min. WOD: Fran. Accessory: 3×12 curls.` | Three blocks ✓ |
| CrossFit Open-style | `Part 1: 4-min AMRAP. Rest 1 min. Part 2: 3-min AMRAP.` | Sequence of blocks + a "rest" block | **GAP** — pure rest block |

### Mobility / prehab / warmup

| Pattern | Example | Schema mapping |
|---|---|---|
| Flow | `3 rounds: cat-cow 10, 90/90 hold 30s/side, thoracic opener 5/side` | `circuit`, rounds=3 ✓ |
| Isometric holds | `3×30s plank` | `straight_sets` with prescription `{sets, duration_sec}` ✓ |
| Dynamic warmup | `2 rounds: leg swings 10, lunge w/ rotation 5/side, world's greatest 5/side` | `circuit` ✓ |

### Edge / less common

| Pattern | Example | Schema mapping |
|---|---|---|
| Timed test | `12-min Cooper test` | `continuous` with `target_duration_sec=720` ✓ |
| Technique work | `5×3 clean pulls @ 70%, focus on lockout` | `straight_sets` + prescription notes ✓ |
| Accessory giant set | `5 rounds no rest: 10 face pulls, 10 band pull-aparts, 15 tricep pushdowns` | `circuit`, `rest_between_rounds_sec=0` ✓ |
| Ascending ladder | `1-2-3-4-5-…-10 reps of pull-ups, rest as needed` | **GAP** — per-round rep variation |
| Descending ladder (chipper) | Same as 100-80-60-40-20 above | Same GAP |

---

## Identified gaps

Seven gaps, ordered by how often I'd need them:

### G1. Per-set / per-round rep variation
Pyramids, wave loading, 21-15-9, chippers, ladders. The current `prescription_json` is one flat object per workout_item. Can't describe "set 1: 12 reps @ 60kg, set 2: 10 @ 65kg, …" without duplicating the workout_item.

### G2. Intra-set rest (cluster sets, rest-pause, myo-reps)
A single "set" with small rests inside it: 5 cluster reps, rest 15s, 5 more, rest 15s, etc. The spec's `rest_between_sets_sec` is one-level; clusters are a nested level.

### G3. Tempo notation
3-0-1-0 or similar. Not in prescription today.

### G4. Explicit drop sets
Same exercise, dropping load between "mini-sets". Currently I'd chain 3 workout_items for the same exercise — clunky and the app can't detect "this is a drop set" for display.

### G5. Distance-based intervals
`intervals` only has `work_sec/rest_sec`. 10×400m doesn't fit cleanly.

### G6. Multi-segment continuous (progression runs, fartlek)
`continuous` is one target. A progression run has segments.

### G7. Pure rest block
Workouts like "4-min AMRAP, rest 1 min, 3-min AMRAP" need an explicit rest between blocks. Currently a between-block rest is implicit.

---

## Proposed additive extensions

All additive, all JSON-blob-safe (no SQLite schema changes needed).

### E1. `sets_detail` in `prescription_json` (addresses G1, G4)

When reps/load vary per set, use an array instead of flat fields:

```json
{
  "sets_detail": [
    {"reps": 12, "load_kg": 60},
    {"reps": 10, "load_kg": 65},
    {"reps": 8,  "load_kg": 70},
    {"reps": 6,  "load_kg": 75}
  ]
}
```

For 21-15-9 on a for-time workout, stays at block level (see E7).

For drop sets, the same array with a `drop: true` flag on subsequent entries:

```json
{
  "sets_detail": [
    {"reps": 10, "load_kg": 20},
    {"reps": "amrap", "load_kg": 15, "drop": true},
    {"reps": "amrap", "load_kg": 10, "drop": true}
  ]
}
```

The `drop: true` tells the app to display these as a drop-set cluster (one rest timer at the end of the group, no rest between drops).

### E2. `intra_set_rest_sec` + `sub_sets` in `prescription_json` (addresses G2)

```json
{
  "sets": 4,
  "reps": 5,
  "load_kg": 100,
  "intra_set_rest_sec": 15,
  "sub_sets": 4
}
```

Means: 4 sets. Each set = 4 sub-sets of 5 reps with 15s rest inside. Between top-level sets: `rest_between_sets_sec` from block config.

### E3. `tempo` in `prescription_json` (addresses G3)

```json
{
  "sets": 4,
  "reps": 5,
  "load_kg": 100,
  "tempo": "3-0-1-0"
}
```

String in standard eccentric-bottom-concentric-top notation. App displays; timer engine can optionally cue per-rep if we want (defer).

### E4. Distance-based extensions to `intervals` timing_config (addresses G5)

```json
{
  "timing_mode": "intervals",
  "timing_config_json": {
    "work_distance_m": 400,
    "rest_distance_m": 200,
    "target_pace_sec_per_km": 240
  },
  "rounds": 10
}
```

App reads: "10 × run 400m @ 4:00/km, then jog 200m recovery." Either `work_sec` or `work_distance_m` must be present; same for rest.

### E5. `segments` in `continuous` timing_config (addresses G6)

```json
{
  "timing_mode": "continuous",
  "timing_config_json": {
    "segments": [
      {"duration_sec": 1200, "target_pace_sec_per_km": 330, "label": "easy"},
      {"duration_sec": 1200, "target_pace_sec_per_km": 280, "label": "tempo"}
    ]
  }
}
```

Handles progression runs, negative splits, warmup-in-a-run, etc. For fartlek, one segment with `freestyle: true` and notes.

### E6. Cadence target (bonus — hooks into Apple Watch, see research below)

Add to relevant timing configs:
```json
{"target_cadence_spm": 180}
```

For running, the Watch can read live cadence via HealthKit. The app displays target vs actual.

### E7. `rounds_rep_scheme` at block level (addresses G1 for chippers/ladders)

```json
{
  "timing_mode": "for_time",
  "rounds": 3,
  "rounds_rep_scheme": [21, 15, 9],
  "workout_items": [
    {"exercise": "thruster", "prescription": {"load_kg": 42.5}},
    {"exercise": "pull-up"}
  ]
}
```

App interprets: round 1 does 21 of each, round 2 does 15, round 3 does 9. `reps` per item is omitted when `rounds_rep_scheme` is present.

For ladders (1-2-3-…-10), the same field with `[1,2,3,4,5,6,7,8,9,10]` and `rounds=10`.

### E8. Rest block — just a timing mode (addresses G7)

Add to `timing_mode` enum: `rest` — takes `duration_sec`, no workout_items. App shows a countdown and auto-advances to the next block.

```json
{"timing_mode": "rest", "timing_config_json": {"duration_sec": 60}}
```

---

## Summary: eight extensions, all additive

1. **`sets_detail`** (per-set variation + drop sets)
2. **`intra_set_rest_sec` + `sub_sets`** (clusters, rest-pause, myo-reps)
3. **`tempo`** string on prescription
4. **`work_distance_m` / `rest_distance_m` / `target_pace_sec_per_km`** on `intervals` config
5. **`segments`** array on `continuous` config
6. **`target_cadence_spm`** on `continuous` and `intervals` configs
7. **`rounds_rep_scheme`** array at block level
8. **`rest`** added to `timing_mode` enum

No entity changes. No column changes. Everything slots into existing JSON blobs except E8 which is a new enum value.

With these, I can encode every pattern in the taxonomy above. The app's responsibility stays "read the mode, drive the timer, show what's prescribed."

---

## Apple Watch research summary

You asked about cadence and pushing workouts to the Watch. Both are doable as of iOS 17+/watchOS 10+, and by 2026 these APIs are mature.

### Can we read cadence (and friends) live?

**Yes.** `HKLiveWorkoutBuilder` streams quantity samples in real time during an active workout session. Running cadence (steps/min), running power, vertical oscillation, and ground contact time are all available to a watchOS app that runs its own `HKWorkoutSession`. Cycling cadence works too if a Bluetooth cadence sensor is paired to the Watch (the Watch itself doesn't derive cycling cadence without a sensor).

Implication: our Watch companion app runs a workout session during our workouts. It subscribes to the metrics we care about (HR, cadence, pace/distance, power) and writes them into our local SwiftData store alongside set_logs.

### Can we push a workout to the Watch?

**Yes, via `WorkoutKit`** (iOS 17+/watchOS 10+). `WorkoutComposition` + `CustomWorkout` + `IntervalBlock` let us construct structured workouts and schedule them to appear in the native Fitness app on Watch. watchOS 11 added custom step names (e.g. "3×5 Squat @ 100kg").

**Fit for our workout types:**

| Workout type | WorkoutKit fit |
|---|---|
| Running / cycling intervals | Excellent — maps cleanly |
| Tempo runs with HR/pace alerts | Good |
| Straight-set strength | Poor — WorkoutKit has no rep counter; only time/distance/energy goals |
| AMRAP / EMOM with reps | Poor — no rep tracking |
| Mixed hybrid with strength + cardio | Partial — cardio portions push cleanly, strength portion is a "strength training" step with a time cap |

### Recommendation for the Watch

Use both:
- **For endurance workouts** (pure `continuous` and `intervals` blocks, single-modality runs/rides) — also push them via WorkoutKit to the native Fitness app. User can choose: execute in our app, or in Fitness. Apple's app handles pace/cadence/HR alerts natively.
- **For strength, CrossFit, hybrid, and any workout with reps** — execute in our WatchKit app (companion to the iPhone app). We drive the timer and log reps; HealthKit provides HR/cadence/power metrics underneath.

This dual mode is optional and not a v1 blocker. v1 plan: ship our WatchKit app with HealthKit integration. Add WorkoutKit push for endurance workouts in v1.1 if there's a UX win.

---

## Recommendations

### Lock into the spec now
- E1 (sets_detail), E2 (intra-set rest), E3 (tempo), E4 (distance intervals), E7 (rounds_rep_scheme) — these unblock 90% of the missing patterns
- E8 (rest block) — trivial addition
- Watch companion app is in-scope for v1; HealthKit reads HR + cadence; writes `hr_avg_bpm`, `hr_max_bpm`, and (if present) `cadence_avg_spm` to `set_log`

### Add to `set_log`
- `cadence_avg_spm Integer?` — for runs and rides (null otherwise)

### Add to `user_parameters` keys (known)
- `resting_hr_bpm`, `max_hr_bpm`, `1rm_<exercise_slug>_kg`, `easy_pace_sec_per_km`, `threshold_pace_sec_per_km`, `5k_pr_sec`, `preferred_cadence_spm`

(Not schema — just known keys the app knows how to resolve.)

### Defer
- E5 (continuous segments) — useful for progression runs but can be encoded as two `continuous` blocks in sequence. Revisit after first running plans land.
- E6 (cadence target) — add once HR is flowing; follow-on PR.
- WorkoutKit push — v1.1.

### Out of scope (reaffirm)
- Partner/team workouts
- Competition/Rx'd tracking, leaderboards
- Nutrition, body comp (conversation-only)
- Exercise library curation UI (Claude pushes, no dedupe UX in app)

---

## Open questions

- **Exercise dedupe/canonicalization.** Claude pushes exercises. If Claude pushes "Back Squat" with a new UUID every time, we fracture history. Should the server canonicalize on name? On a slug field? Flag this as the first real "spec needs more" item when we design the exercises endpoint.
- **Warmup sets.** `is_warmup` is on `set_log`. Is it also on `workout_item` to mark that a set *should* be logged as warmup? Probably yes — add as a flag on the item.
- **RIR vs RPE.** Some lifters use RIR (reps in reserve) instead of RPE. Both fit in prescription_json; no schema call needed. Flag as a convention decision for Claude.

---

## Done when

- This doc is reviewed.
- Accepted extensions (E1–E4, E7, E8) are merged into `docs/specs/v2-architecture.md`.
- `set_log` gets `cadence_avg_spm` in the spec.
- An "Exercise canonicalization" open question lands in the spec or a follow-up ADR.
