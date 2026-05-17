---
title: Closeout checklist
status: stable
date: 2026-04-17
last_reviewed: 2026-05-17
purpose: "What to check before declaring a change done. Enforces the complete-cutover philosophy so nothing partial lands."
covers:
  - all
  - docs/sdlc.md
---

# Closeout checklist

Run through this before any commit that represents "done." It's short on purpose — every item corresponds to a real failure mode this repo has locked out (legacy code, schema drift, undocumented decisions).

## Universal

- [ ] `make check` passes (green locally before pushing — pre-push also enforces the Python/import subset).
- [ ] `make pre-qa` was run for cross-stack, app-logic, or visible iOS changes; if a required realistic-local harness is missing, the gap is routed before closeout.
- [ ] Telemetry/proof requirements in the implementation plan were satisfied:
      event names, queue rows, local-store rows, server rows, logs, or API
      readbacks exist for behavior the UI cannot prove. If no telemetry was
      needed, the closeout says why.
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
- [ ] Local set_log preservation/reset decision confirmed — either the SwiftData stage is lightweight, the custom stage has an export+reimport path, or the owning cutover spec explicitly permits a destructive QA-data reset.

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

## Primitives data-model cutover

If the change is part of the accepted primitives cutover:

- [ ] `docs/specs/primitives-data-model.md` and affected aspect docs remain the target authority.
- [ ] Legacy per-timing-mode authoring/result payloads are not accepted in the final merged state.
- [ ] Primitive cutover data handling matches the owning spec: either completed local workout history preservation is proven, or the destructive QA-data reset is explicit and tested.
- [ ] `docs/prescription.md`, `docs/features/timing-modes.md`, and `docs/specs/v2-architecture.md` are either rewritten to the primitive contract or explicitly marked as current-state legacy references until the final docs sweep lands.
- [ ] Contract tests assert primitive schema parity, not the old 12-case enum contract.

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

## Feature contract / gap map

If the change implements or proves target behavior tracked in a feature doc:

- [ ] The affected `docs/features/*` contract is updated in the same commit.
- [ ] Any closed item is removed from or updated in the feature doc's `Current gaps` section.
- [ ] `docs/feature-gap-map.md` is updated with the new state. Proof references live in the owning feature/aspect doc, QA surface, or test names, not in the gap map.

## App-facing UX QA

If the change affects user-visible iOS behavior:

- [ ] `make check-app` passes, or any current pre-QA failure is named and scoped before QA starts.
- [ ] `make qa-ready` passes before simulator/device QA starts.
- [ ] The relevant feature/spec/bug note was read, and the QA run covered the user expectation changed by this work.
- [ ] For persistence, sync, offline, auth, telemetry, or backend behavior, QA
      included the matching readback surface from `docs/observability-map.md`
      in addition to screenshots or video.
- [ ] XcodeBuildMCP was used for the simulator build/run and for the useful interaction tools: taps, swipes, long presses, dismissals, inputs, screenshots, recording, and `snapshot-ui`.
- [ ] The proof matched the claim: visual changes used visual evidence, state/persistence/sync claims used tests or state readbacks, and device-only behavior used a real-device path when needed.
- [ ] Simulator video and screenshots were captured when the change had a visible iPhone UI surface.
- [ ] The recording was reviewed with `img ask --video`, and the verdict was read before closeout.
- [ ] Any bugs or open product/design questions found during QA were routed to `docs/bugs.md` or `docs/open-questions.md`.

## Backlog and scratch planning

If the change closes, narrows, discovers, or reprioritizes a backlog gap:

- [ ] The owning durable requirement docs were updated before the backlog.
- [ ] `docs/feature-gap-map.md` rows were removed, narrowed, or added to match the owning docs.
- [ ] `docs/backlog.md` was updated only if lane ownership, posture, or next planning move changed.
- [ ] Scratch phase or implementation plans that no longer describe active work were deleted. If rationale must survive, its durable conclusion was promoted to the owning docs or an ADR.
- [ ] Raw `scratch/qa-runs/` artifacts for completed QA runs were removed, and any still-open bug row now carries a reproducible behavior/date instead of depending on a scratch path.
- [ ] No durable phase-plan directory or stale plan doc was added under `docs/`.

## After context loss

If resuming work and you're not sure whether earlier steps were completed, re-read the commit history and the spec before continuing. Don't close out based on guesses.
