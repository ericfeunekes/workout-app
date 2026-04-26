---
title: Superseded schema cutover — skipped side intent
status: superseded
last_reviewed: 2026-04-26
purpose: Superseded backlog implementation plan for adding skipped set logs, the reserved side round-trip field, and block intent across server, schema, app, sync, and docs.
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

Superseded by completed Phase 2:
`docs/plans/backlog/feedback-implementation-phases/phase-02-schema-cutover-foundation.md`
and commit `b81ab85`.

Feedback-ripple disposition D1 keeps the shipped `set_log.side` field as a
reserved round-trip field. It is not the active authoring model for unilateral
work; unilateral work is authored with separate exercise/workout items unless a
future phase deliberately promotes `set_log.side`.

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
- Aggregate semantics must not infer left/right grouping from the reserved
  `side` field unless a later taxonomy phase explicitly promotes it.

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
- A later taxonomy phase deliberately promotes `set_log.side` from reserved
  round-trip field to active grouping/analytics semantics.
