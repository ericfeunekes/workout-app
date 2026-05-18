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
  - docs/feature-gap-map.md
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

Run: `uv sync --extra dev && uv run pytest`.

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

Run the fast Core + Sync subset with `make test-core`.

Run every currently wired app package test target with:

```bash
make test-app-packages
```

This gate covers executable Swift package test targets and XCTest packages
under `app/Packages/`. It is the package-level app proof expected before
implementation closeout for app logic changes.

## App-hosted tests — `app/WorkoutDBTests`

**Integrated app build and launch proof.** Run via Xcode / `xcodebuild`.

Scope:
- app target compiles and links with all package dependencies
- app-hosted smoke tests for launch-time composition
- targeted integrated invariants that need the actual app bundle or simulator
  host

Current gap `TEST-GAP-002`: the `WorkoutDB` scheme currently has only a no-op
smoke test. This tier proves compile/link/XCTest invocation for the generated
app scheme; it is not behavioral app-hosted proof until real launch-time or
composition invariants are added. The next useful invariant is a debug-fixture
launch that proves `RootView` / `Shell.RootTabView` composition, dependency
wiring, and at least one route handoff can render without crashing.

Run directly:

```bash
make test-app-xcode
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

Current harness: `make test-sync-real-http` starts FastAPI against a temporary
SQLite database, seeds primitive workout data through real HTTP, drives the
Swift Sync stack through `URLSessionTransport`, writes through SwiftData, pushes
slot and aggregate primitive results back, and reads the server database to
prove persistence and same-UUID upsert. It is wired into `make pre-qa`.

## Runtime proof — traces, memory graphs, and lifecycle

Runtime proof is still pre-QA when the claim is about cost, object lifetime, or
app lifecycle behavior. Simulator video can show a symptom; it cannot prove the
cause.

Use ETTrace when changing or claiming performance for:

- ticking timer routes, especially Active/Rest flows with `TimelineView` or
  frequent state updates
- launch, bootstrap, and first visible render latency
- scroll-heavy Today and History lists
- any SwiftUI refactor whose purpose is fewer view updates, less CPU, or less
  layout churn

Use memgraph/leaks proof when changing or claiming object lifetime for:

- save-and-done, reset/change-server, and next-workout rebuild flows
- sheet open/dismiss loops
- History list -> detail -> back navigation
- foreground/background task lifetime, especially push flusher and sync tasks
- closures that retain view models, stores, or async pipelines

Store raw runtime artifacts under `scratch/qa-runs/<YYYY-MM-DD>-<slug>/` while
the run is active. A durable closeout should summarize the focused flow,
simulator/device, app build, app-owned hot types or leaked types, and whether
the trace/memgraph actually proves the claim. Do not promote runtime behavior
to `verified` from source inspection alone.

Run `make qa-runtime-ready` before trace/memgraph work. It verifies the local
XcodeBuildMCP, `xctrace`, `simctl`, and `leaks` tool surface and creates the
scratch artifact root. It does not capture traces by itself.

## Pre-QA Gate

`make pre-qa` is the current local gate before entering `docs/QA.md` flows.
It composes:

- `make check` for Python lint/import contracts, Python tests, and schema
  package tests
- `make test-sync-real-http` for FastAPI + SQLite + Swift URLSession primitive
  sync and server-persistence proof
- `make check-app` for every wired app package test plus the generated iOS app
  scheme compile/link smoke

`make pre-qa` does not replace QA. It proves the deterministic and
realistic-local layers currently wired in the repo. If the behavior depends on
a missing realistic-local harness, route that capability gap through the owning
docs and `docs/feature-gap-map.md` before relying on QA.

Before simulator/device QA, run `make qa-ready` to verify XcodeBuildMCP tool
availability. That is QA readiness, not testing proof.

## Proof Expectations By Change Type

- **Server schema change** → server test (models) + contract test (parity with app) + migration integration test.
- **New API endpoint** → server test (route behavior) + update `docs/ARCHITECTURE.md` if it changes sync story.
- **Sync protocol change** → server test (endpoint) + contract test (both sides
  agree) + Swift Sync package test; run `make test-sync-real-http` when the
  claim depends on URLSession, auth headers, primitive result push plus server
  persistence, or the real FastAPI boundary.
- **New timing mode before primitives cutover** → update spec + server enum + app enum + contract test + app timer test.
- **Primitives data-model cutover** → update the primitives spec/aspects, server schema, Swift DTOs, SwiftData schema, contract tests, local-history migration proof, and app execution tests in the same cutover branch before merge.
- **New `user_parameters` key the app interprets** → app package test for the
  resolver and persistence/sync proof if the key is stored or pushed.
- **User-visible iOS feature change** → Swift package tests for logic/state,
  app-hosted smoke/integration proof where composition matters, then
  `docs/QA.md` for simulator/device UX evidence.
- **SwiftUI performance or large-view refactor** → package tests for state and
  sheet routing, plus ETTrace when the claim is lower CPU, smoother scrolling,
  faster render, or fewer updates.
- **Object lifetime, reset, save-and-done, foreground/background, or sheet
  lifecycle change** → package/app-hosted proof for state ownership, plus
  memgraph/leaks evidence when the claim is no retained view model, task, store,
  or sheet model after dismissal/reset.
- **Foreground/background sync lifecycle change** → package or app-hosted proof
  for the app-sync owner named in `docs/sync.md`, plus simulator QA for
  background/foreground behavior. The deterministic proof must cover
  foreground pull, cache writeback, `lastSyncAt`, push flusher
  start/restart/stop posture, token rejection, and lifecycle telemetry.
  Current gap `TEST-GAP-004`: package tests now pin the Shell coordinator,
  but simulator/app-root evidence does not yet prove the `scenePhase` path in
  a running app.
- **Watch, HealthKit, haptics, physical ergonomics, sleep/wake, or real network
  behavior** → package/fake tests for logic plus real-device or dedicated proof
  per `docs/QA.md` before claiming the device behavior verified.
- **Pure helper** → unit test in the owning stack.

## What's not under test yet

- Claude-side behavior (conversation-driven planning, progression) — by design. If an invariant about what Claude pushes needs pinning, encode it as a server-side validator + test.
- `TEST-GAP-002`: real app-hosted behavioral invariants beyond the current
  no-op app compile/link smoke.
- `TEST-GAP-003`: real-device proof harnesses for Watch, HealthKit, and
  device-only behavior.
- `TEST-GAP-004`: foreground/background sync lifecycle proof. The package suite
  now covers the Shell app-sync coordinator's foreground pull, cache writeback,
  `lastSyncAt`, flusher start/restart/stop posture, token rejection, offline
  fallback, and lifecycle telemetry. Remaining proof gap: simulator/app-root
  evidence that the running app's `scenePhase` path invokes that coordinator
  correctly.
- `TEST-GAP-005`: runtime proof baselines for timer routes, large Today/History
  surfaces, save/reset object lifetime, and sheet dismissal loops. ETTrace and
  memgraph evidence are required before claiming those runtime properties
  verified.
