---
title: Phase 3 — execution read-model seams implementation plan
status: completed
last_reviewed: 2026-04-26
purpose: Create shared execution read models so preview, active/rest, history, and watch do not re-derive workout structure independently.
covers:
  - app/Packages/Features/Execution/
  - app/Packages/Core/Session/
  - app/Packages/Core/Prescription/
  - docs/features/execute-loop.md
  - docs/features/workout-preview.md
  - docs/set-edit-sheet.md
---

# Phase 3 — Execution Read-Model Seams

> Historical/source-material note: this completed phase is retained for
> provenance. Future work must start from current feature/aspect docs and
> `docs/feature-gap-map.md`, not from this plan's imperative language.

## Unit Statement

Introduce stable read models for current task, remaining/upcoming work,
progress, block intent, and editability without changing the user-facing
workflow yet.

## Boundaries Touched

- `FeaturesExecution`: read-model builders and projection types.
- `CoreSession`: cursor/state inputs remain pure; no UI dependency added.
- `CorePrescription`: parsed work target and per-implement load conventions are
  consumed.
- Future consumers: Preview, Active/Rest, History, Watch projection.

## Dependencies And Preconditions

- Phase 2 schema fields are available, or this phase must use temporary
  computed defaults and explicitly mark schema-backed fields deferred.
- Existing `ExecutionNextUpPresentation`, `ExecutionTimerPresentation`, and
  `WorkTargetPresentation` are likely seams to extend.
- `FeaturesExecution` must not import `WatchBridge`.

## Uncertainty Reduction Summary

- Architecture/history: `ExecutionViewModel` and drivers already derive active,
  timer, next-up, and logging state; duplication risk grows as Preview/Watch use
  similar concepts.
- Blast radius: read models feed many views but should not mutate state.
- Contract/testing: pure read models are highly testable with fixtures.

## Approach

Extract or formalize read models before changing screens. Keep them
watch-neutral and UI-neutral enough that Shell can later map them to watch DTOs.

## Steps

1. Inventory current presentation builders and duplicated derivations.
2. Define read models:
   - `CurrentTaskPresentation`
   - `RemainingWorkPresentation`
   - `UpcomingWorkPresentation`
   - `BlockProgressPresentation`
   - `ExecutionEditability`
   - `ExecutionProjection`
3. Wire builders from `WorkoutContext` + `SessionState`.
4. Replace existing direct derivation in Active/Rest only where behavior stays
   unchanged.
5. Add fixture-heavy tests for straight sets, superset, AMRAP, rest block,
   unilateral item variants, skip/defaults, and block intent null/non-null.
6. Update docs with the new internal seam and ownership rule.

## Good

- Existing UI behavior is unchanged except for bugs discovered and pinned.
- There is one place to ask "what do I do now?" and "what remains?"
- Watch and preview phases have a projection seam instead of scraping SwiftUI.

## Done

- Read models cover the feedback-driven concepts and have fixture tests.
- Active/Rest still pass existing tests.
- No `WatchBridge` import appears in `FeaturesExecution`.

## Proof Map

- Check: targeted `FeaturesExecutionTests` for read-model fixtures.
  - Boundary: pure computation.
  - Proves: current/upcoming/remaining/progress derivation across modes.
  - Expected: pass with named scenarios.
  - Risk remaining: visual layout not proven until later phases.
- Check: `rg -n "WatchBridge" app/Packages/Features/Execution`.
  - Boundary: architecture fitness.
  - Proves: execution stays watch-neutral.
  - Expected: no hits.
  - Risk remaining: Shell mapping later may still be wrong.
- Check: existing execution package tests.
  - Boundary: regression.
  - Proves: no behavior drift in logging/timers.
  - Expected: pass.

## Independent Review

- Artifact: read-model diff and tests.
- Reviewer: Codex read-only review focused on duplication, ownership, and
  hidden behavior changes.
- Reopen condition: UI behavior changes without explicit acceptance, or a new
  read model embeds watch/protocol concerns.

## Closeout

- Update feature docs if read-model terms become part of implementation
  vocabulary.
- Update downstream phase plans if names differ.

## Implementation Notes

- Added `ExecutionProjection` as the shared read-model seam over
  `WorkoutContext` and `SessionState`.
- Made projection DTOs and `ExecutionTimerPresentation` public so downstream
  Preview, Shell, History, and Watch mapping code can consume or fixture them.
- Kept `FeaturesExecution` watch-neutral; `WatchBridge` remains absent from the
  package.
- `.today` projection now exposes the first executable task and upcoming work,
  so Preview does not need to re-derive driver/cursor display strings.
- Overdue rest projects as `OVER REST` elapsed instead of clamped `REST 0:00`.

## Completion Proof

- `FeaturesExecutionTests.ExecutionProjectionTests`: 6 tests passed.
- `FeaturesExecution` package tests: 357 tests passed.
- `rg -n "WatchBridge" app/Packages/Features/Execution`: no hits.
- Codex review thread `019dcaa4-41de-7de1-b52a-fe17b080b77e`: initial
  findings fixed; re-review clean.
- iOS simulator `build_run_sim`: succeeded for `WorkoutDB` on `WorkoutDB-Dev`.
- Simulator snapshot: Today screen rendered with planned workout cards and root
  tabs.

## Recovery Context

This phase creates seams only. Do not redesign screens and do not implement
watch messages here.

## Residual Uncertainty / Accepted Risks

- Some read models may need renaming after Phase 4/5 implementation pressure.
  - Accepted because behavior is pinned by tests.
  - Signal: two later consumers need incompatible shapes.

## Escalation Triggers

- Existing UI tests fail from read-model substitution.
- Read models require session mutations to answer display questions.
