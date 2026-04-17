-- 003_workout_updated_at.sql — add updated_at to workout so sync/pull detects edits.
-- Spec: "updated_at on every record. Last-write-wins within each flow direction."
-- Without this, PUT /api/workouts/:id changes are invisible to an app pulling by timestamp.
--
-- SQLite limitation: ALTER TABLE ADD COLUMN cannot be made conditional, and NOT NULL
-- requires a constant default. Strategy: add with an epoch placeholder, then backfill
-- from created_at so existing rows have sensible values.

ALTER TABLE workout ADD COLUMN updated_at TEXT NOT NULL DEFAULT '1970-01-01T00:00:00';
UPDATE workout SET updated_at = created_at;

CREATE INDEX IF NOT EXISTS idx_workout_user_updated ON workout(user_id, updated_at);
