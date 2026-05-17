---
title: SetEditSheet
status: built
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

`SetEditSheet` is the shared shell and intent model for editing workout values.
It should feel like one surface while allowing mode-specific editor families for
strength rows, scored work, cardio targets, carries, and other timing-mode
shapes.

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
- side, only when an explicit caller owns that shipped/reserved field
- distance
- duration
- skipped/performed state for logged rows
- notes
- carry/load-plus-distance details

Fields that do not apply to the source prescription should be absent, not
disabled filler.

Editor families are mode-specific. Straight sets, supersets, and circuits can
share a strength-style editor. EMOM, intervals, continuous, accumulate, Tabata,
custom, scored, rest, and loaded carry contexts need explicit field families or
documented current gaps; do not force them through one visual form just because
the shell/model can express the fields.

## Invariants

- Past corrections mark the row manual and never retrigger autoreg.
- History edits update the existing logical set log instead of creating a
  duplicate row.
- History edits are same-row overwrite under the current schema. They do not
  create an audit-grade field-diff trail unless a later structural unit adds
  that provenance.
- `side` is not user-authored from this sheet. Per D1, unilateral work is
  authored as separate exercise items rather than by toggling `set_log.side`.
- Leaving a field untouched preserves the existing value.
- Clearing a value is explicit when the field supports it.
- Marking a row skipped preserves `weightUnit`. The stored unit belongs to the
  prescription-side row semantics, not the performed metrics.
- Moving a row from skipped to performed requires at least one metric (`reps`,
  `load`, `duration`, or `distance`) before the edit can save.
- The sheet emits edit intents; callers own persistence and sync side effects.

## Deliberate non-goals

- No workout programming or exercise selection.
- No completed past-log "this and all future sets" scope. For preview/future and
  active setup edits, the target contract includes explicit apply scope for the
  current row versus remaining future rows of the same authored item.
- No Watch UI; Watch surfaces consume the result of edits, not this sheet.

## Current gaps

- `SETEDIT-GAP-001`: Existing visual edit surfaces are still split across
  preview/detail, active rest pills, and the History `EditSetSheet`.
- `SETEDIT-GAP-002`: Apply-to-remaining scope for preview/future and active
  setup edits is not yet implemented or proven.
- `SETEDIT-GAP-003`: Bodyweight remains contract-level and display-level only
  for History; editing it is a separate `user_parameters` correction problem.
- `SETEDIT-GAP-004`: Distance, duration, side, skipped state, notes, and
  carry/load-plus-distance are contract-tested at the shared model layer and
  proven in History where they are set-log fields. They still need visual proof
  across all mode-specific active and preview contexts, including small-phone
  layout and disabled/available field contrast.
- `SETEDIT-GAP-005`: The shared contract is still stronger than the shared
  presentation. Preview, Active, Complete, and History need one sheet-routing
  and presentation model so mode-specific editor families do not drift.

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
