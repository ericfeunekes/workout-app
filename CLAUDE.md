# WorkoutDB — Agent Instructions

Monorepo for a workout system built on **"dumb app, smart conversation"**. Read `docs/specs/v2-architecture.md` in full before any non-trivial work — the philosophy and data model are load-bearing.

See `docs/AGENTS.md` for the docs navigator and `docs/ARCHITECTURE.md` for the system map.

## Project Overview

- `server/` — Python + FastAPI + SQLite home server. Schema, API endpoints, sync.
  - `workoutdb_server/` — Python package
  - `db/migrations/` — idempotent SQL migrations
- `app/` — SwiftData iOS app. The "dumb" client: show, time, log.
- `schema/` — shared schema definitions between server and app (not yet populated)
- `docs/` — architecture, testing contract, target spec (see `docs/AGENTS.md`)
- `tests/` — server tests (`tests/server/`) and cross-stack contracts (`tests/contract/`); iOS tests live alongside the Xcode target in `app/`
- `scratch/` — ephemeral multi-unit work (gitignored)

## Workflows

See `docs/WORKFLOW.md` for the operational lifecycle and `docs/sdlc.md` for
the planning flow. Quick pointers:

### Starting work
- Classify the change: trivial / scoped / non-trivial. Non-trivial → `scoping:requirements-planning` if the durable requirement is missing, stale, or too thin. Use interview only as discovery that feeds requirements.
- Call something a spike only when a planning-blocking empirical unknown cannot be settled by docs/code reading. Do not label implementation slices or fake-backed scaffolds as spikes.
- Read `docs/specs/v2-architecture.md` (target architecture, accepted) and `docs/ARCHITECTURE.md` (system map at a glance).
- Read the affected area's README (`server/README.md`, `app/README.md`, `schema/README.md`).
- Schema change? Read `docs/MIGRATIONS.md` before touching entity definitions.

### During work
- Schema change → follow the seven-step cutover flow in `docs/MIGRATIONS.md`.
- New API endpoint → route in `server/workoutdb_server/api/`, models updated, test in `tests/server/`, `docs/ARCHITECTURE.md` updated if sync story changes.
- New timing mode → extend enum in server + SwiftData + spec; app timer engine handles it.
- iOS or SwiftUI change → load the relevant repo-local skill before planning
  or editing. Use the smallest matching skill set:
  - `ios-debugger-agent` when building, launching, UI-driving, screenshotting,
    log-capturing, or diagnosing the iOS simulator app with XcodeBuildMCP.
    Use the live tool names discovered in-session; do not commit simulator
    UUIDs or machine-specific MCP paths.
  - `swiftui-ui-patterns` when creating or materially changing SwiftUI screens,
    navigation, sheets, controls, state ownership, async UI state, previews, or
    component structure.
  - `swiftui-view-refactor` when splitting large SwiftUI views, removing inline
    actions or side effects, tightening Observation usage, or standardizing
    MV-first view composition. This means do not introduce unnecessary new view
    models; it does not mean deleting existing `TodayViewModel`,
    `ExecutionViewModel`, `HistoryViewModel`, or other deliberate app patterns.
  - `swiftui-performance-audit` when a SwiftUI change may affect scroll
    smoothness, render churn, broad observation, list identity, layout cost, CPU,
    memory, or battery. Start code-first; require profiling evidence when source
    inspection cannot prove the cause.
  - `ios-ettrace-performance` when the task asks for runtime performance proof,
    startup/render/navigation profiling, CPU-heavy work, timer/rendering stalls,
    or before/after flamegraph evidence. Capture one focused simulator flow,
    preserve symbolicated flamegraph JSON, and remove temporary ETTrace app
    wiring before closeout unless Eric explicitly asks to keep it.
  - `ios-memgraph-leaks` when investigating memory growth, retain cycles,
    leaked view/session objects, lingering tasks after navigation, save-and-done
    cleanup, reset/change-server flows, or proving a leak fix with before/after
    memgraph evidence. Do not claim a leak fix from lower memory alone; report
    app-owned leaked types and the ownership path or grouped leak evidence.
  - `ios-app-intents` when exposing WorkoutDB actions or entities through
    Apple's AppIntents framework: Shortcuts, Siri, Spotlight, widgets, controls,
    `AppIntent`, `AppEntity`, `EntityQuery`, or `AppShortcutsProvider`. Do not
    trigger this for ordinary domain "intent" fields such as block intent copy
    or `SetEditIntent`. App Intents must stay thin: route into existing app
    services and never add workout programming, exercise selection, progression,
    or analysis logic.
  - `swiftui-liquid-glass` only when adopting, reviewing, or changing iOS 26+
    Liquid Glass UI. Do not introduce Liquid Glass as incidental polish. Prefer
    reusable treatment in `DesignSystem` when it becomes a pattern, gate iOS 26
    APIs with availability checks, and keep non-glass fallbacks aligned with
    existing design primitives.
- Repo rules override generic SwiftUI skill defaults: preserve the
  dumb-app/smart-conversation boundary, package graph boundaries,
  `DesignSystem` tokens, explicit existing view-model ownership, offline-first
  execution, and `docs/QA.md` simulator evidence requirements. Do not remove
  intentional route/tab switches just to satisfy generic "stable view tree"
  guidance.
- Performance traces and memgraphs do not replace `make pre-qa` or `docs/QA.md`.
  They are additional proof when the claim is runtime cost or object lifetime.
  Store app-facing trace/memgraph artifacts under the active
  `scratch/qa-runs/<run-id>/`; use temp dirs for narrow investigations.
- Testing audit is pre-QA. Use it to find automated and realistic-local proof
  gaps — unit, integration, contract, end-to-end, local service, persistence,
  time, concurrency, and device-adjacent harness gaps. Do not collapse it into
  simulator/video QA; `docs/QA.md` starts after the relevant testing proof is
  green or the capability gap is named.
- Bug found → hypothesis-driven debugging before patching.

### Finishing work
- Follow `docs/runbooks/closeout.md` — the per-change checklist enforces the cutover philosophy.
- Pre-push hook runs import-linter and `pytest` automatically; install once with `pre-commit install --hook-type pre-commit --hook-type pre-push`.

### After context loss
- Re-read this file, `docs/WORKFLOW.md`, and `docs/specs/v2-architecture.md`.
- Read `docs/sdlc.md` for the planning flow, then `docs/backlog.md` for current lanes and gap ownership. Check `scratch/` for ephemeral handoff notes if a slice is already in progress.

## Review workflow — independent review, lead synthesizes

**Reviews, sweeps, and investigations must use an independent review path, not the same implementer context.** The three roles are fixed:

- **Implementation = Claude subagent** (dispatched from the main thread).
- **Review / sweep / investigation = code-analysis review, critic, or another available independent reviewer.**
- **Synthesis = the lead Claude agent in the main conversation.** Synthesis is NOT delegated to a spawned subagent — the lead reads review findings directly, filters false-positives, and dispatches the next fix-it round from the main thread.

Same-model review misses the same blind spots that produced the bug. That's the load-bearing reason for the split.

The loop for every non-trivial unit of work:

1. Claude implementer subagent writes the fix.
2. Independent review runs through the available review tool or skill for the domain.
3. **Lead Claude synthesizes in the main thread** — reads reviewer findings, filters false-positives, dispatches a Claude fix-it subagent with the real findings inline.
4. Repeat step 2. Loop until the independent review returns clean.

**Sweeping the codebase state to find new issues uses an independent review or investigation path, not the implementer context.** Same goes for hypothesis-driven bug investigations and adversarial reviews. Synthesis of findings always happens in the main conversation.

Write temporary review prompts under `scratch/reviews/` on demand. If that
directory does not exist, there is no active review handoff. Per-domain prompts
cite focus files, questions, hazards, and gates.

Same-model Claude-reviews are acceptable only for trivial scoped fixes, pure doc edits, or config tweaks already guarded by automated checks.

See `docs/WORKFLOW.md` § "The implementer / reviewer cycle" for the full story.

## Module Coordination

- **Schema change** touches: `server/workoutdb_server/models.py` (SQLAlchemy ORM), `server/db/migrations/NNN_*.sql`, `server/workoutdb_server/api/schemas.py` (Pydantic), `schema/Sources/WorkoutDBSchema/*.swift` (Swift DTOs), regenerated `schema/openapi.json`, SwiftData models in `app/` (when the Xcode project exists), contract tests in `tests/contract/`, and the data model section of `docs/specs/v2-architecture.md`. See `docs/MIGRATIONS.md` for the cutover flow.
- **Sync protocol change** touches: `server/workoutdb_server/api/sync.py`, the iOS sync manager in `app/`, `schema/openapi.json`, the "Sync model" section of `docs/specs/v2-architecture.md`, and contract tests.
- **New timing mode** touches: `TimingMode` in `schema/Sources/WorkoutDBSchema/Enums.swift`, the `Literal` in `api/schemas.py`, the SQL `CHECK` constraint in `001_initial.sql` (add via new migration — never edit), the contract test in `tests/contract/test_swift_schema_parity.py`, the timing modes table in `docs/specs/v2-architecture.md`, and the app's timer engine.
- **User parameter key added** is data-only — no code change needed unless the app is supposed to interpret it. If the app must interpret it (e.g. new `percent_1rm` variant), update the resolver in `app/` and document the key.

## Build & Verify

```bash
# One-time setup after cloning
uv sync --extra dev
pre-commit install --hook-type pre-commit --hook-type pre-push
cp .env.example .env      # then fill in WORKOUTDB_BEARER_TOKEN

# Server
make check                # lint/import contracts + Python tests + schema Swift tests
uv run ruff check .       # lint
uv run ruff format .      # format
uv run uvicorn workoutdb_server.main:app --reload   # run locally
# Python validation/error messages still need to stay under ruff's
# 100-character line limit; wrap long strings at edit time.

# App
make test-core           # fast Core + Sync package subset
make test-app-packages   # every wired app package test target
make xcodegen            # regenerate app/WorkoutDB.xcodeproj from project.yml
make test-app-xcode      # generated app compile/link smoke on simulator
make test-execution-ui   # execution XCUITest proof; code-signing-free
make test-healthkit-ui   # signed HealthKit authorization/projection UI proof
make pre-qa              # current local pre-QA gate before docs/QA.md
make qa-ready            # verify XcodeBuildMCP before simulator/device QA
```

TestFlight/App Store distribution is agent-operated. Do not rely on Eric being
present to type passwords. Preflight must prove signing material, provisioning
profiles, and App Store Connect upload credentials are available
non-interactively. Use `make release-preflight`, `make release-bump-build`, and
`make release-testflight RELEASE_REF=<committed-ref>`; the release runner builds
from a detached temporary worktree at the resolved SHA and records a manifest
under `scratch/qa-runs/`. Use a dedicated non-login release keychain, or create
a temporary keychain from non-interactively retrieved certificate material, and
pass it to Xcode with `OTHER_CODE_SIGN_FLAGS = --keychain <path>`. Treat any
login-keychain, Apple ID, `op signin`, or Xcode GUI prompt as a release blocker.

**CI** (`.github/workflows/ci.yml`): Linux only, server tests + ruff on push and PR. iOS build/test deferred until the app exists and we revisit public-vs-private repo. See `docs/WORKFLOW.md` § "CI scope" for the budget math.

**Secrets**: `.env` (gitignored) holds the bearer token and DB path. Server loads via `pydantic-settings` with `env_prefix="WORKOUTDB_"`. The same bearer token is pasted into the iOS app's first-run setup — server and app share one secret, Tailscale handles network-layer trust.

## Invariants

### System philosophy

- **Dumb app, smart conversation.** The app never does programming logic, exercise selection, periodization, or progression. All of that lives in Claude conversations and arrives as data via the server. If a change adds "app reasons about X", push back — X probably belongs in `user_parameters` or in conversation.
- **UUIDs everywhere, no auto-increment IDs.** Every entity has a `UUID` primary key so sync merges are trivial.
- **Direction-based sync, no conflict resolution.** Plans flow server → app; results flow app → server. Never both for the same field.
- **Schema parity between server and app.** If the Python model changes and the SwiftData model doesn't (or vice versa), sync breaks. Contract tests enforce this.
- **`prescription_json` and `timing_config_json` are JSON blobs by design.** New prescription shapes and timing configs don't require schema changes — add the shape to the spec and the app reader, not to the table.
- **Claude owns exercise IDs.** The server does not canonicalize on exercise name. Claude lists `/api/exercises` at conversation start and reuses UUIDs for recurring exercises.
- **`user_parameters` is append-only.** Every push inserts a new row. Overwrites would destroy history; history is load-bearing for longitudinal analysis.
- **App must execute a fully-pulled workout with zero network calls.** Offline-first is not optional — cellular at the gym, travel, and hotel WiFi fail too often.

### Development philosophy (single-user, no legacy)

This repo has one user (Eric) and one prod deployment (also Eric). There is no "existing user base" to migrate, no backwards compatibility to preserve, and no deprecation curve to honor. Act accordingly:

- **Complete cutovers only.** When something changes, change it everywhere in one commit — server, app, schema, tests, docs. No feature flags, no legacy paths, no parallel old+new codepaths, no "one sprint to deprecate X" periods. If you find yourself writing an adapter between old-shape and new-shape code, you're doing it wrong.
- **Resolve nitpicks at the time.** Naming is off → rename it now. Tiny inconsistency → fix it now. We do not carry a "small stuff to clean up later" list. Technical debt accumulated here will outlive the short-term pain of resolving it immediately.
- **No legacy fallback code.** v1 (Python CLI, YAML, Google Calendar, intents, muscle/movement/equipment tables) is gone. Don't resurrect any of it. If you see a code path "in case the old thing is still around," delete it.
- **Local data preservation is explicit per cutover.** Workout logs on Eric's phone are normally the only data worth preserving through schema changes; everything else can be re-pushed by Claude. For the primitives cutover, current local/server workouts are QA data and may be reset instead of migrated. Do not assume preservation or deletion silently — the owning spec must say which applies.
- **Pre-production server-state cutovers prefer recreation.** While this app is still QA/pre-production, do not keep legacy preservation paths for local server identity changes unless Eric explicitly requests them. Prefer destructive local recreation: clear coupled local cache/session/queue/cursor state and rebuild from the selected server.
- **Schema changes are always cutovers.** Server migration + SwiftData version bump + API update + contract test + spec update all ship together unless the owning spec invokes the destructive cutover exception in `docs/MIGRATIONS.md`. App and server schema versions are always identical in the running system — see `docs/MIGRATIONS.md` for the flow.

### Migrations

- **Migrations are append-only and idempotent.** `server/db/migrations/NNN_*.sql` — never edit a merged migration.
- **Every schema change is a coordinated cutover** across server migration, SwiftData versioned schema, API models, contract test, and the spec unless the owning spec invokes the destructive cutover exception. See `docs/MIGRATIONS.md` for the detailed flow.
- **Local set_logs need an explicit migration decision.** SwiftData migrations use lightweight stages where possible. When a stage can't be lightweight, either export → transform → re-import is explicit and documented, or the owning cutover spec explicitly permits resetting QA data.

### Architectural enforcement

- **Boundaries are enforced at lint time, not at review time.** Python server boundaries are checked by `import-linter` contracts in `pyproject.toml` (run `uv run lint-imports`). Contracts run in pre-push and CI.
- **New architectural boundaries require new contracts.** Adding a module or package? Add an import-linter contract in the same commit. If reaching for an import that would violate an existing contract, extract the shared logic into the right layer — do not loosen the contract. See `docs/WORKFLOW.md` § "Architectural enforcement".
- **Architecture review means the full `code-analysis:architecture` audit artifact.** Do not call an architecture review complete unless it includes the current-state snapshot, boundary matrix, hotspot register with scores, top interventions, draft ADRs, and smallest next step from the skill.

## Planning and backlog lifecycle

Use `docs/sdlc.md` as the progressive-disclosure map. The order is:

1. Requirements planning updates durable feature, domain, aspect, architecture, or spec docs.
2. Known missing behavior or proof becomes a gap in the owning docs and `docs/feature-gap-map.md`.
3. `docs/backlog.md` groups gap IDs into lanes and marks which lanes are active, parallel, spikes, requirements-only, or later capabilities.
4. Pick the active work tree: one lane, a phase series inside a lane, or one phase.
5. Use `scoping:phase-planning` only when the selected work tree needs outcome-level sequencing. Phase specs live in `scratch/`, not `docs/`.
6. Use `scoping:implementation-planning` for one selected phase or small unit. Implementation plans live in `scratch/`.
7. Closeout removes or narrows closed gaps in the owning docs and `docs/feature-gap-map.md`, updates `docs/backlog.md` only when lane routing changed, and removes stale scratch plans.

Do not add durable plan directories under `docs/`. Requirements docs describe how the system should work; backlog says which gaps remain and how they group; scratch carries temporary execution plans.

## Agent harness

`.claude/` and `.codex/` are checked in so agent harness config (MCP wiring, enabled plugins, project overlays) stays in sync across machines. `.xskills/` and `.claude/settings.local.json` are agent-local and gitignored. `scratch/` is for ephemeral multi-unit work.

For MCP tooling, keep one canonical command path per server. Do not add repo-local wrappers, fallback command chains, or machine-specific MCP variants unless Eric explicitly asks for that split. XcodeBuildMCP is the global `xcodebuildmcp` command; keep machine-specific simulator IDs and home paths out of committed config.

For WorkoutKit handoff work, keep the push lane separate from results reconciliation. Pushing, scheduling, or opening WorkoutKit content is one slice; HealthKit or WorkoutKit completion readback, matching, import, and Setmark reconciliation belong to a later lane unless Eric explicitly asks to combine them.
