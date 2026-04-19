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

As of 2026-04-19 (post-QA campaign): **zero open P0/P1 bugs** after 32 fixes across 6 fix-it rounds driven by a 14-scenario Codex QA campaign. See `scratch/qa-runs/_campaign-tracker.md` for the run log and `scratch/qa-runs/BUGS.md` for the full campaign bug report (all closed rows retained there for evidence; not migrated here per "closed bugs live in git" convention).

### P0 — blocks v1

_None._

### P1 — workaround exists or rarely hit

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| bug-019 | SwiftData `ModelContext.transaction` doesn't rollback on throw (iOS 17.x) | [persistence](features/persistence.md) | `wontfix (platform)` | Platform bug. Mitigated in app code via explicit do/catch/rollback pattern. Documented in `docs/architecture/hotspots.md`. Regression-tested by WorkoutCacheTests. |

### P2 — cosmetic / polish / feature-gap

| ID | Title | Affected feature | Status | Notes |
|---|---|---|---|---|
| bug-029 | Tab bar accessibility IDs missing | QA | `deferred (v1.1+)` | SwiftUI TabView doesn't propagate accessibilityIdentifier. Workaround: coordinate-tap. Real fix needs a custom tab bar or UIKit bridge — tracked in `docs/open-questions.md` § "Tab bar accessibility IDs missing (harder than expected)". |
| bug-061 | Cluster sets (`sub_sets` / `intra_set_rest_sec`) render as plain sets at execution | [execute-loop](features/execute-loop.md) | `deferred (v1.1+)` | Prescription shape parses. Today card renders "4 × (3 × 5) @ 20 kg" correctly. Active screen ignores the cluster structure and treats it as a plain straight-set block. Feature-gap, not regression. Driver-side wiring deferred. From qa-042. |
| bug-062 | Visual distortion on scenePhase resume during live block timer | [timing-modes](features/timing-modes.md) | `watchlist` | EMOM / Tabata / time-capped blocks backgrounded mid-interval may show a brief distorted floating-window frame on return before snapping back to fullscreen. Not testable via swift test — needs SwiftUI scene-phase harness. From qa-046. |
| bug-063 | Numeric-input flash / transient value on keypad entry | [execute-loop](features/execute-loop.md) | `watchlist` | img-ask observed "100" → "10" transient on reps entry, and double-number overlays during log-sheet transitions. Could be NumPadSheet buffer rendering during input. Not reproducible from QA flow alone; needs a dedicated input-timing test. From qa-011. |
| bug-064 | UI transition flickers on log → rest and advance paths | [execute-loop](features/execute-loop.md) | `watchlist` | Minor flicker between state transitions observed via img-ask across multiple QA runs. From qa-009, qa-012, qa-013. Visually noticeable but not data-affecting. Defer unless user reports. |
| bug-065 | CompleteView capture/note section spacing too tight | [save-and-done](features/save-and-done.md) | `watchlist` | Field titles nearly touch their placeholder text. Cosmetic. From qa-031. |
| bug-066 | Rest-pill RIR `--` placeholder off-center | [execute-loop](features/execute-loop.md) | `watchlist` | Dashes vertically misaligned vs numeric values in sibling pills. Cosmetic. From qa-032. |
| bug-067 | Rest-banner secondary text too close to bottom border | [autoreg](features/autoreg.md) | `watchlist` | Reason text padding asymmetric. Cosmetic. From qa-033. |

**ID allocation:** bug-061 onwards reserved for post-QA-campaign findings. bug-001–060 remain closed in git history. `qa-001`–`qa-047` are the campaign's internal tracking ids; the ones that survived as open bugs are migrated here with bug-NNN numbers. The full campaign BUGS.md is preserved at `scratch/qa-runs/BUGS.md` for evidence.

---

## How to use this

- **Starting work on a bug:** move it to `in-progress`, put your name/agent ID next to it.
- **Adding a bug:** next ID (`bug-061` next; `bug-001`–`bug-060` already assigned, most closed), pick priority, link affected feature doc.
- **Fixing a bug:** close it in the same commit as the fix. Delete the row here; make sure the fix's invariant lives somewhere durable (`CLAUDE.md`, feature doc, or spec). Cite the regression test in the commit message, not here.
- **Demoting a feature's status:** file a bug here in the same commit that updates `docs/spec.md`.
- **Wontfix / deferred:** short rationale in Notes; link ADR or open-question if a design decision supports the call.

Cross-ref: `docs/spec.md` feature matrix reflects aggregated state; individual bugs here drive it down as they're found.
