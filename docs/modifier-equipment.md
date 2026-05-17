---
title: Modifier and equipment modeling
status: planned
last_reviewed: 2026-05-17
purpose: Durable authoring contract for modifiers, equipment context, and exercise variants without app-side programming inference.
covers:
  - docs/prescription.md
  - docs/workout-generation.md
  - docs/workout-taxonomy.md
  - docs/features/workout-preview.md
  - docs/features/execute-loop.md
  - docs/features/history.md
---

# Modifier and Equipment Modeling

## Target behavior

Claude-authored workouts must represent exercise variants, modifiers, and
equipment context explicitly enough that the app can display, execute, and log
them without inferring programming meaning.

The app may show setup cues, variant labels, per-implement load conventions, or
history context. It must not decide that one variation is equivalent to another,
choose equipment, rewrite progression, or infer stimulus from a modifier.

## Ownership

- Claude owns variant choice and equipment-aware programming.
- The app owns display and logging of the authored variant.
- History may group by the exercise identity it receives. Any cross-variant
  aggregation must be an explicit later taxonomy requirement.
- `prescription_json`, exercise names/notes, alternatives, and workout notes are
  the preferred first homes. Add schema only when a concrete query, sync, or UI
  requirement cannot be met by authored data.

## Vocabulary rules

- **Variant identity:** If left/right, machine/free-weight, grip, implement, or
  stance changes must produce distinct logged history, author it as a distinct
  exercise or workout item.
- **Setup/display modifier:** If the difference only helps the athlete set up,
  put it in notes or display metadata.
- **Execution-affecting modifier:** If the modifier changes what the user logs
  or sees during execution, put it in `prescription_json` with an explicit
  target/load/duration/distance shape.
- **Equipment substitution:** Use `exercise_alternative` when the user may swap
  during a workout. The override must remain executable inside the block's
  timing mode.
- **Analysis-only label:** Use tags or notes until there is a proven query that
  needs structured schema.

## Examples

| Scenario | Preferred representation | Reason |
| --- | --- | --- |
| Single-arm dumbbell row, left and right actuals matter | Two exercise/workout items, e.g. `DB Row (Left)` and `DB Row (Right)` | History and corrections stay explicit without relying on `set_log.side`. |
| Farmer carry, 48 kg per hand for 40 m | Distance target plus load; note whether load is per-hand | App displays/logs distance and load; Claude retains semantic meaning. |
| Machine chest press instead of bench | `exercise_alternative` with reason and load/unit override | The swap is explicit and does not make the app choose equipment. |
| Tempo squat | `tempo` in `prescription_json` | Execution can display the authored cue; app does not infer tempo from exercise name. |
| Test-day squat | Workout tags/notes such as `test_day` until query needs prove schema | Avoid premature structured fields. |

## Current gaps

- `MOD-GAP-001`: The vocabulary above is not yet fully reflected in
  `docs/prescription.md` and `docs/workout-generation.md` as an authoring
  checklist.
- `MOD-GAP-002`: There is no canonical example table covering strength,
  loaded carries, machine substitutions, unilateral variants, and analysis-only
  labels in the workout-generation flow.
- `MOD-GAP-003`: Cross-variant history aggregation is undefined. Until a later
  requirement promotes it, History should group by authored exercise identity.
- `MOD-GAP-004`: No schema change is justified yet. A future phase must name
  the concrete query/sync/UI behavior before adding structured modifier or
  equipment columns.

## Acceptance criteria

1. A future implementation can display authored modifier/equipment context
   without deriving training meaning in the app.
2. Substitutions remain explicit alternatives or authored plan changes, not app
   heuristics.
3. History grouping remains faithful to authored exercise identity unless a
   later requirement defines cross-variant aggregation.
4. Any schema addition is backed by a named behavior that cannot be served by
   prescription JSON, exercise notes, alternatives, tags, or workout notes.
