-- 004_rir_cutover.sql — replace set_log.rpe with set_log.rir and add performed_exercise_id.
--
-- See docs/decisions/ADR-2026-04-17-rir-autoreg-sync.md.
--
-- Changes:
--   1. Drop rpe (float, 6–10 scale). Pre-v1 system has no production data to preserve.
--   2. Add rir INTEGER with CHECK (0..5). Nullable — user may skip the RIR picker.
--   3. Add performed_exercise_id TEXT NULL (FK exercise.id) so session-local swaps are
--      recorded on the log row without mutating the workout_item template.
--
-- SQLite supports DROP COLUMN in 3.35+ (Feb 2021) which covers our runtime. ALTER TABLE
-- steps run sequentially; idempotence is preserved by the migration runner's version check.

ALTER TABLE set_log DROP COLUMN rpe;

ALTER TABLE set_log ADD COLUMN rir INTEGER
    CHECK (rir IS NULL OR (rir >= 0 AND rir <= 5));

ALTER TABLE set_log ADD COLUMN performed_exercise_id TEXT
    REFERENCES exercise(id);

CREATE INDEX IF NOT EXISTS idx_set_log_performed_exercise
    ON set_log(performed_exercise_id)
    WHERE performed_exercise_id IS NOT NULL;
