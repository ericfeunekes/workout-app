---
title: Testing
status: accepted
last_reviewed: 2026-05-17
purpose: Proof contract — what each test tier covers, how to run it, and what changes require which tier.
covers:
  - tests/
  - server/
  - app/
  - schema/
---

# Testing

Proof contract for WorkoutDB. Every change should leave its proof surface green before merge.

See also: `docs/MIGRATIONS.md` (schema cutover flow — contract tests run as part of each migration), `docs/prescription.md` (current pre-primitives prescription shape contract), `docs/specs/primitives-data-model.md` (accepted target shape that supersedes the per-timing-mode data model once the cutover lands), `docs/sync.md` (sync protocol contract — offline execution is a load-bearing invariant that needs explicit coverage once the app exists), and `docs/QA.md` (exploratory/simulator QA evidence and issue-recording rules).

The system has three testable stacks — each gets its own tier:

## Server tests (Python) — `tests/server/`

**Fast, pytest, no iOS dependency.**

Scope:
- Pydantic / ORM model validation.
- API route handlers (via `httpx.AsyncClient` against an in-memory FastAPI app).
- Sync endpoint correctness (pull-with-since, idempotent results push).
- Migration idempotency and forward compatibility.

Run: `uv pip install -e ".[dev]" && pytest`.

## Contract tests — `tests/contract/`

**Cross-stack schema parity.** Pin the schema shape so the server and SwiftData can't drift silently.

Scope:
- Every entity in the spec is present in both server and app schemas.
- Every field name, type, and nullability matches.
- Current pre-primitives state: `timing_mode` enum and `prescription_json` shapes are identical on both sides.
- Primitives cutover state: Block > Set > Slot schema, timing/traversal/repeat cells, primitive prescription fixtures, and primitive log roles are identical on both sides. The cutover is not done while both contract families are accepted.

Mechanism depends on the `schema/` decision (OpenAPI vs hand-mirrored). Until `schema/` is populated, contract tests live as failing placeholders or spec-referenced assertions.

## App tests — inside `app/` Xcode target

**SwiftData + UI behavior.** Run via Xcode / xcodebuild.

Scope:
- SwiftData model round-trips.
- Timer engine correctness per `timing_mode`.
- `percent_1rm` resolution against `user_parameters`.
- Offline queue behavior for results push.

## Proof expectations by change type

- **Server schema change** → server test (models) + contract test (parity with app) + migration integration test.
- **New API endpoint** → server test (route behavior) + update `docs/ARCHITECTURE.md` if it changes sync story.
- **Sync protocol change** → server test (endpoint) + contract test (both sides agree) + app test (sync manager).
- **New timing mode before primitives cutover** → update spec + server enum + app enum + contract test + app timer test.
- **Primitives data-model cutover** → update the primitives spec/aspects, server schema, Swift DTOs, SwiftData schema, contract tests, local-history migration proof, and app execution tests in the same cutover branch before merge.
- **New `user_parameters` key the app interprets** → app test for the resolver.
- **Pure helper** → unit test in the owning stack.

## What's not under test yet

- Claude-side behavior (conversation-driven planning, progression) — by design. If an invariant about what Claude pushes needs pinning, encode it as a server-side validator + test.
