---
title: Feedback verify sweep — 2026-04-25
status: backlog
last_reviewed: 2026-04-26
purpose: Timeboxed proof sweep for feedback items that need code, simulator, or UI-test evidence before docs can mark them resolved.
covers:
  - FEEDBACK-AND-SPEC-2026-04-25.md
  - docs/feature-gap-map.md
  - docs/features/
---

# Feedback Verify Sweep — 2026-04-25

## Unit Statement

Run the outstanding `[verify]` sweep from the feedback docs pass as its own
proof task. The sweep records which feedback items are resolved, open, or
inconclusive and attaches an evidence type for each.

## Scope

- Start from the unresolved `[verify]` items in
  `FEEDBACK-AND-SPEC-2026-04-25.md` plus the feedback-ripple additions noted in
  `scratch/feedback-ripple-phase-updates.md`.
- Use the output shape:

| item | state | proof_type | evidence_ref |
|---|---|---|---|
| P0-1 | resolved / open / inconclusive | code_inspection / test_result / simulator_observation / ui_test / inspection_inconclusive | file:line, test name, QA run, or screenshot |

## Proof Rules

- Code inspection can resolve pure logic/routing questions only.
- Visual, tap-target, contrast, and timer-flow items need simulator observation
  or a pinned UI test before they can be marked resolved.
- If a single item exceeds its cap, mark it `inspection_inconclusive` and move
  on.

## Timebox

- Total cap: 2 hours.
- Per item: 15 minutes for logic/code items, 10 minutes for visual or
  tap-target items.

## Done

- Sweep results are appended to `FEEDBACK-AND-SPEC-2026-04-25.md`.
- Any changed state is mirrored into the owning feature doc's `Current gaps`
  section and `docs/feature-gap-map.md`.
- Items requiring simulator proof have QA artifacts under `scratch/qa-runs/` or
  remain open.
