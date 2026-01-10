# Intent Taxonomy (source of truth)

This document is the canonical, human-maintained list of intent labels used by:
- `workout_block.intent_primary_id`
- `workout_block.intent_secondary_id`
- (optionally) template/item intents as we extend the model

We will evolve and deduplicate this taxonomy over time. Prefer reusing existing
labels before adding new ones.

## How to update

1) Search for an existing intent that fits.
2) If none fits, add a new intent under the closest parent.
3) Keep names short, consistent, and readable in UI.

## Naming conventions

- Use lowercase words with spaces (e.g., `intervals`, `strength base`).
- Avoid synonyms unless they encode distinct meaning.
- Prefer 1–2 words.

## Current taxonomy

### Primary intents

- conditioning
- strength
- accessory
- mobility
- skill
- warmup

### Secondary intents (by parent)

#### conditioning
- intervals
- for time
- aerobic base
- mixed modal

#### strength
- max strength
- hypertrophy
- power

#### accessory
- core
- unilateral
- prehab

#### mobility
- joint prep
- cooldown

#### skill
- technique

#### warmup
- general
- specific
