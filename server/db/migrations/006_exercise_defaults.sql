-- 006_exercise_defaults.sql — smart defaults: exercise-library defaults with
-- server-resolved snapshot on workout ingest.
--
-- See docs/decisions/ADR-2026-04-18-smart-defaults.md.
--
-- Changes:
--   1. exercise.default_prescription_json TEXT NULL — library-level prescription
--      fields (e.g. target_rir, autoreg) that apply to every workout_item
--      referencing this exercise unless the item overrides them.
--   2. exercise.default_alternatives_json TEXT NULL — library-level alternatives
--      (JSON array matching the exercise_alternative shape minus the workout-
--      item pointer). Items that omit alternatives fall back to this list.
--   3. workout_item.prescription_json_raw TEXT NULL — the exact sparse JSON the
--      client sent, preserved for debugging / re-merge. Null when the resolved
--      form equals what the client sent (no merge happened).
--
-- All columns are nullable with no default — no backfill needed. Existing
-- rows continue to carry fully-resolved prescriptions; the merge is a no-op
-- when library defaults are absent.

ALTER TABLE exercise ADD COLUMN default_prescription_json TEXT;

ALTER TABLE exercise ADD COLUMN default_alternatives_json TEXT;

ALTER TABLE workout_item ADD COLUMN prescription_json_raw TEXT;
