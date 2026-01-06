# Execution (Sessions + Logging)

## Sessions
`workout_session` captures what actually happened:
- links to a user, gym, and optional template
- start/end times, notes, summary

## Performed blocks/items
`session_block` and `session_item` track the performed structure
and keep a link back to the template where possible.

## Set logs
`set_log` is the core of the logging system:
- tracks reps, weight, duration, distance, calories, RPE
- captures warmup vs. work sets
- supports both strength and conditioning/interval logging in one table

## Equipment usage
`session_item_equipment_choice` records the implement used and
can bootstrap `gym_observed_equipment`.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
