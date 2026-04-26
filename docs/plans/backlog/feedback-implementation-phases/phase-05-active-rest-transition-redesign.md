---
title: Phase 5 — active rest transition redesign implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Implement the main in-workout UX redesign for active, rest, and between-block transition screens.
covers:
  - app/Packages/Features/Execution/
  - docs/features/execute-loop.md
  - docs/features/block-transition.md
---

# Phase 5 — Active / Rest / Transition Redesign

## Unit Statement

Redesign the in-workout Active, Rest, and Transition surfaces around clear
current position, remaining work, rest progress, skip, and next-block setup.

## Boundaries Touched

- Execution UI: `ActiveView`, `RestView`, transition route/screen.
- Execution state transitions and reducer mutations for skip/advance.
- Read models from Phase 3.
- Persisted fields from Phase 2 for skip and side where needed.
- Active/log-time support for carries and duration/distance work targets.

## Dependencies And Preconditions

- Phase 2 schema cutover is complete for `set_log.skipped` and `set_log.side`.
- Phase 3 read models exist.
- Phase 4 preview/edit contract is complete.
- Simulator QA is required for visual/tap-target claims.

## Uncertainty Reduction Summary

- Architecture/history: `ExecutionViewModel` owns timers/logging; rest and
  active UI already have separate sheets and timer presentations.
- Blast radius: wrong transition logic can corrupt logs or cursor advancement.
- Contract/testing: unit tests can prove state transitions; simulator proves
  usability.

## Approach

Keep reducer semantics explicit. Build visual redesign on top of read models,
then add only the mutations required for skip and transition.

## Steps

1. Replace dead rest copy with rest progress grid.
2. Add scrolling active column and clear current-position indicators.
3. Add superset logging boundary: no mid-superset log sheet unless explicitly
   allowed by the contract.
4. Add between-block transition screen with physical setup information.
5. Add skip affordance and persist skipped logs.
6. Add per-side active/logging behavior where prescribed.
7. Add active/log-time capture for carries and duration/distance prescriptions.
8. Add simulator QA scenarios for P0 visual/tap items and timer continuity.

## Good

- At any moment the screen answers "what do I do now?" and "what comes next?"
- Rest shows real progress through the block, not filler text.
- Skip is deliberate and persisted.
- Per-side/manual work is explicit; the app does not fake automatic completion.

## Done

- P0 active/rest issues have simulator proof.
- Timer continuity is proven by tests or simulator observation.
- Skip and per-side logging persist through local cache and sync.
- Carries and duration/distance work can be logged during execution and later
  corrected through the shared edit model.
- Feature docs/gap map updated.

## Proof Map

- Check: reducer and execution VM tests for skip, advance, per-side,
  carry/duration/distance logging, transition.
  - Boundary: pure state + cross-module.
  - Proves: mutations and cursor transitions are correct.
  - Expected: pass.
- Check: UI tests or snapshot-compatible view tests where available.
  - Boundary: user-facing.
  - Proves: key controls render enabled/visible.
  - Expected: pass or documented simulator evidence.
- Check: iOS simulator QA for Active/Rest/Transition.
  - Boundary: user-facing critical path.
  - Proves: tap targets, timer, progress grid, transition screen.
  - Expected: recorded QA evidence.

## Independent Review

- Artifact: execution redesign diff, reducer changes, tests, simulator QA.
- Reviewer: Codex review focused on state corruption, logging ownership, and
  visual proof overclaims.
- Reopen condition: skipped/per-side logs do not persist, or timer proof is only
  code inspection.

## Closeout

- Update `docs/features/execute-loop.md`, `docs/features/block-transition.md`,
  and `docs/feature-gap-map.md`.
- Attach QA run paths.

## Recovery Context

This is the core in-workout UX phase. Do not add watch protocol or history
correction scope here.

## Residual Uncertainty / Accepted Risks

- Some polish around ETA remains later.
  - Accepted because ETA is later polish.
  - Signal: user cannot complete workout without ETA.

## Escalation Triggers

- Redesign requires unplanned data model fields.
- Simulator cannot prove the tap/timer claims because debug launch fixtures are
  missing; add fixture support before continuing.
