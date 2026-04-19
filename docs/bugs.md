---
title: Bugs — live tracker
status: living
purpose: Defects found in code — separate from open-questions.md (design debates) and feature docs (intended behavior).
covers:
  - whole project
---

# Bugs

This file tracks **defects** — code that does the wrong thing vs. spec, or things the spec promised and the code didn't deliver.

**Not here:**
- Unresolved design decisions → `docs/open-questions.md`
- Feature QA scenarios → `docs/features/<slug>.md`
- Architectural risk register → `docs/architecture/hotspots.md`

**Closed bugs are not archived in this file.** Git is the changelog — `git log -p -- docs/bugs.md` recovers any prior entry. Invariants that came out of bug fixes live in `CLAUDE.md` / `docs/spec.md` / feature docs; the bug entry itself is disposable once it's closed.

## Priority conventions

- **P0** — blocks v1 ship. Feature doesn't work or produces wrong data in the normal flow.
- **P1** — ship with workaround, fix before first real use. Visible but bypassable.
- **P2** — cosmetic, edge case, polish. Won't block Eric's first gym session.

## Status conventions

- `open` — identified, not yet started
- `in-progress` — someone's actively fixing
- `wontfix` — acknowledged, deliberately not fixing (with reason)
- `deferred` — moved to v1.1+ (with reason)

Fixed bugs are removed from this file once closed — the fix, the regression test, and any invariant it established live in the feature doc / spec / `CLAUDE.md`.

---

## Active

As of 2026-04-18: **zero open P0/P1/P2 bugs.** The R1 + R2 + P2 cutover (bug-043 – bug-060) closed the backlog; see `scratch/codex-reviews/SYNTHESIS.md` for the wave log and `docs/spec.md` § "Current focus" for the summary.

### P0 — blocks v1

_None._

### P1 — workaround exists or rarely hit

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| bug-019 | SwiftData `ModelContext.transaction` doesn't rollback on throw (iOS 17.x) | [persistence](features/persistence.md) | `wontfix (platform)` | Platform bug. Mitigated in app code via explicit do/catch/rollback pattern. Documented in `docs/architecture/hotspots.md`. Regression-tested by WorkoutCacheTests. |

### P2 — cosmetic / polish

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| bug-029 | Tab bar accessibility IDs missing | QA | `deferred (v1.1+)` | SwiftUI TabView doesn't propagate accessibilityIdentifier. Workaround: coordinate-tap. Real fix needs a custom tab bar or UIKit bridge — tracked in `docs/open-questions.md` § "Tab bar accessibility IDs missing (harder than expected)". |

---

## How to use this

- **Starting work on a bug:** move it to `in-progress`, put your name/agent ID next to it.
- **Adding a bug:** next ID (`bug-061` next; `bug-001`–`bug-060` already assigned, most closed), pick priority, link affected feature doc.
- **Fixing a bug:** close it in the same commit as the fix. Delete the row here; make sure the fix's invariant lives somewhere durable (`CLAUDE.md`, feature doc, or spec). Cite the regression test in the commit message, not here.
- **Demoting a feature's status:** file a bug here in the same commit that updates `docs/spec.md`.
- **Wontfix / deferred:** short rationale in Notes; link ADR or open-question if a design decision supports the call.

Cross-ref: `docs/spec.md` feature matrix reflects aggregated state; individual bugs here drive it down as they're found.
