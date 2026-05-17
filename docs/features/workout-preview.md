---
title: workout-preview
status: built
last_reviewed: 2026-05-17
purpose: Target contract and QA scenarios for opening a planned workout before execution starts.
covers:
  - docs/features/today.md
  - docs/features/execute-loop.md
  - docs/set-edit-sheet.md
  - app/Packages/Features/Today/
  - app/Packages/Features/Execution/
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionProjection.swift
---

# workout-preview

## Target behavior

Opening a planned workout shows a preview first. Starting execution is a
separate deliberate action.

The preview answers:

- what workout is selected
- what blocks and exercises are coming
- what the first active task will be
- what editable values can still be changed before the workout starts

Today cards may still expose start affordances, but tapping the card body should
not silently start a session. The app should make accidental starts hard in a
gym context where taps are imprecise.

## State surface

- **Inputs:** planned workout, blocks, workout items, exercise catalog,
  prescription/timing config parsing, last-performed summaries, current session
  state if one exists.
- **Outputs:** preview read model, explicit start action, scoped edit intents
  routed through `docs/set-edit-sheet.md`.
- **Projection ownership:** preview should consume the shared execution
  projection seam for first-task, remaining-work, upcoming-work, block-intent,
  and editability answers. It should not re-derive execution cursor rules or
  driver-specific display strings in a separate preview-only model.
- **State transitions:** preview has no live timers. `Start` is the only route
  from preview into execution.

## Edit contract

Preview edits are planned-workout edits before a session starts. They can change
values that are safe to seed into execution, such as load, reps, RIR target,
duration, distance, bodyweight, or carry/load details when the authored
prescription supports them. Unilateral work stays at the authored
exercise/workout-item level; preview does not choose left/right variants or
perform local exercise selection.

Preview edits must not become app-side programming logic. If the desired change
is workout design rather than execution setup, the app should surface a Claude
handoff instead of inventing a local plan mutation.

## Deliberate non-goals

- No local workout programming, periodization, or exercise selection.
- No server sync from the preview unless a later selected phase explicitly owns
  planned-workout mutation.
- No app-side workout PUT publisher exists today. Server-side workout mutation
  uses whole-tree replacement with last-write-wins semantics; when preview
  persistence is built, concurrency/freshness is a fresh decision rather than an
  inherited sync guarantee.
- No automatic start from card body tap.
- No Watch-specific layout here.

## Current gaps

- `TODAY-GAP-001`: The core preview-first entry path is built through Today's
  preview/detail sheet. A richer dedicated `WorkoutPreviewView` remains target
  behavior.
- `PREVIEW-GAP-001`: Preview editability is not proven for all target fields.
- `PREVIEW-GAP-002`: Preview edit persistence is not implemented. Any future
  publisher must be
  built against the server's whole-tree replacement contract and must decide how
  to handle stale local previews versus newer server workout trees.
- `PREVIEW-GAP-003`: Preview still uses Today's read-side block detail instead of directly
  importing `ExecutionProjection`; that preserves the feature-package boundary
  that only Shell may compose sibling features. Execution-side preview work now
  exposes a projection-backed work queue for current-block remaining and future
  work.
- `PREVIEW-GAP-004`: A dedicated `WorkoutPreviewView` and single preview sheet
  routing model are not yet extracted. Add this seam before expanding richer
  preview edits so Today does not absorb preview-specific interaction state.
- `TODAY-GAP-002`: Simulator proof is required before any preview tap target or
  layout claim is marked `verified`.

## QA scenarios

### S1. Card body opens preview

- **setup:** at least one planned workout is visible on Today.
- **steps:** tap the workout card body.
- **expected:** preview opens; no session timer starts; execution route remains
  inactive.

### S2. Explicit Start begins execution

- **setup:** preview is open for a valid planned workout.
- **steps:** tap `Start`.
- **expected:** execution starts once; Today does not also fire a duplicate
  start action.

### S3. Current-block remaining is visible

- **setup:** workout has multiple sets in the first block and later blocks.
- **steps:** open preview.
- **expected:** preview shows the first block's remaining work before future
  blocks.

### S4. Edit value before start

- **setup:** weighted exercise with editable prescription.
- **steps:** open preview -> edit the starting load through SetEditSheet ->
  Start.
- **expected:** execution seeds with the edited load and the edit is marked as
  user/manual setup, not autoreg.

### S5. Tap targets under simulator

- **setup:** simulator at smallest supported phone size.
- **steps:** open Today, preview, and Start.
- **expected:** card body, close, edit, and Start targets are reachable and do
  not overlap.
