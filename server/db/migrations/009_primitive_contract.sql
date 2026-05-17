-- Primitive cutover checkpoint: authored primitive workout JSON plus
-- app-owned primitive result rows. Idempotent for local replays.

ALTER TABLE workout ADD COLUMN primitive_blocks_json TEXT NOT NULL DEFAULT '[]';

CREATE TABLE IF NOT EXISTS primitive_set_log (
    id TEXT PRIMARY KEY,
    role TEXT NOT NULL CHECK (role IN ('slot', 'set_result', 'block_result')),
    slot_id TEXT,
    set_id TEXT,
    block_id TEXT,
    workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
    planned_exercise_id TEXT REFERENCES exercise(id),
    performed_exercise_id TEXT REFERENCES exercise(id),
    set_index INTEGER NOT NULL,
    set_repeat_index INTEGER NOT NULL DEFAULT 0,
    block_repeat_index INTEGER NOT NULL DEFAULT 0,
    reps INTEGER,
    weight REAL,
    weight_unit TEXT CHECK (weight_unit IN ('kg', 'lb') OR weight_unit IS NULL),
    duration_sec REAL,
    rounds INTEGER,
    rir INTEGER CHECK (rir IS NULL OR (rir >= 0 AND rir <= 5)),
    is_warmup INTEGER NOT NULL DEFAULT 0,
    completed_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_primitive_set_log_workout
    ON primitive_set_log(workout_id);
CREATE INDEX IF NOT EXISTS idx_primitive_set_log_set
    ON primitive_set_log(set_id);
CREATE INDEX IF NOT EXISTS idx_primitive_set_log_slot
    ON primitive_set_log(slot_id);
