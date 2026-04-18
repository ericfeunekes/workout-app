---
title: Development workflow
status: stable
date: 2026-04-17
purpose: "How work progresses in this repo — the lifecycle from idea to deployed code, and the rules that hold across every cycle."
covers:
  - AGENTS.md
  - docs/MIGRATIONS.md
  - docs/runbooks/closeout.md
---

# Development workflow

This repo has one developer and one user (both Eric). There are no sprints, no standups, no PR review boards. The workflow below exists to keep decisions and rationale durable across Claude conversations so that future sessions — without the context of this one — can continue to improve the system safely.

## The lifecycle

```
idea → spec → plan → implement → verify → close → deploy
```

### Idea

Eric starts a conversation. Work classifies into one of three sizes:

- **Trivial** (typo, rename, one-line fix) — skip straight to implement.
- **Scoped change** (one module, known shape) — skip spec; go to plan.
- **Non-trivial** (new feature, schema change, cross-stack) — start with a spec interview.

Claude's job is to classify out loud at the start of a conversation. "This is non-trivial; interviewing first." Or "this is scoped; jumping to the plan." Eric can overrule.

### Spec

For non-trivial work, use `skill:interview` (asks adaptive questions, writes a decisions doc) or update `docs/specs/v2-architecture.md` directly when the change is a refinement.

A spec is done when someone without this conversation's context could implement it.

**Specs live in `docs/specs/`.** ADRs live in `docs/decisions/`. Exploration docs that support a spec live next to the spec with a "decisions-applied" status once their findings are merged.

### Plan

For any work beyond trivial, write a plan before implementing. Options:

- `skill:feature-planning` for high-level scope (multi-unit)
- `skill:implementation-planning` for a single unit of work
- Inline plan in the conversation for smaller scoped changes — no separate doc

Plans capture: what's changing, which files, what proves it works, what the closeout looks like. The plan is the shared artifact Eric can scan before greenlighting implementation.

### Implement

Apply the plan. A few standing rules:

- **Complete cutovers.** Schema change means server migration + SwiftData version bump + API + contract test + spec update, all in one commit. See `docs/MIGRATIONS.md` for the mechanics.
- **No legacy paths, no feature flags.** Change fully or don't change at all.
- **Resolve nitpicks in the moment.** Small inconsistency, off naming, dead code — fix now, don't accumulate a list.
- **Trust the harness.** If a decision is in `AGENTS.md`, `docs/MIGRATIONS.md`, or a spec, it's load-bearing — don't re-debate it in conversation.

### Verify

Before closeout:

- `ruff check` + `ruff format --check`
- `pytest` (server tests pass)
- Contract tests pass (once they exist)
- For app changes: `xcodebuild` on the iOS Simulator scheme (see `docs/ios-dev-loop.md`)
- For non-trivial changes: **always** dispatch an independent reviewer agent — self-review by the implementer catches nothing new

The pre-push git hook enforces the Python checks automatically; see `.pre-commit-config.yaml`.

## The implementer / reviewer cycle — **Codex reviews, not same-model subagents**

Implementation subagents are Claude. **Reviews are Codex (a different model).** This is load-bearing — a sibling Claude subagent shares too many blind spots with the lead Claude agent to catch real bugs. The durable rule is:

> **A review is only trustworthy when it comes from a different model than the one that wrote the code.**

### The cycle

For any non-trivial unit of work:

1. **Dispatch a Claude implementer subagent** with a tight brief: what to build, which files to touch, what stop conditions (tests pass, build succeeds, specific gates green), and any conventions to follow. Attach full-path reading lists — don't make the implementer discover context.
2. **Implementer returns a self-report** including files changed, design decisions, gate outputs, and any deviations or judgment calls.
3. **Dispatch a Codex review via `cxd task`** — Codex is a different model, reading the same repo. One-shot form:
   ```bash
   cxd task --sandbox read-only --detach --cwd $PWD \
     --service-name review-<domain> --effort medium \
     -f path/to/review-prompt.md
   ```
   The review prompt cites: what the implementer claims they did, the files to focus on, the questions to answer, the specific hazards to probe, and the gates Codex should re-run. See `scratch/codex-reviews/_template-header.md` + `_session-context.md` for the methodology baseline.
4. **Lead agent synthesizes.** Codex verdict = ship / needs-another-round. If needs-another-round, dispatch another Claude implementer with Codex's findings inline. Loop until Codex signs off.

Same-model Claude-subagent reviews are acceptable only for: trivial scoped fixes, pure doc edits, or config tweaks already guarded by automated checks. Every other change goes through Codex.

### Why Codex and not another Claude

Codex sees the codebase cold. It doesn't carry the rationalizations the implementing agent built up. Historically this project has caught real bugs through Codex review that Claude self-review missed: silent `compactMap` drop on `advancementByBlock` restore, fire-and-forget `Task` snapshot race in session persistence, non-idempotent `.userParameter` push path. None of these were visible to Claude implementers or Claude reviewers.

### Parallel Codex reviews

For multi-domain work (e.g. a feature cutover touching drivers + sync + UI), fire parallel Codex reviews — one per domain — via `_dispatch.sh`. Monitor with `_monitor.sh`. Pattern lives in `scratch/codex-reviews/` as a working template.

### Lightweight Codex reviews

A Codex review prompt doesn't have to be long. 100–150 lines is typical: 3–5 files of focus, 5–8 domain-specific questions, 3–5 hazards to probe, plus the shared `_template-header.md` + `_session-context.md`. The value is the independent reading, not the prompt length.

## Skills — when to invoke which

Claude Code exposes named skills for specific phases of work. Use them rather than improvising — they encode project-wide conventions and produce durable artifacts.

| Skill | Use when |
|---|---|
| `scoping:feature-planning` | Before writing any code on a non-trivial feature. Clarifies user stories, scope, decomposition, and acceptance criteria. Produces a feature spec. |
| `scoping:implementation-planning` | After `feature-planning`, when the unit of work is scoped and you want the full plan for building + proving + reviewing + closing out. |
| `code-analysis:architecture` | Any question about where a piece of code belongs, what a new module's dependencies should look like, or whether two concerns should share a file. Three modes: audit (existing), greenfield (new), enforcement (automated checks). |
| `code-analysis:review` | Multi-perspective review of a change. Lead agent understands the context, subagents attack from distinct angles, lead synthesizes. Uses the implementer/reviewer cycle described above. |
| `code-analysis:debugging` | Hypothesis-driven bug investigation. If you've done two rounds of guessing and haven't isolated the root cause, invoke this instead of guessing a third time. |
| `code-analysis:diagnose-problem-pattern` | When several recent bugs or tests point at a shared structural issue — surface the pattern before patching another symptom. |
| `codex:review` / `codex:second-opinion` | When the main agent's reasoning needs a fresh set of eyes from a different model (Codex). Especially useful after deep-context work where the main agent may have blind spots. |

Skills are composable. A non-trivial change typically goes: feature-planning → architecture (if structural) → implementation-planning → implementer subagent → reviewer (via code-analysis:review) → fix-it loop → close.

## iOS development loop

See `docs/ios-dev-loop.md` for the full story. Short version:

- **Preferred stack:** XcodeBuildMCP registered in `.mcp.json`. Exposes structured tool calls for build, install, launch, `snapshot-ui`, `tap`, `screenshot`, log capture, LLDB. Activates on Claude Code session start.
- **Fallback stack (documented):** `xcrun simctl` + `xcodebuild` + screenshot → Read, with `#if DEBUG` launch arguments (`--start-active`, `--jump-rest`, `--jump-complete`) for screen-specific jumps.
- **SourceKit diagnostic noise:** a flood of "No such module" SourceKit warnings is an editor-index artifact, not a build failure. Trust `swift build` / `xcodebuild` output; ignore the editor diagnostic stream.
- **UI snapshot testing:** not wired yet. When layout regressions start biting, reach for `swift-snapshot-testing`.

### Close

Follow `docs/runbooks/closeout.md`. The checklist is short and enforces the cutover philosophy — every affected surface is updated, every decision is in a durable file, nothing is left for "later."

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
- **Pre-push hook**: full `pytest` run.

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
- Check `docs/plans/active/` for in-flight work (directory created when first plan lands).
- If confused about history or intent, ask Eric — don't guess.
