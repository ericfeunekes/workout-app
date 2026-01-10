# MVP Definition (what "done" means)

## MVP user stories
1) As a user, I can create a local SQLite DB and evolve it with migrations.
2) As a user, I can seed a reference library manually (templates + tags) without a bulk importer.
3) As a user, I can schedule workouts for myself and my partner (planned calendar in DB), or keep a plan unassigned as a reference.
4) As a user, I can generate or instantiate a 28-day plan for a partner based on:
   - her goal (e.g., strength, hypertrophy, conditioning)
   - her available days
   - constraints (time cap, equipment constraints if known)
5) As a user, I can author and adjust plans via YAML.
6) As a user, I can export a printable PDF plan and re-enter results in a structured, manual-first way.
7) As a user, I can export my library and schedule as JSON (and optionally `.ics`).

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
  - [ ] `list-library` (filter by tags)
  - [ ] `plan generate` (create or instantiate a 28-day plan)
  - [ ] `plan import-yaml` (primary authoring path)
  - [ ] `plan validate-yaml`
  - [ ] `export-pdf` (printable plan + workout sheets)
  - [ ] `import-logs` (file-based structured re-entry; manual-first)
  - [ ] `export` (library + schedule)
- [ ] Simple plan instantiation and/or basic rule-based generator (not ML)
- [ ] Minimal tests:
  - [ ] migrations apply cleanly from scratch

## Definition of done (MVP end-state)
This is the “ready to design cloud + iOS” threshold.

Core loop
- You can run:
  1) init DB
  2) seed a reference library (manual-first; loader can come later)
  3) define reference plans (not tied to an athlete)
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

PDF + data-entry-friendly logging
- PDF output uses a consistent, data-entry-friendly layout for athlete inputs
- Input format is structured for reliable manual re-entry

Adaptive weekly adjustments (manual-first)
- After importing logs, you can manually update the next week’s plan
- Rules/tools exist to surface what changed (load, volume, adherence), but final decisions are manual

## MVP checklist (implementation order)
1) Phase 0 foundation (schema + migrations + CLI scaffolding)
2) Phase 1 reference library (manual-first)
3) Phase 3 planning + scheduling (28-day + YAML authoring)
4) Phase 4 output + feedback loop (PDF + scan-friendly re-entry)
5) Manual weekly adjustment workflow (surface changes, apply edits)
