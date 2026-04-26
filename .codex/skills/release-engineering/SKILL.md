---
name: release-engineering
description: Use this skill when establishing or tightening release workflows, CI/CD gates, and breaking-change controls. Focuses on minimal, repeatable practices aligned to the current stack.
---
# Release Engineering

Establish release workflows and quality gates that keep shipping safe without slowing teams down.

## When to Use This Skill

- Defining or tightening CI/CD for a repo
- Establishing tag-based release workflows
- Managing breaking changes in APIs or data contracts
- Standardizing release practices across repos

## Core Principles

1. **Build once, promote by version** - the same artifact moves across environments.
2. **Fast feedback** - quick local checks, comprehensive CI validation.
3. **Contract-first** - protect API/data contracts before merges.
4. **Reproducible builds** - frozen dependencies and deterministic artifacts.
5. **Rollback-ready** - explicit rollback paths for every release.

## Standard Tooling (by stack)

**Python repos**:
- Dependency sync: `uv sync --frozen`
- Lint/format: `uv run ruff check ...`, `uv run ruff format --check ...`
- Type check: prefer `ty` or repo task wrapper via `uv run`
- Tests: `uv run pytest ...`
- Contract checks: OpenAPI diff / contract guard
- Diff coverage: `diff-cover` in PRs

**Web/JS repos**:
- `npm ci` (workspace lockfile enforced)
- `npm run lint`, `npm run typecheck`
- `npm run test:unit`, `npm run test:integration`
- Tag-based releases drive environment deploys

**Databricks apps**:
- `uv sync --frozen`
- Deploy via Databricks CLI + repo scripts

Use repo-provided task runners when they exist; avoid ad-hoc commands.

## Release Triggers (Standard Pattern)

- **Dev:** auto on `main` (allow opt-out for noisy repos)
- **Stage:** manual promotion by **version/SHA**
- **Prod:** tag-driven **deploy** of an existing artifact

**Important:** Tags **label** a built artifact; they should not trigger a rebuild.

## Artifact Existence Gate

Before promoting a release version:
- Verify the artifact exists in the registry/package store.
- If the version already exists, **fail fast** and require a version bump.

This prevents accidental re-publishing of the same version.

## Quality Gates (Lean)

### Local / Pre-commit
- Format + lint
- Type check
- Fast unit tests

### PR / CI
- Full lint + type check
- Unit + integration tests
- Contract checks (OpenAPI or schema diffs)
- Diff coverage threshold (per repo policy)
- Security scan appropriate to stack (npm audit, semgrep)

### Release / Deploy
- Deployment readiness checks
- Smoke tests on target environment
- Rollback plan verified

## Release Workflow (Tag-Based, recommended)

Use explicit tags to promote existing artifacts across environments:

- `vX.Y.Z-dev.N` -> dev
- `vX.Y.Z-rc.N` -> staging (shadow/slot)
- `vX.Y.Z` -> production
- `vX.Y.Z-rollback.N` -> production rollback

Typical flow:
1. Build artifact on merge to `main` and publish to registry.
2. Validate in dev.
3. Promote the **same version** to stage (manual).
4. Tag the validated version for prod deploy.

## Migration Safety (APIs + DB)

- Migrations must be **backwards-compatible**.
- Breaking changes require a **two-step rollout** (additive first, removal later).
- Do not assume rollback is safe after schema changes.

## Smoke Checks (stack-specific)

- **API:** read + write probe (not just `/health`).
- **Workers/Agents:** heartbeat/job pickup.
- **Web UI:** login page render (optional where appropriate).

## Breaking Change Management

- Detect via OpenAPI/schema diffs and migration reviews.
- Announce breaking changes early with migration guidance.
- Prefer additive changes + deprecation windows.

See `references/breaking-changes.md` for concrete patterns.

## References

- `references/release-workflow.md`
- `references/tag-based-deployment.md`
- `references/breaking-changes.md`
- `references/pr-gates.md`
- `references/quality-metrics.md`
- `references/github-actions-templates.md`

## Related Skills

- review
- security
- documentation-maintenance
