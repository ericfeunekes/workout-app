---
title: Phase 6 — history post-workout correction implementation plan
status: completed
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

Add full-field post-workout correction for logged sets inside the current
provenance contract: same logical set-log row, same UUID, overwrite in place,
no field-diff audit trail. Covered fields include duration, distance, load,
reps, RIR, notes, skipped state, and any shipped side field only as an explicit
round-trip field, not the primary unilateral authoring model.

## Boundaries Touched

- History session detail and trend surfaces.
- Persistence queries and update paths for edited logs.
- Sync push queue idempotent edited-log behavior.
- Shared SetEditSheet contract from Phase 4.
- Current non-audit-grade provenance contract for edited set logs.

## Dependencies And Preconditions

- Phase 2 schema fields are landed.
- Phase 4 SetEditSheet contract exists.
- Phase 5 creates real skipped logs to display and correct.
- Unilateral work is exercise-level unless a later taxonomy phase promotes a
  stronger canonical link. Do not build Phase 6 aggregation around `set_log.side`
  by default.
- Audit-grade provenance is deferred unless D2 is explicitly promoted before
  implementation starts.

## Uncertainty Reduction Summary

- Architecture/history: past-set edit already preserves same UUID and avoids
  autoreg; this phase extends field coverage.
- Blast radius: edited history logs must not duplicate server rows.
- Contract/testing: persistence and sync idempotency tests are mandatory.

## Approach

Extend the existing past-edit path rather than inventing a separate history
mutation model. Keep corrections explicit and idempotent by set log ID, and be
honest that the current server contract is overwrite-without-field-diff.

## Steps

1. Expand history detail read model for all logged fields.
   **Done for set-log fields in this phase scope.**
2. Wire SetEditSheet into history corrections.
   **Done through the shared DesignSystem edit intent and History visual
   adapter.**
3. Add readable unilateral display using exercise-level identity; only use
   `set_log.side` as an explicitly authored/round-tripped field if present.
   **Done without using `set_log.side` as the aggregation model.**
4. Add skipped log display/correction.
   **Done; skipped corrections clear performance metrics and skipped-only rows
   are excluded from by-exercise aggregates.**
5. Add duration/distance/carry correction.
   **Done for logged set rows through History correction.**
6. Preserve same UUID on push for every correction.
   **Done.**
7. Add persistence/sync/history tests and simulator QA.
   **Done.**

## Progress

- 2026-04-26 — History set-row correction complete for load/unit, reps,
  duration, distance, RIR set/clear, skipped/performed state, side round-trip,
  and notes. The History sheet emits the shared `SetEditIntent`; the view model
  overwrites the existing set-log row by stable ID, emits telemetry, pushes the
  edited row, and reloads.
- 2026-04-26 — Skipped-row semantics corrected. Marking a historical row
  skipped clears performance metrics, skipped rows render as `SKIPPED`, and
  skipped-only exercises do not appear in by-exercise picker/trend aggregates.

## Good

- After a workout, any materially wrong log field can be corrected.
- Corrections do not rerun autoreg or mutate workout prescriptions.
- Unilateral history is readable without corrupting aggregate trends.
- The UI does not imply audit-grade edit history that the schema cannot support.

## Done

- History correction covers all fields in the phase scope.
- Edited logs upsert by existing set log ID.
- Current gaps name that corrections are same-row overwrite and not audit-grade.
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
- Reopen condition: edit creates a new log ID, unilateral aggregation lies, or
  the UI implies audit-grade provenance without schema support.

## Closeout

- Update history feature doc and gap map. **Done.**
- Note any remaining analysis/reporting gaps separately from correction gaps.
  **Done.**
- Add current gaps for audit-grade provenance:
  - no `set_log.updated_at`;
  - no field-diff telemetry event;
  - no durable History edit log;
  - event-log retention is not enough to reconstruct corrections indefinitely.
  **Done.**
- FeaturesHistory package tests: 48 passed.
- Persistence package tests: 57 passed.
- DesignSystem executable test harness: 15 passed.
- Sync executable test harness: 37 passed.
- iOS simulator QA: completed a workout, edited a History row to skipped,
  observed the row render as `SKIPPED`, and confirmed the skipped-only exercise
  left the by-exercise picker.
- Final Codex review: `019dcc18-01af-7ef0-9a81-11d9cb0a4b2c`.

## Recovery Context

This phase is correction/history only. In-workout active/rest behavior should
already be closed or remain in Phase 5.

## Residual Uncertainty / Accepted Risks

- Longitudinal analytics for unilateral asymmetry may remain basic.
  - Accepted if raw history is correct and not misleading.
  - Signal: trend chart combines left/right in a way that hides asymmetry.
- Post-workout correction remains same-row overwrite.
  - Accepted for this phase because this is a single-user app and raw
    correction accuracy matters before audit reconstruction.
  - Signal: user or reviewer needs to distinguish in-the-moment skip/log state
    from retroactive correction after telemetry retention expires.

## Escalation Triggers

- Existing local history cannot be safely migrated or corrected by same UUID.
- Sync endpoint semantics reject corrected duplicate IDs.
- Phase scope is promoted to audit-grade provenance; that requires a sibling
  schema/API/telemetry unit before History UI claims it.
