---
title: Phase 11 — modifier equipment modeling implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Define authored modifier and equipment modeling so exercise variants stay explicit without app-side programming logic.
covers:
  - docs/feature-gap-map.md
  - docs/prescription.md
  - docs/features/workout-generation.md
  - docs/features/exercise-catalog.md
---

# Phase 11 — Modifier / Equipment Modeling

## Unit Statement

Define how Claude-authored workouts represent modifiers, equipment context, and
exercise variants so the app can display and log them without inferring
programming logic.

## Boundaries Touched

- Prescription vocabulary for modifier and equipment fields.
- Exercise catalog and generation docs.
- Future JSON shapes in `prescription_json`.
- Display-only app behavior for variant labels and setup cues.

## Dependencies And Preconditions

- Phase 1 has routed feedback item #22 as future design/current gap.
- Phase 2 schema foundation is understood; prefer JSON/authored data unless a
  concrete behavior requires a column.
- Dumb-app invariant remains load-bearing: the app displays authored intent and
  records outcomes; it does not choose variants.

## Approach

Design the authored data model before implementation. Start with examples from
real workouts, classify what must affect execution versus display, and avoid a
schema migration until there is a proven query/sync need.

## Steps

1. Collect modifier/equipment examples from feedback and current docs.
2. Classify each example as execution-affecting, setup/display-only, history
   analysis, or future programming input.
3. Decide where each class belongs: `prescription_json`, exercise metadata,
   alternatives, workout notes, or a future schema field.
4. Write display rules for phone execution, preview, history, and watch slots.
5. Add generator checklist language so Claude authors explicit variants instead
   of relying on app heuristics.
6. Create a follow-on implementation plan only for concrete app-visible behavior
   that emerges from the design.

## Good

- A reviewer can tell how to author "same exercise, different setup" without
  inventing app behavior.
- The app stays dumb: no implicit equipment/modifier inference.
- Display rules are explicit enough for phone/watch UI phases.
- Schema changes are deferred unless justified by a specific behavior.

## Done

- `docs/prescription.md` and owning feature docs define the modifier/equipment
  vocabulary.
- `docs/feature-gap-map.md` routes feedback item #22 to this design and any
  follow-on implementation gap.
- At least three examples show how strength, carry, and machine/equipment
  variants are represented.
- Independent review is clean or real findings are patched.

## Proof Map

- Check: example table review against current feedback.
  - Boundary: product contract.
  - Proves: real modifier/equipment cases can be represented.
  - Expected: no orphan example.
- Check: schema decision note.
  - Boundary: architecture.
  - Proves: JSON/authored data versus schema field choice is deliberate.
  - Expected: no unplanned migration in this phase.
- Check: independent Codex review.
  - Boundary: external review.
  - Proves: no hidden app-side programming logic or missing display contract.
  - Expected: clean.

## Independent Review

- Artifact: modifier/equipment docs and gap-map routing.
- Reviewer: Codex focused on dumb-app violations, ambiguous authoring
  vocabulary, and premature schema design.
- Reopen condition: the app would need to infer variant meaning, or examples
  cannot be represented.

## Closeout

- Update phase index and gap map.
- If implementation is needed, create a separate scoped phase with code/test/QA
  proof.

## Recovery Context

This is a design/documentation phase. Do not implement schema or app changes
until the model has concrete app-visible behavior and proof needs.

## Residual Uncertainty / Accepted Risks

- Some modifier data may become useful for analytics later.
  - Accepted because that should be driven by observed queries, not speculation.
  - Signal: history/reporting requires filtering by modifier/equipment.

## Escalation Triggers

- The desired behavior requires cross-workout querying, not just display.
- Watch or execution UI cannot present the authored variant without additional
  structured fields.
