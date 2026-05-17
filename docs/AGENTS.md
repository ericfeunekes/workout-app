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
- `prescription.md` — authoring vocabulary. What Claude must put in a workout so the app can execute it. Per-timing-mode shapes, RIR + autoregulation rules, parametric shapes.
- `workout-taxonomy.md` — bootstrap workout-domain and block-archetype taxonomy. Use this before authoring new workout shapes so training intent maps to the right timing/logging primitive.
- `workout-execution-requirements.md` — athlete-facing timer, transition, logging, and summary requirements for workout archetypes.
- `workout-execution-design-plan.md` — pass-based plan for aligning the execution docs, then designing each flow before implementation.
- `features.md` and `features/INDEX.md` — target feature contracts and QA scenarios. Use `feature-gap-map.md` to see the current gaps grouped into implementation phases.
- `plans/backlog/workout-system-roadmap.md` — pickup map that ties together completed feedback/execution/history work, the future primitives cutover, and downstream Watch phases. Start here when asking "what phase are we in?"
- `plans/backlog/feedback-implementation-phases/` — downstream implementation phase directory for the 2026-04-25 feedback and watch redesign sequence. Start here when selecting the next phase after the feature-docs contract pass.
- `watch-metrics.md` — target watchOS slot, metric, target-window, and phone/watch lifecycle contract.
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
- `prescription.md` — prescription authoring vocabulary. Per-timing-mode shapes, RIR + autoreg rules, parametric shapes, authoring checklist.
- `workout-taxonomy.md` — maps workout domains to mutually-exclusive block archetypes and current timing modes.
- `workout-execution-requirements.md` — documents how each archetype should execute from the athlete perspective before implementation details are chosen.
- `workout-execution-design-plan.md` — tracks the alignment and flow-design passes that must happen before build planning.
- `features.md` — narrative entry point for user-visible feature contracts.
- `features/INDEX.md` — per-feature target contracts, QA scenario index, and current-gap convention.
- `feature-gap-map.md` — cross-feature index of target behavior that is not implemented or not yet proven.
- `watch-metrics.md` — target watchOS contract for the three watch views, persistent HR, target windows, sensor fallbacks, and phone/watch action versioning.
- `sync.md` — sync cadence, conflict rules, first-run UX, offline behavior, auth posture.
- `runbooks/closeout.md` — per-change closeout checklist (enforces the complete-cutover philosophy).
- `runbooks/first-real-workout.md` — critical path from "alpha-ready codebase" to "first real workout logged to server." Lists Eric-actions (credentials, hardware, decisions) vs Claude-actions (last-mile code + wiring). The hand-off sequence.
- `infrastructure/home-server.md` — one-time setup + ongoing deploy for the Python server (Tailscale, launchd, backup, rollback).
- `specs/` — accepted specs (`v2-architecture.md`, `primitives-data-model.md` + aspect dir) and decision explorations (`data-model-exploration.md`).
- `architecture/` — the structural contract. Start at `architecture/context.md` (the 9-question answers), then `boundaries.md` (allowed dependency directions), `fitness-functions.md` (every rule → automated check), `hotspots.md` (preemptive risk register), `swift-packages.md` (iOS package graph).
- `ios-dev-loop.md` — how an agent drives the iOS app (build / launch / screenshot / tap / iterate). Recommends XcodeBuildMCP; documents the ad-hoc fallback (xcrun simctl + debug launch args) that works without it.
- `decisions/` — ADRs. Current set: `ADR-2026-04-17-ux-scope.md`, `ADR-2026-04-17-rir-autoreg-sync.md`, `ADR-2026-04-17-architecture.md`, `ADR-2026-04-18-shell-package-placement.md`, `ADR-2026-04-18-smart-defaults.md`.
- `open-questions.md` — the living gap register. Items that surfaced from consistency passes but aren't decided yet, with working assumptions and disposition (decide-next / defer / resolve-in-code / watchlist).
- `design/` — Claude Design handoff bundle (HTML/CSS/JSX prototypes, wireframes, rules). Read `design/ORIGIN.md` first, then `design/HANDOFF.md`. Reference, not spec.
- `plans/active/` — current implementation plans. Start here before continuing an in-flight multi-slice build.
- `plans/backlog/workout-system-roadmap.md` — overall current roadmap across feedback implementation, primitives cutover, and Watch work.
- `plans/backlog/feedback-implementation-phases/` — phase-by-phase implementation plans for carrying the 2026-04-25 feedback through schema, execution UX, history, watch authority, watch UI, and future in-app Claude/chat.
- `plans/backlog/primitives-cutover-phases/` — phase specs for the primitives-data-model cutover. README owns the phase list and deferral notes; per-phase files carry outcome-altitude specs consumed by implementation-planning.
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
- `plans/debt/` — when active implementation work starts producing durable non-current follow-ups.

## Front matter

Add YAML front matter (`title`, `status`, `purpose`, `covers`) to new docs. Existing docs predate this; migrate opportunistically.
