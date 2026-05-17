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

## Gap Map

`docs/feature-gap-map.md` is the cross-feature sequencing view. It mirrors the
feature docs' `Current gaps` sections and groups gaps into implementation
phases. The docs pass fills the phase column from feedback priority and obvious
delivery clusters; implementation planning can reshuffle when a specific unit is
selected.

Do not use the gap map as an implementation plan. Plans live in
`docs/plans/active/` only while a scoped unit is actively being worked.
Completed and superseded plans move to `docs/plans/archive/` for provenance.

Watch-primary execution is the next planned feature thread. It extends the
execution loop to Apple Watch without making the Watch a server actor: the
phone remains responsible for authoring, customization, and server sync, while
the live workout has one primary authority at a time. The full feature spec is
`docs/features/watch-primary-execution.md`; the lower-level watch slot and
metric contract is `docs/watch-metrics.md`.

The watch work depends on the execution, timing-mode, persistence, push-queue,
telemetry, and sync contracts. Implementation planning should read those feature
docs first, then read the feature-gap map, the watch-primary spec, and
`docs/watch-metrics.md`.
