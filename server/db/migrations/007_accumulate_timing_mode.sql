-- 007_accumulate_timing_mode.sql — add `accumulate` to block.timing_mode.
--
-- SQLite cannot alter a CHECK constraint in place, so rebuild `block` with
-- the expanded timing-mode list and copy rows across unchanged.

PRAGMA foreign_keys = OFF;

CREATE TABLE block_new (
    id TEXT PRIMARY KEY,
    workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
    parent_block_id TEXT REFERENCES block_new(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    name TEXT,
    timing_mode TEXT NOT NULL CHECK (timing_mode IN (
        'straight_sets', 'superset', 'circuit', 'emom', 'amrap',
        'for_time', 'intervals', 'tabata', 'continuous', 'accumulate', 'custom', 'rest'
    )),
    timing_config_json TEXT NOT NULL,
    rounds INTEGER,
    rounds_rep_scheme_json TEXT,
    notes TEXT
);

INSERT INTO block_new (
    id,
    workout_id,
    parent_block_id,
    position,
    name,
    timing_mode,
    timing_config_json,
    rounds,
    rounds_rep_scheme_json,
    notes
)
SELECT
    id,
    workout_id,
    parent_block_id,
    position,
    name,
    timing_mode,
    timing_config_json,
    rounds,
    rounds_rep_scheme_json,
    notes
FROM block;

DROP TABLE block;
ALTER TABLE block_new RENAME TO block;

CREATE INDEX IF NOT EXISTS idx_block_workout ON block(workout_id);
CREATE INDEX IF NOT EXISTS idx_block_parent ON block(parent_block_id);

PRAGMA foreign_keys = ON;
