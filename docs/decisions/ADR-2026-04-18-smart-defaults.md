---
title: Smart defaults — exercise-library defaults with server-resolved snapshot
status: accepted
date: 2026-04-18
covers:
  - server/workoutdb_server/models.py
  - server/workoutdb_server/api/*.py
  - server/db/migrations/
  - schema/Sources/WorkoutDBSchema/Entities.swift
  - docs/prescription.md
  - docs/specs/v2-architecture.md
---

# ADR: Smart defaults — exercise-library defaults with server-resolved snapshot

**Complements:** `ADR-2026-04-17-architecture.md`, `docs/prescription.md`.

## Context

Today's `prescription_json` carries *every* field every time. A 5-exercise session is ~150 lines of JSON and ~90% of it is identical day-to-day: `target_rir`, `autoreg.overshoot_step_kg`, `autoreg.undershoot_step_kg`, `rest_between_sets_sec`, per-exercise alternatives. Claude is going to be authoring hundreds of these; reviewing one is already tedious.

The invariants we can't compromise:

1. **Per-exercise granularity is real.** Bench wants ±2.5 kg step; curl wants ±1 kg; overhead press wants ±1.25. This varies by the exercise, not the session — the same exercise wants the same step size in every session it appears.
2. **History must stay stable.** A completed workout from March 5 must always render the same way it did on March 5 — if the exercise library changes later, old prescriptions shouldn't retroactively shift.
3. **The app stays offline-first.** Cache consumers must be able to execute a workout without any runtime merge dependency on server state.

## Options considered

**A. Exercise-library defaults + item overrides + server-resolved snapshot on ingest.** *(Chosen.)*
Extend `Exercise` with `default_prescription_json`. When Claude pushes a workout, items may omit any fields that match the library default. The server merges library + item at ingest and stores *both*: the raw (sparse) input and the resolved (complete) output. The app always reads the resolved form. History is stable because the resolved blob is immutable once stored.

**B. Workout-level defaults.** `workout.defaults_json` inherited by items. Still repetitive across workouts.

**C. User parameters keyed by movement pattern.** Fuzzy categorization; drift risk.

**D. Client-side defaults table.** Coupled to app release cadence; can't tune per-athlete.

## Decision

**Option A.** Smart defaults live on the `Exercise` entity. The server owns the merge + snapshot. The app reads only resolved prescriptions.

### Schema changes

- `exercise` table gains `default_prescription_json TEXT` (nullable). Same shape as `workout_item.prescription_json`; any subset of keys allowed.
- `workout_item` table gains `prescription_json_raw TEXT` (nullable, nullable means "same as prescription_json", used only when the author sent a sparse form). The existing `prescription_json` column is redefined as *always the resolved form*.
- No schema change to `block.timing_config_json` in this ADR — timing config is already block-scoped and small enough. Revisit if it grows.
- Alternatives: `Exercise` gains `default_alternatives_json` (JSON array matching `exercise_alternative` shape). Items can still override. Same merge rule.

### Merge semantics (server side, on POST /api/workouts and PUT /api/workouts/{id})

For each item in the incoming workout:

1. Fetch the item's `exercise_id` → read `exercise.default_prescription_json` (may be null).
2. Deep-merge: `resolved = library_default || {} merged with item.prescription_json`.
   - Scalar keys: item wins.
   - Nested `autoreg` block: merge field-by-field, item wins on conflict. Missing `autoreg` on item ⇒ library's `autoreg` used wholesale; null library + null item ⇒ no autoreg.
3. Store `workout_item.prescription_json` = resolved, `workout_item.prescription_json_raw` = what the client sent (or null if they were identical).
4. Same for alternatives: item's `alternatives` list replaces library default when present; if absent AND library default present, library default is copied into the item's stored alternatives.

**The merge happens once, at ingest.** After that, the workout row carries its own fully-resolved prescription and is immune to library mutations.

### Library mutations

- Updating `exercise.default_prescription_json` affects **future pushes only**. Existing workouts keep their snapshotted resolved blob.
- If Claude wants to rewrite an in-flight workout with new defaults, it pushes a `PUT /api/workouts/{id}` with the full tree — the server re-merges against the *current* library and re-stores.

### App impact

- `schema/Sources/WorkoutDBSchema/Entities.swift`: `Exercise` gains `defaultPrescriptionJson: String?`, `defaultAlternativesJson: String?`. `WorkoutItem` gains `prescriptionJsonRaw: String?` (optional — not strictly needed at runtime, but round-tripped for completeness).
- `CoreDomain.Exercise` mirrors.
- `CorePrescription.PrescriptionParser` reads `prescription_json` same as today — already resolved at read time. **No driver or autoreg logic changes.**
- `SyncAPI.pullLatest` returns the resolved form as it does today. Invisible to the app.

### Authoring ergonomics

A typical bench item drops from ~30 lines:

```json
{
  "sets": 4, "reps": 5, "load_kg": 102.5,
  "target_rir": 2,
  "autoreg": { "overshoot_at": 2, "overshoot_step_kg": 2.5, "undershoot_at": 2, "undershoot_step_kg": 2.5, "apply_to": "remaining" }
}
```

…to:

```json
{ "sets": 4, "reps": 5, "load_kg": 102.5 }
```

…assuming `Exercise.default_prescription_json` carries `{"target_rir": 2, "autoreg": {...}}`. Five-exercise workout drops from ~150 lines to ~30.

### What this doesn't solve

- **Workout-level overrides** (e.g., deload week where every exercise should use a smaller step). Not addressed — each item still has to override. If repetitive in practice, revisit with Option B as an additional layer.
- **Cross-exercise autoreg** (bench grinder → drop OHP). Still not built. Orthogonal.

## Migration plan

1. **Migration** `006_exercise_defaults.sql`: adds `default_prescription_json`, `default_alternatives_json` to `exercise`; adds `prescription_json_raw` to `workout_item`. All nullable — no backfill needed.
2. **Server models**: `Exercise`, `WorkoutItem` get the new optional columns.
3. **Pydantic schemas**: `ExerciseUpsert` + `ExerciseRead` gain optional fields. `WorkoutItemIn` stays the same (client still sends whatever it sends). `WorkoutItemRead` optionally surfaces `prescription_json_raw`.
4. **Merge helper**: new `workoutdb_server/sync/prescription_merge.py` with deep-merge logic, unit-tested against fixtures in `schema/fixtures/prescription_merge_*.json`.
5. **Server `POST /api/workouts` + `PUT`**: run the merge helper per item before insert. Idempotent — re-pushing the same workout re-merges against current library.
6. **Schema package**: `Entities.swift` updated; contract tests in `tests/contract/test_swift_schema_parity.py` updated.
7. **iOS DomainMapping**: maps the new optional Exercise fields — they're ignored at runtime (app reads resolved prescription only).
8. **Documentation**:
   - `docs/prescription.md` gains a top section "Authoring shape: sparse overrides on library defaults" explaining the merge.
   - `docs/specs/v2-architecture.md` data-model table updated to note the new columns.
   - `docs/bugs.md` entry `bug-014` (smart defaults) closes.

Single cutover — no feature flag. Claude's existing full-shape authored workouts continue to parse (they already carry every field; the merge is a no-op).

## Verification

- Contract tests: Swift schema ↔ Python schema parity for the new fields.
- Unit tests for the merge helper: library-only / item-only / both / nested autoreg / alternatives.
- Round-trip tests: POST a sparse workout → GET → resolved form has library defaults merged in.
- History stability test: POST a workout with sparse prescription; update library defaults; GET the original workout; resolved form unchanged.

## Status

Accepted 2026-04-18. Implementation tracked under `bug-014` in `docs/bugs.md`; begins after the timing-mode driver build slice clears (higher priority since no timing modes except straight_sets currently run).
