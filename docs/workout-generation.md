---
title: workout-generation
status: draft
last_reviewed: 2026-05-17
purpose: Practical guide for generating executable workouts from WorkoutDB's current workout components, timer modes, prescription shapes, and logging model.
covers:
  - docs/prescription.md
  - docs/workout-taxonomy.md
  - docs/workout-execution-requirements.md
  - docs/features/timing-modes.md
  - server/workoutdb_server/models.py
  - schema/Sources/WorkoutDBSchema/
---

# Workout generation

This is the practical authoring guide for Claude or a human coach generating workouts for Setmark / WorkoutDB.

The goal is not just "make valid JSON." The goal is to author a workout that the app can execute offline, with the right timer running, the right thing visible to the athlete, the right log fields available at the right moment, and enough structure for Claude to reason over results later.

Use this as the top-level entry point. Use `docs/prescription.md` for the exact JSON vocabulary, `docs/workout-taxonomy.md` for the taxonomy, `docs/workout-execution-requirements.md` for the athlete-facing execution rules, and `docs/features/timing-modes.md` for current app behavior and QA scenarios.

## Mental model

The system has one load-bearing idea:

**Claude writes the plan. The app executes the plan.**

The app should not decide programming, progression, exercise selection, or workout intent. Those decisions must be encoded as data before the app starts the workout.

Author every workout in this order:

1. Decide the training intent.
2. Split the session into executable blocks.
3. Pick one timing mode per block.
4. Fill each block's timing config.
5. Fill each item prescription.
6. Add alternatives, autoregulation, warmups, notes, and tags where useful.
7. Check that the athlete-facing execution loop makes sense.
8. Check that the result will be logged in a form Claude can use later.

If a workout cannot be represented cleanly with those steps, do not force it into `custom` first. Identify the missing primitive and document the gap in `docs/open-questions.md`.

For modifiers, equipment context, unilateral variants, substitutions, and
setup-only labels, use `docs/modifier-equipment.md` before inventing new
prescription keys. The app displays authored context; it does not infer
programming meaning from equipment or variant names.

## Data model cheat sheet

Workout generation mostly writes these entities:

| Entity | Authoring role | Important fields |
|---|---|---|
| `workout` | The scheduled session. | `name`, `scheduled_date`, `status`, `source`, `notes`, `tags_json`, ordered `blocks`. |
| `block` | A coherent execution unit with one timer/logging mode. | `name`, `position`, `timing_mode`, `timing_config_json`, optional `rounds`, optional `rounds_rep_scheme_json`, `notes`, ordered `workout_items`. |
| `workout_item` | One exercise station inside a block. | `exercise_id`, `position`, resolved `prescription_json`, raw sparse `prescription_json_raw`. |
| `exercise` | Claude-owned movement identity. | `id`, `name`, `notes`, `demo_url`, `default_prescription_json`, `default_alternatives_json`. |
| `exercise_alternative` | Swap options for the specific workout item. | `exercise_id`, `reason`, optional `parameter_overrides_json`. |
| `set_log` | What the app records during execution. | `set_index`, `reps`, `weight`, `weight_unit`, `duration_sec`, `distance_m`, `rir`, `is_warmup`, timestamps, optional HR/cadence/motion fields, `notes`. |
| `user_parameters` | Append-only facts Claude and the app can use later. | `key`, `value`, `updated_at`, `source`. Latest value is by key and timestamp. |

Important constraints:

- UUIDs are authored or generated everywhere. Do not depend on exercise names as stable IDs.
- Plans flow server to app. Results flow app to server. Do not design a workout that needs the app to call Claude mid-session.
- `prescription_json`, `timing_config_json`, `tags_json`, `rounds_rep_scheme_json`, and `parameter_overrides_json` are JSON blobs by design. Extend behavior through documented shapes before adding schema columns.
- `block.name` matters. It is the athlete-facing boundary: "Easy run", "Strength A", "10 min AMRAP", "Cooldown".
- `workout_item.prescription_json` is resolved. Exercise defaults are merged on ingest; historical workout items do not retro-update when library defaults change.
- `set_log` is the current result carrier. Some block-level scores are encoded through set logs plus notes until a dedicated `block_result` entity exists.
- Modifier and equipment meaning must be authored explicitly. Use distinct
  exercise/workout-item identity when history should stay distinct; use notes or
  display metadata for setup-only context; use alternatives for in-workout
  substitutions.

Work targets:

- Author the primary item target as `target.kind/value/unit` when the target is duration or distance, or when the display unit matters.
- Treat reps as the same abstraction: reps are `kind = "reps"` with `unit = "reps"`, not a fundamentally different shape.
- The app displays the authored unit but logs canonical fields: reps to `reps`, duration to `duration_sec`, and distance to `distance_m`.
- Loaded duration/distance work is valid: a farmer carry can show `200 ft` as the primary target and `53 lb` as load, then push `distance_m = 60.96`, `weight = 53`, and `weight_unit = "lb"`.

## Authoring snippets vs API payloads

This doc uses two levels of examples:

- **Pattern snippets** use readable `"exercise": "Dumbbell bench press"` labels so the workout intent is obvious.
- **API payloads** must use UUID fields such as `exercise_id`, `position`, and JSON-blob string fields.

When writing a real server payload:

- Resolve every exercise label to an existing `exercise.id` first, or create a new exercise with a stable UUID.
- Serialize JSON blob fields as strings at the API boundary: `timing_config_json`, `prescription_json`, `tags_json`, `rounds_rep_scheme_json`, and `parameter_overrides_json`.
- Use `rounds_rep_scheme` as the authoring concept, but send the wire field as `rounds_rep_scheme_json`.
- Include explicit positions for blocks and items.

Minimal wire-shaped example:

```json
{
  "name": "Upper Hypertrophy",
  "scheduled_date": "2026-04-25",
  "status": "planned",
  "source": "claude",
  "tags_json": "[\"hypertrophy\",\"upper\"]",
  "blocks": [
    {
      "position": 0,
      "name": "Main press",
      "timing_mode": "straight_sets",
      "timing_config_json": "{\"rest_between_sets_sec\":150}",
      "rounds": null,
      "rounds_rep_scheme_json": null,
      "workout_items": [
        {
          "position": 0,
          "exercise_id": "00000000-0000-0000-0000-000000000001",
          "prescription_json": "{\"sets\":4,\"reps\":8,\"load_kg\":70,\"weight_unit\":\"lb\",\"target_rir\":2,\"autoreg\":{\"overshoot_at\":2,\"overshoot_step_kg\":5,\"undershoot_at\":2,\"undershoot_step_kg\":5,\"apply_to\":\"remaining\"}}"
        }
      ]
    }
  ]
}
```

## Domain lenses

Domains are not mutually exclusive execution types. They describe intent so Claude can choose the right block structure and defaults.

| Domain lens | Use for | Typical blocks |
|---|---|---|
| Strength / hypertrophy / powerlifting | Muscle gain, load progression, top sets, accessories, RIR-based work. | `straight_sets`, `superset`, `circuit`, cluster/rest-pause prescriptions. |
| CrossFit / functional fitness / metcon | Rounds, mixed modal work, scored density, chippers, EMOMs, AMRAPs. | `amrap`, `for_time`, `emom`, `circuit`, `intervals`, `rest`. |
| Running / endurance | Continuous runs, intervals, tempo, zone work, distance or duration targets. | `continuous`, `intervals`, `accumulate`, composed blocks. |
| Skill / isometric / mobility / recovery | Holds, practice volume, quality reps, warmups, cooldowns, active recovery. | `continuous`, `accumulate`, `custom`, `rest`, sometimes `straight_sets`. |

Use the domain to set language, tags, and defaults. Use the archetype and timing mode to determine execution.

## Block archetypes

Pick the archetype before the timing mode. The archetype answers "what kind of work is this?"

| Archetype | User experience | Usually maps to |
|---|---|---|
| `set_based` | Start a set, do prescribed work, log actuals, rest, repeat. | `straight_sets`; sometimes `superset` / `circuit` for grouped strength. |
| `round_robin` | Move through multiple stations in repeated rounds. | `superset`, `circuit`, `emom`, `amrap`, `tabata`. |
| `task_for_time` | Complete prescribed work as fast as practical. | `for_time`. |
| `time_boxed_max_work` | Fixed clock, maximize completed rounds/reps/work. | `amrap`, some `custom`. |
| `scheduled_intervals` | Work and rest boundaries are clock-driven. | `intervals`, `tabata`, `emom`. |
| `continuous_target` | One continuous effort with a duration, distance, pace, HR, or zone target. | `continuous`. |
| `accumulate_target` | Accumulate a target over one or more efforts, with optional free breaks. | `accumulate`. |
| `rest_transition` | Planned recovery or transition between blocks. | `rest`. |

Do not use "strength", "CrossFit", or "running" as execution labels. A running workout can contain intervals, continuous targets, and task-for-time segments. A CrossFit workout can contain VO2 intervals. A strength session can contain circuits and time caps.

## Timing mode decision table

| If the athlete should... | Use | Why |
|---|---|---|
| Do one exercise for N sets with optional rest and log load/reps/RIR. | `straight_sets` | Best strength/hypertrophy default. Supports row-based load/reps/RIR logging and autoreg. |
| Alternate two or more exercises as a grouped strength unit with rest after the group. | `superset` | Preserves the idea of one grouped round, without treating each exercise as a separate block. |
| Rotate through stations with optional rest between stations and rounds. | `circuit` | Best for round-robin work where station order matters. |
| Start a new station or effort every fixed interval. | `emom` | The clock owns boundaries; app shows interval and cap timers. |
| Work for a fixed total clock and record completed rounds plus partial reps. | `amrap` | The timer belongs to the whole block, not each exercise. |
| Complete a fixed task and record elapsed time. | `for_time` | Best for chippers, named workouts, "N rounds for time". |
| Follow repeated work/rest/distance intervals. | `intervals` | Best for running/conditioning intervals and repeat efforts. |
| Do fixed 20/10 intervals for 8 rounds. | `tabata` | Specialized interval shorthand. |
| Do one uninterrupted duration/distance/zone/pace effort. | `continuous` | Best for steady runs/rides/rows and standalone efforts. |
| Accumulate a target with optional free breaks. | `accumulate` | Best for dead hangs, carries, 100 push-ups, accumulated duration/distance/reps. |
| Use an explicit segment script that no normal mode covers. | `custom` | Escape hatch. Prefer documented modes first. |
| Insert planned recovery or transition. | `rest` | First-class rest block with its own timer and title. |

## Safe current subset

This guide intentionally distinguishes what is safe to author now from target behavior that still needs product or data-model work.

| Mode | Safe to author now | Be careful with | Avoid relying on |
|---|---|---|---|
| `straight_sets` | Strength/hypertrophy sets, warmups, rep ranges, per-set variation, clusters, RIR, log-time load edits, autoreg. | Percent-based loads require the needed `user_parameters`; varied pyramids plus autoreg need deliberate step choices. | Dynamic references such as "backoff from today's top set." |
| `superset` | Grouped round-robin strength/accessory work. | Batch logging and alternatives that preserve the round structure. | Round-robin autoreg or alternatives that change set count inside the item. |
| `circuit` | Multi-station rounds, complexes with zero between-station rest, accessory circuits, loaded carries, and fixed-duration holds using `target.kind/value/unit`. | Whether the score is station completion or total time. | Treating a scored metcon as a generic circuit when `amrap` or `for_time` is the real contract. |
| `emom` | Clock-driven station rotation. | Strength-style stations still need explicit user logging. | Fake missed rows or auto-completed reps when the interval boundary passes. |
| `amrap` | Global timer, station completion, rounds plus partial reps. | Only the current partial station should be editable at the cap. | Per-exercise timers inside a normal AMRAP. |
| `for_time` | Fixed work with manual finish and total elapsed time. | Time caps are warnings unless verified otherwise. | Automatic cap partial capture or rich split scoring as current behavior. |
| `intervals` | Time-based intervals and manual distance intervals. | Distance intervals require manual lap/advance until sensors exist. | Inferring distance completion from target pace. |
| `tabata` | Standard 20/10 interval work. | What per-round metric is worth logging. | Complex scored result models beyond current set logs. |
| `continuous` | One sustained duration/distance/zone/pace effort. | Distance completion and pace/HR targets are guidance unless sensor support exists. | Automatic transition on detected distance unless explicitly verified. |
| `accumulate` | Reps or duration accumulation with free breaks. Distance targets can be authored, but useful live tracking still needs manual metric entry or sensors. | Loaded distance/duration targets preserve load, but per-hand vs total implement load must be clear in notes. | Polished carry-specific split editing or sensor-complete carry detection. |
| `custom` | Rare scripted segments with clear notes. | Use only after stricter modes fail. | Hiding known patterns in custom to avoid modeling them. |
| `rest` | Explicit transition or recovery blocks. | Keep zero items. | Normal between-set rest, which belongs in the work block config. |

## Timer and logging modes

### `straight_sets`

Use for classic strength, hypertrophy, warmups, accessories, and most RIR-driven work.

Author:

- Block `timing_mode`: `straight_sets`.
- Block config: usually `rest_between_sets_sec`; optionally `rest_between_exercises_sec`.
- Item prescription: `sets`, `reps`, optional `load_kg` plus `weight_unit`, optional `target_rir`, optional `autoreg`, optional `tempo`, optional `warmups`, or richer shapes such as `sets_detail`, drop sets, and cluster/rest-pause.

Execution:

- Starting the workout lands on a visible `READY` timer.
- The athlete taps `set start`.
- The app switches to a set elapsed timer.
- The athlete taps `done`, edits load/reps/RIR in one row-based log sheet, then rest starts.
- Rest can be extended, and expired rest counts up in red.
- RIR is per set, normally for strength/hypertrophy work.

Result:

- One `set_log` per top-level set.
- Logs can carry weight, reps, RIR, duration, warmup flag, and notes.
- Autoreg can adjust remaining non-done, non-manual sets on that item.

### `superset`

Use for paired or small grouped strength work where the athlete completes multiple exercises before a shared rest.

Author:

- Block `timing_mode`: `superset`.
- Block config: `rest_between_rounds_sec`, optional `logging_mode`.
- Block `rounds`: number of grouped rounds.
- Items: each station gets its own prescription.

Execution:

- The athlete moves station by station inside each round.
- Shared rest appears after the group.
- Use it when the group should feel like one unit, not unrelated blocks.

Result:

- The app logs each station's work.
- Round-robin autoreg support is more constrained than straight-set autoreg; do not assume complex per-station future-set rewriting unless the feature doc says it is supported.

### `circuit`

Use for three or more stations where order matters and rest may occur between stations, between rounds, or both.

Author:

- Block `timing_mode`: `circuit`.
- Block config: `rest_between_exercises_sec`, `rest_between_rounds_sec`.
- Block `rounds`: number of rounds.
- Items: each station prescription.

Execution:

- The app advances through stations and rounds.
- This is the default representation for complexes if rest between stations is zero and rest between rounds is nonzero.

Result:

- Logs remain item/station based.
- If the workout is actually scored only by total time, consider `for_time` instead.

### `emom`

Use when the clock determines when the next station starts: "every minute on the minute", every 90 seconds, etc.

Author:

- Block `timing_mode`: `emom`.
- Block config: `interval_sec`, `total_minutes` or equivalent cap.
- Items: station prescriptions that rotate across intervals.

Execution:

- The block has a global cap and interval boundaries.
- For strength-style EMOMs, the athlete still starts/logs the station rather than the app fabricating a completed set when the boundary passes.
- Automatic transitions are driven by the interval clock; the user should still be able to manually advance if they intentionally stop early.

Result:

- Logs should reflect completed station work.
- Missed intervals should not silently create fake reps.

### `amrap`

Use for "as many rounds/reps as possible" inside one fixed clock.

Author:

- Block `timing_mode`: `amrap`.
- Block config: required `time_cap_sec`.
- Items: the ordered stations in one round.
- Station prescriptions usually describe reps/load/distance per round, not a per-station timer.

Execution:

- The timer is global for the block.
- The athlete taps `next` after finishing the current station.
- `next` records station completion and advances through the round.
- At the cap, the app asks for partial completion on the current station: prior stations can be checked complete, the current station can receive extra reps, unreached stations stay locked.

Result:

- The meaningful score is rounds plus extra reps.
- Station logs are useful for reconstruction, but the athlete-facing result should read like "7 rounds + 4 reps".

Do not author AMRAP as a per-exercise timer unless the workout genuinely has per-exercise timed stations. Most AMRAPs have one global timer across the whole block.

### `for_time`

Use when the task is fixed and the score is elapsed time.

Author:

- Block `timing_mode`: `for_time`.
- Block config: optional `time_cap_sec`.
- Block `rounds` and/or `rounds_rep_scheme` when the work repeats; serialize as `rounds_rep_scheme_json` in API payloads.
- Items: station prescriptions for the fixed task.

Execution:

- The timer is elapsed time or time cap for the block.
- The athlete advances through prescribed work.
- Current v1 behavior is finish-oriented: the user taps `finish` to log total duration. Expired caps do not automatically complete the workout.

Result:

- The result is total elapsed duration, currently represented through existing logs/notes rather than a first-class block result entity.
- Time-cap partial capture is a known area to be careful about; do not overpromise a polished partial-result sheet unless verified in the feature docs.

### `intervals`

Use for structured work/rest intervals, especially running, rowing, cycling, and conditioning.

Author:

- Block `timing_mode`: `intervals`.
- Block config: repeated work/rest seconds or distances, interval count, optional target pace, HR, cadence, or zone.
- Items: usually one exercise such as Run, Row, Bike, SkiErg, or Shuttle.

Execution:

- Time-based intervals can auto-transition.
- Distance-based intervals are manual until sensor/watch integration can infer distance completion.
- The active screen should emphasize the current interval target and next boundary.

Result:

- Logs can include duration, distance, HR, cadence, and notes where available.
- Splits are useful, but they should be triggered by real interval boundaries or explicit user taps, not invented.

### `tabata`

Use for classic 20 seconds work / 10 seconds rest / 8 rounds.

Author:

- Block `timing_mode`: `tabata`.
- Block config can be minimal because the protocol is fixed.
- Items: one or more stations depending on the intended rotation.

Execution:

- Automatic 20/10 work/rest boundaries.
- Timer-driven; the athlete is not expected to manually tap every transition.

Result:

- Logs should preserve enough work completed per round/station to be useful without turning the interface into a dashboard.

### `continuous`

Use for one continuous effort.

Author:

- Block `timing_mode`: `continuous`.
- Block config: one or more targets such as `target_duration_sec`, `target_distance_m`, pace, HR, or zone.
- Items: usually one exercise.

Execution:

- The active face shows the goal that matters: distance, duration, pace, or zone.
- If the goal can be detected automatically in the future, transition can be automatic; in v1, assume user-driven completion unless the feature doc says otherwise.
- In a composed workout, consecutive continuous efforts can each have their own block timer, with an overall timer when the whole composed segment is timed.

Result:

- Logs can carry duration, distance, HR, cadence, and notes.

### `accumulate`

Use when the athlete accumulates a target over one or more efforts and may break freely.

Examples:

- Accumulate 2 minutes dead hang.
- Complete 100 push-ups, resting whenever needed.
- Carry 100 feet total with a given load.
- Accumulate 5 minutes in a position.

Author:

- Block `timing_mode`: `accumulate`.
- Block config: exactly one main target, such as total duration, reps, or distance.
- Item prescription: the movement plus optional load, side, or instructions.

Execution:

- The athlete can break and resume.
- For duration-first efforts, the app can record chunks based on start/break/done.
- For rep-first work, break can insert an editable row; the athlete can enter the chunk reps then or leave it until the end.
- For distance-first loaded carries, distance entry is currently less polished unless sensors/manual metric entry are available.

Result:

- Multiple chunks may roll up into one accumulated target.
- This is the right primitive when rest is free rather than scheduled.

### `custom`

Use only when none of the normal timing modes can express the workout.

Author:

- Block `timing_mode`: `custom`.
- Block config: explicit segments.
- Notes should explain why the block is custom and what the athlete should expect.

Execution:

- Treat this as an escape hatch, not a default.
- The more a custom block is reused, the stronger the signal that the taxonomy needs a new documented primitive.

### `rest`

Use for planned recovery, setup, or transition between blocks.

Author:

- Block `timing_mode`: `rest`.
- Block config: `duration_sec`.
- Usually no items.
- Give the block a useful name: "Walk to treadmill", "Rest before AMRAP", "Cooldown".

Execution:

- The app should enter rest directly, including when the rest block is first in the workout.
- Rest is first-class; do not fake it with an empty exercise.

Result:

- Usually no set log.

## Prescription components

### Sets, reps, load, and units

Use direct `sets`, `reps`, `load_kg`, and `weight_unit` for straightforward strength work.

Rules:

- `load_kg` is the historical key name even when `weight_unit` is `"lb"`.
- Treat `weight_unit` as the source of truth for the numeric load.
- Prefer explicit `weight_unit: "lb"` for Eric's current gym convention unless the item is truly kilogram-based.
- Bodyweight work should not fake load as a heavy zero. Use the documented bodyweight prescription shape.
- If the athlete might change load at execution time, the app supports log-time load correction for strength rows.

### RIR

RIR means reps in reserve. It is normally a strength/hypertrophy target, not a universal workout metric.

Rules:

- Use `target_rir` when effort target matters.
- RIR is logged per top-level set.
- For composite sets, RIR is normally the final-set effort rating for the whole top-level set.
- Do not require RIR for AMRAP, for-time, pure running, or simple mobility work unless there is a specific coaching reason.

### Autoregulation

Autoregulation is discoverable through the prescription, not something the user should have to ask for.

Use it when:

- The exercise has repeated future sets in the same item.
- Load should respond to actual reps or RIR.
- The athlete can safely adjust load mid-session.
- The goal is hypertrophy, strength, or load-practice quality.

Avoid it when:

- The movement is skill-limited rather than load-limited.
- The workout is scored by time or total rounds.
- There are no remaining sets to adjust.
- The prescription shape is ambiguous, such as some pyramids, tempo-only prescriptions, or duration-first work.

Current behavior:

- Autoreg is per item.
- `target_rir` is required when `autoreg` is present.
- Supported triggers include overshooting RIR, missing prescribed reps, and hitting failure.
- Remaining non-done, non-manual sets can be adjusted.
- Proposals apply by default with an undo affordance.
- Current app behavior is strongest for `straight_sets`; be conservative when authoring autoreg in round-robin modes.

Useful defaults:

```json
{
  "target_rir": 2,
  "autoreg": {
    "overshoot_at": 2,
    "overshoot_step_kg": 5,
    "undershoot_at": 2,
    "undershoot_step_kg": 5,
    "apply_to": "remaining"
  }
}
```

Adjust the step by exercise. A squat can often move in larger jumps than a lateral raise. The `_kg` suffix on the step keys is historical; the numeric step is interpreted in the item's `weight_unit`.

### Percent-based loads

Use `percent_1rm` when the workout should resolve load from a user parameter such as `one_rep_max_<exercise_id>_kg`.

Rules:

- Make sure the required user parameter key exists or is part of the conversation setup.
- Logged values are authoritative. If a missing parameter causes manual entry, do not retroactively rewrite the completed log.
- For "today's top set as baseline" or "backoff from today's top single", there is no first-class dynamic-load reference yet. Claude should hardcode loads or document the gap.

### Rep ranges

Use rep ranges when the target is effort inside a range rather than a fixed number.

Example: 3 sets of 8-12 at RIR 2.

Rules:

- Pair with RIR when progression depends on the athlete's effort.
- Autoreg can be useful, but be explicit about whether the load should move during the current session or only in the next authored workout.

### Unilateral work

Author unilateral variants as explicit exercise/workout items for lunges, split squats, carries, suitcase holds, single-arm presses, and similar work when left/right actuals matter.

Rules:

- Make the side expectation explicit in the exercise identity or workout item.
- Treat `load_kg` as per-implement load for the authored item. Do not hide meaningful left/right asymmetry inside one ambiguous number.

### Tempo

Use tempo when rep quality matters.

Rules:

- Tempo changes the difficulty of each rep; do not blindly combine it with autoreg unless that is intentional.
- Put the tempo where the active face can show it as a coaching cue.

### Warmups

Use warmups when the athlete should do preparatory sets before work sets.

Rules:

- Mark warmup rows so history and top-set summaries can exclude them.
- Keep warmup prescriptions simple enough to execute quickly in the gym.

### Per-set variation

Use `sets_detail` when sets differ by load, reps, or intent.

Examples:

- Pyramid: 8 @ 135, 6 @ 155, 4 @ 175.
- Top set plus backoffs.
- Five normal sets followed by one rest-pause set.

Rules:

- Each top-level set is still a set boundary.
- Autoreg on varied sets is more complex; the working assumption is to adjust each remaining set's own prescribed load by the configured step, preserving the shape.

### Drop sets

Use drop-set shapes when load decreases inside a top-level set without a normal rest boundary.

Rules:

- If the athlete should not interact between drops, keep it as one top-level set with multiple slots.
- If the athlete should manually start/stop/rest/log each segment, model the segments as separate sets or expose slot transitions.
- RIR is logged at the top-level set unless a future shape explicitly captures per-slot effort.

### Cluster, rest-pause, and myo-reps

Use cluster/rest-pause shapes when one top-level set contains sub-sets separated by short intra-set rests.

Examples:

- 4 clusters of 3 reps with 20 seconds intra-set rest.
- Rest-pause: 10 reps, 15 seconds, 7 reps, 15 seconds, 5 reps.
- Myo-reps activation set followed by short-rest mini-sets.

Rules:

- A top-level cluster is still one set for RIR and primary logging.
- Intra-set rest can be timed inside the set.
- The workout author decides whether slot transitions are exposed.
- If transitions are off, the athlete logs the composed set as one unit.
- If transitions are on, rest slots create visible transitions between slots.
- Expanded per-slot actual editing is deferred; use notes if detailed slot misses matter.

### Alternatives and swaps

Use alternatives when the athlete might need to swap equipment or movement at the gym.

Rules:

- Alternatives are per workout item, not global programming decisions.
- Include a reason that helps the athlete decide: "no bench available", "shoulder-friendly", "hotel gym".
- Use `parameter_overrides_json` when the alternative changes reps, load, unit, target RIR, or nested prescription keys.
- For round-robin blocks, be cautious with alternatives that change set counts; changing one station's row count can skew the cursor.

### Notes

Use notes for coaching cues and information that does not change execution semantics.

Good notes:

- "Stay nasal breathing."
- "Stop 1 rep before form breaks."
- "Use total load, not per-hand load."
- "If treadmill pace feels too hot, cap at RPE 7."

Bad notes:

- Hidden timer rules that should be in `timing_config_json`.
- Hidden logging requirements that should be in `prescription_json`.
- A complete alternate workout that should be a separate block or alternative.

## Auto-adjustment recipes

### Hypertrophy default

Use for repeated strength sets where the athlete should stay near target effort.

```json
{
  "sets": 3,
  "reps": 10,
  "load_kg": 60,
  "weight_unit": "lb",
  "target_rir": 2,
  "autoreg": {
    "overshoot_at": 2,
    "overshoot_step_kg": 5,
    "undershoot_at": 2,
    "undershoot_step_kg": 5,
    "apply_to": "remaining"
  }
}
```

Behavior:

- Log 10 reps at RIR 4: remaining sets move up.
- Log 8 reps when 10 were prescribed: remaining sets move down.
- Log RIR 0 when target was 2: remaining sets move down.
- Undo holds autoreg for that item for the rest of the session.

### Small-isolation default

Use smaller steps for dumbbell lateral raises, curls, rear delt raises, and similar work.

```json
{
  "sets": 3,
  "reps": 12,
  "load_kg": 20,
  "weight_unit": "lb",
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

### Heavy compound default

Use larger steps only when the exercise and available plates support it.

```json
{
  "sets": 5,
  "reps": 5,
  "load_kg": 225,
  "weight_unit": "lb",
  "target_rir": 2,
  "autoreg": {
    "overshoot_at": 2,
    "overshoot_step_kg": 10,
    "undershoot_at": 2,
    "undershoot_step_kg": 10,
    "apply_to": "remaining"
  }
}
```

### When to omit autoreg

Omit autoreg for:

- One-off tests.
- AMRAPs and for-time workouts.
- Running pace work.
- Skill drills.
- Holds where the result is duration.
- Carries where the main adjustment is distance or implement availability.

Claude can still use the completed result later to author the next workout.

## Worked recipes

These are patterns to adapt, not exact API payloads.

### Whole-body hypertrophy session

Use when the goal is controlled volume and RIR-based progression.

Workout:

- Block 1: "Main strength", `straight_sets`.
- Block 2: "Upper/lower accessories", `superset`.
- Block 3: "Pump finisher", `circuit` or `straight_sets`.

Example block:

```json
{
  "name": "Main strength",
  "timing_mode": "straight_sets",
  "timing_config_json": {"rest_between_sets_sec": 150},
  "workout_items": [
    {
      "exercise": "Dumbbell bench press",
      "prescription_json": {
        "sets": 4,
        "reps": 8,
        "load_kg": 70,
        "weight_unit": "lb",
        "target_rir": 2,
        "autoreg": {
          "overshoot_at": 2,
          "overshoot_step_kg": 5,
          "undershoot_at": 2,
          "undershoot_step_kg": 5,
          "apply_to": "remaining"
        }
      }
    }
  ]
}
```

Execution check:

- The athlete gets a ready timer, set elapsed timer, row-based load/reps/RIR logging, rest countdown, and autoreg banner if needed.

### Strength superset

Use when two exercises should be grouped and rested after the pair.

```json
{
  "name": "Press and pull superset",
  "timing_mode": "superset",
  "rounds": 4,
  "timing_config_json": {
    "rest_between_rounds_sec": 120,
    "logging_mode": "batch_at_round_rest"
  },
  "workout_items": [
    {
      "exercise": "Incline dumbbell press",
      "prescription_json": {"reps": 10, "load_kg": 55, "weight_unit": "lb", "target_rir": 2}
    },
    {
      "exercise": "Chest-supported row",
      "prescription_json": {"reps": 12, "load_kg": 70, "weight_unit": "lb", "target_rir": 2}
    }
  ]
}
```

Execution check:

- The group should feel like one repeated unit.
- Rest should happen after both movements unless the block explicitly includes rest between stations.

### Cluster set inside a strength block

Use when one top-level set is composed of mini-sets with short intra-set rest.

```json
{
  "sets": 3,
  "reps": 3,
  "sub_sets": 4,
  "intra_set_rest_sec": 20,
  "load_kg": 185,
  "weight_unit": "lb",
  "target_rir": 1
}
```

Execution check:

- The app treats each cluster as one top-level set.
- Intra-set rest is visible inside the set.
- RIR belongs to the final effort for that top-level set.
- If exact mini-set misses matter, use notes until per-slot actual editing exists.

### AMRAP

Use for a fixed clock with rounds plus reps scoring.

```json
{
  "name": "10 min AMRAP",
  "timing_mode": "amrap",
  "timing_config_json": {"time_cap_sec": 600},
  "workout_items": [
    {"exercise": "Thruster", "prescription_json": {"reps": 10, "load_kg": 95, "weight_unit": "lb"}},
    {"exercise": "Burpee", "prescription_json": {"reps": 10}},
    {"exercise": "Pull-up", "prescription_json": {"reps": 10}}
  ]
}
```

Execution check:

- One global `AMRAP CAP` timer.
- The athlete taps `next` after each station.
- At the buzzer, the result sheet captures extra reps for the current partial station.
- The result should read as rounds plus reps, not as three unrelated strength logs.

### For time

Use when fixed work is scored by elapsed time.

```json
{
  "name": "5 rounds for time",
  "timing_mode": "for_time",
  "rounds": 5,
  "timing_config_json": {"time_cap_sec": 900},
  "workout_items": [
    {"exercise": "Kettlebell swing", "prescription_json": {"reps": 15, "load_kg": 53, "weight_unit": "lb"}},
    {"exercise": "Run", "prescription_json": {"distance_m": 200}}
  ]
}
```

Execution check:

- The cap or elapsed timer is block-level.
- The athlete should be able to finish manually.
- If the time cap expires, current behavior should not be assumed to auto-score partial work.

### EMOM

Use when the interval clock owns station boundaries.

```json
{
  "name": "12 min EMOM",
  "timing_mode": "emom",
  "timing_config_json": {
    "interval_sec": 60,
    "total_minutes": 12
  },
  "workout_items": [
    {"exercise": "Row calorie", "prescription_json": {"reps": 12}},
    {"exercise": "Push-up", "prescription_json": {"reps": 10}},
    {"exercise": "Goblet squat", "prescription_json": {"reps": 12, "load_kg": 53, "weight_unit": "lb"}}
  ]
}
```

Execution check:

- The current interval and total cap are visible.
- The app should not fabricate completion when an interval passes.

### Running intervals

Use for repeat pace or speed work.

```json
{
  "name": "Speed intervals",
  "timing_mode": "intervals",
  "timing_config_json": {
    "interval_count": 8,
    "work_distance_m": 400,
    "rest_sec": 90,
    "target_pace_sec_per_km": 300
  },
  "workout_items": [
    {"exercise": "Run", "prescription_json": {"distance_m": 400}}
  ]
}
```

Execution check:

- If distance completion cannot be sensed, the athlete must be able to advance manually.
- Splits should be tied to interval boundaries or explicit taps.

### Continuous run

Use for long slow distance, tempo, or zone work.

```json
{
  "name": "Easy aerobic run",
  "timing_mode": "continuous",
  "timing_config_json": {
    "target_distance_m": 10000,
    "target_hr_zone": "zone_2"
  },
  "workout_items": [
    {"exercise": "Run", "prescription_json": {"distance_m": 10000}}
  ]
}
```

Execution check:

- The active face should emphasize distance/zone.
- End-of-workout stats matter more than set-level detail.

### Accumulate target

Use when free breaks are allowed and the target is total accumulated work.

```json
{
  "name": "Dead hang accumulation",
  "timing_mode": "accumulate",
  "timing_config_json": {
    "target_duration_sec": 120
  },
  "workout_items": [
    {"exercise": "Dead hang", "prescription_json": {"load_kg": 20, "weight_unit": "lb"}}
  ]
}
```

Execution check:

- The athlete starts, breaks, resumes, and finishes when accumulated duration reaches the target.
- For reps-first accumulate work, break can insert an editable row for chunk reps.

### Loaded carry

Use short-term as `accumulate`, `circuit`, or `for_time` depending on the score.

Examples:

- Farmer's walk 2 x 40 m at 48 kg per hand: `straight_sets` or `accumulate` with distance and load notes.
- 5 rounds for time of sandbag carry + burpees: `for_time`.
- Accumulate 100 m yoke carry: `accumulate`.

Authoring rule:

- Put distance and load in the prescription.
- Use notes to clarify per-hand vs total load until carry-specific display/logging is first-class.

### Hybrid composed day

Use separate blocks when goals change.

Example:

1. "AMRAP primer" - `amrap`, 8 minutes.
2. "Transition" - `rest`, 3 minutes.
3. "Easy run" - `continuous`, 5 km zone 2.
4. "Squat repeats" - `for_time` or `circuit`, depending on whether the score is total time or completed work.

Execution check:

- Each block has a title.
- Timers reset at meaningful boundaries.
- Automatic transitions only occur when the goal can be inferred; manual override should remain available.

## Discoverability rules for generators

When generating a workout, apply these defaults proactively:

- Add `target_rir` to strength/hypertrophy work when effort matters.
- Add `autoreg` to repeated strength sets when there are future sets to adjust and load changes are safe.
- Add alternatives for gym-dependent exercises: bench, rack, cable station, machines, specialty bars.
- Add block names for every meaningful section.
- Add warmups for heavy compounds and first movement patterns of the day.
- Add `tags_json` for later analysis: `hypertrophy`, `strength`, `metcon`, `zone_2`, `intervals`, `test_day`, `deload`, `active_recovery`.
- Add rest blocks when recovery/setup is part of the workout, not an incidental pause.
- Add notes only for cues, not hidden execution semantics.

## Result persistence matrix

The app currently persists completed work primarily through `set_log` rows, status updates, notes, and append-only `user_parameters`. Author scored workouts with this in mind.

| Archetype | Primary result today | Supporting detail | Generator guidance |
|---|---|---|---|
| `set_based` | One or more `set_log` rows with actual reps/load/RIR/duration. | Warmup flag, notes, timestamps, autoreg-adjusted targets. | Safe for history and future prescription generation. |
| `round_robin` | Station-level `set_log` rows by round/station. | Round position comes from block structure and set index. | Safe for completion; avoid treating it as a single scored result unless notes make that clear. |
| `task_for_time` | Total elapsed duration via current logs/notes. | Optional station completion detail where supported. | Safe for finish-only workouts; cap partials and rich splits are target-only. |
| `time_boxed_max_work` | Rounds plus reps encoded through station logs and an AMRAP result note. | Completed stations plus current partial station. | Safe for normal AMRAP scoring; do not require first-class `block_result` queries yet. |
| `scheduled_intervals` | One row per interval or station where supported. | Duration, distance, HR, cadence when available. | Safe for time intervals; distance and missed/partial intervals are more manual. |
| `continuous_target` | One effort row with duration/distance/HR/cadence where available. | Notes and completion status. | Safe for duration-first efforts; distance auto-detection waits for sensors. |
| `accumulate_target` | Chunk rows or rolled-up accumulated rows depending on target. | Duration/reps/distance chunks and notes. | Safe for reps/duration accumulation; loaded-distance carries need manual conventions. |
| `rest_transition` | Usually no `set_log`. | Timer timestamps and workout flow context. | Safe for planned transitions; do not use as data-bearing work. |

If Claude needs queryable scored results across AMRAP, For Time, max-duration holds, and intervals, that is a signal for a coordinated `block_result` schema cutover. Do not hide that need in free-form notes and pretend it is solved.

## Current support boundaries

Do not overclaim these areas:

- First-class `block_result` persistence does not exist yet. AMRAP and For Time use mode-native UI plus current log/note shapes.
- Distance auto-completion depends on future sensor/watch integration. In v1, many distance boundaries are manual.
- Loaded carries are representable but do not yet have a polished carry-specific log surface.
- Weighted max-duration holds need explicit duration-first behavior; fixed-duration holds are easier than max-duration tests.
- Dynamic references like "backoff sets at 80% of today's top set" are not first-class.
- Density sets and time-capped fixed strength prescriptions need a clarified primitive.
- Cluster per-slot actual editing is deferred.
- Alternatives can override prescription keys, but the author must ensure the override still makes sense for the block's timing mode.

## Authoring checklist

Before pushing a workout, answer these questions:

1. Does every block have a clear title and one timing mode?
2. Does each timing mode match the athlete's goal, not just the sport domain?
3. Is there always a visible timer when execution starts?
4. Does the app know whether transitions are manual or clock-driven?
5. Does each item have the minimum prescription needed for the active face?
6. Are load, reps, duration, distance, and RIR used only where they make sense?
7. Are RIR and autoreg present on strength work where useful, and absent where misleading?
8. Are alternatives available for equipment-sensitive movements?
9. Are block notes and item notes coaching cues rather than hidden control flow?
10. Will the resulting logs let Claude understand what happened after the workout?
11. If the workout is scored, is the score represented by an existing mode result or explicitly marked as a current gap?
12. If the author had to use `custom`, is there a note explaining why no first-class mode fits?

## If a desired workout does not fit

Do not invent unsupported behavior in JSON. Use this escalation path:

1. Try to express it as existing blocks composed together.
2. Try `accumulate` for free-rest totals, `continuous` for uninterrupted targets, `intervals` for scheduled work/rest, and `for_time` / `amrap` for scored metcons.
3. If it still does not fit, use `custom` only with clear notes.
4. Add or update an item in `docs/open-questions.md` with:
   - how Claude would author it,
   - what the active face should show,
   - what timer boundary exists,
   - what the user edits at log time,
   - what fields should land in `set_log`,
   - whether this needs a new timing mode, a new prescription shape, or only better docs.
