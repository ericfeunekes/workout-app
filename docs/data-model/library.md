# Library (Raw → Templates)

## Raw ingestion
Every import is stored verbatim so we can re-parse later:
- `workout_source` describes origin and licensing.
- `raw_workout` stores the original text + parse status.

Practical convention (recommended):
- Use **one** `workout_source` row per logical corpus (e.g., "STC workouts 2025"),
  even if it spans multiple files (PDFs/pages).
- Treat `raw_workout.external_ref` as a stable, human-readable key **unique within a source**,
  e.g. `stc-workouts-2025/page-001#day-1`.

## Templates
Templates are the structured, reusable workouts:
- `workout_template` is the workout container.
- `workout_block` captures block-level structure and stimulus intent.
- `workout_item` captures exercise prescriptions.
- `workout_item_set_prescription` handles per-set variation.
 - intent IDs on templates/blocks/items link into `intent_taxonomy`.

Tags support discovery across the library:
- `tag` + `entity_tag` link templates/exercises to searchable labels.

YAML validation enforces unique names for users, intents, and templates.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
