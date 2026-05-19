---
title: Bugs — live tracker
status: living
last_reviewed: 2026-05-19
purpose: Canonical active defect tracker. Closed issues live in git history; unbuilt feature gaps live in owning requirement docs and the gap map.
covers:
  - whole project
---

# Bugs

This file is the **single source of truth for active defects** — code that does
the wrong thing against accepted requirements or feature docs.

Unbuilt target behavior is not a bug by itself. If QA discovers missing behavior
that was never implemented, update the owning requirement docs' `Current gaps`
sections and `docs/feature-gap-map.md`; route the work through
`docs/backlog.md`.

**Not here:**
- Unresolved design decisions → `docs/open-questions.md`
- Unbuilt feature gaps → owning requirement docs + `docs/feature-gap-map.md`
- Feature QA scenarios → `docs/features/<slug>.md`
- Architectural risk register → `docs/architecture/hotspots.md`
- Raw QA run artifacts → `scratch/qa-runs/` while the run is active; migrate any still-open issue here before ending the run

**Closed bugs are not archived in this file or duplicated in another live tracker.** Git is the changelog — `git log -p -- docs/bugs.md` recovers any prior entry. Invariants that came out of bug fixes live in `AGENTS.md`, owning requirement docs, or ADRs; the bug entry itself is disposable once it's closed.

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

As of 2026-05-19: there are no active P0/P1 primitive-lane bugs tracked here.
Primitive completion bugs bug-093, bug-096, bug-097, bug-098, and bug-099 were
closed by the primitive completion/history remediation; the fixed invariants now
live in the primitive spec, History doc, DesignSystem contract, and test suite.
The workout-type matrix runner instability bug-094 and TokenStore Keychain gate
bug-100 were also closed by the same remediation batch.

### P0 — blocks v1

_None._

### P1 — workaround exists or rarely hit

_None._

### P2 — cosmetic / polish

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| bug-083 | Inconsistent workout-card CTA placement makes selected-vs-alternate state unclear | Today plan queue | in-progress | UX QA while reviewing the first real week: selected workout rendered `start workout` at bottom, other cards rendered `start this workout` near top. Position does not communicate priority unless the user already knows the rule, so it reads as sloppy. Fix: keep CTA placement consistent and use explicit badge/label for state. |
| bug-085 | Today exposes off-screen workout cards as activatable accessibility targets | Today plan queue / accessibility | open | Simulator QA on 2026-04-25: tapping an off-screen workout by accessibility label activated the wrong/current visible workflow and started a missed workout while trying to inspect the bridge plan. Some of this is MCP automation behavior, but the app should make visible card targets unambiguous for VoiceOver and UI automation, ideally with stable IDs and no accidental off-screen activation path. |
| bug-087 | Alternative swaps cannot clear inherited load or represent non-integer rep targets | Execution / alternatives | open | Payload-contract QA on 2026-04-25: bodyweight/band alternatives inherit parent load when the override omits load, and string reps such as `amrap` are not a valid override shape. This can make a bodyweight substitute look loaded or make an alternative unusable. |
| bug-088 | Conditional workout choices are hidden in notes instead of executable controls | Today / execution / workout authoring payloads | open | Week-review QA on 2026-04-25: choices like skip/reduce lower-body work or choose core vs easy engine based on Sunday were authored as prose notes. That is readable but not executable in the app, so the athlete has no clear tap target for the intended branch. |
| bug-091 | Debug simulator launch shows prolonged blank white screen before first UI | App launch / shell | watchlist | Primitive lane QA on 2026-05-17: video review saw a distinct blank white screen before the Today debug plan appeared and again before the primitive capstone relaunch appeared. The app continued without crash and the primitive flow was not blocked, so this is tracked as non-blocking launch polish unless it recurs outside debug simulator launch. 2026-05-19 workout-type E2E video saw the same brief white launch flash in a debug `--jump-complete primitive_capstone_fast` launch; still non-blocking, but recurring. |
| bug-092 | Timer End confirmation allows active timer content to bleed through alert | Execution / timer modes | open | Workout-type video QA on 2026-05-18: focused clocked-mode recording proved `emom`, `amrap`, `for_time`, `intervals`, and `tabata`, but the visual reviewer flagged active timer text/graphics bleeding through the `End workout?` confirmation during Tabata and mixed interval-style flows. |
| bug-095 | Primitive debug fixture can visually complete while primitive logs stay empty | Debug fixtures / execution QA | watchlist | Final WorkoutKit remediation QA on 2026-05-18 found the `primitive_strength_density` debug seed could show a logged completion while SwiftData telemetry reported `primitive_set_log_count: 0`. Cause was split IDs between legacy `WorkoutItem` rows and `PrimitiveSlot` rows, which broke slot-position lookup. Fixed in the active branch by reusing the same ID; keep watchlisted until closeout confirms no sibling debug fixture can mask primitive persistence without telemetry readback. 2026-05-19 QA found separate History rendering and EMOM early-end gaps tracked as bug-096 and bug-097. |

**ID allocation:** bug-001–060 were assigned during the initial QA campaign; `bug-061+` are post-campaign findings. `qa-001`–`qa-047` were campaign-internal ids; any finding that still matters as an active defect must have a `bug-NNN` row here. Next ID: `bug-101`.

---

## How to use this

- **Starting work on a bug:** move it to `in-progress`, put your name/agent ID next to it.
- **Adding a bug:** use the next ID listed above, pick priority, link affected feature doc.
- **Fixing a bug:** close it in the same commit as the fix. Delete the row here; make sure the fix's invariant lives somewhere durable (`AGENTS.md`, owning requirement docs, or an architecture/schema spec when that is the true owner). Cite the regression test in the commit message, not here.
- **Demoting a feature's release-evidence status:** file a bug here in the same commit that updates `docs/spec.md`.
- **Wontfix / deferred:** short rationale in Notes; link ADR or open-question if a design decision supports the call.

Cross-ref: `docs/spec.md` feature matrix reflects aggregated release-evidence state; individual bugs here drive it down as they're found.
