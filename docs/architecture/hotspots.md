---
title: Hotspot register
status: accepted
date: 2026-04-17
purpose: The modules we know will become brittle if unchecked — recorded preemptively, with the enforcement mechanism that prevents each. Hotspots in an existing system are a refactor target; hotspots in a greenfield design are a design target.
covers:
  - app/
  - server/
---

# Hotspot register

A hotspot is a module that accumulates churn + complexity + boundary leakage + blast radius until it's impossible to change safely. In a greenfield design we don't score after the fact — we name the candidates now and set the architectural guardrail that prevents each.

## Scoring guide (reference)

| Dimension | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| **Churn** | Rarely touched | Monthly | Weekly | Most PRs |
| **Complexity** | Simple | Some branching | Multiple concerns interleaved | Deep context required |
| **Boundary leakage** (0–2) | Clean interfaces | Some coupling | Implementation leaks to callers | — |
| **Blast radius** (0–2) | Single module | 2–3 consumers | Ripples across system | — |

Thresholds: 8–10 address now · 5–7 address on next touch · 0–4 monitor.

Scores below are **projected** for greenfield modules (what the module will score *if unchecked*) vs **prevented** (the score we expect with the enforcement in place).

---

## Register

### HS-1 · `Sync` as a god object

**What the hotspot becomes unchecked:** a single `SyncManager` class that owns the pull queue, the push queue, connection state, auth errors, conflict resolution, retry logic, and the live "currently syncing" signal. Grows to 800+ lines, any change touches every responsibility, tests require mocking five collaborators.

**Projected score (unchecked):** Churn 3 + Complexity 3 + Boundary 2 + Blast 2 = **10**.

**Prevented by:** splitting into named responsibilities from day one.

- `PullService` — owns `GET /api/sync/pull`, parses into Domain types, writes to Persistence.
- `PushQueue` — owns the queue of pending `set_log` + status updates. Persistent across app launches. Idempotent retry.
- `ConnectionManager` — owns the offline/online signal, retry cadence, 401 handling.
- (Later, if needed) `ConflictResolver` — for the offline-completion-vs-server-update case. Kicks in only when actually needed.

**Enforcement:** SwiftPM makes them separate types in `Sync/Sources/Sync/`. SwiftLint `file_length: 400` prevents any single file from absorbing. `types_body_length: 200` prevents any single type from absorbing. FF-13 (no URLSession outside Sync) keeps them the only packages doing I/O — no end-run.

**Prevented score:** Churn 3 + Complexity 1 + Boundary 0 + Blast 1 = **5**. Acceptable — sync inherently churns.

---

### HS-2 · `TimingEngine` mega-switch

**What the hotspot becomes unchecked:** a single `TimingEngine.tick(for mode: TimingMode)` that grows an ever-larger `switch` over all 11 modes, with per-mode state interleaved in one type. Adding the 12th mode requires reading every existing branch.

**Projected score (unchecked):** Churn 2 + Complexity 3 + Boundary 1 + Blast 2 = **8**.

**Prevented by:** strategy pattern with one driver per mode.

- Protocol `TimingDriver` in `Core/Session` with methods `start(context:)`, `tick(now:)`, `advance(log:)`, `state: TimingState`.
- One conforming type per mode in `Features/Execution/Drivers/`: `StraightSetsDriver`, `SupersetDriver`, `EmomDriver`, `AmrapDriver`, etc. One mode = one file.
- `DriverFactory` that maps `timing_mode` → driver. Trivially testable.

**Enforcement:** SwiftLint `type_body_length: 200` forces any driver that outgrows that limit to split. `file_length: 400` caps per-file growth. Adding a mode is a new file, not an edited switch — no mega-switch can form.

**Prevented score:** Churn 1 (per driver) + Complexity 1 + Boundary 0 + Blast 0 = **2**.

---

### HS-3 · `PrescriptionReader` as computation engine

**What the hotspot becomes unchecked:** a class that both parses `prescription_json` AND computes derived values (resolved load after percent_1rm, autoreg-adjusted load, warm-up exclusion, etc.). Becomes the place every Feature asks "what's the effective load for this set?" — a domain-god.

**Projected score (unchecked):** Churn 3 + Complexity 3 + Boundary 2 + Blast 2 = **10**.

**Prevented by:** split parsing from computation, split per shape.

- `Core/Prescription` — per-shape parsers only: `parseStraightSets(json)`, `parseSuperset(json)`, etc. Return typed structs. No computation.
- `Core/Autoreg` — pure autoreg functions that take a typed prescription + logged set, return `AutoregProposal?`. No parsing.
- `Core/Session` — resolves percent_1rm against user_parameters. No autoreg logic, no parsing logic.

**Enforcement:** package boundaries (FF-11) — each package can only do its one thing because its imports are scoped. A unit test per parser and per autoreg rule. Grep test `tests/architecture/test_prescription_purity.py` asserts `Core/Prescription/**/*.swift` contains no references to `user_parameters` or `autoreg` (parsers don't compute).

---

### HS-4 · `SettingsView` dumping ground

**What the hotspot becomes unchecked:** one 1200-line SwiftUI view with 40 rows covering server address, watch pairing, units, autoreg defaults, reset, dev toggles, hidden gestures. Re-ordering sections becomes a merge conflict generator.

**Projected score (unchecked):** Churn 2 + Complexity 2 + Boundary 1 + Blast 1 = **6**.

**Prevented by:** section-as-type.

- `Features/Settings` exposes a data-driven list of `SettingsSection` values. Each section is its own struct with its own tiny view model.
- Reorder = swap list entries; add = append a struct. No edits to a mega-view.

**Enforcement:** SwiftLint `file_length: 400` + `type_body_length: 200`. Convention: new Settings surface requires adding a `SettingsSection` type, not extending `SettingsView`.

---

### HS-5 · Ambient `Utils/` / `Helpers/` bucket

**What the hotspot becomes unchecked:** an `app/Packages/Core/Utils` or `server/workoutdb_server/utils.py` where string padding, date formatting, UUID generation, kg↔lb conversion, and anything else "shared" lands. Becomes an undeclared dependency of every module.

**Projected score (unchecked):** Churn 3 + Complexity 2 + Boundary 2 + Blast 2 = **9**.

**Prevented by:** banning it outright.

- No `Utils/`, no `Helpers/`, no `Common/` packages. Shared code either has a real name (`Core/Foundation` for clock + IDs + math; `DesignSystem` for visual primitives) or lives where it's used.
- If a function is needed by two modules, it gets a named home. Three uses = consider whether a named module deserves it. Never a junk drawer.

**Enforcement:** structural test `tests/architecture/test_no_utils_bucket.py` fails on any package or module named `utils`, `helpers`, `common`, `shared`, `misc`, or `util` anywhere in `server/`, `app/`, or `schema/`.

---

### HS-6 · `api/schemas.py` as domain-shadow

**What the hotspot becomes unchecked:** the Pydantic file grows to mirror every internal domain type + every request/response variant, becomes 1000+ lines, and casual changes to a model cascade across unrelated endpoints.

**Projected score (unchecked):** Churn 3 + Complexity 2 + Boundary 1 + Blast 2 = **8**.

**Prevented by:** one schemas file per route module.

- `api/schemas.py` is removed. Each route module (`api/workouts.py`, `api/sync.py`, etc.) defines its own request/response schemas inline or in a sibling `api/workouts_schemas.py`.
- Cross-route shared types move to `models.py` (ORM) or to a named `api/common_types.py` only if the shared type is deliberate.

**Enforcement:** FF-2 (complexity) naturally caps per-file growth; structural test `tests/architecture/test_schemas_split.py` fails if `api/schemas.py` exceeds 300 lines — forces the split once it grows.

*(Note: today the file exists as `api/schemas.py`. This hotspot is a planned intervention at the next schema change, not an immediate one.)*

---

### HS-7 · Watch as duplicate logic center

**What the hotspot becomes unchecked:** the WatchKit extension grows a second copy of session-state reasoning, prescription parsing, or autoreg logic — because watch developers don't want to cross the WatchConnectivity boundary for every decision.

**Projected score (unchecked):** Churn 2 + Complexity 2 + Boundary 2 + Blast 2 = **8**.

**Prevented by:** watch imports Core/* via SwiftPM.

- `Core/*` packages build for both iOS and watchOS targets (a SwiftPM concern — listed in `supportedPlatforms`).
- The watch target imports Core like the phone target. No duplication of Domain, Prescription, Autoreg, Session.
- Watch-specific code lives only in `WatchBridge` (IPC boundary) and in Watch-only Features. Everything else is shared.

**Enforcement:** `app/Packages/Core/*/Package.swift` declares `supportedPlatforms: [.iOS(.v17), .watchOS(.v10)]`. Watch target's `Package.swift` depends on the same Core packages. Drift would fail to build.

---

### HS-8 · `docs/` / `README.md` drift

**What the hotspot becomes unchecked:** docs describe a shape the code no longer matches. Contract rules state one thing; structural tests enforce another. `docs/prescription.md` adds a shape that no fixture exercises.

**Projected score (unchecked):** Churn 3 + Complexity 0 + Boundary 2 + Blast 1 = **6**.

**Prevented by:** structural tests that read docs.

- FF-5 (ADR index parity) — `docs/AGENTS.md` must list every file in `docs/decisions/`.
- FF-6 (prescription shape ↔ fixture parity) — every shape in `docs/prescription.md` has a fixture.
- FF-7 (no RPE) — a semantic regression surfaces as a test failure.
- FF-10 (open-questions hygiene) — the gap register stays machine-readable.

---

## Platform-quirk caveats

Recorded so future implementers don't relearn these the hard way.

### SwiftData `ModelContext.transaction { ... }` does **not** roll back on throw (iOS 17.x)

Despite what Apple's docs suggest, `ModelContext.transaction(block:)` does not rewind staged inserts when the block throws in iOS 17.x — the inserts remain in the context and flush on the next successful `save()`.

**Discovered:** 2026-04-18, during the `WorkoutCacheImpl.save(_:)` atomicity fix. A test (`WorkoutCacheTests::testSaveRollsBackOnThrowMidLoop`) proved inserts leaked across a thrown `transaction` block.

**Correct pattern:** explicit `rollback()` in a `catch`, then rethrow.

```swift
do {
    for row in dataset.workouts { upsert(row) }
    for row in dataset.blocks   { upsert(row) }
    // ...
    try modelContext.save()
} catch {
    modelContext.rollback()
    throw error
}
```

**Invariant:** any Persistence method that stages multiple `insert`/`update` calls before `save()` must use the explicit-rollback pattern. `transaction { }` is a trap. Revisit if iOS 18+ fixes the behaviour.

---

## Resolved

*(none)* — will be populated as interventions ship.

---

## How to add an entry

1. Name the module and the shape of the hotspot.
2. Project the score unchecked (what does it become if nobody pushes back?).
3. Identify the design move that prevents it.
4. Wire the enforcement into `docs/architecture/fitness-functions.md` in the same commit.
5. Project the prevented score.

**A hotspot without a named preventative is a risk. A hotspot with a preventative that isn't in fitness-functions.md is an aspiration.**
