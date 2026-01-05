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

## Core idea: store raw first, parse second
Many workouts are messy. You want zero data loss.

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
- Manually create templates and reference plans
- Tag templates with program/phase/week for grouping
- Keep raw text when available (manual paste is fine)

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
