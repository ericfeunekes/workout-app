---
title: Schema cutover — skipped side intent
status: backlog
last_reviewed: 2026-04-26
purpose: Backlog implementation plan for adding skipped set logs, side-aware logging, and block intent across server, schema, app, sync, and docs.
covers:
  - server/workoutdb_server/models.py
  - server/db/migrations/
  - server/workoutdb_server/api/schemas.py
  - schema/Sources/WorkoutDBSchema/
  - app/Packages/Persistence/
  - app/Packages/Sync/
  - docs/prescription.md
---

# Schema Cutover — Skipped / Side / Intent

## Unit statement

Add the persisted fields needed by the feedback contracts:

- `set_log.skipped BOOLEAN NOT NULL DEFAULT 0`
- `set_log.side TEXT NOT NULL DEFAULT 'bilateral'`
- `block.intent TEXT NULL`

This is a complete cutover, not a compatibility layer.

## Boundaries touched

- Server SQLAlchemy models and idempotent SQL migration.
- Pydantic API schemas and sync payloads.
- Shared Swift schema DTOs and OpenAPI snapshot.
- SwiftData/Persistence models and local migrations.
- Sync encoding/decoding and contract tests.
- Prescription docs and feature-gap map.

## Semantics

- `skipped = true` records a deliberate skip, not a missing log.
- `side` values are `left`, `right`, or `bilateral`; no `n/a` value.
- New Claude-authored blocks should include `block.intent`, but server accepts
  null and the app renders no placeholder when null.
- Per-side aggregates must not double-count bilateral work as two sides.

## Proof map

- Migration tests prove existing rows receive default values.
- Server API tests prove pull/push round trips include the new fields.
- Swift schema parity tests prove Python/Swift DTOs agree.
- Persistence tests prove local cache preserves skipped/side/intent.
- Sync tests prove results and pulls preserve the fields.
- Simulator QA is required only when a user-facing surface claims skip, side, or
  intent display is usable.

## Done

- All schema surfaces agree.
- Existing local set logs survive migration.
- Feature docs and `docs/feature-gap-map.md` move the relevant gaps only as far
  as the implementation and proof justify.
- Independent Codex review is clean before simulator QA for any visible surface.

## Escalation triggers

- A fourth persisted field becomes necessary.
- SwiftData migration cannot be lightweight for local set logs.
- Server aggregate semantics for side-aware logs remain ambiguous.
