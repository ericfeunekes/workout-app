# Routing And Linking Rules

Decide where each piece of information lives and how to connect it.

## Topic Routing

| Need | Location | Rationale |
| --- | --- | --- |
| Run a single service or module | `<service>/README.md` | Keep executable steps beside code |
| Test suite usage | `tests/README.md` | Daily workflow |
| Test strategy or policy | `docs/testing.md` or folder | Cross-team rules |
| Incident response | `docs/runbooks/*` | Ops coordination |
| Feature narrative | `docs/features/<slug>.md` | Cross-team understanding |
| Architecture overview | `docs/architecture/overview.md` | System map |
| Data/flow diagrams | `docs/architecture/flows.md` | Critical paths |
| Infra inventory | `docs/infra/environments.md` | Environment clarity |
| Canonical contracts | `contracts/` | Single source of truth |
| Skills catalogue | `docs/skills/index.md` | Entry point for bundled skills |

## Link Hygiene

- Link root `README.md` → `docs/index.md`
- Each feature doc links to its owning services’ READMEs and back again
- Architecture diagrams and flows link to feature docs and relevant skill directories
- Runbooks link to exact commands in READMEs and to mitigation skills or scripts
- Doc pages point to `skills/<slug>/SKILL.md` when the reader should load a skill
- Use relative links inside the repo to keep navigation durable

## Naming And Structure

- Start flat: `docs/<topic>.md`
- Promote only when a folder earns `index.md` plus focused subpages
- Keep depth ≤2 levels under `docs/`
- Name ADRs `docs/adr/ADR-YYYY-MM-DD-<slug>.md`
- Name runbooks `docs/runbooks/<type>/<slug>.md`
- Tag doc status in front matter: `draft`, `stable`, or `deprecated`

## Front Matter

Place this at the top of every Markdown doc in `docs/`:

```yaml
---
title: <Page Title>
status: draft # or stable, deprecated
last_reviewed: <YYYY-MM-DD>
purpose: "Short single-job statement."
---
```

Update `last_reviewed` during each substantial change and during scheduled reviews.
