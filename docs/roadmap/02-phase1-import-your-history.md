# Phase 1 — Reference Ingestion + Parsing (library bootstrapping)

## Objective
Populate a workout library from your old plans and notes so you have examples to:
- browse
- reuse
- generate weekly plans from

Also ingest “reference plans” that are not tied to an athlete.

## Preflight (before schema changes or import tooling)
- Run the extracted JSON analysis to understand real field shapes
- Use findings to finalize the minimal schema and parser expectations
 - Defer bulk import of extracted JSON until the MVP loop is stable

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

## Import formats (MVP)
- Folder import:
  - `.md` and `.txt` (one workout per file)
- CSV import:
  - columns: `date,title,text,tags` (minimum)
- “paste mode”:
  - CLI reads stdin or opens an editor

## Parsing (MVP)
Goal: create templates when obvious; otherwise keep raw only.

### Parsing outputs
- Create `workout_template`, `workout_block`, `workout_item` when parse confidence is high.
- Otherwise:
  - keep `raw_workout.parse_status = needs_review`
  - do NOT discard the workout

Reference plans:
- If a file represents a multi-week plan, store as:
  - a set of templates
  - tags that group them into a “plan pack”

### Minimum workout structures to support
- Straight sets (e.g., 5x5)
- Superset markers (A1/A2)
- AMRAP + duration
- EMOM + duration
- For time + time cap
- Intervals (run/bike/row repeats)

## Acceptance criteria
- Import 50+ workouts in < 2 minutes
- At least:
  - 70% stored successfully as raw
  - 30% parsed into structured templates (your real number will vary; the key is *no data loss*)
- Reference plans can be tagged and reused as plan inputs

## Nice-to-have (optional, still MVP-safe)
- “review queue” CLI:
  - `review-raw --status needs_review`
  - shows raw text and lets you link to an existing template or edit the parsed JSON
