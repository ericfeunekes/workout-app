---
title: Phase 2 — schema cutover foundation implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Implement the coordinated schema foundation for skip persistence, per-side logging, and block intent.
covers:
  - server/workoutdb_server/models.py
  - server/workoutdb_server/api/schemas.py
  - server/workoutdb_server/api/sync.py
  - server/db/migrations/
  - schema/Sources/WorkoutDBSchema/
  - schema/openapi.json
  - app/Packages/Core/Domain/
  - app/Packages/Persistence/
  - app/Packages/Sync/
  - docs/prescription.md
  - docs/features/execute-loop.md
  - docs/features/history.md
---

# Phase 2 — Schema Cutover Foundation

## Unit Statement

Land one coordinated data-model cutover for `set_log.skipped`,
`set_log.side`, and `block.intent` across server, shared schema, SwiftData,
sync payloads, domain models, tests, and docs.

## Boundaries Touched

- Persistence: server SQLite migration and SwiftData schema migration.
- Wire contract: Pydantic schemas, OpenAPI, shared Swift DTOs.
- App domain: `Block`, `SetLog`, DTO mapping, push/pull mapping.
- Sync: results payload encoding/decoding and push queue compatibility.
- History/execution consumers: fields are available but UI behavior can remain
  minimal until later phases.
- Docs: prescription vocabulary, migration notes, feature-gap map.

## Dependencies And Preconditions

- Phase 1 docs identify these as locked schema decisions.
- Existing local set logs are the only preservation constraint.
- Single-user cutover applies: no feature flags and no compatibility layer.
- Migration must preserve existing logs by backfilling:
  - `skipped = false`
  - `side = bilateral`
  - `block.intent = null`

## Uncertainty Reduction Summary

- Architecture/history: schema fields exist in three representations today:
  server ORM/API, shared schema DTOs, and SwiftData/domain models.
- Blast radius: `SetLog` travels through execution push, history load,
  persistence mapping, server `/api/sync/results`, and OpenAPI contract tests.
- Migration posture: SwiftData needs a version bump and migration stage; server
  migrations are append-only and idempotent.

## Approach

Do the full schema cutover in one phase, but keep UI semantics conservative.
The app may write defaults and round-trip the fields before Phase 5/6 exposes
all behavior.

## Steps

1. Add server migration for `set_log.skipped`, `set_log.side`, and
   `block.intent` with idempotent guards and constraints.
2. Update SQLAlchemy ORM models and Pydantic read/write schemas.
3. Regenerate `schema/openapi.json` and update shared Swift DTOs.
4. Update app `CoreDomain` models and `Persistence` SwiftData models with a
   new schema version and migration stage.
5. Update `DomainMapping`, Sync DTO mapping, push queue encoding, and pull
   decoding.
6. Add contract and persistence tests.
7. Update docs and mark schema cutover gaps as built but not UX-verified.

## Good

- Existing logs survive migration and read as non-skipped, bilateral.
- New fields round-trip server -> app -> server without data loss.
- Block intent can be null; app renders no placeholder where it is not yet used.
- No UI phase is forced to infer per-side behavior before its own plan.

## Done

- Server migration, app migration, shared schema, DTO mapping, tests, and docs
  all land together.
- Contract tests prove server/OpenAPI/Swift schema parity.
- SwiftData migration tests prove old stores migrate.
- iOS simulator starts after migration and can pull/execute/push a workout.

## Proof Map

- Check: `uv run pytest tests/server tests/contract`
  - Boundary: server + contract.
  - Proves: migration, API schemas, sync payloads, and OpenAPI parity.
  - Expected: pass.
  - Risk remaining: app local migration still separate.
- Check: Swift package tests for `Persistence`, `Sync`, `CoreDomain`, schema.
  - Boundary: cross-module + persistence.
  - Proves: domain/DTO mapping and SwiftData migration.
  - Expected: pass.
  - Risk remaining: real device local data shape beyond test fixture.
- Check: iOS simulator build/run and one pull/start/log/push smoke.
  - Boundary: user-facing + integration.
  - Proves: migrated app can still execute the critical path.
  - Expected: app launches; workout can log and enqueue/push.
  - Risk remaining: full per-side UX is Phase 5/6.

## Independent Review

- Artifact: full schema diff across server, schema, app, docs, and tests.
- Reviewer: Codex read-only review focused on cutover completeness and data loss.
- Reopen condition: any schema parity drift, missing migration, or log-loss path.

## Closeout

- Update `docs/MIGRATIONS.md` only if migration mechanics changed.
- Update `docs/feature-gap-map.md` rows for skip, side, and intent.
- Report exact proof commands and simulator QA evidence.

## Recovery Context

Build the schema foundation only. Do not implement active/rest redesign or
watch behavior in this phase.

## Residual Uncertainty / Accepted Risks

- Per-side aggregate semantics may need refinement under real history usage.
  - Accepted because Phase 6 owns history UX.
  - Signal: trend/history tests reveal misleading left/right aggregation.

## Escalation Triggers

- SwiftData migration cannot be lightweight and risks local log loss.
- Contract tests show OpenAPI/Swift schema drift.
- A fourth field is discovered as necessary for the same cutover.
