# Intent (Taxonomy + Stimulus)

Intent captures *why* a workout/block/item exists so we can
search, swap, and bias toward a goal without guessing.

## Taxonomy
`intent_taxonomy` is a two-level hierarchy:
- Level 1: broad intent (e.g., strength, hypertrophy, conditioning, endurance)
- Level 2: specific method (e.g., pump, mechanical_tension, vo2max)

Fields:
- `intent_id`, `parent_intent_id`, `name`, `description`

## Usage
Intents are designed to label templates, blocks, and items via
`intent_primary_id` and `intent_secondary_id`.
We keep the taxonomy stable and use descriptions to standardize meaning.

CLI helpers:
- `workoutdb intent seed --db path/to.db` to load a minimal starter set.
- `workoutdb intent list --db path/to.db` to view available intents.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
