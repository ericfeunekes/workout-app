# Phase 3 — Plan Generation + Scheduling (28-day, reference-aware)

## Objective
Turn your library into a 28-day schedule for each person using reference plans and templates.

## Minimal tables to add
### User profile / goals (simple)
- `user_goal`:
  - user_id
  - goal_kind: `strength`, `hypertrophy`, `conditioning`, `general`
  - focus_muscles (json array of muscle names or ids)
  - sessions_per_week
  - minutes_per_session
  - notes

### Planned schedule
- `planned_workout`:
  - planned_id
  - user_id
  - date (YYYY-MM-DD)
  - template_id (nullable: sometimes you schedule “rest”)
  - status: `planned`, `skipped`, `done`
  - notes
  - generated_by: `manual`, `generator_v1`

## Generator v1 (rule-based, small but useful)
Inputs:
- user_goal
- date range (next 28 days)
- optionally: available equipment types (if known) else ignore
- optional: reference plan packs (preferred)

Rules (example set)
- Strength (3 days/wk):
  - 2 days: full-body strength template (squat/hinge + push + pull)
  - 1 day: conditioning + accessories
- Hypertrophy (4 days/wk):
  - upper/lower split + 1 conditioning day
- Conditioning:
  - 2 easy aerobic sessions + 1 harder interval day + 1 mixed day

Constraints:
- avoid repeating the same movement pattern on consecutive days
- keep estimated duration <= minutes_per_session
- prefer templates with matching tags/stimulus goal when available

Output:
- Fill `planned_workout` rows
- Print a human-readable summary to the console
- If reference plans are provided, prefer them over freeform selection

## Scheduling UX (CLI)
- `plan set-goal --user wife --goal hypertrophy --sessions-per-week 4 --minutes-per-session 45`
- `plan generate --user wife --weeks 4 --out plan.json`
- `plan generate --user wife --reference-plan "hypertrophy-4wk-v1" --out plan.json`
- `plan propose plan.json`
- `plan approve --batch-id plan-xxxx`
- `plan apply --batch-id plan-xxxx`
- `plan show --user wife --from 2026-01-06 --to 2026-02-02` (defaults to next 7 days)
- `plan import-yaml path/to/plan.yaml`

## Plan-as-file (primary UX)
Use YAML as the canonical authoring surface for plans.
It is easier to edit than CLI flags and supports cloning + manual adjustments.

Acceptance criteria
- In under 1 minute, you can produce a 28-day plan for your wife that:
  - has the correct number of sessions
  - respects max session duration
  - alternates patterns sensibly
