---
title: Architecture — monorepo shape, Swift package graph, enforcement
status: accepted
date: 2026-04-17
covers:
  - server/
  - app/
  - schema/
  - tests/
  - docs/architecture/
---

# ADR: Architecture — monorepo shape, Swift package graph, enforcement

**Complements:** `ADR-2026-04-17-ux-scope.md` (auth, network reach, watch scope, history query shape), `ADR-2026-04-17-rir-autoreg-sync.md` (RIR, autoreg, sync formalization). This ADR sits on top of both and converts the system we've spec'd into a structural contract with enforcement.

## Context

By this point the spec (`docs/specs/v2-architecture.md`), prescription vocabulary (`docs/prescription.md`), and sync protocol (`docs/sync.md`) describe *what* the system does. The design bundle describes *how it feels*. Two consistency passes surfaced the remaining shape-level questions: monorepo layout, Swift app package graph, state ownership, dependency direction, and how to prevent the modules we've already named as future hotspots (SyncManager god, TimingEngine mega-switch, PrescriptionReader computation engine, SettingsView dumping ground, Utils bucket, api/schemas.py shadow).

The user directive was clear: decisions and contracts are written; automation enforces. A rule that lives only in prose will be violated within a week. Hotspots must be designed against by the graph and the lint rules, not just flagged in docs.

This ADR codifies the answer. The detailed views live in `docs/architecture/`:
- `context.md` — the 9-question answers and intentional postponements.
- `boundaries.md` — the boundary matrix for server and Swift packages.
- `fitness-functions.md` — every rule → the tool that enforces it.
- `hotspots.md` — preemptive register of named risk + its enforcement.
- `swift-packages.md` — the Swift package graph authoritative table.

## Decision

### 1. Monorepo shape: one deployable server + one iOS+watchOS app

Three deployable units: `workoutdb-server` (Python FastAPI + SQLite), `WorkoutDB.app` (iOS), `WorkoutDBWatch.app` (watchOS). No microservices, no workers, no queue. Watch talks to phone, phone talks to server.

Top-level directories capped at 8, allowlisted in `tests/architecture/test_monorepo_shape.py` (FF-4). Allowed set: `server/`, `app/`, `schema/`, `tests/`, `docs/`, `deploy/`, `scratch/`, `planner/` (reserved for the upstream Claude CLI, doesn't exist yet).

### 2. Server layering: foundation → data → api, already in place

No change to the existing structure. `import-linter` contracts in `pyproject.toml` already enforce the three layer rules (FF-1). Addition: `ruff` now selects `E/F/W/I/B/C901` with `max-complexity = 10` (FF-2, FF-3).

### 3. Swift app: feature-module monorepo inside `app/`

Package graph documented in `docs/architecture/swift-packages.md`. Core principles:

- **Pure Core.** `Core/*` packages import nothing from edge modules. SwiftData, URLSession, HealthKit, WatchConnectivity are all forbidden in Core.
- **Feature isolation.** `Features/*` packages do not import each other. Cross-feature flow routes through `Core/Session` or the app shell's navigator.
- **Edges are named.** Disk → `Persistence`; network → `Sync`; HealthKit → `HealthKitBridge`; watch IPC → `WatchBridge`. Each edge is the only place its corresponding API appears.
- **Wire types stop at Sync.** `schema` DTOs don't cross the Sync boundary. Sync maps DTOs to Domain types; Features see only Domain types.
- **No Utils/Helpers/Common packages.** Shared code has a named home (`Core/Foundation` for pure utilities, `DesignSystem` for visual primitives) or lives where it's used.

### 4. State ownership: one authoritative writer per piece of mutable state

Documented in `docs/architecture/context.md` § 3. Notable:
- `set_log` rows owned by the app (writer + editor). Server stores.
- `user_parameters` append-only: Claude pushes most keys; app pushes `bodyweight_kg` at completion. Direction is still server-read, app-write for that one key.
- Local session state (cursor, route, log, `adjust`, `autoregHeld`, `rest_ends_at`) owned by `Core/Session`. Features subscribe via a `SessionStore` protocol.
- Bearer token in keychain; server URL in `UserDefaults`; both mediated by `Persistence`.

### 5. Dependency directions: explicit, acyclic, enforced by compiler + linter

Full matrix in `docs/architecture/boundaries.md`. Enforced at three levels:
1. **Compiler (strongest).** SwiftPM's `Package.swift` dependency declarations — a package can only import its declared deps.
2. **Import linter.** `import-linter` contracts in `pyproject.toml` (Python side).
3. **Source linter.** SwiftLint `custom_rules` in `app/.swiftlint.yml` catch within-package violations (a Feature file importing `URLSession` directly when its package has no Sync dep).

### 6. Enforcement: every rule has exactly one mechanism

Full registry in `docs/architecture/fitness-functions.md`. 15 fitness functions across three zones:

- **Server (live today):** FF-1 (layering), FF-2 (complexity), FF-3 (ruff lint surface).
- **Cross-stack structural tests (live today):** FF-4 (monorepo shape), FF-5 (ADR index parity), FF-6 (prescription shape ↔ fixture parity — skips until first fixture lands, then enforces), FF-7 (no RPE — xfail until cutover), FF-8 (OpenAPI drift — existing), FF-9 (Swift parity — existing), FF-10 (open-questions hygiene).
- **iOS app (activation-pending, config committed):** FF-11 (Core purity via SwiftPM), FF-12 (Feature isolation via SwiftPM), FF-13 (SwiftLint custom rules for URLSession/SwiftData/HealthKit/WatchConnectivity/print/RPE/Utils/cross-Feature imports), FF-14 (Swift cyclomatic complexity), FF-15 (file/type body length).

No warning-only rules. Every rule is `error`; exceptions go into `docs/architecture/boundaries.md` violations register with owner + expiry.

### 7. Preemptive hotspot register

`docs/architecture/hotspots.md` names 8 modules that would become god objects if unchecked — with the specific design move + automation that prevents each:

- **HS-1 `Sync` god object** → split into `PullService` + `PushQueue` + `ConnectionManager` on day one; FF-13 keeps URLSession out of other packages; `file_length: 400` caps any single Sync file.
- **HS-2 `TimingEngine` mega-switch** → `TimingDriver` protocol with one conforming file per timing mode in `Features/Execution/Drivers/`; `file_length` and `type_body_length` caps prevent monolithization.
- **HS-3 `PrescriptionReader` computation engine** → split parsing (`Core/Prescription`, per-shape functions) from computation (`Core/Autoreg` for autoreg rules, `Core/Session` for percent_1rm resolution); package boundaries enforce separation.
- **HS-4 `SettingsView` dumping ground** → section-as-type, data-driven list of `SettingsSection` values.
- **HS-5 Utils/Helpers bucket** → banned outright; SwiftLint custom rule + structural test.
- **HS-6 `api/schemas.py` domain-shadow** → cap file size; split by route module at the next schema change.
- **HS-7 Watch duplicate logic** → Core/* builds for both iOS and watchOS; watch imports the same Core packages, no duplication.
- **HS-8 Docs drift** → structural tests (FF-5, FF-6, FF-7, FF-10) make docs machine-checkable.

### 8. Intentional postponements

Named in `docs/architecture/context.md` § 9. Key ones:
- Microservices / queues / workers → single-user doesn't justify.
- Cache layer → revisit if p99 latency on sync pull exceeds 500 ms.
- Codegen from OpenAPI → hand-written DTOs stay until the surface exceeds ~50 entities.
- TCA or equivalent → `@Observable` + `SessionStore` is enough for the state shape.
- `planner/` CLI in this repo → reserved slot only; ships when the CLI author starts.
- Watch as independent sync client → phone remains sole server-facing client.
- Observability stack (tracing, metrics) → JSON logs + request IDs suffice.

## Consequences

### Delivered today (this ADR's commit)

- `docs/architecture/context.md`, `boundaries.md`, `fitness-functions.md`, `hotspots.md`, `swift-packages.md` — the full structural contract.
- `pyproject.toml` updated: ruff now enforces `E/F/W/I/B/C901` with McCabe threshold 10. `[tool.ruff.lint.per-file-ignores]` exempts B008 for FastAPI route defaults.
- `tests/architecture/` with five structural tests: monorepo shape (FF-4), ADR index parity (FF-5), prescription shape parity (FF-6, skips until first fixture), no-RPE (FF-7, xfail until cutover), open-questions hygiene (FF-10).
- `app/.swiftlint.yml` — SwiftLint config with 9 custom rules covering FF-13, plus FF-14 (complexity) and FF-15 (file/type length). Activates automatically once the Xcode project exists.
- `.pre-commit-config.yaml` — SwiftLint hook added, no-ops until the project exists.

### Still to do (scoped as the smallest next step; see below)

- The RIR cutover (FF-7 xfail → pass): `server/db/migrations/NNN_rpe_to_rir.sql` + `performed_exercise_id` column; model + schema + Swift DTO updates; OpenAPI regeneration; fixture updates. See `docs/decisions/ADR-2026-04-17-rir-autoreg-sync.md` § Consequences.
- Xcode project creation — the moment this lands, FF-11 through FF-15 activate.
- First prescription shape fixtures — unlocks FF-6.

### Things that did not change

- Server layout stays as-is.
- Schema package (`schema/`) stays hand-written DTOs + OpenAPI + Swift.
- Existing contract tests (FF-8, FF-9) stay.
- Pre-commit / pre-push hook behaviour stays the same shape.

## Alternatives considered

- **A single big Swift target with source folders, not SwiftPM packages.** Faster to set up; no compile-time boundary enforcement. Rejected — the whole point of this ADR is compile-time enforcement over prose.
- **TCA for app state.** Formal, deterministic, testable. Rejected — the session state shape (cursor, log, autoregHeld) fits `@Observable` cleanly; TCA's machinery would be overkill.
- **`Utils/` under `Core/`** for small helpers. Rejected — that's exactly the pattern HS-5 prevents. `Core/Foundation` has a named purpose (clock, IDs, formatting); nothing else goes there.
- **Watch as a SwiftPM package under `schema/`.** Rejected — mixes wire contract with a domain concern. Watch faces are Features.
- **Warning-level enforcement on some rules, error on others.** Rejected — warnings decay. Every rule is error-level; exceptions are explicit and time-bound.
- **Dependency-cruiser-style cross-stack graphs.** Rejected for now — `import-linter` + SwiftLint + structural tests cover the current surface. Revisit if the monorepo ever grows a third language or independent tooling needs cross-language dep analysis.

## Done when

- [x] ADR is committed.
- [x] `docs/architecture/*.md` all exist and are accepted.
- [x] Python enforcement live: ruff with complexity, import-linter contracts, 5 structural tests, all green in `uv run pytest`.
- [x] Swift enforcement config committed ahead of project creation (`app/.swiftlint.yml`).
- [x] Pre-commit hook for SwiftLint added (no-ops until project lands).
- [x] ADR index (`docs/AGENTS.md` + FF-5) lists this ADR.

## Open questions

- What's the watchOS deployment target? `supportedPlatforms` in Package.swift needs a specific version. Assumed `.watchOS(.v10)` but worth confirming before the first Xcode project.
- Who is the owner of exceptions in the violations register? Single-user today = Eric. List in a future ADR when a second contributor appears.
