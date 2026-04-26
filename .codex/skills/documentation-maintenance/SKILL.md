---
name: documentation-maintenance
description: Use this skill when auditing, expanding, or refactoring repository documentation so structure stays lean, tone remains direct, automation holds the line, and cross-links to bundled skills stay accurate.
---
# Documentation Maintenance

Keep repo docs sharp, current, and easy for agents to follow.

## Documentation Architecture (README vs AGENTS vs docs)

Three types of documentation, each with distinct purpose:

| File | Purpose | Audience | Scope |
|------|---------|----------|-------|
| `README.md` | What is this? How do I start? | Humans | Root only |
| `AGENTS.md` (symlinked to `CLAUDE.md`) | How does this work? Conventions, patterns, examples. | AI agents | Any directory |
| `docs/` | Deep reference: architecture, decisions, how things work | Both | Progressive |

Use `references/architecture.md` for the full decision framework and `references/agents-md-authoring.md` when writing or refactoring AGENTS.md.

## When to Use This Skill
- Bootstrapping docs for a new repo or onboarding a maintainer.
- Deciding whether to create, merge, or retire doc pages and folders.
- Writing feature narratives, runbooks, or interface guides that reference skills.
- Wiring automation that enforces metadata, freshness, and README coverage.
- Refreshing docs after incidents, roadmap changes, or new skills land in the repo.

## Quick Start
1. Load `references/progressive-structure.md` to match the repo phase.
2. If touching AGENTS.md/CLAUDE.md/SKILL.md, load `skill:prompting` and follow `workflows/INSTRUCTION_FILES.md`.
3. If touching AGENTS.md, load `references/agents-md-authoring.md` and start from `templates/agents-md-root.md` or `templates/agents-md-directory.md`.
4. Run `uv run scripts/check_docs.py` and `uv run scripts/check_readmes.py`; note every failure.
5. Draft target pages using the markdown files in `templates/`.
6. Follow the workflow below, keeping sentences imperative, succinct, and cross-linked.

## Workflow

### 1. Assess Current State
- Inventory existing docs; confirm `docs/index.md` links into each critical path.
- Check for stale or missing front matter; flag anything without `last_reviewed`.
- Read `references/routing-and-linking.md` to verify topics live in the right place.
- Identify which skills already exist; open `docs/skills/index.md` or plan to create it.

### 2. Plan Topology
- Use triggers in `references/progressive-structure.md` to decide whether to add a page or promote to a folder.
- Score ambiguous topics with `uv run scripts/should_make_doc.py`.
- Capture planned additions or deletions in `docs/decisions.md` if they change navigation.

### 3. Shape Pages
- Copy the closest file from `templates/` and rename it under `docs/` or a module README.
- Replace placeholders with concrete commands, links, and metrics; keep each page focused on one job.
- Link to the relevant skill (e.g., `skills/documentation-maintenance/SKILL.md`) when the reader should load it before acting.

### 4. Write And Link
- Follow the rules in `references/writing-style.md` for tone, sentence length, and accessibility.
- Add cross-links early and often: services ↔ features, runbooks ↔ commands, docs ↔ skills.
- Update `docs/skills/index.md` using the template if new skills land in the repo.
- Remove or merge superseded pages; mark them `status: deprecated` until deletion.
- Use skill-relative prefixes: `skill:<dir>`, `playbook:<dir>`, `reference:<skill>/<file>`, `template:<skill>/<path>`, `script:<skill>/<path>`, `asset:<skill>/<path>`, `example:<skill>/<path>`. Avoid raw relative URLs when referencing bundled assets.

### 5. Automate And Review
- Update CODEOWNERS and `docs/MAINTAINERS.md` so owners receive review requests.
- Run the two lint scripts locally; fix all findings before opening a PR.
- Ensure `.github/workflows/docs.yml` matches the job in `references/automation.md`.
- During incident retros or quarterly reviews, refresh `last_reviewed` and note doc debt.
- Run cross-link validation to confirm prefixes resolve:
  ```bash
  uv run scripts/check_skill_links.py docs
  ```

## Bundled Resources
- `references/progressive-structure.md`: phased tree, promotion triggers, skills catalogue guidance.
- `references/routing-and-linking.md`: routing table, linking rules, front-matter schema.
- `references/automation.md`: local commands, CI workflow, ownership cadence.
- `references/writing-style.md`: tone, readability, accessibility, and skill callouts.
- `templates/*.md`: ready-to-copy page skeletons for core doc types plus the skills index.
- `scripts/check_docs.py`: validates metadata, freshness, size, and secret patterns.
- `scripts/check_readmes.py`: enforces README coverage and root linking.
- `scripts/check_skill_links.py`: validates that `skill:`/`playbook:` references resolve to bundled assets.
- `scripts/should_make_doc.py`: scores whether to author a page or folder.

Keep the skill lean: move detailed lists into references, executable logic into scripts, and reusable markdown into templates.

## Related Skills

- review
- release-engineering
