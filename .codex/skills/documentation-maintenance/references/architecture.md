# Documentation Architecture

Division of responsibilities between README, AGENTS.md, and docs/.

## The Split

| File | Purpose | Audience | Scope |
|------|---------|----------|-------|
| **README.md** | What is this? How do I start? | Humans | Root only |
| **AGENTS.md** | How does this work? Conventions, patterns. | AI agents | Any directory needing instructions |
| **docs/** | Deep reference: architecture, decisions, how things work | Both (human-first) | Progressive structure |
| **skills/** | Procedural workflows, loaded on demand | AI agents | `.claude/skills/` ↔ `.codex/skills/` |

**Core insight**: Humans read README, then ask their agent questions. Agents read AGENTS.md files to understand how to work in each area.

---

## README.md

One file at repository root. Human onboarding only.

### What It Contains

1. **Project identity** (1-2 sentences)
   - What is this?
   - Why does it exist?

2. **Quickstart** (5-10 lines)
   - Install dependencies
   - Run the thing
   - Run tests

3. **Project layout** (brief)
   - What's in each top-level directory
   - Links to docs/ for depth

4. **Links out**
   - `docs/` for architecture, decisions
   - Contributing guidelines if open source

### What It Does NOT Contain

- Coding conventions (→ AGENTS.md)
- Architecture details (→ docs/architecture/)
- Runbooks (→ docs/runbooks/)
- Agent instructions (→ AGENTS.md)

### Example README

```markdown
# Project Name

Brief description of what this project does and why.

## Quickstart

```bash
uv sync
uv run pytest
uv run python -m myproject
```

## Layout

- `src/` — Application code
- `testing/` — Test suites (unit, integration, smoke)
- `infra/` — Infrastructure definitions
- `docs/` — Architecture, decisions, runbooks

## Documentation

See [docs/](docs/) for architecture decisions, runbooks, and detailed guides.
```

**Target length**: 30-80 lines. If longer, move content to docs/.

---

## AGENTS.md (symlinked to CLAUDE.md)

Instructions for AI agents. Follows prompting skill best practices.

### Hierarchy

```
repo/
├── AGENTS.md                    # Global conventions
├── src/
│   └── auth/
│       └── AGENTS.md            # Auth-specific patterns
├── testing/
│   ├── AGENTS.md                # Testing conventions
│   └── deployment/
│       └── AGENTS.md            # Deployment pipeline specifics
└── infra/
    └── AGENTS.md                # Infrastructure conventions
```

Child AGENTS.md files inherit from parent. Only document what differs or needs emphasis.

### When to Create Directory AGENTS.md

Create when at least two are true:

- Agents repeatedly make mistakes in this area
- Conventions differ from root
- Non-obvious patterns exist
- Complex workflows need examples
- Area has specific anti-patterns to avoid

### What Goes in Root AGENTS.md

- Core coding values (simplicity, maintainability, efficiency, safety)
- Global tooling (uv, ruff, ty, etc.)
- Testing philosophy
- Global patterns with examples
- Anti-patterns with examples

**Target length**: 100-200 lines with examples.

### What Goes in Directory AGENTS.md

- Conventions specific to that directory
- Patterns that differ from or extend root
- Common tasks with examples
- Anti-patterns specific to this context

**Target length**: 30-100 lines.

### AGENTS.md Best Practices

From the prompting skill:

1. **Examples for key behaviors** — 2-4 diverse examples, good/bad contrasts
2. **Quantitative constraints** — "3-6 sentences", not "be concise"
3. **XML-like sections** — Group related rules
4. **Omit what models know** — Focus on YOUR conventions
5. **Imperative tone** — "Use X" not "You should use X"

### Example: testing/AGENTS.md

```markdown
# Testing Conventions

Inherits from root AGENTS.md. Testing-specific patterns.

## Test Organization

| Directory | Purpose | I/O | Markers |
|-----------|---------|-----|---------|
| `unit/` | Pure functions | None | — |
| `integration/` | Service interactions | Fakes (respx, vcr) | — |
| `smoke/` | Real endpoints | Live | `@pytest.mark.smoke` |

## Fixtures

<fixture_patterns>
All fixtures in `conftest.py` at each level. Never in test files.

Good:
```python
# conftest.py
@pytest.fixture
def auth_client(settings: Settings) -> AuthClient:
    return AuthClient(settings)
```

Bad:
```python
# test_auth.py
@pytest.fixture  # Don't put fixtures in test files
def auth_client():
    return AuthClient(Settings())  # Don't instantiate directly
```
</fixture_patterns>

## Running Tests

```bash
uv run pytest testing/unit           # Fast, no I/O
uv run pytest testing/integration    # Needs Docker
uv run pytest -m smoke               # Hits real endpoints
```

## Anti-Patterns

- Don't create test gating (`@pytest.mark.skipif(not HAS_KEY)`)
- Don't invent env vars—use existing config
- Don't mock what you can inject
```

---

## docs/

Deep reference material. Human-first but agent-readable.

### What It Contains

- **Architecture** — System design, component relationships, data flows
- **Decisions** — ADRs, why we chose X over Y
- **Infrastructure** — How infra works, not how to change it (that's AGENTS.md)
- **Runbooks** — Operational procedures for incidents
- **Features** — Detailed feature documentation
- **Interfaces** — API specs, schemas, contracts

### Progressive Structure

Start minimal. Add pages/folders as complexity grows.

**Phase 0 — Seed** (new project):
```
docs/
├── index.md
├── quickstart.md
└── decisions.md
```

**Phase 1 — Sprout** (2+ maintainers or external consumers):
```
docs/
├── index.md
├── architecture/
│   └── overview.md
├── decisions/
│   └── ADR-001-*.md
└── runbooks/
    └── incident-response.md
```

**Phase 2 — Trunk** (3+ team, incidents occur):
```
docs/
├── index.md
├── architecture/
│   ├── overview.md
│   ├── data.md
│   └── flows.md
├── decisions/
├── runbooks/
│   ├── oncall.md
│   └── playbooks/
├── features/
│   └── <feature>.md
└── interfaces/
    ├── http.md
    └── events.md
```

### When to Create a Page vs Folder

**Create a page** when:
- Topic is self-contained
- Content fits in <300 lines
- Single audience

**Promote to folder** when:
- Two or more stable subpages exist
- Different audiences need distinct views
- Content exceeds 300 lines
- Topic has versioned or lifecycle aspects

### docs/ vs AGENTS.md

| docs/ | AGENTS.md |
|-------|-----------|
| How things work | How to work here |
| Architecture, decisions | Conventions, patterns |
| Human-first | Agent-first |
| Reference material | Operating instructions |
| Read when learning | Read when doing |

**Example**:
- docs/architecture/auth.md — How the auth system works, components, flows
- src/auth/AGENTS.md — Conventions when modifying auth code, patterns to follow

---

## Skills

Procedural workflows loaded on demand.

### Location

```
.claude/skills/    ←→    .codex/skills/    (symlinked)
```

### When to Create a Skill vs AGENTS.md

| Skill | AGENTS.md |
|-------|-----------|
| Reusable across repos | Repo-specific |
| Complex multi-step workflows | Conventions and patterns |
| Needs scripts, templates, assets | Just instructions |
| Loaded on demand | Always in context |

### Referencing Skills from AGENTS.md

```markdown
## Documentation

When updating docs, load `skill:documentation-maintenance` first.
```

---

## Summary

```
repo/
├── README.md                 # Human: what, why, quickstart (30-80 lines)
├── AGENTS.md → CLAUDE.md     # Agent: global conventions (100-200 lines)
├── src/
│   └── <module>/
│       └── AGENTS.md         # Agent: module-specific (30-100 lines)
├── testing/
│   └── AGENTS.md             # Agent: testing conventions
├── docs/
│   ├── index.md              # Entry point, links to sections
│   ├── architecture/         # How things work
│   ├── decisions/            # Why we chose X
│   ├── runbooks/             # Operational procedures
│   └── features/             # Feature documentation
└── .claude/skills/           # Procedural workflows
```

**The principle**: README for humans to start, AGENTS.md for agents to operate, docs/ for deep reference, skills/ for reusable workflows.
