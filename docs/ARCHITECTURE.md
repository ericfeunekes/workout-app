---
title: Architecture
status: accepted
last_reviewed: 2026-05-17
purpose: One-page system map + domain router. Summarizes the shape; routes to the spec and per-package READMEs for detail.
covers:
  - docs/
  - server/
  - app/
  - schema/
---

# Architecture

Top-level system map for WorkoutDB. The canonical, detailed reference is `docs/specs/v2-architecture.md` — this file routes to it and summarizes the shape.

## Philosophy

**Dumb app, smart conversation.** The app does three things: show the workout, time it, log what happened. All intelligence — programming, periodization, progression, alternatives, readiness — lives in conversation with Claude and arrives in the app as data.

## System shape

```
┌────────────────────┐
│  Claude            │   (conversation)
│  (programming,     │
│   progression,     │
│   readiness)       │
└──────┬─────────────┘
       │ pushes plans, exercises,
       │ alternatives, user_parameters
       ▼
┌────────────────────┐
│  Home server       │   server/
│  FastAPI + SQLite  │
│  (REST API, sync)  │
└──────┬─────────▲───┘
 pulls │         │ pushes set_logs,
 plans │         │ status changes
       ▼         │
┌────────────────────┐
│  iOS app           │   app/
│  SwiftData         │
│  (show, time, log) │
└────────────────────┘
```

## Domains

### `server/` — Home server
Python + FastAPI + SQLite. The exchange layer. Owns:
- Schema (mirrors SwiftData in `app/`)
- REST endpoints for plans, exercises, user_parameters, results push, sync pull
- Single-user bearer-token auth
- Idempotent migrations under `server/db/migrations/`

See `server/README.md` and spec § "API contract".

### `app/` — iOS app
Swift + SwiftData. The "dumb" client. Owns:
- Workout execution UI (show prescription, drive the right timer per `timing_mode`)
- Set logging
- Pull-to-refresh and queued push (works fully offline)
- Percentage-based load resolution via `user_parameters`

Runs the 12 timing modes: `straight_sets`, `superset`, `circuit`, `emom`, `amrap`, `for_time`, `intervals`, `tabata`, `continuous`, `accumulate`, `custom`, `rest`. Applies client-side autoregulation based on per-item `target_rir` and `autoreg` rules. See `app/README.md` for the in-app behavior contract, `docs/workout-generation.md` for the end-to-end workout authoring workflow, `docs/prescription.md` for the per-mode prescription shapes, and `docs/sync.md` for sync + first-run behavior.

### `schema/` — Shared schema
Single source of truth for cross-stack data contracts. Committed `openapi.json` is the wire contract; hand-written Swift Codable DTOs under `Sources/WorkoutDBSchema/` mirror the server's Pydantic schemas. Cross-decoded fixtures live in `fixtures/`. See `schema/README.md`.

### `tests/` — Cross-cutting tests
Server tests under `tests/server/`. Contract tests that pin cross-stack schema parity under `tests/contract/` (OpenAPI drift, Swift enum parity, fixture round-trips on both sides).

## Data model (summary)

Core principle: **composition with timing**. Everything is blocks; a block has a `timing_mode` and contains exercises or nested blocks.

This is the current implemented pre-primitives baseline. Entities: `app_user`,
`exercise`, `exercise_alternative`, `block`, `workout_item`, `workout`,
`set_log`, `user_parameters`. UUIDs everywhere.

See spec § "Data model" for field-level definitions. Target data-model
planning for new work starts from `docs/specs/primitives-data-model.md`.

## Sync model

Direction-based, no conflict resolution:
- Server → app: workouts, exercises, alternatives, user_parameters, `last_performed` snapshots
- App → server: set_logs, workout status changes, body-weight-at-completion (as a `user_parameters` row)

Cadence: on app open + on log write + ~60s foreground retry. Conflict rule: server wins for prescriptions, app wins for logs, live session is frozen. First-run: connection string (URL + bearer token) via paste or QR — no login surface.

See `docs/sync.md` for the full rules, and the spec § "Persistence architecture" for the entity/contract details.

## Where to go next

- Target architecture → `docs/specs/v2-architecture.md`. Its data-model section is the current pre-primitives baseline; target primitives work uses `docs/specs/primitives-data-model.md`.
- Structural contract (boundaries + fitness functions + hotspots + Swift package graph) → `docs/architecture/` (start at `context.md`)
- Workout generation workflow → `docs/workout-generation.md` (how Claude/humans compose blocks, timing modes, prescriptions, autoreg, alternatives, and result expectations)
- Prescription authoring vocabulary → `docs/prescription.md` for the current pre-primitives app; `docs/specs/primitives-data-model.md` for the accepted target primitives contract.
- Modifier/equipment authoring → `docs/modifier-equipment.md`
- Sync + connectivity + first-run → `docs/sync.md`
- Early Apple Watch delivery → `docs/features/watch-workoutkit-handoff.md`
- Later custom Watch execution → `docs/features/watch-primary-execution.md` and `docs/watch-metrics.md`
- Proof contract → `docs/TESTING.md`
- Server specifics → `server/README.md`
- App specifics → `app/README.md` (the in-app behavior contract lives here)
- Cross-stack schema → `schema/README.md`
- Design reference (wireframes, hi-fi, rules) → `docs/design/` (start at `ORIGIN.md`)
- Decision records → `docs/decisions/`
- Open questions → `docs/open-questions.md`
