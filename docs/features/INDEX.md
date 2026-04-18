---
title: Features — index
status: living
purpose: Single entry point for per-feature behavioral contracts + QA scenarios.
covers:
  - docs/features/*.md
---

# Features

This directory holds one doc per user-visible feature. Each doc is a **behavioral contract + QA scenarios** — what the CODE does today (not what specs wish it did), the edge cases, and a driveable scenario list that persona-based QA agents can execute against the running app.

Authoritative spec content (data model, timing-mode shapes, sync protocol) still lives in `docs/specs/`, `docs/prescription.md`, `docs/sync.md`. These feature docs cross-reference those — they don't duplicate.

## Reading order for a cold start

1. `bootstrap.md` — how the app gets to a usable state after launch
2. `today.md` — what the user sees first
3. `execute-loop.md` — the heart: log a set, rest, advance
4. `autoreg.md` — the load-adjustment rules layered on execute-loop
5. `save-and-done.md` — how a session terminates
6. `history.md` — what you see after the fact
7. Everything else — touched by the above, covered for completeness

## Feature list

| Feature | One-line summary | Status (2026-04-18) |
|---|---|---|
| [firstrun](firstrun.md) | URL+token entry, validate, kick off first pull | ✅ Built |
| [bootstrap](bootstrap.md) | Pull → cache → build VMs → wire push flusher | ✅ Built |
| [today](today.md) | Show the picked workout's card + start button | ✅ Built (last-session chip is pass-through stub) |
| [execute-loop](execute-loop.md) | Log sets, rest timer, autoreg banner, advance | ⚠️ Works for `straight_sets` only |
| [timing-modes](timing-modes.md) | 11 declared timing modes drive the Execute loop | ⚠️ **10 of 11 drivers are stubs** |
| [autoreg](autoreg.md) | Per-item RIR/rep-driven load adjustments, accept/undo | ✅ Built (no negative-load floor) |
| [save-and-done](save-and-done.md) | Finalize workout: note + bw, local cache, status push | ⚠️ Body-weight and note inputs not built |
| [history](history.md) | Completed workouts list, session detail, by-exercise view | ⚠️ Detail set-row edit stubbed |
| [exercise-swap](exercise-swap.md) | Substitute alternative exercise mid-workout | ⚠️ **No UI** — data path only |
| [past-set-edit](past-set-edit.md) | Tap past set to correct load/reps/RIR | ⚠️ **Local only, no server push** |
| [persistence](persistence.md) | Live session survives backgrounding/relaunch | ✅ Built |
| [push-queue](push-queue.md) | Durable queue for set_logs, status, telemetry events | ✅ Built (telemetry added 2026-04-18) |
| [telemetry](telemetry.md) | Structured event log, local-first, lazy sync to server | ✅ Built (emit coverage partial; see doc) |

**Legend:** ✅ built and tested — ⚠️ built partially, see the feature doc for specifics.

## How to use these for QA

1. Pick a feature doc.
2. Walk the scenario list. Each scenario is a self-contained case — setup, steps, expected, optional notes.
3. Drive it against a running simulator (XcodeBuildMCP or manual). Observe against the "expected" line.
4. If you find a gap, file it in `docs/open-questions.md` with a link back to the scenario ID (e.g. "autoreg S12 — no negative-load floor").
5. For ambitious passes, run a persona agent (coach, athlete, impatient user) across multiple docs; cross-reference their report with the server-side telemetry event log.

## Maintenance rules

- If a feature's behavior changes, update its doc in the same commit. Stale feature docs are worse than missing ones.
- Don't split a feature into two files — if the scenario list exceeds ~25, the feature is too broad; split *the feature*, not the doc.
- When a scenario is proven by a test, add `(tested: <test_name>)` next to its header so future readers know what's backstopped.
- Keep under ~200 lines per doc. Length is a smell.
