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
| [firstrun](firstrun.md) | URL+token entry, validate, kick off first pull | ✅ Tested + MCP-validated at bug-048 scope boundary |
| [bootstrap](bootstrap.md) | Pull → cache → build VMs → wire push flusher | ✅ Tested; MCP E2E validated 2026-04-18 |
| [today](today.md) | Show the picked workout's card + start button | ✅ Tested (last-session chip + `lastPerformed` remain pass-through stubs — `PullService.lastPerformed` is returned by sync but not threaded through `AppBootstrap` into `TodayLoader`) |
| [execute-loop](execute-loop.md) | Log sets, rest timer, autoreg banner, advance | ✅ Validated (straight_sets); tested (other 10 modes) |
| [timing-modes](timing-modes.md) | 11 declared timing modes drive the Execute loop | ✅ All 11 drivers built + tested |
| [autoreg](autoreg.md) | Per-item RIR/rep-driven load adjustments, accept/undo | ✅ Validated (overshoot) / tested (other branches); negative-load floor shipped |
| [save-and-done](save-and-done.md) | Finalize workout: note + bw, local cache, status push | ✅ Tested; bodyweight + note capture shipped |
| [history](history.md) | Completed workouts list, session detail, by-exercise view | ✅ Tested; edit sheet + bodyweight chip shipped |
| [exercise-swap](exercise-swap.md) | Substitute alternative exercise mid-workout | ✅ Validated; long-press UI shipped; sets-override drop on round-robin + telemetry |
| [past-set-edit](past-set-edit.md) | Tap past set to correct load/reps/RIR | ✅ Tested; same-UUID upsert; History edit sheet shipped |
| [persistence](persistence.md) | Live session survives backgrounding/relaunch | ✅ Tested; V3 migration + subtree reconcile + normalization pass |
| [push-queue](push-queue.md) | Durable queue for set_logs, status, telemetry events | ✅ Tested; backoff, dead-letter, priority FIFO, dedup |
| [telemetry](telemetry.md) | Structured event log, local-first, lazy sync to server | ✅ Tested; typed payloads; 90-day server retention |

**Legend:** ✅ built and tested. See the feature doc for scenario-level coverage and any known gaps.

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
