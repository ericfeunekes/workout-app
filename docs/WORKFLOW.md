---
title: Development workflow
status: stable
date: 2026-04-17
last_reviewed: 2026-05-17
purpose: "How work progresses in this repo — the lifecycle from request to deployed code, and the rules that hold across every cycle."
covers:
  - AGENTS.md
  - docs/sdlc.md
  - docs/MIGRATIONS.md
  - docs/QA.md
  - docs/runbooks/closeout.md
---

# Development workflow

This repo has one developer and one user (both Eric). There are no sprints, no standups, no PR review boards. The workflow below exists to keep decisions and rationale durable across Claude conversations so that future sessions — without the context of this one — can continue to improve the system safely.

For the progressive-disclosure planning model, read `docs/sdlc.md`: durable
requirements -> gap map -> backlog lanes -> active work tree -> scratch phase
or implementation plan -> closeout.

## The operational lifecycle

```
request → requirements → backlog/plan → implement → verify → close → deploy
```

### Request

Eric starts a conversation. Work classifies into one of three sizes:

- **Trivial** (typo, rename, one-line fix) — skip straight to implement.
- **Scoped change** (one module, known shape) — skip new requirements; go to plan.
- **Non-trivial** (new feature, schema change, cross-stack) — start with
  `scoping:requirements-planning` when the durable requirement is missing,
  stale, or too thin. Use interview only as optional discovery that feeds the
  requirements update.

Claude's job is to classify out loud at the start of a conversation. "This is
non-trivial; updating requirements first." Or "this is scoped; jumping to the
plan." Eric can overrule.

### Requirements

For non-trivial work, use `scoping:requirements-planning` when the durable
requirement is missing, stale, or too thin. Feature, domain, and aspect changes
update their owning docs first. Architecture and schema contracts live in
`docs/specs/`. ADRs capture decisions and rationale, not active work plans.

A requirement is done when someone without this conversation's context can
understand the intended behavior, authority, scope, acceptance bar, and current
gaps.

### Plan

For any work beyond trivial, write a plan before implementing. Options:

- `scoping:requirements-planning` when the durable application requirement is
  missing, stale, or too thin to govern implementation
- `scoping:phase-planning` when settled requirements need decomposition into
  outcome-level delivery chunks
- `scoping:implementation-planning` for a single unit of work
- Inline plan in the conversation for smaller scoped changes — no separate doc

Use `docs/sdlc.md` to decide where the plan belongs. Requirements and gaps live
in durable docs. Backlog lanes live in `docs/backlog.md`. Phase and
implementation plans live in `scratch/` and are only for the selected active
work tree.

Plans capture: what's changing, which files, what proves it works, what the closeout looks like. The plan is the shared artifact Eric can scan before greenlighting implementation.

### Implement

Apply the plan. A few standing rules:

- **Complete cutovers.** Schema change means server migration + SwiftData version bump + API + contract test + spec update, all in one commit. See `docs/MIGRATIONS.md` for the mechanics.
- **No legacy paths, no feature flags.** Change fully or don't change at all.
- **Resolve nitpicks in the moment.** Small inconsistency, off naming, dead code — fix now, don't accumulate a list.
- **Trust the harness.** If a decision is in `AGENTS.md`, `docs/MIGRATIONS.md`, or a spec, it's load-bearing — don't re-debate it in conversation.

Large complete cutovers may use **branch checkpoints** when one review cycle
cannot hold the whole change. A branch checkpoint is not a shippable state and
must not merge to `main`; it exists so implementation-planning, review, and QA
can prove one coherent outcome before moving to the next. The merge boundary
still obeys the complete-cutover rule: no legacy path, no unsupported user path,
and all affected code, tests, schemas, and docs on the new contract.

### Verify

Before closeout:

- `make check` for Python lint/import contracts, Python tests, and schema
  package tests
- `make check-app` for app-facing work: every wired Swift package test plus the
  generated iOS app scheme compile/link smoke
- `make pre-qa` before entering `docs/QA.md` on any change that spans server,
  schema, app logic, or visible iOS behavior; if the needed realistic-local
  harness is missing, route that gap before relying on QA
- Contract tests pass
- For app changes: run the pre-QA checks in `docs/TESTING.md` first, then
  follow `docs/QA.md`. Match proof to the claim; use XcodeBuildMCP simulator QA
  for visible iOS behavior, record and review video with `img ask --video` when
  visible UI changes, use tests/readbacks/logs for state and sync claims, and
  use real devices for Watch, HealthKit, or device-only claims.
- For non-trivial changes: **always** dispatch an independent reviewer agent — self-review by the implementer catches nothing new

The pre-push git hook enforces the Python checks automatically. Full app
pre-QA remains an explicit local gate because it needs macOS/Xcode; see
`.pre-commit-config.yaml` and `docs/TESTING.md`.

## The implementer / reviewer cycle — **independent review, not same-context review**

Implementation and review must not happen in the same reasoning context. A sibling same-model subagent can share too many blind spots with the lead implementer to catch real bugs. The durable rule is:

> **A review is only trustworthy when it is independent from the context that wrote the code.**

### The cycle

For any non-trivial unit of work, the three roles are:

- **Implementation = Claude subagent.** Dispatched from the main thread with a tight brief.
- **Review = code-analysis review, critic, or another available independent reviewer.** The reviewer reads the same repo cold and attacks the claim from a different stance.
- **Synthesis = the lead agent** (the human-facing Claude in the main conversation). Synthesis is **not** delegated to a spawned subagent — the lead reads reviewer findings directly, filters false-positives, and dispatches the next fix-it round from the main thread.

The loop:

1. **Dispatch a Claude implementer subagent** with a tight brief: what to build, which files to touch, what stop conditions (tests pass, build succeeds, specific gates green), and any conventions to follow. Attach full-path reading lists — don't make the implementer discover context.
2. **Implementer returns a self-report** including files changed, design decisions, gate outputs, and any deviations or judgment calls.
3. **Run an independent review** using `code-analysis:review`, the critic, or another currently available review path. The review brief cites what the implementer claims they did, the files to focus on, the questions to answer, the specific hazards to probe, and the gates the reviewer should inspect or re-run. Write temporary prompts under `scratch/reviews/` on demand; if the directory is absent, there is no active review handoff.
4. **Lead synthesizes in the main thread.** Reviewer verdict = ship / needs-another-round. If needs-another-round, the lead dispatches another implementer with reviewer findings inline. Loop until the independent review signs off.

**Sweeps and investigations also use an independent path.** Codebase-state sweeps ("what might be broken?"), hypothesis-driven bug investigations, and adversarial reviews should run outside the implementer context when scope is non-trivial.

Same-context reviews are acceptable only for: trivial scoped fixes, pure doc edits, or config tweaks already guarded by automated checks. Every other change gets independent review.

### Why independence matters

An independent reviewer sees the codebase cold. It doesn't carry the rationalizations the implementing agent built up. Historically this project has caught real bugs through independent review that self-review missed: silent `compactMap` drop on `advancementByBlock` restore, fire-and-forget `Task` snapshot race in session persistence, non-idempotent `.userParameter` push path.

### Parallel reviews

For multi-domain work (e.g. a feature cutover touching drivers + sync + UI),
run parallel reviews — one per domain. Keep prompt files and monitor
notes in `scratch/reviews/` while the review is active, then delete them
after findings are resolved or promoted into durable docs.

### Lightweight reviews

A review prompt doesn't have to be long. 100–150 lines is typical: 3–5 files of focus, 5–8 domain-specific questions, and 3–5 hazards to probe. The value is the independent reading, not the prompt length.

## Skills — when to invoke which

Claude Code exposes named skills for specific phases of work. Use them rather than improvising — they encode project-wide conventions and produce durable artifacts.

| Skill | Use when |
|---|---|
| `scoping:requirements-planning` | When a durable repo requirement is missing, stale, or too thin. Produces or updates the application contract, acceptance criteria, state/authority notes, and docs routing. |
| `scoping:phase-planning` | When settled requirements are too large for one implementation loop and need outcome-level delivery chunks with proof of completion. |
| `scoping:implementation-planning` | When one phase or unit is ready to become a proof-mapped build plan with concrete files, tests, review gates, and closeout. |
| `code-analysis:architecture` | Any question about where a piece of code belongs, what a new module's dependencies should look like, or whether two concerns should share a file. Three modes: audit (existing), greenfield (new), enforcement (automated checks). |
| `code-analysis:review` | Multi-perspective review of a change. Lead agent understands the context, subagents attack from distinct angles, lead synthesizes. Uses the implementer/reviewer cycle described above. |
| `code-analysis:testing-audit` | When a change needs pre-QA proof-bar discovery: identify missing realistic-local, contract, integration, end-to-end, persistence, time, concurrency, or device-adjacent harnesses before simulator/device QA. |
| `code-analysis:investigate` | Hypothesis-driven problem investigation. If you've done two rounds of guessing and haven't isolated the root cause, invoke this instead of guessing a third time. |
| `code-analysis:diagnose-problem-pattern` | When several recent bugs or tests point at a shared structural issue — surface the pattern before patching another symptom. |
| Independent review | When non-trivial implementation needs fresh review context. Use the implementer/reviewer cycle above. |

Skills are composable. A non-trivial change typically goes: `scoping:requirements-planning` when the contract is missing or stale → update `docs/feature-gap-map.md` and `docs/backlog.md` → select the active work tree → `scoping:phase-planning` when the selected lane or unit needs sequencing → `code-analysis:architecture` if structural decisions are still open → `scoping:implementation-planning` → implementer subagent → independent review → fix-it loop → close gaps via `docs/runbooks/closeout.md`.

## iOS development loop

See `docs/ios-dev-loop.md` for the full story. Short version:

- **Preferred stack:** XcodeBuildMCP registered in `.mcp.json`. Exposes structured tool calls for build, install, launch, `snapshot-ui`, `tap`, `screenshot`, log capture, LLDB. Activates on Claude Code session start.
- **Fallback stack (documented):** `xcrun simctl` + `xcodebuild` + screenshot → Read, with `#if DEBUG` launch arguments (`--start-active`, `--jump-rest`, `--jump-complete`) for screen-specific jumps.
- **SourceKit diagnostic noise:** a flood of "No such module" SourceKit warnings is an editor-index artifact, not a build failure. Trust `swift build` / `xcodebuild` output; ignore the editor diagnostic stream.
- **UI snapshot testing:** not wired yet. When layout regressions start biting, reach for `swift-snapshot-testing`.

### Close

Follow `docs/runbooks/closeout.md`. The checklist is short and enforces the
cutover philosophy — every affected surface is updated, every decision is in a
durable file, nothing is left for "later." For app-facing work, the closeout
response includes the QA summary from `docs/QA.md`; durable docs only get proof
or status notes when a bug, gap, feature status, or release status changes.

### Deploy

**No CI/CD pipeline for deployment.** The home server is on a Tailscale mesh that GitHub Actions runners can't reach, and single-user doesn't justify the infra.

Deploy flow:

1. Eric commits + pushes to `main` on GitHub.
2. Eric SSHs to the home server over Tailscale.
3. On the server: `git pull && uv sync && systemctl restart workoutdb-server` (or equivalent — see `docs/infrastructure/home-server.md`).
4. App deploy: open Xcode, rebuild, install to Eric's phone via USB or TestFlight personal build.

Downtime during deploy is acceptable — Eric isn't working out during the deploy.

## CI scope

See `.github/workflows/ci.yml`. GitHub Free personal plan (confirmed April 2026):

- **Public repos:** unlimited standard-runner minutes.
- **Private repos:** 2,000 minutes/month. Linux = 1× multiplier; Windows = 2×; **macOS = 10×** (so ~200 actual macOS minutes/month on private).
- **Self-hosted runners:** as of March 2026, these also consume quota on private repos.

This repo's CI stays narrow because most validation runs locally via pre-commit/pre-push:

- **On push and PR (Linux only)**: `ruff check`, `ruff format --check`, `pytest` on the server package. ~1–2 minutes per run; even 100 pushes/month is well under budget on private.
- **Deferred until the iOS app and deployment story actually exist**: iOS build/test on macOS runners, any deploy automation. When we get there, the public-vs-private trade-off gets revisited (public = unlimited macOS CI; private = keep the repo private but pay for iOS minutes out of the 2,000 budget or move iOS CI off GitHub).
- **Not planned on GitHub Actions**: deploy to the home server. The server is on Tailscale; GitHub runners aren't. If deploy automation lands, it's more likely a self-hosted runner on the home server or a local `make deploy` than an Actions workflow.

Quality stays high via local hygiene, not via CI fan-out:

- **Pre-commit hook**: ruff format + ruff check --fix on staged files.
- **Pre-push hook**: import-linter + full `pytest` run.
- **Manual current local gate**: `make pre-qa` for server/schema/app package
  tests and app scheme compile/link smoke.
- **Manual QA readiness**: `make qa-ready` for XcodeBuildMCP availability
  before simulator/device QA.

Both hooks are configured in `.pre-commit-config.yaml`. Install once after cloning with `pre-commit install --hook-type pre-commit --hook-type pre-push`.

## Architectural enforcement

Boundaries are enforced at lint time so violations fail the commit, not the review.

### Python server (`server/workoutdb_server/`)

**Tool:** `import-linter`. Contracts live in `pyproject.toml` under `[tool.importlinter]`. Run with `uv run lint-imports`. Runs in pre-push and CI.

**Current layered contracts (evolve as modules land):**

```
┌─────────────────────────────────────┐
│ api/  (FastAPI routes)              │  outermost — depends on everything below
├─────────────────────────────────────┤
│ sync/ (push/pull orchestration)     │  outermost — sibling of api
├─────────────────────────────────────┤
│ db, models, migrations              │  data layer — depends only on config
├─────────────────────────────────────┤
│ config                              │  foundation — no repo-local imports
└─────────────────────────────────────┘
```

Rules encoded:
- `config` imports nothing repo-local.
- `db`, `models`, `migrations` never import from `api` or `sync`.
- `sync` never imports from `api` (they're peers; shared logic belongs in a service module).

### When to add a new contract

Adding a new architectural boundary? Add (or extend) a contract in the same commit. Triggers:

- **New top-level package under `workoutdb_server/`** (e.g., `services/`, `integrations/`) — decide its layer, add it to the forbidden lists of lower layers.
- **Split of an existing module** (e.g., `models.py` → `models/{workouts,exercises,users}.py`) — usually a `layers` contract replacing the flat list so all siblings stay at the same depth.
- **Cross-module dependency that feels wrong** — if adding `import workoutdb_server.api.routes` inside `db.py` makes the test suite pass but feels wrong, it *is* wrong. Encode the rule in a contract so it can't slip in later.

If you're reaching for code that violates a contract, the right answer is almost never "loosen the contract." Either extract the shared logic into the correct layer, or rethink the design.

### Swift app (`app/`)

**Not yet enforced** because the Xcode project doesn't exist. When it lands:

- Use SwiftLint for style, with rules checked into the repo.
- Use Xcode targets or SwiftPM modules to enforce architectural boundaries (e.g., a separate `WorkoutCore` module for the data model + sync manager, depended on by the UI target but not vice versa).
- Add a `swiftlint` step to `.pre-commit-config.yaml` and to CI if/when we enable iOS CI.

### Cross-stack (server ↔ app)

- Schema parity is enforced by contract tests in `tests/contract/` (see `docs/TESTING.md`).
- `schema/` (when populated) has no runtime imports of `server/` or `app/`. Whatever format we adopt (OpenAPI, hand-mirrored schemas), this is a principle we hold.

## Branching

Default branch: `main`. For day-to-day work Eric commits directly to `main` after local verification passes. Branches + PRs are optional — useful for exploratory work or when Claude wants a commit staged for review before merging.

No long-lived feature branches. No release branches. If a change is too big to ship complete, break it into smaller complete changes.

## Versioning & releases

No semver, no tags, no release notes. The home server and the app always run the same schema version (enforced by `docs/MIGRATIONS.md`'s version handshake). If a release artifact is ever needed (e.g., for backup or rollback), tag the commit with `deploy/YYYY-MM-DD` — cheap and manual.

## After context loss

Resuming work without this conversation's context:

- Re-read `AGENTS.md` and this file.
- Read the affected spec (`docs/specs/v2-architecture.md`) and any ADRs in `docs/decisions/`.
- Read `docs/sdlc.md` for the planning flow, then `docs/backlog.md` for current lanes and gap ownership. Check `scratch/` for ephemeral handoff notes if a slice is already in progress.
- If confused about history or intent, ask Eric — don't guess.
