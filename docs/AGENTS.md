---
title: docs navigator
status: accepted
last_reviewed: 2026-05-17
purpose: Index of durable documentation for WorkoutDB. When landing in docs/, start here.
covers:
  - docs/
---

# docs/ — Navigator

Durable documentation for WorkoutDB. Start here when landing in `docs/`.

See the repo root `AGENTS.md` for workflow and invariants. Ephemeral/in-progress notes live in `scratch/` at the repo root, not here.

## Read first

- `specs/v2-architecture.md` — **accepted** target architecture. Every non-trivial change is evaluated against this. Read in full before working on schema, sync, or the app. **Note:** the Data model section is superseded by `specs/primitives-data-model.md`; everything else in v2 remains authoritative.
- `specs/primitives-data-model.md` — **accepted target spec (not yet implemented)** for the prescription + log + runtime-resolution data model. Replaces the 12-timing-mode enum with 7 composable primitives under a Block > Set > Slot hierarchy. Aspect files under `specs/primitives-data-model/` cover authoring shape, log shape, runtime resolution, and cutover posture.
- `workout-generation.md` — canonical workout authoring guide. Start here when generating plans: data model, safe current timing modes, autoreg, result persistence, examples, and generator checklist.
- `prescription.md` — current pre-primitives authoring vocabulary. What Claude must put in a workout so the app can execute it today. For target primitives work, use `specs/primitives-data-model.md` instead.
- `workout-taxonomy.md` — bootstrap workout-domain and block-archetype taxonomy. Use this before authoring new workout shapes so training intent maps to the right timing/logging primitive.
- `workout-execution-requirements.md` — athlete-facing timer, transition, logging, and summary requirements for workout archetypes.
- `features.md` and `features/INDEX.md` — target feature contracts and QA scenarios. Use `feature-gap-map.md` to see unresolved gap IDs for future planning.
- `backlog.md` — lightweight lane and gap router. Start here when asking "what lane are we working?" or "which gaps does this close?"
- `watch-metrics.md` — target watchOS slot, metric, target-window, and phone/watch lifecycle contract.
- `features/watch-workoutkit-handoff.md` — shorter Apple Watch delivery path: map eligible Setmark workouts into Apple's Workout app through WorkoutKit before building custom watch-primary execution.
- `features/in-app-claude.md` — future Claude proposal/review/acceptance workflow; read before planning app-side Claude or chat behavior.
- `modifier-equipment.md` — modifier/equipment authoring vocabulary and gaps; read before adding structured variant, setup, or equipment behavior.
- `sync.md` — sync cadence, conflict rules, first-run UX, offline behavior, auth posture.
- `ARCHITECTURE.md` — one-page system map; routes into the spec and per-package READMEs.
- `TESTING.md` — proof contract (server, app, cross-stack contract).

## Standard surfaces

- `ARCHITECTURE.md` — top-level system map and domain router.
- `WORKFLOW.md` — development lifecycle (idea → spec → plan → implement → verify → close → deploy), CI scope, branching, deploy flow.
- `TESTING.md` — proof contract; what each test tier covers and how to run it.
- `QA.md` — exploratory/simulator QA recording rules; keeps `docs/bugs.md` as the only active issue tracker and `scratch/qa-runs/` as raw evidence only.
- `MIGRATIONS.md` — schema migration mechanics for server SQL + SwiftData, the single-user cutover flow, and recovery procedures.
- `workout-generation.md` — generator-facing authoring guide that composes the data model, taxonomy, timing modes, prescriptions, autoregulation, support boundaries, and examples into one workflow.
- `prescription.md` — current pre-primitives prescription authoring vocabulary. Per-timing-mode shapes, RIR + autoreg rules, parametric shapes, authoring checklist. Rewrite during the primitives docs sweep.
- `workout-taxonomy.md` — maps workout domains to mutually-exclusive block archetypes and current timing modes.
- `workout-execution-requirements.md` — documents how each archetype should execute from the athlete perspective before implementation details are chosen.
- `features.md` — narrative entry point for user-visible feature contracts.
- `features/INDEX.md` — per-feature target contracts, QA scenario index, and current-gap convention.
- `feature-gap-map.md` — cross-feature index of unresolved implementation/proof gaps. Owning feature/aspect docs are the source of truth; backlog lanes and implementation notes cite gap IDs from here.
- `backlog.md` — current lane router. It groups gap IDs into work lanes without preserving stale phase order or implementation steps.
- `modifier-equipment.md` — authored modifier/equipment vocabulary and current gaps for variants, setup context, and app-display-only behavior.
- `watch-metrics.md` — target watchOS contract for the three watch views, persistent HR, target windows, sensor fallbacks, and phone/watch action versioning.
- `sync.md` — sync cadence, conflict rules, first-run UX, offline behavior, auth posture.
- `runbooks/closeout.md` — per-change closeout checklist (enforces the complete-cutover philosophy).
- `runbooks/first-real-workout.md` — critical path from "alpha-ready codebase" to "first real workout logged to server." Lists Eric-actions (credentials, hardware, decisions) vs Claude-actions (last-mile code + wiring). The hand-off sequence.
- `infrastructure/home-server.md` — one-time setup + ongoing deploy for the Python server (Tailscale, launchd, backup, rollback).
- `specs/` — accepted specs (`v2-architecture.md`, `primitives-data-model.md` + aspect dir) and decision explorations (`data-model-exploration.md`).
- `architecture/` — the structural contract. Start at `architecture/context.md` (the 9-question answers), then `boundaries.md` (allowed dependency directions), `fitness-functions.md` (every rule → automated check), `hotspots.md` (preemptive risk register), `swift-packages.md` (iOS package graph).
- `ios-dev-loop.md` — how an agent drives the iOS app (build / launch / screenshot / tap / iterate). Recommends XcodeBuildMCP; documents the ad-hoc fallback (xcrun simctl + debug launch args) that works without it.
- `decisions/` — ADRs. Current set: `ADR-2026-04-17-ux-scope.md`, `ADR-2026-04-17-rir-autoreg-sync.md`, `ADR-2026-04-17-architecture.md`, `ADR-2026-04-18-shell-package-placement.md`, `ADR-2026-04-18-smart-defaults.md`.
- `open-questions.md` — unresolved product/design decisions only. Implementation/proof gaps belong in the owning feature/aspect doc and `feature-gap-map.md`.
- `design/` — Claude Design handoff bundle (HTML/CSS/JSX prototypes, wireframes, rules). Read `design/ORIGIN.md` first, then `design/HANDOFF.md`. Reference, not spec.
- `bugs.md` — active QA issue tracker. Closed issues are removed; use git history for past rows.

See also `schema/README.md` (outside `docs/`) — the shared schema package (OpenAPI + Swift DTOs) and its drift-prevention contract tests. Common dev commands: `make help` at the repo root.

## Where new docs go

- Domain-specific detail that outgrows a README → `docs/{domain}.md` (single file first). Promote to `docs/{domain}/` only when a reader has to scroll past content irrelevant to their task.
- Cross-cutting decisions → `docs/decisions/ADR-YYYY-MM-DD-{slug}.md` (directory created on first ADR).
- Ephemeral sketches → `scratch/` at the repo root (gitignored).
- Per-package design notes → inside the package, not here (e.g. `server/README.md`, `app/README.md`).

## Not yet present

These canonical surfaces haven't been needed yet. Add when:

- `CORE-BELIEFS.md` — when invariants in root `AGENTS.md` outgrow it.
- Durable plan directories — do not add them. Use `docs/backlog.md` for current lanes and `scratch/` for ephemeral implementation notes.

## Front matter

Add YAML front matter (`title`, `status`, `purpose`, `covers`) to new docs. Existing docs predate this; migrate opportunistically.
