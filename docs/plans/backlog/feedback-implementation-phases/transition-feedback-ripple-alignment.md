---
title: Transition — feedback ripple alignment
status: historical source material
last_reviewed: 2026-05-17
purpose: Historical record of feedback-ripple planning findings that have been routed into current feature gaps and docs.
covers:
  - scratch/feedback-ripple-phase-updates.md
  - docs/plans/backlog/feedback-implementation-phases/
  - docs/features/
  - docs/open-questions.md
  - docs/prescription.md
  - docs/set-edit-sheet.md
---

# Transition — Feedback Ripple Alignment

> Historical/source-material note: this transition is retained for provenance.
> Future work must start from current feature/aspect docs and
> `docs/feature-gap-map.md`, not from this plan's imperative language.

## Unit Statement

Record the feedback-ripple investigation's planning corrections: side semantics
are exercise-level, audit-grade edit provenance is deferred, Phase 1's verify
sweep was separated, and workout-tree replacement does not preserve old set logs
today.

This transition existed because the findings landed after several numbered
phases had already closed. The durable requirements now live in the owning
feature/aspect docs and `docs/feature-gap-map.md`.

## Decisions

- **D1 — `set_log.side`: keep the shipped field, but do not make it the active
  authoring model.** Unilateral work is authored as separate exercise/workout
  items such as `DB Row (Left)` and `DB Row (Right)`. `set_log.side` is a
  shipped/reserved round-trip field. No UI, grouping, or analytics should infer
  per-side behavior from it until a later phase deliberately promotes that
  field.
- **D2 — audit trail: name the limit and defer the structural fix.** Phase 6
  may correct all materially editable fields by overwriting the existing
  logical set-log row. It is not audit-grade. `set_log.updated_at`,
  field-diff telemetry, and a history-side edit log are a separate structural
  unit if the need is promoted later.
- **H2 — orphan preservation: do not mark resolved as preservation.** Current
  server tree replacement deletes old blocks/items and cascades their set logs.
  That answers the current behavior but does not preserve orphaned set logs. If
  preservation is desired, it needs its own schema/API decision.

## Boundaries Touched

- Phase plans and feature docs only.
- No server, schema, SwiftData, Sync, Execution, History, or Watch code.
- No migration 009 for `set_log.side`.
- No audit-trail schema work.

## Historical steps

These were the intended cleanup steps at the time:

1. Update Phase 1 with a transition note: the original docs pass is closed, but
   the `[verify]` sweep and targeted doc narrowings are transition work.
2. Update Phase 2 and the old schema-cutover plan so `set_log.side` is described
   as shipped/reserved, not the active per-side authoring model.
3. Update Phase 4 and SetEditSheet wording from a uniform editor to a shared
   shell/model with mode-specific editor families and per-context persistence.
4. Update Phase 5 closeout wording so completed work is not reopened, while
   per-side/history parity remains downstream.
5. Update Phase 6 wording: full-field correction is scoped
   to the current same-row overwrite provenance contract.
6. Update feature docs and registers:
   - `docs/features/workout-preview.md`: app-side workout PUT publisher does
     not exist; concurrency/freshness is a future decision.
   - `docs/set-edit-sheet.md`: shared shell plus mode-specific editor families.
   - `docs/features/history.md` and `docs/features/past-set-edit.md`: same-row
     overwrite is not audit-grade.
   - `docs/prescription.md`: unilateral authoring uses exercise-level identity.
   - `docs/features/execute-loop.md`: avoid uniform SetEditSheet claims where
     mode-specific editors are required.
   - `docs/open-questions.md`: H2 records current cascade-delete behavior and
     the separate preservation decision.
7. Schedule the `[verify]` sweep as its own timeboxed session. Do not bury it in
   this transition edit. Tracking plan:
   `docs/plans/backlog/feedback-verify-sweep-2026-04-25.md`.

## Good

- A reviewer can see which phase is truly done and which doc/proof cleanup is
  still pending.
- Phase 6 cannot be interpreted as audit-grade unless D2 is explicitly
  promoted.
- Per-side behavior is not accidentally built on `set_log.side`.
- The orphan-preservation question is not incorrectly closed.

## Done

- D1/D2/H2 dispositions are reflected in the numbered phase plans and affected
  feature docs.
- The old skipped/side/intent schema plan is marked superseded by Phase 2.
- Phase 6 explicitly scopes correction to same-row overwrite and lists
  audit-trail provenance as a current gap/deferred structural unit.
- `[verify]` sweep remains visible as a standalone follow-up with owner, proof
  shape, and timebox.
- Independent review has checked that this transition did not reopen completed
  app work or silently add new implementation scope.

## Proof Map

- Check: documentation diff review.
  - Boundary: planning contract.
  - Proves: no phase overclaims side semantics, audit provenance, or orphan
    preservation.
  - Expected: clean.
- Check: `uv run .codex/skills/documentation-maintenance/scripts/check_docs.py docs`.
  - Boundary: docs hygiene.
  - Proves: links and docs conventions remain valid.
  - Expected: pass.
- Check: independent Codex review before committing.
  - Boundary: external planning review.
  - Proves: stale assumptions and accidental scope expansion are caught.
  - Expected: clean or findings patched.

## Recovery Context

Start from `scratch/feedback-ripple-phase-updates.md`, but apply the corrections
from the 2026-04-26 review: Phase 5 is already completed, `set_log.side` is not
the authoring model, and cascade delete is not orphan preservation.
