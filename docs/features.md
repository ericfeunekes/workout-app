---
title: Features brief
status: living
last_reviewed: 2026-04-26
purpose: Narrative map of user-visible features and where their specs or behavioral contracts live.
covers:
  - docs/features/
---

# Features Brief

WorkoutDB is organized around a small set of athlete-facing capabilities: get the
app connected, see today's planned work, execute a workout without network
dependence, record what happened, and review or correct the log afterward.

Feature docs describe the target contract for those capabilities. They are not
just snapshots of what the code happens to do today. A reviewer should be able
to read a feature doc and judge whether a plan, implementation slice, or QA run
matches how the feature is supposed to work.

## Feature Doc Doctrine

Each feature doc should answer four questions:

1. What is the intended behavior?
2. What state, inputs, and outputs define that behavior?
3. What is deliberately out of scope?
4. What proof shows the implementation matches the target?

When the current implementation, tests, or simulator proof do not match the
target, the feature doc carries a `Current gaps` section. Gaps are not future
wishlists; they are known mismatches against the intended behavior.

## Status And Proof

`docs/features/INDEX.md` owns the feature list and status model. A feature or
section can be `planned`, `building`, `built`, or `verified`.

`verified` has a higher bar than "the source looks right." UI, layout,
tap-target, contrast, and timer-flow behavior need simulator evidence or a
pinned UI test. `docs/QA.md` defines the accepted proof artifacts.

## Gap Index

`docs/feature-gap-map.md` is the cross-feature gap index. The owning feature or
aspect doc remains the source of truth; the map gives each unresolved gap a
stable ID so a future phase plan can say exactly which gaps it addresses.

Do not use the gap map as an implementation plan. Plans are just-in-time
artifacts in `docs/plans/active/` for selected work. Deferred capabilities stay
as requirements and gaps in their owning docs.

## Watch Direction

Early Apple Watch delivery starts with
`docs/features/watch-workoutkit-handoff.md`: map eligible workouts into Apple's
Workout app through WorkoutKit and prove completion reconciliation. Custom
Setmark watch-primary execution remains a later capability owned by
`docs/features/watch-primary-execution.md` and `docs/watch-metrics.md`.
