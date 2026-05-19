---
title: Testing
status: accepted
last_reviewed: 2026-05-18
purpose: Proof contract — what each test tier covers, how to run it, and where to find proof patterns by risk shape.
covers:
  - tests/
  - server/
  - app/
  - schema/
  - docs/testing/
  - docs/feature-gap-map.md
  - docs/QA.md
---

# Testing

Pre-QA proof contract for WorkoutDB. Testing proves behavior through automated
or realistic-local checks before exploratory simulator/device QA starts.

See also: `docs/MIGRATIONS.md` for schema cutovers,
`docs/specs/primitives-data-model.md` for the active primitive workout
contract, `docs/sync.md` for sync rules, and `docs/QA.md` for exploratory
simulator/device QA after testing gates are green.

## Testing vs QA

Testing and QA are separate proof layers.

- **Testing is pre-QA.** It covers deterministic, automated, and
  realistic-local proof: unit tests, package tests, integration tests,
  contract tests, app-hosted smoke tests, local service harnesses, and
  end-to-end probes where the repo can run them repeatably.
- **QA is exploratory/runtime evidence.** It follows `docs/QA.md`: simulator or
  real-device runs, gestures, screenshots, recordings, `snapshot-ui`,
  `img ask --video`, issue routing, and human-visible product judgment.
- **Do not use QA to replace missing tests.** If a behavior can be proven
  through a deterministic test or realistic-local harness, prove it here first;
  then use QA to inspect the user experience and device/runtime behavior.
- **Do not use mocks as realistic-local proof for real boundaries.** Mocks and
  fakes are useful for unit/component tests. Boundary proof needs the closest
  local stand-in the repo supports: SQLite DBs, in-process FastAPI app,
  SwiftData containers, real URLSession/fake server, recorded fixtures,
  controlled clocks, or real concurrent execution.

When the test infrastructure lacks the stand-in a seam needs, record that as a
capability gap. The choice is then build the infra, defer with named risk, or
cut the behavior from scope. Do not silently downgrade the proof bar to a mock.

## Maintaining The Proof Framework

When implementation, review, QA, or a testing audit finds that the expected
test type or approach was unclear, consider whether these docs need a general
proof-pattern update. The bar is reuse: update the framework when the gap would
affect future work in the same risk class, not for every one-off example or
bug.

Useful updates describe the shape of proof future plans should choose:

- the risk class or seam involved
- the deterministic or realistic-local harness that should carry confidence
- the failure modes that must be exercised
- the evidence that belongs in QA only after pre-QA proof exists

Keep examples short and representative. The testing docs should stay general
enough to guide all repo work and specific enough that implementation plans can
cite a concrete proof pattern instead of saying only "add tests."

## Testing Subdocs

Use these docs when implementation planning needs a proof map. Pick the
smallest proof pattern that matches the risk, then add stronger layers only
when the claim crosses a real boundary.

- `docs/testing/proof-patterns.md` — reusable proof selection by change shape.
  Start here when planning or reviewing tests.
- `docs/testing/app-state-and-persistence.md` — SwiftData, local stores,
  session snapshots, destructive reset, sync ownership, background/foreground
  lifecycle, and local-service probes.
- `docs/testing/execution-and-editing.md` — primitive execution, timers,
  route transitions, current/remaining/upcoming projections, set edits,
  preview edits, history corrections, and shared edit invariants.
- `docs/testing/external-boundaries.md` — HealthKit, WorkoutKit,
  WatchConnectivity, Cloudflare Access, real HTTP, simulator vs real-device
  proof, and capability-gap language.
- `docs/testing/runtime-and-ui-proof.md` — ETTrace, memgraph/leaks, XCUITest
  action identity, snapshot UI, DesignSystem/accessibility proof, and what
  visual QA can and cannot prove.

## Test Tiers

The system has several testable stacks. Each tier answers a different question.

### Server tests — `tests/server/`

**Fast, pytest, no iOS dependency.** These prove server behavior against the
FastAPI app and local SQLite-backed state.

Scope:

- Pydantic / ORM model validation.
- API route handlers through `httpx.AsyncClient` against an in-memory FastAPI
  app.
- Sync endpoint correctness: pull-with-since and idempotent results push.
- Migration idempotency and forward compatibility.

Run:

```bash
uv sync --extra dev && uv run pytest
```

### Contract tests — `tests/contract/` and `schema/`

**Cross-stack schema parity.** Pin the schema shape so the server and SwiftData
cannot drift silently.

Scope:

- Every entity in the spec is present in both server and app schemas.
- Every field name, type, and nullability matches.
- Active primitives state: Block > Set > Slot schema, timing/traversal/repeat
  cells, primitive prescription fixtures, and primitive log roles are identical
  on both sides.
- Legacy bridge/projected values may stay under app package tests while
  residual runtime cutover work is open, but contract tests must not accept old
  per-timing-mode authoring/result payloads as a second wire contract.

Run:

```bash
uv run pytest tests/contract
cd schema && swift test
```

### Swift package tests — `app/Packages/`

**App logic below the visible UI.** These are the main pre-QA proof layer for
the iOS app.

Scope:

- Pure Core behavior: IDs, formatting, domain values, prescription parsing,
  autoregulation, session reducer, timing state, and primitive semantics.
- Feature view-model behavior: Today, Execution, FirstRun, History, Settings,
  and WatchFaces.
- Persistence behavior against SwiftData containers and Keychain/defaults
  wrappers where available.
- Sync behavior against deterministic transports and queues.
- Watch/HealthKit bridge behavior against fakes where real device behavior is
  not being claimed.

Run:

```bash
make test-core
make test-app-packages
```

This gate covers executable Swift package test targets and XCTest packages
under `app/Packages/`. It is the package-level app proof expected before
implementation closeout for app logic changes.

### App-hosted tests — `app/WorkoutDBTests`

**Integrated app build and launch proof.** Run via Xcode / `xcodebuild`.

Scope:

- app target compiles and links with all package dependencies
- app-hosted smoke tests for launch-time composition
- targeted integrated invariants that need the actual app bundle or simulator
  host
- focused UI tests that prove production routes and action identity

Run:

```bash
make test-app-xcode
make test-execution-ui
make test-workout-type-ui
make test-healthkit-ui
```

`make test-app-xcode` is the code-signing-free compile/link smoke. Keep focused
UI proofs on named targets so the default smoke gate does not quietly become an
entitlement-dependent test.

`make test-execution-ui` is wired into `make pre-qa` through `make check-app`.
It runs deterministic end-confirmation smoke coverage only. Route-change alert
dismissal remains an opt-in XCUITest until it has a deterministic route driver
instead of relying on wall-clock timer passage.

`make test-workout-type-ui` is opt-in. Run it when a change claims coverage
across timing modes or composed primitive execution cases.

`make test-healthkit-ui` is a signed simulator target. Run it only when the
claim depends on HealthKit authorization, batch/archive HealthKit reads, or
local archive projection. It does not prove live Apple Watch metric delivery.

### Realistic-local probes

Use realistic-local integration and end-to-end probes when behavior crosses
more than one runtime boundary and package or server tests only prove the
pieces separately.

Current harness: `make test-sync-real-http` starts FastAPI against a temporary
SQLite database, seeds primitive workout data through real HTTP, drives the
Swift Sync stack through `URLSessionTransport`, writes through SwiftData,
pushes slot and aggregate primitive results back, and reads the server database
to prove persistence plus same-UUID upsert for the slot row. Aggregate rows are
currently proven for persistence, not repeated upsert. It is wired into
`make pre-qa`.

## Pre-QA Gate

`make pre-qa` is the current local gate before entering `docs/QA.md` flows. It
composes:

- `make check` for Python lint/import contracts, Python tests, and schema
  package tests
- `make test-sync-real-http` for FastAPI + SQLite + Swift URLSession primitive
  sync and server-persistence proof
- `make check-app` for every wired app package test plus the generated iOS app
  scheme compile/link smoke and code-signing-free execution UI proof

Entitlement-dependent probes, such as `make test-healthkit-ui`, sit outside
`make pre-qa` because `test-app-xcode` intentionally runs with
`CODE_SIGNING_ALLOWED=NO`. Run the signed target when the claim depends on
HealthKit authorization, batch/archive HealthKit reads, or local archive
projection. It is not live Apple Watch metric proof.

`make pre-qa` does not replace QA. It proves the deterministic and
realistic-local layers currently wired in the repo. If the behavior depends on
a missing realistic-local harness, route that capability gap through the owning
docs and `docs/feature-gap-map.md` before relying on QA.

Before simulator/device QA, run `make qa-ready` to verify XcodeBuildMCP tool
availability. That is QA readiness, not testing proof.

## Current Gaps

- Claude-side behavior is not directly tested by design. If an invariant about
  what Claude pushes needs pinning, encode it as a server-side validator and
  test.
- `TEST-GAP-002`: real app-hosted behavioral invariants beyond the current
  compile/link smoke.
- `TEST-GAP-003`: real-device proof harnesses for Watch-backed live HealthKit
  metrics and other device-only behavior. Simulator archive proof is routed
  through `docs/testing/external-boundaries.md` and
  `docs/healthkit-data-access.md`.
- `TEST-GAP-004`: foreground/background sync lifecycle proof. Package tests pin
  the Shell coordinator, but simulator/app-root evidence does not yet prove the
  running app's `scenePhase` path invokes that coordinator correctly.
- `TEST-GAP-005`: runtime proof baselines for timer routes, large Today/History
  surfaces, save/reset object lifetime, and sheet dismissal loops. ETTrace and
  memgraph evidence are required before claiming those runtime properties
  verified.
