# Catalog (Exercises, Muscles, Equipment)

## Exercises
Core exercise record plus structural taxonomy:
- `exercise` stores the canonical name and basic attributes (e.g., modality: strength/conditioning/skill/mobility).
- `exercise_family` groups close variants (e.g., bench press family).
- `exercise_muscle` links exercises to muscle groups with weighted roles.
- `movement_pattern` (push/pull/squat/hinge/carry/locomotion/core/other) supports splits.
- `exercise_alias` maps messy input to canonical names.

Why it matters:
- Enables “push/pull/legs” planning and movement balance.
- Allows substitutions by matching patterns + muscle profile.

## Muscles
- `muscle_group` supports a simple hierarchy (e.g., chest → upper chest).
- `muscle_alias` helps parse legacy text.

## Equipment
Equipment is modeled as capabilities and concrete models:
- `equipment_type` is the capability vocabulary.
- `equipment_model` is a specific implement (or a “virtual” placeholder).
- `equipment_model_type` maps models to multiple capabilities.
- `gym_inventory` says what a gym has.
- `gym_observed_equipment` is bootstrapped from usage.

Exercise setups (future-friendly, not required for MVP):
- `exercise_setup`, `setup_equipment_group`, `setup_equipment_option`
  describe feasible ways to perform the exercise.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
