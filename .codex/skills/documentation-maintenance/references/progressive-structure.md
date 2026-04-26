# Progressive Documentation Structure

Start minimal. Add docs as complexity grows.

## Phases

### Phase 0 — Seed (New Project)

Create only:

```
docs/
├── index.md          # Entry point, links to sections
└── decisions.md      # ADRs, why we chose X
```

**Trigger to advance**: 2+ maintainers OR external consumers appear.

### Phase 1 — Sprout

Add when second maintainer or external consumer joins:

```
docs/
├── index.md
├── decisions/
│   └── ADR-001-*.md
├── architecture/
│   └── overview.md
└── runbooks/
    └── incident-response.md
```

**Trigger to advance**: 3+ team members OR incidents occur.

### Phase 2 — Trunk

Add when team grows or incidents reveal gaps:

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

**Trigger to advance**: Regulated industry OR multi-team platform.

### Phase 3 — Canopy

Add for compliance or platform scale:

```
docs/
├── ...
├── roadmap.md
├── changelog.md
├── observability.md
└── risk-register.md
```

---

## When to Create a Page

Create a new page when at least two are true:

- Same question asked 3+ times in 30 days
- Incident MTTR increased ≥15 minutes due to missing doc
- New external consumer depends on the knowledge
- Existing page mixes two distinct jobs

---

## When to Create a Folder

Promote a page to a folder when at least two are true:

- Two or more stable subpages exist
- Examples or diagrams overcrowd the page
- Different audiences need distinct views
- Topic has versioned lifecycles or review cadence

---

## Page Length Guidelines

| Length | Action |
|--------|--------|
| <100 lines | Consider merging with related page |
| 100-300 lines | Good size |
| >300 lines | Consider splitting into folder |

---

## Example: Deciding Structure

**Scenario**: New project, solo developer.

→ Use **Seed** phase. Just `index.md` and `decisions.md`.

**Scenario**: Team of 3, had first incident last week.

→ Advance to **Trunk**. Add `runbooks/`, `architecture/`.

**Scenario**: Same question about auth asked 4 times this month.

→ Create `docs/architecture/auth.md` or `docs/features/auth.md`.

**Scenario**: Auth page is 400 lines with diagrams, code samples, and API docs.

→ Promote to `docs/architecture/auth/` folder with subpages.

---

## README Rules

Root `README.md`:
- Purpose, quickstart, layout
- Link to `docs/index.md`
- 30-80 lines

Module READMEs (e.g., `src/auth/README.md`):
- Local dev commands, fixtures
- Pointers back to relevant docs
- Optional, create only if module has non-obvious setup

---

## Front Matter

All docs/ pages should have:

```yaml
---
title: Page Title
last_reviewed: 2024-01-15
owner: @username
---
```

This enables automated freshness checks via `check_docs.py`.
