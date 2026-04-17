---
title: Closeout checklist
status: stable
date: 2026-04-17
purpose: "What to check before declaring a change done. Enforces the complete-cutover philosophy so nothing partial lands."
covers:
  - all
---

# Closeout checklist

Run through this before any commit that represents "done." It's short on purpose — every item corresponds to a real failure mode this repo has locked out (legacy code, schema drift, undocumented decisions).

## Universal

- [ ] `uv run ruff check` passes.
- [ ] `uv run ruff format --check` passes.
- [ ] `uv run pytest` passes (green locally before pushing — pre-push hook also enforces).
- [ ] No TODOs, FIXMEs, or "temporary" code introduced. If a nitpick was noticed during the work, it was resolved as part of the commit (see `AGENTS.md` invariants).
- [ ] No legacy / v1 references resurrected (YAML, Google Calendar, intent taxonomy, muscle/movement/equipment tables, the `workoutdb` CLI).
- [ ] Commit message explains *why*, not just *what*.

## Schema change

If server models, SwiftData models, or the spec's entity definitions changed:

- [ ] Server SQL migration added under `server/db/migrations/NNN_*.sql`, idempotent.
- [ ] SwiftData `VersionedSchema` version bumped and migration stage added in `app/` (once the Xcode project exists).
- [ ] Server API models (SQLAlchemy + Pydantic) updated.
- [ ] Swift DTOs in `schema/Sources/WorkoutDBSchema/` updated to match.
- [ ] `schema/openapi.json` regenerated and committed (see `schema/README.md`).
- [ ] Contract tests under `tests/contract/` pass (`test_openapi_drift`, `test_swift_schema_parity`).
- [ ] `docs/specs/v2-architecture.md` entity table reflects the change.
- [ ] Server and app schema versions are equal (see `docs/MIGRATIONS.md` version handshake).
- [ ] Local set_log preservation plan confirmed — either the SwiftData stage is lightweight, or the custom stage has an export+reimport path.

## API change

If a route was added, removed, or changed:

- [ ] `docs/specs/v2-architecture.md` § "API contract" updated.
- [ ] `docs/ARCHITECTURE.md` updated if the sync story changed (endpoints that affect pull/push direction).
- [ ] Route test added in `tests/server/`.
- [ ] Pydantic request/response models updated.

## New timing mode / prescription shape

- [ ] `docs/specs/v2-architecture.md` timing-modes table or prescription examples updated.
- [ ] Server enum (if a new timing_mode) updated.
- [ ] SwiftData enum updated.
- [ ] App timer engine knows how to drive the new mode (or documented as deferred).
- [ ] Contract test covers the new shape on both sides.

## User-parameter key that the app should interpret

- [ ] Known-keys section of `docs/specs/v2-architecture.md` updated with the new key and its semantics.
- [ ] Resolver updated in `app/` (for keys the app reads to resolve prescriptions).

## New architectural boundary

If the change introduces a new top-level module, package split, or layering boundary:

- [ ] `import-linter` contract added or extended in `pyproject.toml` (see `docs/WORKFLOW.md` § "Architectural enforcement").
- [ ] `uv run lint-imports` passes locally.
- [ ] If the boundary is Swift-side: SwiftLint rule added or target/module split configured, and documented in `app/README.md`.
- [ ] If the boundary is cross-stack: contract test in `tests/contract/` pins the interface.

## New invariant / decision worth preserving

- [ ] Invariant landed in `AGENTS.md` (if it applies to every future change) or in an ADR under `docs/decisions/` (if it's a single decision with rationale worth pinning).
- [ ] Spec updated if the invariant constrains the schema or sync story.

## After context loss

If resuming work and you're not sure whether earlier steps were completed, re-read the commit history and the spec before continuing. Don't close out based on guesses.
