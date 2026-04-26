---
title: Phase 1 — feature docs contracts implementation plan
status: completed
last_reviewed: 2026-04-26
purpose: Convert feedback into target feature contracts, current gaps, proof rules, and downstream implementation phases.
covers:
  - docs/plans/active/feature-docs-feedback-contracts.md
  - docs/features/
  - docs/feature-gap-map.md
  - docs/QA.md
  - docs/prescription.md
---

# Phase 1 — Feature Docs Contracts

## Unit Statement

Convert the 2026-04-25 workout feedback into durable target-contract feature
docs, a feature-gap map, and proof rules that let later implementation phases
understand intended behavior, built behavior, and remaining gaps.

## Canonical Plan Relationship

The full implementation plan already exists and has been independently
reviewed:

- `docs/plans/active/feature-docs-feedback-contracts.md`

This file is the durable backlog copy of that phase. If Phase 1 resumes, refresh
the active plan and this phase together so the phase directory remains
standalone enough for later reviewers.

## Boundaries Touched

- Feedback synthesis and feature-doc doctrine.
- `docs/features/` target behavior contracts.
- `docs/feature-gap-map.md` feedback-to-gap routing.
- `docs/QA.md` proof vocabulary.
- `docs/prescription.md` authored workout vocabulary.
- Downstream implementation phase index.

## Dependencies And Preconditions

- Latest workout feedback and feature planning skill have been reviewed.
- Feature docs describe intended behavior, not only current implementation.
- Current gaps are allowed, but must be explicit and routed.

## Approach

Turn feedback into reviewable product contracts before implementation. The
output should let a reviewer answer whether a future phase is correct without
reverse-engineering the app.

## Steps

1. Sweep the feedback items and existing feature docs.
2. Lock the feature-doc doctrine: target behavior first, current gaps second.
3. Update affected feature docs with the intended behavior and current gaps.
4. Update `docs/feature-gap-map.md` so every feedback item has an owner,
   resolved state, current gap, later polish route, or future design route.
5. Update QA/proof vocabulary where feature docs use `verified`, simulator
   proof, real-device proof, or agent review.
6. Update prescription docs for block intent, side/carry/duration/distance, and
   authored vocabulary needed by downstream phases.
7. Create or refresh downstream implementation phases for every open gap.

## Good

- Feature docs describe target behavior, not only current code.
- Unimplemented or unproven behavior appears as `Current gaps`.
- `docs/feature-gap-map.md` maps each feedback item to a current gap, resolved
  item, later polish, or future design route.
- `docs/QA.md` defines what `verified` means.
- `docs/prescription.md` owns block intent, unilateral authoring, and
  per-implement load vocabulary.
- No feedback item is left orphaned because it feels like "later."

## Done

- Active plan milestones are checked.
- Proof map in the active plan has run.
- Independent Codex review is clean.
- Downstream phases in this directory remain aligned with the final gap map.
- Reviewers can use feature docs and the gap map to judge later plans without
  reading implementation code first.

## Proof Map

- Check: compare feedback item list against `docs/feature-gap-map.md`.
  - Boundary: documentation contract.
  - Proves: every feedback item is routed.
  - Expected: no missing feedback IDs.
- Check: targeted content review of updated feature docs.
  - Boundary: product contract.
  - Proves: docs describe intended behavior and current gaps.
  - Expected: no doc claims current behavior is complete without proof.
- Check: `uv run .codex/skills/documentation-maintenance/scripts/check_skill_links.py docs/features docs/plans/backlog/feedback-implementation-phases`.
  - Boundary: documentation hygiene.
  - Proves: skill links remain valid.
  - Expected: pass.
- Check: independent Codex review.
  - Boundary: external review.
  - Proves: missing routing, overclaims, and proof gaps are found before coding.
  - Expected: clean or real findings patched.

## Independent Review

- Artifact: feature docs, gap map, QA/prescription updates, and phase index.
- Reviewer: Codex review focused on orphaned feedback, false completion claims,
  and missing proof vocabulary.
- Reopen condition: any feedback item lacks a route, or any feature doc claims
  a behavior is done without proof.

## Closeout

- Leave the active plan and this phase aligned.
- Ensure downstream phases own each remaining current gap or future design
  route.
- Phase 1 closed in `docs/plans/active/feature-docs-feedback-contracts.md` with
  docs checks and Codex review complete.
- Feedback-ripple follow-up, captured after this phase closed, found transition
  cleanup that should not reopen Phase 1 implementation:
  - the `[verify]` sweep remains owed as its own timeboxed session;
  - stale per-side wording must be reframed around exercise-level unilateral
    authoring;
  - feature docs must avoid implying audit-grade edit provenance until that
    structural unit exists.
  The owning plan is
  `docs/plans/backlog/feedback-implementation-phases/transition-feedback-ripple-alignment.md`.

## Recovery Context

Resume from `docs/plans/active/feature-docs-feedback-contracts.md`, then check
this file for the durable phase contract and downstream phase alignment. If the
feedback-ripple transition is still open, complete or explicitly defer it before
Phase 6 or Watch work continues.
