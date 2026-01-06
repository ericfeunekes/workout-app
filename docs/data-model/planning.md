# Planning (Goals + Scheduling)

## Goals
`user_goal` stores the high-level target and scheduling constraints:
- goal kind (strength/hypertrophy/conditioning/general)
- sessions per week
- minutes per session
- optional focus muscles

## Planned workouts
`planned_workout` maps templates to calendar dates:
- `date`, `start_time`, `duration_min` drive calendar export.
- `status` tracks planned/skipped/done.
- calendar linkage: `calendar_id`, `calendar_event_id`, `calendar_html_link`.
- `plan_id` links to a plan container.
- `meta_json` stores per-day metadata (e.g., week labels, deload flags).

## Plans
`plan` is a lightweight container for named plans:
- `name` and `meta_json` for plan-level notes and intent
- link to `planned_workout` rows via `plan_id`

YAML validation enforces unique plan day dates (one entry per date per plan).

Goals → templates is intentionally rule-based and lightweight for now.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
