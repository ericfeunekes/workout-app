---
title: Bugs — live tracker
status: living
purpose: Canonical active QA issue tracker. Closed issues live in git history; raw QA evidence lives outside this tracker.
covers:
  - whole project
---

# Bugs

This file is the **single source of truth for active QA issues** — code that does the wrong thing vs. spec, feature gaps surfaced by QA, or things the spec promised and the code didn't deliver.

**Not here:**
- Unresolved design decisions → `docs/open-questions.md`
- Feature QA scenarios → `docs/features/<slug>.md`
- Architectural risk register → `docs/architecture/hotspots.md`
- Raw QA run artifacts → `scratch/qa-runs/` while the run is active; migrate any still-open issue here before ending the run

**Closed bugs are not archived in this file or duplicated in another live tracker.** Git is the changelog — `git log -p -- docs/bugs.md` recovers any prior entry. Invariants that came out of bug fixes live in `AGENTS.md` / `docs/spec.md` / feature docs; the bug entry itself is disposable once it's closed.

See `docs/QA.md` for the QA recording workflow and evidence rules.

## Priority conventions

- **P0** — blocks v1 ship. Feature doesn't work or produces wrong data in the normal flow.
- **P1** — ship with workaround, fix before first real use. Visible but bypassable.
- **P2** — cosmetic, edge case, polish. Won't block Eric's first gym session.

## Status conventions

- `open` — identified, not yet started
- `in-progress` — someone's actively fixing
- `wontfix` — acknowledged, deliberately not fixing (with reason)
- `deferred` — moved to v1.1+ (with reason)
- `watchlist` — known non-blocking polish or instability to revisit if it recurs

Fixed bugs are removed from this file once closed — the fix, the regression test, and any invariant it established live in the feature doc / spec / `AGENTS.md`.

---

## Active

As of 2026-04-25: no active P0/P1 bugs are tracked here. Active P2 items remain below.

### P0 — blocks v1

_None._

### P1 — workaround exists or rarely hit

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| _None_ | | | | |

### P2 — cosmetic / polish / feature-gap

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| bug-083 | Inconsistent workout-card CTA placement makes selected-vs-alternate state unclear | Today plan queue | in-progress | UX QA while reviewing the first real week: selected workout rendered `start workout` at bottom, other cards rendered `start this workout` near top. Position does not communicate priority unless the user already knows the rule, so it reads as sloppy. Fix: keep CTA placement consistent and use explicit badge/label for state. |
| bug-085 | Today exposes off-screen workout cards as activatable accessibility targets | Today plan queue / accessibility | open | Simulator QA on 2026-04-25: tapping an off-screen workout by accessibility label activated the wrong/current visible workflow and started a missed workout while trying to inspect the bridge plan. Some of this is MCP automation behavior, but the app should make visible card targets unambiguous for VoiceOver and UI automation, ideally with stable IDs and no accidental off-screen activation path. |
| bug-087 | Alternative swaps cannot clear inherited load or represent non-integer rep targets | Execution / alternatives | open | Payload-contract QA on 2026-04-25: bodyweight/band alternatives inherit parent load when the override omits load, and string reps such as `amrap` are not a valid override shape. This can make a bodyweight substitute look loaded or make an alternative unusable. |
| bug-088 | Conditional workout choices are hidden in notes instead of executable controls | Today / execution / workout authoring payloads | open | Week-review QA on 2026-04-25: choices like skip/reduce lower-body work or choose core vs easy engine based on Sunday were authored as prose notes. That is readable but not executable in the app, so the athlete has no clear tap target for the intended branch. |

**ID allocation:** bug-001–060 were assigned during the initial QA campaign; `bug-061+` are post-campaign findings. `qa-001`–`qa-047` were campaign-internal ids; any finding that still matters as an active defect must have a `bug-NNN` row here. Next ID: `bug-089`.

---

## How to use this

- **Starting work on a bug:** move it to `in-progress`, put your name/agent ID next to it.
- **Adding a bug:** use the next ID listed above, pick priority, link affected feature doc.
- **Fixing a bug:** close it in the same commit as the fix. Delete the row here; make sure the fix's invariant lives somewhere durable (`AGENTS.md`, feature doc, or spec). Cite the regression test in the commit message, not here.
- **Demoting a feature's status:** file a bug here in the same commit that updates `docs/spec.md`.
- **Wontfix / deferred:** short rationale in Notes; link ADR or open-question if a design decision supports the call.

Cross-ref: `docs/spec.md` feature matrix reflects aggregated state; individual bugs here drive it down as they're found.
