---
title: Boundary matrix
status: accepted
date: 2026-04-17
purpose: The authoritative list of which module may depend on which. Every row + column in the matrix corresponds to a package or layer. Each cell is either allowed or forbidden. Violations are errors, not warnings.
covers:
  - server/
  - app/
  - schema/
---

# Boundary matrix

**How to read.** Rows = source module (the importer). Columns = target module (the imported). Symbols:

| Symbol | Meaning |
|---|---|
| `–` | Allowed |
| `✗` | Forbidden |
| `·` | Self |
| `!` | Actual violation (should be empty in a green build) |

Enforcement level: **error** for every forbidden cell. See `docs/architecture/fitness-functions.md` for which tool catches each rule.

---

## Server (Python) — current state

Source = importer; Target = package it imports.

| Source \ Target | `config` | `logging_setup` | `db` | `models` | `migrations` | `api/*` | `sync/*` |
|---|---|---|---|---|---|---|---|
| **`config`** | · | – | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`logging_setup`** | – | · | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`db`** | – | – | · | – | – | ✗ | ✗ |
| **`models`** | – | – | – | · | – | ✗ | ✗ |
| **`migrations`** | – | – | – | – | · | ✗ | ✗ |
| **`api/*`** | – | – | – | – | – | · | – |
| **`sync/*`** | – | – | – | – | – | ✗ | · |

Enforced by `import-linter` contracts in `pyproject.toml` (already in place). Three layer contracts:
1. Foundation (`config`, `logging_setup`) has no repo-local imports.
2. Data layer (`db`, `models`, `migrations`) never depends on `api`.
3. `sync/*` never depends on `api/*` directly.

### Rules in prose

1. Configuration and logging are the foundation. They know nothing about the rest of the server.
2. The data layer does not reach up into routing. Routes orchestrate data; data doesn't know about routes.
3. Sync logic must not reach into HTTP route handlers. If sync needs something a route has, it's factored out to the data layer or a shared service — not reached for via the route.
4. `api/*` is the outermost layer. Nothing imports from `api/*`.

---

## iOS app (Swift) — target shape

The app doesn't exist yet. This matrix is the spec that Package.swift files and SwiftLint rules will enforce when the Xcode project lands.

Top-level Swift packages (local SwiftPM packages inside `app/Packages/`):

| Source \ Target | `Core/Domain` | `Core/Prescription` | `Core/Autoreg` | `Core/Session` | `DesignSystem` | `schema` | `Persistence` | `Sync` | `HealthKitBridge` | `WatchBridge` | `Features/*` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **`Core/Domain`** | · | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`Core/Prescription`** | – | · | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`Core/Autoreg`** | – | – | · | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`Core/Session`** | – | – | – | · | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`DesignSystem`** | ✗ | ✗ | ✗ | ✗ | · | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`schema`** | ✗ | ✗ | ✗ | ✗ | ✗ | · | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`Persistence`** | – | – | ✗ | ✗ | ✗ | ✗ | · | ✗ | ✗ | ✗ | ✗ |
| **`Sync`** | – | – | ✗ | ✗ | ✗ | – | – | · | ✗ | ✗ | ✗ |
| **`HealthKitBridge`** | – | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | · | ✗ | ✗ |
| **`WatchBridge`** | – | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | – | ✗ | · | ✗ |
| **`Features/*`** | – | – | – | – | – | ✗ | – | – | – | – | ✗ |

Notes:
- `Core/*` packages form a chain: Domain → Prescription → Autoreg → Session. No back-edges. Each `Core` package only imports Domain and `Core` siblings it explicitly declares.
- `Core/*` has zero edge imports (no SwiftData, no URLSession, no HealthKit, no Combine for network work). This is the load-bearing rule for testability.
- `DesignSystem` is pure visual. No Features imports, so a Feature can't sneak a reference to another Feature through DesignSystem.
- `schema` is the wire package; it ships as a SwiftPM dependency and depends on nothing in `app/`.
- `Features/*` can depend on `Core/*`, `DesignSystem`, and edge services (Persistence, Sync, HealthKitBridge, WatchBridge) — but never on another `Features/*` package. Cross-feature flows route through `Core/Session` or the app shell's navigator.
- `Features/*` cannot import `schema` directly — DTOs stop at `Sync`, which maps them to Domain types. This keeps wire schema churn from rippling into Features.
- `Persistence` can import `Core/Domain` and `Core/Prescription` (needs prescription parsing for session state restoration). It does NOT import `Core/Autoreg` or `Core/Session` — those are runtime concerns.
- `WatchBridge` may import `Sync` so watch actions can push to the server via the phone's push queue.

### Rules in prose

1. **Pure Core.** `Core/*` packages are unit-testable with zero mocks. If a Core test needs a stubbed clock, network, or database, the side effect has leaked inward.
2. **Features are siblings.** One Feature never imports another. If two Features need the same thing, it moves to Core.
3. **Wire types stop at Sync.** `schema` DTOs don't cross the Sync boundary. Sync maps DTOs to Domain types; Features see only Domain types.
4. **Edge I/O is named.** Disk (Persistence), network (Sync), HealthKit (HealthKitBridge), watch IPC (WatchBridge). If a new effect appears (audio, location, camera), it gets its own named package.
5. **DesignSystem is visual-only.** Tokens, primitives, animations. No routing logic, no business rules.
6. **The app shell is thin.** `WorkoutDB.app`'s own target composes the packages and hosts the root view. It is not a place where logic accumulates.

---

## Monorepo — top-level invariants

| Directory | Purpose | Rule |
|---|---|---|
| `server/` | Python FastAPI + SQLite | Owns server-side boundaries via `import-linter` |
| `app/` | iOS + watchOS target | Owns app-side boundaries via SwiftPM + SwiftLint |
| `schema/` | Wire contract (OpenAPI + Swift DTOs) | Must not import from `server/` or `app/` — pure types |
| `tests/` | Cross-stack tests (server, contract, architecture) | Contains no production code |
| `docs/` | Durable documentation | No generated files; reference data only |
| `scratch/` | Ephemeral, gitignored | Not part of the boundary system |
| `deploy/` | Deployment assets (systemd, config) | No application code |
| `planner/` | (reserved) upstream Claude CLI | Does not exist yet; reserved top-level slot |

**Monorepo rule:** ≤ 8 top-level directories. A 9th directory requires an ADR. Enforced by a structural test (`tests/architecture/test_monorepo_shape.py`).

---

## Violations register

| Source | Target | Import | Status | Plan | Expiry |
|---|---|---|---|---|---|
| *(none at 2026-04-17)* | | | | | |

Any future violation that must be allowed temporarily is an entry here with owner, reason, and expiry date. No permanent exceptions without an ADR.
