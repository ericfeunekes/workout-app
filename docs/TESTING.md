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
  - docs/QA.md
---

# Testing

Pre-QA proof contract for WorkoutDB. Testing proves behavior through automated
or realistic-local checks before exploratory simulator/device QA starts.

See also: `docs/MIGRATIONS.md` (schema cutover flow), `docs/prescription.md`
(current pre-primitives prescription shape contract),
`docs/specs/primitives-data-model.md` (accepted target shape for the
primitives cutover), `docs/sync.md` (sync protocol contract), and `docs/QA.md`
(exploratory simulator/device QA after testing gates are green).

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
  local stand-in the repo supports: SQLite DBs, in-process FastAPI app, SwiftData
  containers, real URLSession/fake server, recorded fixtures, controlled clocks,
  or real concurrent execution.

When the test infrastructure lacks the stand-in a seam needs, record that as a
capability gap. The choice is then build the infra, defer with named risk, or
cut the behavior from scope. Do not silently downgrade the proof bar to a mock.

## Test Tiers

The system has several testable stacks. Each tier answers a different question.

## Server tests (Python) — `tests/server/`

**Fast, pytest, no iOS dependency.** These prove server behavior against the
FastAPI app and local SQLite-backed state.

Scope:
- Pydantic / ORM model validation.
- API route handlers (via `httpx.AsyncClient` against an in-memory FastAPI app).
- Sync endpoint correctness (pull-with-since, idempotent results push).
- Migration idempotency and forward compatibility.

Run: `uv pip install -e ".[dev]" && pytest`.

## Contract tests — `tests/contract/` and `schema/`

**Cross-stack schema parity.** Pin the schema shape so the server and SwiftData can't drift silently.

Scope:
- Every entity in the spec is present in both server and app schemas.
- Every field name, type, and nullability matches.
- Current pre-primitives state: `timing_mode` enum and `prescription_json` shapes are identical on both sides.
- Primitives cutover state: Block > Set > Slot schema, timing/traversal/repeat cells, primitive prescription fixtures, and primitive log roles are identical on both sides. The cutover is not done while both contract families are accepted.

Mechanism depends on the `schema/` decision (OpenAPI vs hand-mirrored). Until `schema/` is populated, contract tests live as failing placeholders or spec-referenced assertions.

Run: `uv run pytest tests/contract` and `cd schema && swift test`.

## Swift package tests — `app/Packages/`

**App logic below the visible UI.** These are the main pre-QA proof layer for
the iOS app.

Scope:
- Pure Core behavior: IDs, formatting, domain values, prescription parsing,
  autoregulation, session reducer and timing state.
- Feature view-model behavior: Today, Execution, FirstRun, History, Settings,
  and WatchFaces.
- Persistence behavior against SwiftData containers and Keychain/defaults
  wrappers where available.
- Sync behavior against deterministic transports and queues.
- Watch/HealthKit bridge behavior against fakes where real device behavior is
  not being claimed.

Run current partial gate: `make test-core`.

Current gap: `make test-core` does not run every package test target. Add or
use a broader `make test-app-packages` / `make check-app` gate before relying on
package-level app proof for implementation closeout.

## App-hosted tests — `app/WorkoutDBTests`

**Integrated app build and launch proof.** Run via Xcode / `xcodebuild`.

Scope:
- app target compiles and links with all package dependencies
- app-hosted smoke tests for launch-time composition
- targeted integrated invariants that need the actual app bundle or simulator
  host

Current gap: the `WorkoutDB` scheme currently has only a no-op smoke test. Add
real app-hosted invariants before treating this tier as behavioral proof.

Run:

```bash
xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## Realistic-local integration and end-to-end probes

Use these when a behavior crosses more than one runtime boundary and package or
server tests only prove the pieces separately.

Expected shapes:
- server/app sync: run the FastAPI app locally with a temporary SQLite DB and
  drive a Swift Sync probe or integration test against the real HTTP boundary
- persistence migration: exercise real SwiftData migration paths against local
  fixture stores
- URLSession/auth/offline behavior: use a real local server or fake server at
  the HTTP boundary, not only mocked transport calls
- time/retry behavior: use controlled clocks where the code supports them; use
  bounded real-time probes only when clock injection is impossible
- concurrency/idempotency: exercise actual concurrent callers against the seam

Current gap: there is no single local server/app sync harness yet. Keep this as
an explicit capability gap when implementation touches real URLSession +
FastAPI + SQLite behavior.

## Proof Expectations By Change Type

- **Server schema change** → server test (models) + contract test (parity with app) + migration integration test.
- **New API endpoint** → server test (route behavior) + update `docs/ARCHITECTURE.md` if it changes sync story.
- **Sync protocol change** → server test (endpoint) + contract test (both sides
  agree) + Swift Sync package test; add a realistic-local server/app sync probe
  when the claim depends on URLSession, auth headers, or the real FastAPI
  boundary.
- **New timing mode before primitives cutover** → update spec + server enum + app enum + contract test + app timer test.
- **Primitives data-model cutover** → update the primitives spec/aspects, server schema, Swift DTOs, SwiftData schema, contract tests, local-history migration proof, and app execution tests in the same cutover branch before merge.
- **New `user_parameters` key the app interprets** → app package test for the
  resolver and persistence/sync proof if the key is stored or pushed.
- **User-visible iOS feature change** → Swift package tests for logic/state,
  app-hosted smoke/integration proof where composition matters, then
  `docs/QA.md` for simulator/device UX evidence.
- **Watch, HealthKit, haptics, physical ergonomics, sleep/wake, or real network
  behavior** → package/fake tests for logic plus real-device or dedicated proof
  per `docs/QA.md` before claiming the device behavior verified.
- **Pure helper** → unit test in the owning stack.

## What's not under test yet

- Claude-side behavior (conversation-driven planning, progression) — by design. If an invariant about what Claude pushes needs pinning, encode it as a server-side validator + test.
- A complete `make pre-qa` gate that composes server/schema checks, all runnable
  app package tests, app-hosted smoke tests, and any required local
  integration/end-to-end probes.
