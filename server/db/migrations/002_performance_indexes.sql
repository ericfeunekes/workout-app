-- 002_performance_indexes.sql — indexes needed by the sync/pull last_performed query
-- and any other query that looks up recent completed workouts or exercise history.
--
-- Safe to run against an already-populated DB; CREATE INDEX IF NOT EXISTS is idempotent.

CREATE INDEX IF NOT EXISTS idx_workout_user_completed ON workout(user_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_workout_item_exercise ON workout_item(exercise_id);
