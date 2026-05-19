---
title: Architecture
status: accepted
last_reviewed: 2026-05-18
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
 pulls │         │ pushes primitive results,
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
- Workout execution UI (show primitive blocks, drive timing from block semantics)
- Primitive result logging
- Pull-to-refresh and queued push (works fully offline)
- Percentage-based load resolution via `user_parameters`

The active model is primitive composition: authored blocks contain sets, slots,
timing, traversal, work targets, and result roles. The app supports the
primitive cells that the current execution bridge can project and fails closed
for unsupported legal cells instead of guessing a legacy timing mode. Applies
client-side autoregulation only where the primitive bridge exposes a supported
strength set. See `app/README.md` for the in-app behavior contract,
`docs/workout-generation.md` for the end-to-end workout authoring workflow,
`docs/specs/primitives-data-model.md` for active authoring/result vocabulary,
and `docs/sync.md` for sync + first-run behavior.

The app is split into local SwiftPM packages. `Core/*` owns pure domain,
prescription, autoregulation, session, telemetry, and utility logic.
`Persistence`, `Sync`, `HealthKitBridge`, `WatchBridge`, and
`WorkoutKitAdapter` own named side effects. `Features/*` owns Today,
Execution, History, Settings, FirstRun, and WatchFaces. `Shell` owns bootstrap,
root tab composition, cross-feature view model wiring, and push-flusher lifecycle. See
`docs/architecture/swift-packages.md` for the authoritative package graph and
allowed dependencies.

HealthKit data access is routed through `HealthKitBridge` only. Consumers
declare typed batch or live data requests; the bridge owns HealthKit
identifiers, units, permissions, query mechanics, and simulator/device proof
boundaries. `WorkoutKitAdapter` has a narrow exception for HealthKit
activity/location enum types that Apple's WorkoutKit plan constructors require;
it must not own HealthKit data access or readback. See
`docs/healthkit-data-access.md`.

### `schema/` — Shared schema
Single source of truth for cross-stack data contracts. Committed `openapi.json` is the wire contract; hand-written Swift Codable DTOs under `Sources/WorkoutDBSchema/` mirror the server's Pydantic schemas. Cross-decoded fixtures live in `fixtures/`. See `schema/README.md`.

### `tests/` — Cross-cutting tests
Server tests under `tests/server/`. Contract tests that pin cross-stack schema parity under `tests/contract/` (OpenAPI drift, Swift enum parity, fixture round-trips on both sides).

## Data model (summary)

Core principle: **primitive composition with explicit result semantics**.
Workouts carry `primitive_blocks` JSON authored by Claude. Primitive blocks
compose timing, traversal, work targets, sets, slots, and result roles. Server
validation accepts only coherent primitive trees and only result rows whose
role-specific coordinates match the persisted tree.

Legacy `block`, `workout_item`, and `set_log` entities still exist where the
Swift bridge or historical read models consume them, but new primitives-lane
work starts from `docs/specs/primitives-data-model.md`, not from legacy
per-timing-mode prescription shapes.

## Sync model

Direction-based, no conflict resolution:
- Server → app: primitive workouts, exercises, user_parameters,
  `last_performed` summaries
- App → server: primitive result rows, workout status changes,
  workout reset requests, body-weight-at-completion as a `user_parameters` row

Cadence: on app open + on log write + ~60s foreground retry. Conflict rule: server wins for prescriptions, app wins for logs, live session is frozen. First-run: connection string (URL + bearer token) via paste or QR — no login surface.

See `docs/sync.md` for the full rules, and the spec § "Persistence architecture" for the entity/contract details.

## Where to go next

- Target architecture → `docs/specs/v2-architecture.md`. Its data-model section is historical; active primitive data-model work uses `docs/specs/primitives-data-model.md`.
- Structural contract (boundaries + fitness functions + hotspots + Swift package graph) → `docs/architecture/` (start at `context.md`)
- DesignSystem contract → `docs/design-system.md`
- Workout generation workflow → `docs/workout-generation.md` (how Claude/humans compose blocks, timing modes, prescriptions, autoreg, alternatives, and result expectations)
- Prescription authoring vocabulary → `docs/specs/primitives-data-model.md` for active primitive work; `docs/prescription.md` only for legacy projection/reference surfaces while residual bridge code remains.
- Modifier/equipment authoring → `docs/modifier-equipment.md`
- Sync + connectivity + first-run → `docs/sync.md`
- Early Apple Watch delivery → `docs/features/watch-workoutkit-handoff.md`
- Later custom Watch execution → `docs/features/watch-primary-execution.md` and `docs/watch-metrics.md`
- HealthKit batch/live data module → `docs/healthkit-data-access.md`
- Proof contract → `docs/TESTING.md`; reusable proof patterns →
  `docs/testing/`
- Server specifics → `server/README.md`
- App specifics → `app/README.md` (the in-app behavior contract lives here)
- Cross-stack schema → `schema/README.md`
- Design reference (wireframes, hi-fi, rules) → `docs/design/` (start at `ORIGIN.md`)
- Decision records → `docs/decisions/`
- Open questions → `docs/open-questions.md`
