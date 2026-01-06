# Library (Raw → Templates)

## Raw ingestion
Every import is stored verbatim so we can re-parse later:
- `workout_source` describes origin and licensing.
- `raw_workout` stores the original text + parse status.

## Templates
Templates are the structured, reusable workouts:
- `workout_template` is the workout container.
- `workout_block` captures block-level structure and stimulus intent.
- `workout_item` captures exercise prescriptions.
- `workout_item_set_prescription` handles per-set variation.
 - intent IDs on templates/blocks/items link into `intent_taxonomy`.

Tags support discovery across the library:
- `tag` + `entity_tag` link templates/exercises to searchable labels.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
