---
title: workout-taxonomy
status: draft
purpose: Bootstrap taxonomy for workout domains, block archetypes, and how Claude should map training intent to app timing/logging primitives.
covers:
  - docs/specs/v2-architecture.md
  - docs/prescription.md
  - docs/features/timing-modes.md
---

# workout-taxonomy

## Purpose

This document is the bridge between "Claude builds a workout" and "the app can execute, time, and log it."

`docs/prescription.md` defines the current authoring vocabulary. `docs/features/timing-modes.md` defines behavior the app currently implements. This document sits one level above both: it names the workout domains and block archetypes we need to support so Claude can choose the right primitive instead of forcing everything into reps x load or a generic timer.

`docs/workout-execution-requirements.md` defines the athlete-facing timer, transition, logging, and summary behavior for these archetypes.

This is intentionally a bootstrap document. It should grow as we interview real training patterns and QA the app against them.

## Core model

A workout is an ordered sequence of blocks.

A block has one execution archetype. A block may also carry one or more domain lenses.

The distinction matters:

- **Domain lens:** what kind of training this is, such as strength, CrossFit, or running. Domains are useful for planning, display, and analysis, but they are not mutually exclusive.
- **Execution archetype:** how the app executes and logs the block. This must be mutually exclusive enough that the timer, active face, logging sheet, and QA expectations are clear.
- **Timing mode:** the current app implementation tool used to drive a block. Timing modes should map to archetypes; they are not the taxonomy by themselves.

Example: VO2 intervals can be a running workout or a CrossFit conditioning piece. The domain changes, but the execution archetype is still scheduled intervals.

## Domain lenses

### Strength / hypertrophy / powerlifting

Training where the app usually needs load, reps, RIR, rest, and set-level edits.

Examples:

- Back squat 5 x 5 with 3 min rest.
- Bench top set plus back-off sets.
- Dumbbell rows 4 x 10 with RIR target.
- Drop sets, clusters, rest-pause, myo-reps, and complexes.

### CrossFit / functional fitness / metcon

Training where the app usually needs rounds, stations, time caps, interval boundaries, partial completion, and mixed work targets.

Examples:

- 10 min AMRAP of pull-ups, push-ups, and air squats.
- 21-15-9 thrusters and pull-ups for time.
- EMOM alternating calories and burpees.
- Chippers, ladders, loaded carries, sled pushes, and mixed-modal circuits.

### Running / endurance

Training where the app usually needs duration, distance, pace, HR zone, splits, and segment transitions.

Examples:

- 10 km easy at zone 2.
- 8 x 400 m at 5K pace with 90 s jog.
- Tempo run with warm-up and cool-down.
- Progression run, hill repeats, fartlek, long run with marathon-pace blocks.

### Skill / isometric / mobility / recovery

Training where the app may need attempts, quality notes, fixed holds, max holds, side-specific work, low-friction timers, and explicit rest or recovery blocks.

Examples:

- Weighted dead hang for max duration.
- Handstand skill practice for 10 min.
- Plank 3 x 45 s.
- Mobility flow with timed holds.
- Active recovery or cooldown block.

## Execution archetypes

### `set_based`

Prescribed sets of one movement, or a set-major sequence of movements.

Typical domains: strength, hypertrophy, skill.

Current app mapping: `straight_sets`.

Typical work targets:

- Reps.
- Load.
- RIR for strength/hypertrophy work when authored.
- Duration for fixed holds.
- Percent 1RM.
- Tempo.

Timer contract:

- Active shows set elapsed unless a more specific work timer exists.
- Logging starts a rest timer when rest is prescribed.
- Rest can expire into an over-rest count-up.

Logging contract:

- One set row per performed set.
- User can edit load, reps, and RIR at log time when those targets are authored.
- Duration-first sets and max-duration sets need explicit handling before they are considered fully covered.

### `round_robin`

Repeated stations across rounds, where the user moves station to station.

Typical domains: strength accessories, CrossFit, mobility.

Current app mapping: `superset`, `circuit`.

Typical work targets:

- Reps per station.
- Duration per station.
- Distance or calories per station.
- Load per station.

Timer contract:

- Active timer belongs to the current station unless a block-level cap is present.
- Rest may exist between stations and/or between rounds.

Logging contract:

- Either log station-by-station, or defer a round batch to the shared rest screen.
- This distinction must be locked per subtype because it changes the user's active interaction.

### `task_for_time`

Complete a fixed body of work as fast as possible.

Typical domains: CrossFit, running, endurance tests.

Current app mapping: `for_time`.

Typical work targets:

- Fixed rounds.
- Chipper list.
- Rep ladder or rep scheme.
- Fixed distance.

Timer contract:

- Primary timer is elapsed time, with optional time cap as secondary or cap warning.
- The block ends when the work is completed or the user explicitly ends it.

Logging contract:

- The block result is total elapsed time.
- The app may also log station completions when useful for recovery after interruption, progress display, or partial result capture.
- A first-class block-result shape may eventually be needed if `set_log` rows plus notes become too weak for analysis.

### `time_boxed_max_work`

Do as much work as possible inside a fixed time cap.

Typical domains: CrossFit, density strength, testing.

Current app mapping: `amrap`; density strength may need an extension.

Typical work targets:

- Rounds and stations.
- Reps per station.
- Load per station.
- Optional single movement for density work.

Timer contract:

- Primary timer is the global block cap.
- The timer belongs to the block, not the current station.

Logging contract:

- Each `next` means the current station was completed as prescribed.
- At the cap, the app captures the partial station reached.
- Completed rounds can be derived from completed station rows.

### `scheduled_intervals`

Work happens on repeated time or distance boundaries.

Typical domains: running, CrossFit, conditioning.

Current app mapping: `emom`, `intervals`, `tabata`.

Typical work targets:

- Work duration.
- Work distance.
- Rest duration or recovery distance.
- Start every N seconds or minutes.
- Target pace, HR zone, cadence, reps, calories, or load.

Timer contract:

- Primary timer is the current interval or work/rest window.
- Total block cap may be secondary.
- Some variants auto-advance; others require manual lap or done-early input.

Logging contract:

- One interval row per work unit.
- Log duration, distance, HR, cadence, reps, load, or calories depending on the station shape.
- Missed intervals, late logs, and placeholder auto-logs need explicit requirements.

### `continuous_target`

One sustained effort with a target.

Typical domains: running, cycling, rowing, recovery.

Current app mapping: `continuous`.

Typical work targets:

- Duration.
- Distance.
- Pace.
- HR zone.
- Cadence.

Timer contract:

- Primary timer is elapsed time, target countdown, or distance progress depending on the authored target.
- Reaching the target may notify or complete; this needs to be locked by requirement.

Logging contract:

- One block-level effort row.
- Capture duration, distance, HR, cadence, pace where available.

### `accumulate_target`

Accumulate a target total across free bouts.

Typical domains: strength accessory, skill, CrossFit, rehab.

Current app mapping: `accumulate`.

Typical work targets:

- Total duration.
- Total reps.
- Total distance.
- Total time-in-zone.

Timer contract:

- Primary display is accumulated / target.
- Rest between bouts is free by default.
- Detectable bouts can fill automatically; non-detectable bouts create editable chunks.

Logging contract:

- Result is target completion plus chunk breakdown.
- Examples: `1:17 / 2:00 hang`, `65 / 100 push-ups`, `50 / 100 ft carry`.

### Goal overlays and work target kinds

Some concepts are not top-level archetypes:

- **Max effort test** is a goal overlay. It can attach to set-based work, scheduled intervals, continuous targets, or accumulate targets. The summary surfaces the best/top achieved metric.
- **Holds/isometrics** are work target kinds. They can appear as fixed-duration set work, max-effort duration tests, or accumulate targets.
- **Segmented continuous work** is composition for now. Author multiple continuous target blocks that auto-transition when possible rather than inventing a separate archetype.

### `rest_transition`

Explicit non-work time between blocks.

Typical domains: all.

Current app mapping: `rest`.

Timer contract:

- Primary timer is rest countdown.
- Expired rest becomes over-rest count-up.
- User can start early or add time.

Logging contract:

- Actual rest duration can be derived from timestamps.

## Current timing-mode mapping

| Timing mode | Best-fit archetype | Notes |
|---|---|---|
| `straight_sets` | `set_based` | Covers most strength sets; duration-first and max-duration variants need clearer log surfaces. |
| `superset` | `round_robin` | Two-station convention; shared round rest when authored. |
| `circuit` | `round_robin` | N-station convention; supports mixed targets as authored. |
| `emom` | `scheduled_intervals` | Start-on-boundary interval work; missed interval behavior needs explicit requirements. |
| `amrap` | `time_boxed_max_work` | Global cap; `next` completes stations; cap captures partial current station. |
| `for_time` | `task_for_time` | Needs a clear block-result contract and station-completion behavior. |
| `intervals` | `scheduled_intervals` | Running/cardio intervals; distance-based and manual lap behavior need explicit QA contracts. |
| `tabata` | `scheduled_intervals` | Fixed 20/10/8; strength reps capture remains a requirements question. |
| `continuous` | `continuous_target` | Target completion may auto-transition in a sequence, or notify/continue when standalone. |
| `accumulate` | `accumulate_target` | Free-rest chunks toward one total; duration/reps implemented, distance needs richer manual/sensor entry. |
| `custom` | Escape hatch | Too broad to QA as one thing; use only when no stricter archetype fits. |
| `rest` | `rest_transition` | Explicit between-block rest. |

## How Claude should use this

When authoring a workout, Claude should choose in this order:

1. Identify the domain lens for human understanding and later analysis.
2. Split the session into blocks.
3. Assign one execution archetype to each block.
4. Map the archetype to the narrowest timing mode the app supports.
5. Fill `timing_config_json` and `prescription_json` using `docs/prescription.md`.
6. If the desired work cannot be represented without ambiguity, add or update this taxonomy and `docs/open-questions.md` before relying on it.

## Interview backlog

The next requirements pass should resolve these at the implementation/planning level:

- How density strength maps: `time_boxed_max_work` vs an extension to `set_based`.
- How loaded carries encode load: per-hand, total implement load, sled load, or vest load.
- How composite set slot actuals are persisted and edited.
- How calories, attempts/success, quality, side, and load basis are represented.
- Whether block results need a first-class persistence entity or can remain `set_log` plus workout note.
