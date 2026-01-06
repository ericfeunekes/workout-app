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

Goals → templates is intentionally rule-based and lightweight for now.

Deep reference: `docs/roadmap/appendix-a-data-model.md`.
