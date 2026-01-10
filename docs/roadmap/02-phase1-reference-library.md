# Phase 1 — Reference Library (manual-first)

## Objective
Create a minimal, high-quality reference library that you can:
- browse
- reuse
- generate weekly plans from

Also define “reference plans” that are not tied to an athlete.

## Scope clarification
- Bulk import/parsing is **out of scope** for this phase
- We will build the app flow first; a separate loader will handle the specific extracted JSON later

## Core idea: YAML-first authoring
Use a single YAML file to define templates (and optional plans).
Validation should be strict with clear errors.

### Add these tables (if not already)
**Workout sources (provenance)**
- `workout_source`:
  - id
  - kind: `manual`, `file_import`, `link`, `third_party`
  - title
  - author
  - original_url
  - imported_at
  - license_note (free text)

**Raw workouts (canonical archive)**
- `raw_workout`:
  - id
  - source_id
  - external_ref (e.g., filename, URL slug)
  - workout_date (optional)
  - raw_text (the original)
  - raw_format: `markdown`, `plain`, `csv_row`, etc.
  - parse_status: `new`, `parsed`, `failed`, `needs_review`
  - parsed_json (optional; intermediate representation)
  - linked_template_id (nullable FK)

**Reference plans (plan libraries not tied to a user)**
Store these as templates + plan metadata (see Phase 3 for scheduling usage).
Use tags/labels to indicate goal, cycle length, and audience.

## Minimum capabilities (MVP)
- Author templates + tags in YAML
- Validate YAML with clear errors
- Import YAML into the DB (manual-first reference library)
- Plans can be included and scheduled directly (manual-first)

CLI:
- `plan validate-yaml`
- `plan import-yaml`

## Example YAML (minimal)
```yaml
version: 1
users:
  - name: "User"

templates:
  - name: "Upper A"
    tags: ["program:stc", "phase:1", "week:4"]
    blocks:
      - name: "A"
        block_type: "strength"
        structure_type: "straight_sets"
        intent:
          time_cap_sec: 900
        items:
          - exercise: "Split squat"
            prescription:
              sets: 4
              reps_target: 8
              reps_is_per_side: true
          - exercise: "DB clean & alt press"
            prescription:
              sets: 4
              reps_target: 8

plans:
  - name: "Week 1"
    user: "User"
    days:
      - date: 2026-01-06
        template: "Upper A"
      - date: 2026-01-07
        rest: true
```

### Minimum workout structures to support
- Straight sets (e.g., 5x5)
- Superset markers (A1/A2)
- AMRAP + duration
- EMOM + duration
- For time + time cap
- Intervals (run/bike/row repeats)

## Acceptance criteria
- You can build a small, high-quality reference library manually
- Reference plans can be tagged and reused as plan inputs
- No bulk import required in this phase

## Deferred (separate loader)
- Extracted JSON parsing and bulk import
- Automated parsing heuristics
