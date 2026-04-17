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

Runs all 10 timing modes: `straight_sets`, `superset`, `circuit`, `emom`, `amrap`, `for_time`, `intervals`, `tabata`, `continuous`, `custom`. See `app/README.md` and spec § "Timing modes".

### `schema/` — Shared schema
Single source of truth for cross-stack data contracts. Not yet populated — see `schema/README.md` for the decision still open (OpenAPI vs hand-mirrored).

### `tests/` — Cross-cutting tests
Server tests under `tests/server/`. Contract tests that pin cross-stack schema parity under `tests/contract/` (once `schema/` is chosen).

## Data model (summary)

Core principle: **composition with timing**. Everything is blocks; a block has a `timing_mode` and contains exercises or nested blocks.

Entities: `app_user`, `exercise`, `exercise_alternative`, `block`, `workout_item`, `workout`, `set_log`, `user_parameters`. UUIDs everywhere.

See spec § "Data model" for field-level definitions.

## Sync model

Direction-based, no conflict resolution:
- Server → app: workouts, exercises, alternatives, user_parameters
- App → server: set_logs, workout status changes

See spec § "Persistence architecture" and § "Sync mechanics".

## Where to go next

- Target spec (authoritative) → `docs/specs/v2-architecture.md`
- Proof contract → `docs/TESTING.md`
- Server specifics → `server/README.md`
- App specifics → `app/README.md`
- Cross-stack schema → `schema/README.md`
