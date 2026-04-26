---
title: Phase 2 — schema cutover foundation implementation plan
status: completed
last_reviewed: 2026-04-26
purpose: Implement the coordinated schema foundation for skip persistence, a reserved side field, and block intent.
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
  - docs/specs/v2-architecture.md
  - docs/feature-gap-map.md
---

# Phase 2 — Schema Cutover Foundation

## Unit Statement

Land one coordinated data-model cutover for `set_log.skipped`,
`set_log.side`, and `block.intent` across server, shared schema, SwiftData,
sync payloads, domain models, tests, and docs. `set_log.side` is a shipped
round-trip field, not the active unilateral-work authoring model.

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
- No UI phase is forced to infer per-side behavior from `set_log.side` before a
  later plan deliberately promotes that field.

## Done

- Server migration, app migration, shared schema, DTO mapping, tests, and docs
  all land together.
- Contract tests prove server/OpenAPI/Swift schema parity.
- SwiftData migration tests prove old stores migrate.
- iOS simulator starts after migration.

## Proof Map

- Check: `uv run pytest tests/server tests/contract`
  - Boundary: server + contract.
  - Proves: migration, API schemas, sync payloads, and OpenAPI parity.
  - Result: passed, `193 passed`.
  - Risk remaining: app local migration still separate.
- Check: Swift package tests for `Persistence`, `Sync`, `CoreDomain`, schema.
  - Boundary: cross-module + persistence.
  - Proves: domain/DTO mapping and SwiftData migration.
  - Result: passed via Xcode MCP package runs:
    - `CoreDomainTests`: `All 26 cases passed`.
    - `SyncTests`: `All 37 cases passed`.
    - `Persistence`: `57 XCTest cases passed`.
  - Risk remaining: real device local data shape beyond test fixture.
- Check: legacy SwiftData migration probe.
  - Boundary: old on-disk app store -> current app schema.
  - Proves: a real pre-Phase 2 file-scope V4 store opens under V5 with
    `intent == nil`, `skipped == false`, and `sideRaw == "bilateral"`.
  - Result: passed with temporary writer/reader packages built from the Phase 1
    baseline and current tree.
  - Risk remaining: only one representative store shape was generated.
- Check: iOS simulator build/run and UI snapshot.
  - Boundary: user-facing + integration.
  - Proves: the app builds, launches, and presents the Today screen after the
    schema cutover.
  - Result: passed after `clean`; stale incremental build artifacts initially
    linked old `Block` and `SetLog` initializer symbols.
  - Risk remaining: full unilateral work UX and history semantics are Phase 5/6.

## Independent Review

- Artifact: full schema diff across server, schema, app, docs, and tests.
- Reviewer: Codex read-only review focused on cutover completeness and data loss.
- Result: clean after re-review in thread
  `019dca6d-130f-7e60-90cd-21ce5f07ae07`.
- Reopen condition: any schema parity drift, missing migration, or log-loss path.

## Closeout

- `docs/MIGRATIONS.md` did not need changes; migration mechanics stayed within
  the existing append-only/lightweight pattern.
- `docs/feature-gap-map.md` rows for skip, side, and intent are marked
  partially built with simulator proof.
- Feedback-ripple disposition D1: `set_log.side` stays in the schema as a
  shipped/reserved field. Eric's 2026-04-26 per-side correction reframed
  unilateral authoring to exercise-level identity, so active UI, history, and
  analytics must not use `set_log.side` as the primary model unless a later
  phase explicitly promotes it. No migration 009 is planned just to drop the
  field.
- Simulator QA evidence: build/run succeeded on `WorkoutDB-Dev`
  (`22A47946-FD68-4C83-BC3C-FE62BB8E2748`); UI snapshot showed the Today screen
  and screenshot was captured at
  `/var/folders/pc/ndj8g0pn54bcjzbd0ltcwz340000gp/T/screenshot_optimized_43eb454a-4f9a-4f76-a641-6f5ea3e12486.jpg`.

## Recovery Context

Build the schema foundation only. Do not implement active/rest redesign or
watch behavior in this phase.

## Residual Uncertainty / Accepted Risks

- Unilateral aggregate semantics need a future explicit model if exercise-level
  left/right authoring is not enough for analysis.
  - Accepted because Phase 6 owns readable history and a later taxonomy pass can
    add canonical links between left/right exercise variants if needed.
  - Signal: trend/history tests or real analysis need "DB Row" aggregation
    across `DB Row (Left)` and `DB Row (Right)`.

## Escalation Triggers

- SwiftData migration cannot be lightweight and risks local log loss.
- Contract tests show OpenAPI/Swift schema drift.
- A fourth field is discovered as necessary for the same cutover.
