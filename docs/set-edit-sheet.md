---
title: SetEditSheet
status: planned
last_reviewed: 2026-04-26
purpose: Shared edit-surface contract for preview, active-session, and history corrections.
covers:
  - docs/features/workout-preview.md
  - docs/features/execute-loop.md
  - docs/features/past-set-edit.md
  - docs/features/history.md
---

# SetEditSheet

## Target behavior

`SetEditSheet` is the shared UI contract for editing workout values. It should
feel like one sheet even when different call sites expose different field sets.

The sheet is context-sensitive:

- **Preview/future setup:** edits values before they seed execution.
- **Active-session correction:** edits the just-logged or pending work item
  without changing workout programming.
- **History correction:** edits completed set/log fields after the workout.

## Field contract

The sheet must support these authored or logged values when the source context
allows them:

- load and unit
- reps
- RIR, including clear/unknown
- bodyweight
- side: `left`, `right`, `bilateral`
- distance
- duration
- carry/load-plus-distance details

Fields that do not apply to the source prescription should be absent, not
disabled filler.

## Invariants

- Past corrections mark the row manual and never retrigger autoreg.
- History edits update the existing logical set log instead of creating a
  duplicate row.
- Leaving a field untouched preserves the existing value.
- Clearing a value is explicit when the field supports it.
- The sheet emits edit intents; callers own persistence and sync side effects.

## Deliberate non-goals

- No workout programming or exercise selection.
- No completed past-log "this and all future sets" scope. For preview/future and
  active setup edits, the target contract includes explicit apply scope for the
  current row versus remaining future rows of the same authored item.
- No Watch UI; Watch surfaces consume the result of edits, not this sheet.

## Current gaps

- Existing edit surfaces are split across preview/detail, active rest pills, and
  history edit sheets.
- Apply-to-remaining scope for preview/future and active setup edits is not yet
  implemented or proven.
- Distance, duration, side, bodyweight, and carry fields do not have unified
  proof across active, preview, and history contexts.
- Visual proof is required for small-phone layout and disabled/available field
  contrast.

## QA scenarios

### S1. Past edit does not autoreg

- **setup:** logged strength set with autoreg available.
- **steps:** edit reps or RIR after the set is logged.
- **expected:** row changes, is marked manual, and no new autoreg proposal is
  generated.

### S2. History edit updates in place

- **setup:** completed workout in History.
- **steps:** edit a logged set and sync.
- **expected:** the existing set log is updated by stable identity; no duplicate
  set row appears.

### S3. Unsupported field absent

- **setup:** bodyweight exercise with no load field.
- **steps:** open SetEditSheet.
- **expected:** load editing is absent or represented as bodyweight-specific
  state; the user cannot accidentally turn bodyweight into a weighted set unless
  that is an authored field.

### S4. Carry field set

- **setup:** carry prescription with load and distance.
- **steps:** open the sheet from active or history context.
- **expected:** load and distance can be edited without losing either value.

### S5. Small phone layout

- **setup:** smallest supported simulator size.
- **steps:** open each supported field combination.
- **expected:** fields and commit/cancel controls do not overlap and remain
  reachable.
