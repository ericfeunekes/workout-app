---
title: Phase 5 — active rest transition redesign implementation plan
status: completed
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

1. Replace dead rest copy with rest progress grid. **Done for bounded work
   rests.**
2. Add scrolling active column and clear current-position indicators.
   **Partially done for bounded whole-block position.**
3. Add superset logging boundary: no mid-superset log sheet unless explicitly
   allowed by the contract. **Done for round-robin batch logging.**
4. Add between-block transition screen with physical setup information.
   **Done for work-block handoffs.**
5. Add skip affordance and persist skipped logs. **Done for eligible active
   row-based routes.**
6. Add per-side active/logging behavior where prescribed. **Deferred to the
   execution data/history parity phase; schema foundation exists.**
7. Add active/log-time capture for carries and duration/distance prescriptions.
   **Done for active/transition display and log-time capture; history edit parity
   remains downstream.**
8. Add simulator QA scenarios for P0 visual/tap items and timer continuity.

## Progress

- 2026-04-26 — Skip contract slice complete for eligible active row-based
  routes. `skip` advances through the normal rest/progress path, persists and
  caches `skipped=true` with performance metrics empty, suppresses deliberate
  skip for accumulate/score/target-owned modes, and displays skipped rows on
  Rest as `SKIPPED SET` without editable load/reps/RIR pills.
- 2026-04-26 — Rest progress-grid slice complete for bounded work rests.
  Rest now shows `BLOCK n / m`, `N / M DONE`, and performed/skipped/pending
  dots under the timer. The grid hides for standalone rest, unbounded/sentinel
  modes, and round-robin batch-rest pre-commit states.
- 2026-04-26 — Active block-position slice complete for bounded work blocks.
  Active now shows whole-block position from `ExecutionProjection.blockProgress`
  while keeping exercise-local pips and timer/logging behavior unchanged.
- 2026-04-26 — Superset round-log boundary complete. Batch round-robin taps no
  longer open a mid-superset log sheet; final station enters a round-log rest,
  final-round rest hides stale overdue timer copy, and `next` completes the
  workout.
- 2026-04-26 — Transition route complete for work-block handoffs. The route
  shows the finished block, next block, timing mode, first task, timing setup,
  and all station setup lines. `start block` lands on the next active route
  with explicit-start work in `READY` state.

## Good

- At any moment the screen answers "what do I do now?" and "what comes next?"
- Rest shows real progress through the block, not filler text.
- Skip is deliberate and persisted.
- Per-side/manual work is explicit; the app does not fake automatic completion.

## Done

- P0 active/rest/transition Phase 5 issues have simulator proof.
- Timer continuity for Phase 5 routes is proven by tests or simulator
  observation.
- Skip persists through local cache and sync payloads.
- Per-side and history edit parity are tracked as downstream gaps, not Phase 5
  closeout blockers.
- Carries and duration/distance work render and log during execution; later
  correction parity is tracked downstream.
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
- Skip slice QA: `scratch/qa-runs/phase-05-skip-contract.md`.
- Skip slice screenshot: `scratch/qa-runs/phase-05-skip-rest-screen-final.jpg`.
- Rest progress-grid QA:
  `scratch/qa-runs/phase-05-rest-progress-grid.md`.
- Rest progress-grid screenshots:
  `scratch/qa-runs/phase-05-rest-progress-grid.jpg` and
  `scratch/qa-runs/phase-05-rest-progress-skip-regression.jpg`.
- Active block-progress QA:
  `scratch/qa-runs/phase-05-active-block-progress.md`.
- Active block-progress screenshot:
  `scratch/qa-runs/phase-05-active-block-progress.jpg`.
- Superset round-log QA:
  `scratch/qa-runs/phase-05-superset-round-log.md`.
- Superset round-log screenshots:
  `scratch/qa-runs/phase-05-superset-round-1-log-rest-final.jpg`,
  `scratch/qa-runs/phase-05-superset-final-round-log-rest-final.jpg`, and
  `scratch/qa-runs/phase-05-superset-complete-final.jpg`.
- Transition QA:
  `scratch/qa-runs/phase-05-transition-screen.md`.
- Transition screenshots:
  `scratch/qa-runs/phase-05-transition-screen-final.jpg` and
  `scratch/qa-runs/phase-05-transition-active-after-start-final.jpg`.
- Final Codex review:
  `019dcbb2-85e7-7340-ba0c-eb4ee8a8007f`.

## Recovery Context

This is the core in-workout UX phase. Do not add watch protocol or history
correction scope here.

## Residual Uncertainty / Accepted Risks

- Some polish around ETA remains later.
  - Accepted because ETA is later polish.
  - Signal: user cannot complete workout without ETA.
- Test harness follow-up completed on 2026-04-26.
  - `FeaturesExecutionTests` passes through the Xcode-generated package scheme
    (`380 passed, 0 failed`).
  - `WorkoutDB` now has a smoke-test target so the app scheme's simulator test
    action runs (`1 passed, 0 failed`).

## Escalation Triggers

- Redesign requires unplanned data model fields.
- Simulator cannot prove the tap/timer claims because debug launch fixtures are
  missing; add fixture support before continuing.
