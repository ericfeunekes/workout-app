---
title: Features — index
status: living
last_reviewed: 2026-04-26
purpose: Single entry point for per-feature behavioral contracts + QA scenarios.
covers:
  - docs/features/*.md
---

# Features

This directory holds one doc per user-visible feature. Each doc is a **target behavioral contract + QA scenarios**: how the feature is supposed to work, the edge cases that matter, the proof expected from tests or simulator QA, and the current gaps between that target and the implementation.

Authoritative spec content (data model, timing-mode shapes, sync protocol) still lives in `docs/specs/`, `docs/prescription.md`, `docs/sync.md`. These feature docs cross-reference those — they don't duplicate.

## Status model

Feature-doc status is allowed to describe target behavior, not only shipped behavior.

| Status | Meaning |
|---|---|
| `planned` | Target contract is documented; implementation or proof is missing. |
| `building` | Implementation is in progress or partly merged; proof is incomplete. |
| `built` | Implementation exists and is covered by local tests. |
| `verified` | Implementation is proven with the required external check. See `../QA.md` for accepted proof artifacts. |

Each rewritten feature doc should use `Current gaps` for target-contract pieces that are not implemented or not yet proven. Cross-feature sequencing lives in `../feature-gap-map.md`.

## Reading order for a cold start

1. `bootstrap.md` — how the app gets to a usable state after launch
2. `today.md` — what the user sees first
3. `execute-loop.md` — the heart: log a set, rest, advance
4. `autoreg.md` — the load-adjustment rules layered on execute-loop
5. `save-and-done.md` — how a session terminates
6. `history.md` — what you see after the fact
7. Everything else — touched by the above, covered for completeness

## Feature list

| Feature | One-line summary | Status |
|---|---|---|
| [firstrun](firstrun.md) | URL+token entry, validate, kick off first pull | verified at bug-048 scope boundary |
| [bootstrap](bootstrap.md) | Pull -> cache -> build VMs -> wire push flusher | verified 2026-04-18 |
| [today](today.md) | Show the local plan queue, selected workout, preview entry, and refresh | built with current gaps |
| [workout-preview](workout-preview.md) | Preview a selected workout and make Start explicit before execution | planned |
| [execute-loop](execute-loop.md) | Log sets, rest timer, autoreg banner, advance | built with current gaps |
| [block-transition](block-transition.md) | Between-block setup surface before entering the next block | planned |
| [timing-modes](timing-modes.md) | 12 declared timing modes drive the Execute loop | built + tested |
| [autoreg](autoreg.md) | Per-item RIR/rep-driven load adjustments, accept/undo | built + tested |
| [save-and-done](save-and-done.md) | Finalize workout: note + bodyweight, local cache, status push | built + tested |
| [history](history.md) | Completed workouts list, session detail, by-exercise view | built with current gaps |
| [exercise-swap](exercise-swap.md) | Substitute alternative exercise mid-workout | built + tested |
| [past-set-edit](past-set-edit.md) | Tap past set to correct logged values | built with current gaps |
| [persistence](persistence.md) | Live session survives backgrounding/relaunch | built + tested |
| [push-queue](push-queue.md) | Durable queue for set_logs, status, telemetry events | built + tested |
| [telemetry](telemetry.md) | Structured event log, local-first, lazy sync to server | built + tested |

## How to use these for QA

1. Pick a feature doc.
2. Walk the scenario list. Each scenario is a self-contained case — setup, steps, expected, optional notes.
3. Drive it against a running simulator (XcodeBuildMCP or manual). Observe against the "expected" line.
4. If you find a gap, file defects in `docs/bugs.md`; use `docs/open-questions.md` only for unresolved product or design decisions. Link back to the scenario ID.
5. For ambitious passes, run a persona agent (coach, athlete, impatient user) across multiple docs; cross-reference their report with the server-side telemetry event log.

## Maintenance rules

- If a feature's intended behavior changes, update its doc in the same commit. If implementation lags the target, add or update `Current gaps` and `../feature-gap-map.md`.
- Don't split a feature into two files — if the scenario list exceeds ~25, the feature is too broad; split *the feature*, not the doc.
- When a scenario is proven by a test, add `(tested: <test_name>)` next to its header so future readers know what's backstopped.
- Keep under ~200 lines per doc. Length is a smell.
