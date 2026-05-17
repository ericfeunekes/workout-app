---
title: Architecture context and 9-question answers
status: accepted
date: 2026-04-17
purpose: The understanding behind the architecture decisions. Demonstrates what's being designed and why. Everything in docs/architecture/ and docs/decisions/ADR-2026-04-17-architecture.md flows from here.
covers:
  - server/
  - app/
  - schema/
  - tests/
---

# Architecture context

## Context

**What we're shaping.** A three-tier system where Claude (outside the system) authors workouts, a Python FastAPI + SQLite home server stores them, and a SwiftData iOS app (with a WatchKit companion) executes and logs them. The iOS app is an offline-first renderer + logger — no programming logic, no analysis, no exercise selection. The design bundle at `docs/design/` is the UX reference; `docs/specs/v2-architecture.md` is the spec.

**Where we are.** The server exists and is well-layered already — `import-linter` contracts enforce foundation -> data -> api dependency direction. The schema package exists with OpenAPI + Swift DTOs + contract tests preventing drift. The iOS app exists as a local SwiftPM package graph generated into Xcode by `app/project.yml`; Shell owns bootstrap and root tab composition, while Features own user-visible screens. The `docs/open-questions.md` gap register lists unresolved product/design decisions; implementation and proof gaps live in owning docs plus `docs/feature-gap-map.md`.

**What the developer is trying to achieve.** Build correctly from day one. Decisions captured as written contracts; contracts enforced by automation; hotspots designed against before they exist. A future Claude that sits down at this repo six months from now should be unable to accidentally drift — the harness makes the correct move the easy move.

**How the current structure serves (or fails) the goal.**

Serves:
- Server is layered (foundation → data → api) with import-linter contracts.
- Schema parity enforced by OpenAPI drift + Swift round-trip tests.
- Prescription shape vocabulary is documented (`docs/prescription.md`) and marked as the authority.

Fails:
- Swift-side package boundaries exist through SwiftPM and `app/project.yml`; some architectural fitness functions still need stronger automation.
- No complexity gate on Python — a single file can grow unboundedly without signal.
- No structural tests for monorepo invariants (ADR index parity, prescription-shape ↔ fixture parity, no-RPE-resurrection after the RIR cutover).
- The hotspot register is now an active guardrail. Settings, Sync, timer drivers, and DesignSystem seams still need ongoing proof as the app grows.

This doc answers the 9-question sequence that the architecture skill requires. The answers constrain everything downstream.

---

## The 9 questions

### 1. Smallest deployable shape

**Three deployable units:**

1. **`workoutdb-server`** — single Python process, FastAPI + SQLite + `uvicorn`, launchd LaunchDaemon on Eric's home server, reachable over Tailscale.
2. **`WorkoutDB.app`** — the iOS app binary, installed on Eric's phone via Xcode/TestFlight.
3. **`WorkoutDBWatch.app`** — the watchOS companion, installed to the paired watch via the iOS app.

**Communication:**
- iOS ↔ server: HTTPS, bearer-token auth, JSON over REST. See `docs/sync.md` for the protocol.
- iOS ↔ watch: WatchConnectivity (Apple's local IPC).
- watch → server: never directly. Phone is the sole server-facing client.

**No microservices, no background workers, no queue, no cache layer.** Single-user scale doesn't justify them. Revisit when there is a second user with an independent deploy cadence.

### 2. Main domains

Five bounded contexts. Each owns a coherent set of concepts and operations; changes to one do not routinely force a coordinated change in another.

| Domain | Owns | Lives in |
|---|---|---|
| **Prescription** | What Claude authored: the shape of a workout (blocks, items, timing, load, autoreg config). Parsing prescription_json, resolving percent_1rm, applying autoreg rules. | `app/Packages/Core/Prescription`, `app/Packages/Core/Autoreg` (and on the server: `server/workoutdb_server/models.py` + `api/schemas.py`) |
| **Session** | The live-in-flight workout: cursor, route, log, autoregHeld, adjust glyphs, rest timer state. | `app/Packages/Core/Session` |
| **Persistence** | SwiftData stack, migrations, local cache management, keychain for the bearer token. | `app/Packages/Persistence` |
| **Sync** | Talking to the server: Pull, Push Queue, Connection, 401 handling. | `app/Packages/Sync` |
| **Presentation** | SwiftUI views per feature (Today, Execution, History, Settings, FirstRun). Plus Watch faces. | `app/Packages/Features/*` |

**Shared utilities** live in `Core/Foundation` (time, IDs, currency-free math) or `DesignSystem` (visual tokens, primitives). There is no `Utils/` bucket. Rule: if something doesn't fit a named domain, we name it or put it where it's used — never into a shared bag.

### 3. State ownership

Every mutable piece of state has one authoritative writer.

| State | Owner | Readers |
|---|---|---|
| Workouts, blocks, items (prescriptions) | Server (Claude via server) | App reads via Sync → Persistence |
| Exercises, alternatives | Server | App reads via Sync → Persistence |
| `user_parameters` (append-only log) | Server for pushes from Claude; App for `bodyweight_kg` at completion | App reads via Sync for resolution; Claude reads via `GET /api/user-parameters` |
| `set_log` rows | App (during a workout; edits any time) | Server stores; pushed via Sync |
| `workout.status` transitions | App (`planned → active → completed/skipped`) | Server stores |
| Local session state (cursor, route, log, adjust, autoregHeld, rest_ends_at) | App (Session domain only) | Features read via a narrow `SessionStore` protocol |
| Bearer token | Keychain (via Persistence) | Sync reads |
| Server URL | UserDefaults (via Persistence) | Sync reads |

**No shared writers.** If a field would be written from both sides, one side owns it and the other reads a projection. `bodyweight_kg` is the edge case: app pushes; server stores; Claude reads. Direction is still app → server.

### 4. Validation boundaries

Validation happens where untrusted input enters.

| Boundary | Validator | Enforcement |
|---|---|---|
| HTTP requests → server | Pydantic models in `api/schemas.py` | FastAPI runs validation before the route handler sees the request |
| Sync pull response → app | Swift Codable with `CodingKeys`, fails loudly on missing fields | Decoding error surfaces as a sync failure, not silent corruption |
| `prescription_json` → app timing driver | Per-shape parsers in `Core/Prescription` (`parseStraightSets`, etc.) | Each parser returns `Result<T, ParseError>`; callers handle both cases |
| User input (numpad, RIR picker) → session | View-layer input coercion (numeric parsing, clamping) | Session never accepts raw strings |
| First-run connection string → app | Format check (URL + token parseable) before keychain persist | Invalid strings rejected at the welcome screen |
| Watch → phone messages | Codable WatchConnectivity payloads with explicit versioning | Unknown message versions dropped with log |

**Prescription JSON is the key nuance.** The server stores it opaquely — no server-side validation of shape. The app validates when it parses. This is intentional: it lets Claude add shapes without a schema migration, at the cost of "if Claude writes garbage, the app fails at execution time." `docs/prescription.md` is the authority that prevents that.

### 5. Side-effect boundaries

Pure computation lives in `Core/*`. Side effects live in edge packages.

| Effect | Edge module |
|---|---|
| Disk I/O (SwiftData reads/writes, keychain, UserDefaults) | `Persistence` |
| Network I/O (HTTPS, sync, retries) | `Sync` |
| HealthKit queries | `HealthKitBridge` |
| WatchConnectivity | `WatchBridge` |
| Clock (`Date.now`) | Injected as a `Clock` protocol, real impl in `Persistence`, fake in tests |
| Audio (rest timer chime, haptics) | `SystemBridge` (to be named at scaffold time if needed) |

**Testability contract:** `Core/*` packages must be unit-testable with zero mocks. If a Core test has to stub a clock, network, or database, the side effect has leaked inward. Enforced by: `Core/*/Package.swift` cannot import `SwiftData`, `Foundation.URLSession`, or edge packages. See `docs/architecture/boundaries.md`.

### 6. Dependency directions

```
Features/*  ──▶  DesignSystem
    │       ─▶  Core/*  (Domain, Prescription, Autoreg, Session)
    │       ─▶  Sync (via protocol)
    │       ─▶  Persistence (via protocol)
    │       ─▶  HealthKitBridge (via protocol)
    │
Sync        ──▶  Core/Domain
            ──▶  schema DTOs
            ──▶  Persistence (for session-state writes on sync completion)
Persistence ──▶  Core/Domain
HealthKitBridge ──▶  Core/Domain
WatchBridge ──▶  Core/Domain
            ──▶  Sync (for push-on-watch-tap routing)
Core/*      ──▶  nothing (pure)
DesignSystem ──▶  nothing (pure)
schema (SwiftPM package) ──▶  nothing
```

**Rules:**
- `Core/*` imports nothing from edge modules, no SwiftData, no URLSession, no Combine for reactive I/O.
- `Features/*` do not import each other. Cross-feature flow goes through `Session` or a navigator in the shell target.
- `DesignSystem` does not import `Features/*` (so it stays visual-only).
- No back-edges. No cycles.

Enforced by SwiftPM package boundaries (a package declares its dependencies; anything else is a compile error) + SwiftLint custom rules for within-package patterns.

### 7. Quality attributes

Picking the 2–3 that drive architectural tradeoffs and attaching concrete thresholds.

| Attribute | Threshold / target | Tradeoff it justifies |
|---|---|---|
| **Offline-correctness** | A workout fully cached before start must execute to completion with zero network calls. Sync pull + push queue are separate concerns. | Push queue is in-process, persistent, with idempotent retries — costs complexity, buys "you can't be stranded at the gym." |
| **Testability of Core** | `Core/*` unit tests run in ≤ 2 seconds total with no mocks. | Pure-core architecture costs a mapping layer between SwiftData models and domain types — buys the ability to change persistence without touching domain rules. |
| **Schema drift zero** | OpenAPI drift + Swift parity + prescription shape ↔ fixture parity are all CI gates. A new shape merged without a fixture fails the build. | Manual mapping costs more than codegen on day one — buys readable types and a hard signal on drift. |

Explicit non-priorities: throughput (single user), low p99 latency (gym time, not millisecond-sensitive), availability (planned downtime during deploy is fine), security hardening (tailnet + bearer is enough for single-user; no public exposure).

### 8. Enforcement rules

Every rule above gets a specific automated enforcement mechanism. Full registry in `docs/architecture/fitness-functions.md`.

| Rule | Mechanism | Where it runs |
|---|---|---|
| Foundation → data → api layering (server) | `import-linter` contracts | pre-push + CI |
| No cycles in Python imports | `import-linter independence` contracts | pre-push + CI |
| Python complexity per function | `ruff` C901, max-complexity 10 | pre-commit + CI |
| Core/* has no edge imports (Swift) | SwiftPM package graph + SwiftLint `custom_rules` | compile + lint |
| Features/* don't import each other | SwiftPM package graph | compile |
| DesignSystem has no Features imports | SwiftPM package graph | compile |
| No `print`, use `Logger` | SwiftLint `custom_rules` | lint + CI |
| No direct `URLSession` outside Sync | SwiftLint `custom_rules` | lint + CI |
| No direct `SwiftData` outside Persistence | SwiftLint `custom_rules` | lint + CI |
| ADR index ↔ files parity | Python structural test | CI |
| Prescription shape ↔ fixture parity | Python structural test | CI |
| No `RPE`/`rpe_target` resurrection | Python structural test | CI |
| OpenAPI drift | Existing contract test | CI |
| Swift schema parity | Existing contract test | CI |
| Monorepo top-level shape (≤ 8 top-level dirs) | Python structural test | CI |

All `error` level; no warnings-only rules in v1 (rules with soft enforcement erode first).

### 9. Postponed intentionally

Named decisions we are NOT making now, with revisit triggers.

| Postponed | Why | Revisit when |
|---|---|---|
| Microservices / workers / queues | Single-user scale | A second user with independent deploy cadence appears |
| Cache layer | All reads hit SQLite directly; single-digit QPS | p99 latency on sync pull exceeds 500ms |
| Codegen from OpenAPI | Hand-written DTOs are readable; small surface | DTO count exceeds 50 entities or drift maintenance becomes painful |
| TCA or another formal state lib | `@Observable` + a `SessionStore` actor is enough for the state shape | Session state becomes non-local enough to regret (e.g., multi-workout, multi-window) |
| A `planner/` package in this repo | Upstream Claude CLI is a separate effort; docs are the handoff | The CLI's author sits down to build it — it lands as a peer to `server/` |
| Watch as independent sync client | Phone is the sole server-facing client | Watch-first workflow becomes a hard requirement, not a convenience |
| Dependency-cruiser-style cross-stack checks | `import-linter` + SwiftLint + structural tests cover the current surface | Cross-stack coupling emerges that isn't caught by the existing suite |
| Observability stack (tracing, metrics) | JSON logs + request IDs on server are enough | Debugging a cross-stack issue is painful enough to motivate it |
| Mutation testing | `pytest` coverage + Swift Testing for now | Bugs slip past tests repeatedly |
| Chaos / property-based testing for sync | Unit tests + integration tests on the push queue | Sync bugs appear that deterministic tests can't catch |

## Stop gate verification

- [x] All 9 questions answered.
- [x] Every domain has a single state owner.
- [x] Dependency directions drawn explicitly; no cycles allowed.
- [x] 3 quality attributes named with concrete thresholds.
- [x] Every structural rule has an enforcement mechanism identified.
- [x] Postponements documented with revisit triggers.
- [x] C4 context + container views: both present (context = diagram in this doc; container = § 1 deployable shape).

## What is NOT being generalized yet

- **Server remains a single process.** No split between a write-API and a read-API. No separate sync worker.
- **iOS app is one target with packages inside, not a multi-project workspace.** One Xcode project; SwiftPM local packages for module boundaries.
- **No state machine library.** Session state is plain structs under an Observable store.
- **No dependency injection framework.** Protocols + initializer injection. `Clock` is the only non-trivial injected side-effect.
- **No event bus.** Features subscribe to a store; stores don't publish events globally.
- **`planner/` is not in this repo yet.** We reserve the top-level slot and stop.
