---
title: Phase 4 — preview and edit contract implementation plan
status: completed
last_reviewed: 2026-04-26
purpose: Implement the preview-first workout entry and shared edit contract before active/rest redesign.
covers:
  - app/Packages/Features/Today/
  - app/Packages/Features/Execution/
  - app/Packages/Features/History/
  - docs/features/workout-preview.md
  - docs/set-edit-sheet.md
---

# Phase 4 — Preview And Edit Contract

> Historical/source-material note: this completed phase is retained for
> provenance. Future work must start from current feature/aspect docs and
> `docs/feature-gap-map.md`, not from this plan's imperative language.

## Unit Statement

Change workout entry to preview-first, add explicit Start, make "what's next"
include current-block remaining work, and introduce the shared SetEditSheet
shell/model for preview/future/past corrections. Editor families are
mode-specific; a uniform sheet must not be assumed for every timing mode.

## Boundaries Touched

- Today surface and workout preview route.
- Execution "what's next" preview.
- SetEditSheet shared shell/model and mode-specific editor registration.
- Execution pending/future edit path.
- Past-set edit invariant remains preserved.

## Dependencies And Preconditions

- Phase 3 read models exist for remaining/upcoming work and editability.
- Phase 2 fields are preferred but not all UI affordances need to write every
  new field in this phase.
- Past edits must mark `.manual` and never retrigger autoreg.
- Preview-edit persistence must be built against the server's whole-tree
  replacement + last-write-wins contract. No app-side workout PUT publisher
  exists today; concurrency/freshness is a fresh decision when that publisher
  lands.

## Uncertainty Reduction Summary

- Architecture/history: Today currently can start selected workouts; execution
  has existing sheets for logging/past edits; history has past-set edit.
- Blast radius: changing Today tap behavior affects first workout entry.
- Contract/testing: UI interaction and simulator proof are mandatory.

## Approach

Make preview the default entry point and keep Start as the only execution
handoff. Build the shared edit vocabulary/shell first, then adopt
mode-specific editor families only where this phase needs them.

## Steps

1. Add/finish `WorkoutPreviewView` using Phase 3 read models.
2. Change Today tap to open preview; keep explicit Start action.
3. Add Execution "what's next" preview that includes current-block remaining
   work before future blocks.
4. Build the SetEditSheet shell/model with field contracts from
   `docs/set-edit-sheet.md`, including load, reps, RIR, bodyweight, side,
   distance, duration, and carry/load-plus-distance fields.
5. Wire preview/future pending edits where safe.
6. Preserve existing history/past edit behavior through adapter or shared sheet.
7. Add tests and simulator QA.

## Good

- Accidental workout starts are gone.
- Preview answers "what am I about to do?" and allows scoped edits.
- "What's next" means remaining current block plus upcoming work.
- Editing semantics are consistent across preview and past corrections.

## Done

- Today tap opens preview.
- Start explicitly enters execution.
- Current-block remaining appears in the "what's next" preview.
- Shared SetEditSheet shell/model exists, with mode-specific editor families
  either implemented for this phase's surfaces or explicitly routed as current
  gaps.
- Simulator QA proves tap targets and flow.

## Proof Map

- Check: Today and Execution view-model tests.
  - Boundary: cross-module/user flow.
  - Proves: tap opens preview, explicit start, current-block remaining order.
  - Expected: pass.
- Check: SetEditSheet shell/model tests for load/reps/RIR/bodyweight/side/
  distance/duration/carry fields.
  - Boundary: UI component + pure edit model.
  - Proves: edit payloads are correct and past edit invariants hold.
  - Expected: pass.
- Check: iOS simulator QA.
  - Boundary: user-facing.
  - Proves: preview flow is usable and CTA tap targets work.
  - Expected: recording or screenshots saved under `scratch/qa-runs/`.

## Independent Review

- Artifact: Today/Preview/Edit diff and tests.
- Reviewer: Codex review focused on accidental-start regressions and edit
  semantic drift.
- Reopen condition: preview bypasses Start, past edits retrigger autoreg, or
  "what's next" omits current-block remaining.

## Closeout

- Update feature docs and gap map for #1, #2, #3, #6, #7, #12, #13, #15,
  #21, #26 as applicable.
- Attach simulator QA evidence.

## Recovery Context

This phase owns preview and edit contract. It does not redesign active/rest
layout except the preview sheet triggered from execution.

## Implementation Notes

- Today card body now opens the existing detail sheet as the workout preview;
  the direct card-level Start button was removed so execution starts only from
  the preview Start action.
- Execution projection exposes `workQueue`, ordered as current-block remaining
  first, then the next concrete task, then the first future block when present.
- Simulator QA found and fixed two workQueue presentation bugs:
  - `NextUpSheet` duplicated `NEXT BLOCK` by rendering both the projection queue
    and the legacy fallback card.
  - Accumulate target reps rendered as finite set counts (`100 sets left`).
- `DesignSystem.SetEditSheetModel` owns the shared edit intent vocabulary. The
  History visual sheet remains a documented adapter until the active/rest
  redesign phase can migrate all call sites together.
- Feedback-ripple disposition: this phase should be read as the shared edit
  vocabulary/shell phase, not proof that one visual editor covers every timing
  mode. Straight-sets, superset, and circuit can share the strength-style
  family; EMOM, intervals, continuous, accumulate, Tabata, custom, and rest
  need explicit mode-specific contracts or current gaps.
- Simulator QA artifact: `scratch/qa-runs/phase-04-preview-edit-contract.md`.
- Codex review thread `019dcab7-c502-7a51-b540-aa11f3fabc98` is clean after the
  duplicate-row and accumulate-target fixes.

## Residual Uncertainty / Accepted Risks

- Some structural edits may need narrower scope after implementation.
  - Accepted if documented as current gaps.
  - Signal: preview edit creates an execution state the reducer cannot seed.
- App-side workout PUT publishing is not implemented.
  - Accepted because Phase 4 delivered preview-first entry and edit vocabulary.
  - Signal: preview edits need to persist server-side or merge with newer
    workout trees.

## Escalation Triggers

- Preview editing requires schema changes not in Phase 2.
- Shared SetEditSheet cannot preserve past-edit autoreg invariant.
