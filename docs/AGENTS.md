# docs/ — Navigator

Durable documentation for WorkoutDB. Start here when landing in `docs/`.

See the repo root `AGENTS.md` for workflow and invariants. Ephemeral/in-progress notes live in `scratch/` at the repo root, not here.

## Read first

- `specs/v2-architecture.md` — **accepted** target architecture. Every non-trivial change is evaluated against this. Read in full before working on schema, sync, or the app.
- `ARCHITECTURE.md` — one-page system map; routes into the spec and per-package READMEs.
- `TESTING.md` — proof contract (server, app, cross-stack contract).

## Standard surfaces

- `ARCHITECTURE.md` — top-level system map and domain router.
- `WORKFLOW.md` — development lifecycle (idea → spec → plan → implement → verify → close → deploy), CI scope, branching, deploy flow.
- `TESTING.md` — proof contract; what each test tier covers and how to run it.
- `MIGRATIONS.md` — schema migration mechanics for server SQL + SwiftData, the single-user cutover flow, and recovery procedures.
- `runbooks/closeout.md` — per-change closeout checklist (enforces the complete-cutover philosophy).
- `infrastructure/home-server.md` — one-time setup + ongoing deploy for the Python server (Tailscale, systemd, backup, rollback).
- `specs/` — accepted specs (`v2-architecture.md`) and decision explorations (`data-model-exploration.md`).
- `decisions/` — ADRs. Currently: `ADR-2026-04-17-ux-scope.md`.

See also `schema/README.md` (outside `docs/`) — the shared schema package (OpenAPI + Swift DTOs) and its drift-prevention contract tests. Common dev commands: `make help` at the repo root.

## Where new docs go

- Domain-specific detail that outgrows a README → `docs/{domain}.md` (single file first). Promote to `docs/{domain}/` only when a reader has to scroll past content irrelevant to their task.
- Cross-cutting decisions → `docs/decisions/ADR-YYYY-MM-DD-{slug}.md` (directory created on first ADR).
- Ephemeral sketches → `scratch/` at the repo root (gitignored).
- Per-package design notes → inside the package, not here (e.g. `server/README.md`, `app/README.md`).

## Not yet present

These canonical surfaces haven't been needed yet. Add when:

- `CORE-BELIEFS.md` — when invariants in root `AGENTS.md` outgrow it.
- `QA.md` — when the iOS app exists and visual/exploratory QA becomes a routine concern.
- `plans/active/`, `plans/backlog/`, `plans/debt/` — when `skill:feature-planning` produces its first plan file.

## Front matter

Add YAML front matter (`title`, `status`, `purpose`, `covers`) to new docs. Existing docs predate this; migrate opportunistically.
