---
title: Design bundle — origin and refresh
status: reference
purpose: Records where this bundle came from and how to refresh it. Does not mutate the bundle's own docs.
covers: docs/design/**
---

# Origin

This directory is a handoff bundle from **Claude Design** (claude.ai/design), received **2026-04-17**. The `HANDOFF.md`, `README.md`, `BACKLOG.md`, `RULES.md`, `FLOWS.html`, HTML prototypes, `src/`, `components/`, and `styles/` are all authored by the design tool and should be treated as canonical reference.

**Start reading at `HANDOFF.md`** (per the bundle's own README).

## Refresh handle

**Status as of 2026-04-18:** the original handle has returned `404 not found` on GET. Either the Claude Design side treats export links as single-use / short-lived, or the handle was invalidated. The local snapshot is now authoritative.

- Original handle (dead): `https://api.anthropic.com/v1/design/h/-J5jAVdjJnIkBgdxlhe7rA`
- Original local archive: `scratch/design-handoff-2026-04-17.zip` (gitignored)

If the design evolves again, Eric re-exports from claude.ai/design and drops a new zip in place of the 2026-04-17 one. Replace the contents of `docs/design/` (keeping this `ORIGIN.md` in place), and rerun any cross-spec reconciliation notes we produce from it.

## Status in this repo

This bundle is **reference, not specification**. Governance between sources:

- **Design rules UX, copy, interaction, visual language.** When you need to know what a screen looks like, what the user sees, or how an interaction feels — the design bundle is canonical.
- **Spec (`docs/specs/v2-architecture.md`) rules schema, API, and sync.** When you need to know what's on the wire or in the database — the spec is canonical.
- **Conflicts are resolved via ADR**, not by silent drift. The current reconciliation is recorded in `docs/decisions/ADR-2026-04-17-rir-autoreg-sync.md`.

Open reconciliation items land in `docs/decisions/` (ADRs), in `docs/open-questions.md` (the living gap register), or as targeted edits to the spec / app README — never as drift.

Do not implement from the bundle yet — we are still reading and discussing.

## Subdirectories the bundle ships with

- `src/`, `components/`, `styles/` — prototype source (JSX + CSS). Primary design reference.
- `_archive/` — superseded v1 wireframes; the bundle says "ignore unless archaeology."
- `scraps/`, `scratch/`, `uploads/` — dev-session artifacts (screenshots, sketches). Kept as received; trim if we ever want to.
