---
title: Phase 10 — in-app Claude chat design implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Keep in-app Claude/chat as a separate future design surface instead of collapsing it into history notes.
covers:
  - docs/open-questions.md
  - docs/design/in-app-chat.md
  - docs/features/history.md
---

# Phase 10 — In-App Claude / Chat Design

## Unit Statement

Design the future in-app Claude/chat workflow as its own surface for workout
context, proposed edits, accepted/rejected changes, and notes integration.

## Boundaries Touched

- Product design docs and open questions.
- Future server/API contract for proposed edits.
- History notes only as an input/output, not the owner.

## Dependencies And Preconditions

- Phases 2-6 clarify the workout/log correction model.
- Watch phases do not depend on this.
- No implementation should begin until the design doc settles acceptance
  criteria.

## Approach

Run this as `collaboration:interview` plus `scoping:requirements-planning`
first, then create phase or implementation plans for selected slices. Do not
sneak chat behavior into history notes.

## Steps

1. Create `docs/design/in-app-chat.md`.
2. Define user workflows: ask about current workout, propose edit, accept/reject,
   add note, send context to Claude.
3. Define data contracts for proposals and accepted changes.
4. Identify trust and safety boundaries for app-originated edits.
5. Decide whether server needs a new endpoint or whether conversation remains
   outside app v1.
6. Produce future implementation plans only after the design is accepted.

## Good

- Chat is clearly distinct from notes and history correction.
- Proposed changes are inspectable before application.
- The app remains dumb: Claude proposes; app applies explicit accepted changes.

## Done

- Design doc exists with acceptance criteria and non-goals.
- Feature gap map points here for #24.
- No app code is changed in this phase unless a follow-on implementation plan is
  created.

## Proof Map

- Check: design review against feedback #24.
  - Boundary: instruction/product artifact.
  - Proves: workflow is preserved and not collapsed into notes.
- Check: architecture review of proposed data flow.
  - Boundary: trust/data ownership.
  - Proves: app does not become a programming agent.
- Check: independent Codex challenge.
  - Boundary: planning artifact.
  - Proves: hidden trust/scope issues are surfaced.

## Independent Review

- Artifact: `docs/design/in-app-chat.md`.
- Reviewer: Codex challenge/review.
- Reopen condition: design allows unreviewed Claude changes or duplicates
  history edit behavior.

## Closeout

- Update `docs/open-questions.md`, `docs/feature-gap-map.md`, and any future
  feature spec links.

## Recovery Context

This is a design phase, not implementation. If scope becomes concrete, split it
into new implementation-planning phases.

## Residual Uncertainty / Accepted Risks

- Actual Claude integration mechanism remains undecided.
  - Accepted because this is future design.
  - Signal: user asks to build chat before proposal acceptance rules exist.

## Escalation Triggers

- User wants app-side autonomous editing without explicit acceptance.
- Proposed design requires app to perform programming logic.
