---
title: QA
status: accepted
last_reviewed: 2026-04-26
purpose: How exploratory, simulator, and visual QA findings are recorded without creating duplicate issue trackers.
covers:
  - docs/bugs.md
  - scratch/qa-runs/
  - app/
---

# QA

WorkoutDB uses QA runs to find real runtime issues in the iOS app and sync flow. QA evidence can be broad; issue tracking must stay narrow.

## Source of truth

- **Active issues:** `docs/bugs.md`.
- **Closed issues:** git history for `docs/bugs.md`, plus the regression test or invariant added by the fix.
- **Raw evidence:** `scratch/qa-runs/` while the run is active. This directory is gitignored and must not become a second bug tracker.

Do not keep durable issue lists in `scratch/`. A QA run can write temporary notes, screenshots, recordings, JSONL observations, and per-run reports there, but every still-open finding is migrated to `docs/bugs.md` before closeout. Once migration is done, scratch summaries that duplicate the bug list should be deleted or ignored.

## What Counts As A QA Issue

File an active bug when QA finds one of these:

- The app does not execute, log, sync, or render behavior promised by the spec or feature docs.
- A runtime workflow that Eric needs has no usable surface.
- A visible UX problem blocks first real use or makes a normal path risky.
- Simulator or visual evidence reveals a recurring instability, even if the underlying code path is not isolated yet.

Do not file a bug for a design decision that is still unresolved. Put that in `docs/open-questions.md` unless the app already promised the behavior.

## Evidence Standard

Each `docs/bugs.md` row should include the strongest practical evidence in the Notes column:

- **Runtime observation:** simulator state, server DB row, API response, app snapshot, or screenshot.
- **Test result:** failing test or reproducible command output.
- **Code inspection:** exact file or behavior that explains the issue.
- **Spec mismatch:** feature/spec section that promised different behavior.

Use absolute dates for QA sessions when relevant. For example, a missed-workout finding should say `2026-04-22` rather than "yesterday."

## What `verified` Means

Feature docs use `verified` only when the behavior has external proof beyond
code inspection. Acceptable proof artifacts are:

- A pinned UI test or XCUITest that runs in CI.
- A simulator QA run under `scratch/qa-runs/` with a stable run ID, steps,
  expected result, observed result, and screenshots or recording.
- An MCP-driven simulator walk recorded under `scratch/qa-runs/` with the same
  steps, observed state, and screenshot or recording evidence.

UI, layout, contrast, tap-target, and timer-flow behavior cannot be promoted to
`verified` from source inspection alone. High-risk timing surfaces need both the
best practical automated proof for logic and simulator proof for the visible
flow. Schema cutovers need migration, parity, and contract-test proof; simulator
QA only verifies the user-facing behavior that depends on the schema.

## Closeout Rule

At the end of a QA run:

1. Add or update `docs/bugs.md` rows for every still-open issue.
2. Delete or ignore scratch-level bug summaries that duplicate `docs/bugs.md`.
3. Keep raw screenshots, recordings, and per-run reports only as evidence artifacts.
4. If a fix closes a row, remove it from `docs/bugs.md` in the same change that adds the proof.

This keeps one active list while preserving enough evidence to reproduce serious findings.
