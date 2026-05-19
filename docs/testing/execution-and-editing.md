---
title: Execution And Editing Testing
status: accepted
last_reviewed: 2026-05-18
purpose: Proof patterns for primitive execution, timer transitions, route projections, and shared edit/correction surfaces.
covers:
  - app/Packages/Core
  - app/Packages/Features
  - docs/specs/primitives-data-model.md
  - docs/workout-execution-requirements.md
---

# Execution And Editing Testing

Use this when a change affects primitive execution, timers, route transitions,
current/remaining/upcoming projections, preview edits, active set edits, or
history corrections.

## Primitive Execution

Primitive composition tests belong below the UI whenever possible.

`CoreSessionTests` owns deterministic primitive composition fuzzing. The
generator builds repeatable randomized Block > Set > Slot compositions across
timing modes, traversals, work targets, load units, and stimuli. It asserts the
shared semantics oracle:

- legal cases seed into `ExecutionPlan`
- aggregate and result metrics match primitive rules
- visible progress policy is stable
- deterministic log IDs stay unique across generated repeats
- invalid compositions reject with the expected cause

Promote any failing seed that reveals a product bug into a named regression
fixture or UI matrix row. Do not leave it as an unexplained random-only failure.

## Output Readback

`ExecutionViewModelPushTests` owns primitive output readback. These tests assert
that produced `PrimitiveSetLog` rows carry expected roles, index coordinates,
metrics, units, timestamps, and completion-record inclusion.

They also assert `execution.primitive_result_recorded` telemetry mirrors the
same row-shaped facts. QA should compare telemetry to output data for invisible
primitive result claims instead of relying on screen recordings.

## Timer And Route Transitions

Use clock-controlled reducer, driver, or view-model tests for timing behavior.
Avoid bounded real-time sleeps unless the code cannot accept a controlled clock.

Exercise:

- active, rest, transition, and complete states
- first and last set/slot behavior
- skip, done, pause, resume, and cancel actions
- route changes while a workout is active
- current, remaining, and upcoming projections
- elapsed-time and duration boundaries
- unsupported legal primitive cells failing closed instead of guessing

Simulator QA is still required for visible route behavior, but the state machine
must be pinned before visual QA claims correctness.

## Shared Edit And Correction Surfaces

Preview edit, active set edit, history correction, and apply-to-remaining all
need a shared proof shape. A passing test for one context does not prove the
others unless the test matrix explicitly covers them.

For shared edit work, tests should name:

- context: preview, active workout, history, or server-backed correction
- source row or primitive coordinate being edited
- cancel behavior
- commit behavior
- invalid edit rejection
- apply-to-remaining semantics where supported
- audit, overwrite, or replacement semantics
- server whole-tree replacement or local-only mutation boundary

The useful invariant is not "the sheet opens." It is that every context applies
the same domain rule to the correct target and leaves the rest of the workout in
a coherent state.

## UI Matrix Proof

`make test-workout-type-ui` runs workout-type matrix data tests before launching
simulator UI rows. The data tests are part of the proof surface: they assert
that every matrix row declares at least one required runtime action, that
sheet-opening actions commit the sheet, that direct actions do not reuse sheet
commit helpers, and that rest-start rows expect the rest route.

This keeps UI helpers aligned with real execution behavior instead of allowing
a row to pass by only opening and force-ending a workout.

## QA Boundary

QA should exercise the real gestures: taps, swipes, long presses, sheet
dismissal, keyboard edits, timer advancement, route changes, skip/done flows,
and destructive confirmations. QA cannot replace reducer, output readback, or
shared edit invariant tests.
