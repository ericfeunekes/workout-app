# MVP Definition (what "done" means)

## MVP user stories
1) As Eric, I can create a local SQLite DB and evolve it with migrations.
2) As Eric, I can import my historical workouts into a structured library:
   - preserve original text
   - parse into template blocks/items when possible
   - mark "parse failed" but keep the workout anyway
3) As Eric, I can schedule workouts for myself and my wife (planned calendar in DB).
4) As Eric, I can generate a 1–2 week plan for my wife based on:
   - her goal (e.g., strength, hypertrophy, conditioning)
   - her available days
   - constraints (time cap, equipment constraints if known)
5) As Eric, I can export:
   - my library as JSON
   - my schedule as JSON (and optionally `.ics` calendar file)

## Non-goals for MVP
- No iOS UI
- No real-time “is machine busy”
- No automatic “research-backed best plan” logic
- No multi-user auth/security
- No social features

## MVP deliverables (checklist)
- [ ] `db/schema.sql` + `db/migrations/` with a migration runner
- [ ] CLI:
  - [ ] `init-db`
  - [ ] `import-workouts` (folder of .md/.txt/.csv)
  - [ ] `list-library` (filter by tags)
  - [ ] `schedule` (assign template to a date/user)
  - [ ] `generate-plan` (create a week plan)
  - [ ] `export` (library + schedule)
- [ ] Parsing pipeline:
  - [ ] Store raw workout text + source metadata
  - [ ] Parse into structured blocks/items when possible
  - [ ] Validation + error reporting
- [ ] Basic rule-based generator (not ML)
- [ ] Minimal tests:
  - [ ] migrations apply cleanly from scratch
  - [ ] parsing contract tests for common formats (AMRAP, EMOM, intervals, straight sets)

## Definition of done (MVP end-state)
This is the “ready to design cloud + iOS” threshold.

Core loop
- You can run:
  1) init DB
  2) import 50+ past workouts (raw preserved)
  3) import reference plans (not tied to an athlete)
  4) generate a 28-day plan
  5) import/edit plans via YAML file
  6) export plan to a printable PDF
  7) export canonical JSON (templates + planned workouts + sessions)
…without opening a notebook or manually editing the database.

Reference library
- Support “reference plans” that are not attached to a user
- Past workouts/plans can be tagged and reused as references

Workout-building UX (CLI first, UI later)
- Build workouts by goal + muscle group focus
- Helpers can suggest common pairings based on history (decision support, not automation)
- Plan authoring uses YAML as the primary manual interface

PDF + scan-friendly logging
- PDF output uses a consistent, scan-friendly layout for athlete inputs
- Input format is structured so it can be re-imported with high confidence

Adaptive weekly adjustments (manual-first)
- After importing logs, you can manually update the next week’s plan
- Rules/tools exist to surface what changed (load, volume, adherence), but final decisions are manual

## MVP checklist (implementation order)
1) Phase 0 foundation (schema + migrations + CLI scaffolding)
2) Phase 1 ingestion + parsing (raw import + reference plans)
3) Phase 3 planning + scheduling (28-day + YAML authoring)
4) Phase 4 output + feedback loop (PDF + scan-friendly re-entry)
5) Manual weekly adjustment workflow (surface changes, apply edits)
