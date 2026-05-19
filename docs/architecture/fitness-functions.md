---
title: Fitness functions
status: accepted
date: 2026-04-17
purpose: Every architectural rule has exactly one enforcement mechanism. This doc is the registry — rule, tool, config, enforcement level, owner. If a rule is here without a live check, that is a bug.
covers:
  - server/
  - app/
  - schema/
  - tests/
---

# Fitness functions

Every rule from `docs/architecture/context.md` and `docs/architecture/boundaries.md` is enforced by exactly one mechanism listed here. The mechanism must be live — either running today, or with an activation date.

## Enforcement levels

| Level | Blocks what | Runs where |
|---|---|---|
| **error** | Merge / build | pre-commit, pre-push, CI |
| **activation-pending** | (Nothing yet) | Stubbed; activates on named trigger |

**No warning-only rules in v1.** Soft rules erode. If a rule isn't worth failing the build, it isn't a rule.

---

## Server (Python) — live today

### FF-1 · Server layering contract

**Rule:** Foundation (`config`, `logging_setup`) has no repo-local imports. Data layer (`db`, `models`, `migrations`) never imports from `api`. `sync/*` never imports directly from `api/*`. Enforces rows 1, 2, 3 of the server boundary matrix.

**Why it matters:** Any reversal of the dependency direction turns the layer cake into a hairball. Routing concerns leaking into models make the models impossible to test without FastAPI running.

| Field | Value |
|---|---|
| Tool | `import-linter` |
| Config | `pyproject.toml` → `[tool.importlinter]` |
| Enforcement | error |
| Runs | pre-push hook; CI |
| Owner | whoever touches server modules |
| Exceptions | none |

### FF-2 · Python cyclomatic complexity

**Rule:** No Python function exceeds cyclomatic complexity 10. Signals when a function is doing too much and should be split.

**Why it matters:** Hotspots start as one-more-case-in-a-switch. Capping complexity forces the split at the right time, not when the file has become unrecognizable.

| Field | Value |
|---|---|
| Tool | `ruff` C901 |
| Config | `pyproject.toml` → `[tool.ruff.lint.mccabe]` |
| Enforcement | error |
| Runs | pre-commit hook; CI |
| Owner | author of the function |
| Exceptions | none |

### FF-3 · Ruff lint select

**Rule:** The Python codebase stays free of common bug-prone patterns. Specifically: pyflakes (F), pycodestyle errors (E), warnings (W), isort (I), bugbear (B), McCabe (C901).

**Why it matters:** Catches accidental unused imports, missing `__init__.py`, mutable default arguments, and similar footguns before they ship. Low-cost gate.

| Field | Value |
|---|---|
| Tool | `ruff` |
| Config | `pyproject.toml` → `[tool.ruff.lint]` |
| Enforcement | error |
| Runs | pre-commit hook; CI |

---

## Cross-stack (structural tests) — live today

These are pytest tests under `tests/architecture/`. They run in CI and block merges.

### FF-4 · Monorepo top-level shape

**Rule:** ≤ 8 top-level directories in the repo (excluding dotfiles and gitignored dirs). Adding a 9th requires an ADR.

**Why it matters:** The top level is the first thing a new contributor (or future Claude) sees. A sprawling root level is a signal of unowned concerns.

| Field | Value |
|---|---|
| Tool | pytest structural test |
| Config | `tests/architecture/test_monorepo_shape.py` |
| Enforcement | error |
| Runs | CI; pre-push via pytest |
| Exceptions | none |

### FF-5 · ADR index parity

**Rule:** Every file in `docs/decisions/` is referenced in `docs/AGENTS.md`. Every ADR referenced in `docs/AGENTS.md` exists on disk. No orphans in either direction.

**Why it matters:** ADRs that aren't in the index are invisible. Index entries for deleted ADRs lie.

| Field | Value |
|---|---|
| Tool | pytest structural test |
| Config | `tests/architecture/test_adr_index.py` |
| Enforcement | error |
| Runs | CI |

### FF-6 · Prescription shape ↔ fixture parity

**Rule:** Every prescription shape documented in `docs/prescription.md` has a fixture in `schema/fixtures/` that exercises it. Every fixture maps to a documented shape.

**Why it matters:** The whole point of `docs/prescription.md` is to be the authority on what Claude can author. If the doc describes a shape the system doesn't exercise in tests, it's a promise with no contract test behind it.

| Field | Value |
|---|---|
| Tool | pytest structural test |
| Config | `tests/architecture/test_prescription_shape_parity.py` |
| Enforcement | error |
| Runs | CI |
| Exceptions | none — every shape earns its fixture before it lands in the doc |

### FF-7 · No RPE resurrection

**Rule:** `rpe`, `rpe_target`, and `RPE` (as a scale reference) do not appear in production code or accepted docs. Historical references in ADRs (narrating the rename) and in `docs/design/` (reference-not-spec) are allowed. Explicitly: `server/`, `app/`, `schema/`, `docs/prescription.md`, `docs/sync.md`, `docs/specs/v2-architecture.md`, `app/README.md` — must all be RPE-free.

**Why it matters:** The RIR cutover is a complete cutover. Partial RPE returning to any of these surfaces means the cutover is regressing.

| Field | Value |
|---|---|
| Tool | pytest structural test |
| Config | `tests/architecture/test_no_rpe.py` |
| Enforcement | error |
| Runs | CI |
| Exceptions | The test allowlists `docs/decisions/` (historical narration), `docs/design/` (reference bundle), and itself. |

### FF-8 · OpenAPI drift

**Rule:** `schema/openapi.json` matches what the live FastAPI app emits. A server-side schema change that wasn't propagated to `schema/openapi.json` fails the build.

**Why it matters:** The iOS app reads DTOs keyed to this file. Drift = silent sync bugs.

| Field | Value |
|---|---|
| Tool | pytest contract test (already in place) |
| Config | `tests/contract/test_openapi_drift.py` |
| Enforcement | error |
| Runs | CI |

### FF-9 · Swift schema parity

**Rule:** Every Pydantic schema has a mirrored Swift Codable DTO that round-trips the OpenAPI fixtures in both directions.

**Why it matters:** Wire contract is the cross-stack seam. Parity tests are the only thing preventing server-app drift.

| Field | Value |
|---|---|
| Tool | pytest contract test (already in place) |
| Config | `tests/contract/test_swift_schema_parity.py` |
| Enforcement | error |
| Runs | CI |

### FF-10 · Open-questions hygiene

**Rule:** `docs/open-questions.md` is readable machine-checkably — every item has a `**Disposition:**` line with one of the allowed values (`decide-next`, `defer-to-v1.1+`, `resolve-in-code`, `watchlist`, `resolved`). Items with `resolved` disposition must be removed within one ADR cycle.

**Why it matters:** The gap register only works if it can't drift into prose.

| Field | Value |
|---|---|
| Tool | pytest structural test |
| Config | `tests/architecture/test_open_questions.py` |
| Enforcement | error |
| Runs | CI |

---

## iOS app (Swift) — activation-pending

These rules are authored now; they activate on "Xcode project lands" because SwiftLint and Package.swift don't yet exist.

### FF-11 · Swift package graph (Core purity)

**Rule:** `Core/*` packages declare dependencies only on other `Core/*` packages. No SwiftData, no URLSession, no HealthKit, no Combine (for I/O), no edge packages (Persistence, Sync, HealthKitBridge, WatchBridge, Features/*).

**Why it matters:** Core's testability depends on it being pure. The moment a Core package imports URLSession, every Core test becomes an integration test.

| Field | Value |
|---|---|
| Tool | SwiftPM (compile-time) |
| Config | `app/Packages/Core/*/Package.swift` — each `Package.swift` declares only Core siblings as dependencies |
| Enforcement | error (build fails) |
| Runs | every compile |
| Activation | first `app/Packages/Core/` package lands |

### FF-12 · Swift package graph (Feature isolation)

**Rule:** `Features/*` packages do not depend on each other.

**Why it matters:** Feature cross-imports are the most common path to a god module. If two Features share something, it moves to Core.

| Field | Value |
|---|---|
| Tool | SwiftPM (compile-time) |
| Config | `app/Packages/Features/*/Package.swift` |
| Enforcement | error (build fails) |
| Runs | every compile |
| Activation | second `Features/*` package lands |

### FF-13 · SwiftLint custom rules

**Rule:** (a) No `print(...)` — use `Logger` from `os.log`. (b) No `URLSession`/`URLRequest` outside `Sync`. (c) No `ModelContainer`/`ModelContext`/`@Model` outside `Persistence`. (d) No `HKHealthStore`/`HKSampleQuery` outside `HealthKitBridge`. (e) No `WCSession` outside `WatchBridge`.

**Why it matters:** SwiftPM catches cross-package imports; SwiftLint catches the sneakier within-package violations (e.g., a "helper" file in a Feature that imports URLSession directly).

| Field | Value |
|---|---|
| Tool | `SwiftLint` with `custom_rules` |
| Config | `app/.swiftlint.yml` (committed ahead of time; activates when SwiftLint runs) |
| Enforcement | error |
| Runs | pre-commit + CI |
| Activation | first Xcode build |

### FF-13A · WorkoutKit import ownership

**Rule:** WorkoutKit side effects live only in `WorkoutKitAdapter`. App shells
may trigger diagnostics, and `ExportProfile` may classify SDK-free export
plans, but direct `import WorkoutKit` must not appear outside the adapter
package.

**Why it matters:** WorkoutKit is an edge SDK with platform-specific scheduling
and open-in-Workout-app behavior. Keeping imports in one adapter prevents
primitive execution, export-profile classification, and app shell code from
accidentally becoming target-side SDK code.

| Field | Value |
|---|---|
| Tool | pytest structural test |
| Config | `tests/architecture/test_workoutkit_boundaries.py` |
| Enforcement | error |
| Runs | `make check` / CI |

### FF-14 · Swift cyclomatic complexity

**Rule:** No Swift function exceeds cyclomatic complexity 10. Same threshold as Python.

**Why it matters:** Same reason as FF-2 — hotspot prevention.

| Field | Value |
|---|---|
| Tool | SwiftLint `cyclomatic_complexity` |
| Config | `app/.swiftlint.yml` |
| Enforcement | error |
| Runs | pre-commit + CI |
| Activation | first Xcode build |

### FF-15 · No `// MARK:` dumping-ground detection

**Rule:** A file with more than 6 `// MARK:` section headers is flagged — it's likely becoming a god file. Soft rule; starts as warning until the project exists, then promotes to error after baseline measurement.

**Why it matters:** `// MARK:` proliferation is the tell for SettingsView and similar grab-bag files.

| Field | Value |
|---|---|
| Tool | SwiftLint `file_length` + custom regex rule |
| Config | `app/.swiftlint.yml` |
| Enforcement | error |
| Runs | pre-commit + CI |
| Activation | first Xcode build |

---

## How to add a fitness function

1. State the rule in plain language.
2. Choose the strongest enforcement mechanism that applies (type system > linter > structural test > ADR).
3. Add the config + the registry entry here in the same commit.
4. Wire into pre-commit or CI.
5. Fix all current violations or file an exception (in `docs/architecture/boundaries.md` violations register) with an owner and expiry.

**No entry here = no rule.** Decisions that aren't enforced by a mechanism listed here are aspirational, not architectural.
