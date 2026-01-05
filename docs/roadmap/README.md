# Workout System Roadmap (SQLite → iOS 1.0)

This repo starts as a **data product** with a thin CLI. The iOS app (v1.0) is the *client* that arrives later.

## Guiding principles
- **Log first, enrich later**: workouts and results must be recordable even if exercises/equipment/setups are incomplete.
- **Structure ≠ UI**: keep a stable data model; let UI evolve.
- **Provenance matters**: every imported workout should keep its source metadata and (optionally) original text snapshot.
- **Avoid schema churn**: store evolving interpretations (stimulus, metrics, tags) in generic “attachment” tables.
- **Minimal viable increments**: each phase must ship something usable (even if only via CLI).

## Repo outcomes
### MVP (local-only)
- SQLite DB with migrations
- Store “planned workouts” on a schedule for you + your wife
- Generate 28-day plan from your library (manual-first; optional rules)
- Seed a reference library manually (bulk import deferred)
- Optional: equipment capture is **not required** to log workouts

### v1.0 (iOS)
- iOS app that can browse library, follow a workout, log results, capture quick check-ins
- Sync to a backend (or Apple-native storage/cloud) decided later

## Directory layout (recommended)
- `docs/roadmap/` – this roadmap
- `docs/specs/` – stable specs (data model, workout JSON shapes, question packs)
- `db/` – schema + migrations
- `workoutdb/` – python package (db access, parsers, generators)
- `scripts/` – one-off utilities (imports, exports)
- `tests/` – contract tests for parsing + migrations

## Epic structure (split by outcome)
### Epic 1: MVP (local-first data product + CLI)
Goal: prove the full data loop and lock the core model so we can build APIs later.

Includes (updated phases):
- Phase 0: Repo + DB foundation
- Phase 1: Reference library (manual-first)
- Phase 2: External sources ingestion (license-safe, optional)
- Phase 3: Plan generation + scheduling (28-day, reference-aware)
- Phase 4: Output + feedback loop (PDF + scan-friendly logging + manual adjustments)

### Epic 2: iOS 1.0 (client app + sync)
Goal: define cloud/backend + app phases once Epic 1 end-state is stable.

Includes (to be detailed later):
- iOS 1.0 app + sync architecture

See: `docs/roadmap/07-epic2-ios-and-cloud.md`
See also: `docs/roadmap/enhancements.md`

Start here: `docs/roadmap/00-mvp-definition.md`
