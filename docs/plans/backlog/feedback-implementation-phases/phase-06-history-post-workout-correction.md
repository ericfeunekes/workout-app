---
title: Phase 6 — history post-workout correction implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Implement full post-workout correction and history display parity after the execution schema and edit contract are stable.
covers:
  - app/Packages/Features/History/
  - app/Packages/Persistence/
  - app/Packages/Sync/
  - docs/features/history.md
  - docs/set-edit-sheet.md
---

# Phase 6 — History And Post-Workout Correction

## Unit Statement

Add full-field post-workout correction for logged sets, including per-side,
duration, distance, load, reps, RIR, notes, and skipped state.

## Boundaries Touched

- History session detail and trend surfaces.
- Persistence queries and update paths for edited logs.
- Sync push queue idempotent edited-log behavior.
- Shared SetEditSheet contract from Phase 4.

## Dependencies And Preconditions

- Phase 2 schema fields are landed.
- Phase 4 SetEditSheet contract exists.
- Phase 5 creates real skipped/per-side logs to display and correct.

## Uncertainty Reduction Summary

- Architecture/history: past-set edit already preserves same UUID and avoids
  autoreg; this phase extends field coverage.
- Blast radius: edited history logs must not duplicate server rows.
- Contract/testing: persistence and sync idempotency tests are mandatory.

## Approach

Extend the existing past-edit path rather than inventing a separate history
mutation model. Keep corrections explicit and idempotent by set log ID.

## Steps

1. Expand history detail read model for all logged fields.
2. Wire SetEditSheet into history corrections.
3. Add per-side grouping and aggregate display rules.
4. Add skipped log display/correction.
5. Add duration/distance/carry correction.
6. Preserve same UUID on push for every correction.
7. Add persistence/sync/history tests and simulator QA.

## Good

- After a workout, any materially wrong log field can be corrected.
- Corrections do not rerun autoreg or mutate workout prescriptions.
- Per-side history is readable without corrupting aggregate trends.

## Done

- History correction covers all fields in the phase scope.
- Edited logs upsert by existing set log ID.
- Simulator QA proves correction from History detail.

## Proof Map

- Check: History view-model/edit tests.
  - Boundary: user-facing view model.
  - Proves: edit sheet produces correct correction payloads.
  - Expected: pass.
- Check: Persistence tests with real SwiftData store.
  - Boundary: persistence.
  - Proves: corrected rows survive reload and keep UUID.
  - Expected: pass.
- Check: Sync push queue tests.
  - Boundary: cross-module/server contract.
  - Proves: edited set log reuses ID and queues one upsert payload.
  - Expected: pass.
- Check: simulator QA.
  - Boundary: user-facing.
  - Proves: History correction workflow is usable.

## Independent Review

- Artifact: History/Persistence/Sync diff and QA evidence.
- Reviewer: Codex focused on duplicate logs, lost local history, and aggregate
  misrepresentation.
- Reopen condition: edit creates a new log ID or per-side aggregation lies.

## Closeout

- Update history feature doc and gap map.
- Note any remaining analysis/reporting gaps separately from correction gaps.

## Recovery Context

This phase is correction/history only. In-workout active/rest behavior should
already be closed or remain in Phase 5.

## Residual Uncertainty / Accepted Risks

- Longitudinal analytics for per-side asymmetry may remain basic.
  - Accepted if raw history is correct and not misleading.
  - Signal: trend chart combines left/right in a way that hides asymmetry.

## Escalation Triggers

- Existing local history cannot be safely migrated or corrected by same UUID.
- Sync endpoint semantics reject corrected duplicate IDs.
