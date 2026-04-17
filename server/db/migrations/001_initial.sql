-- 001_initial.sql — full v2 schema.
-- All entities per docs/specs/v2-architecture.md with accepted extensions applied.
-- UUIDs stored as TEXT. JSON blobs stored as TEXT. Timestamps stored as TEXT (ISO-8601).
-- Foreign keys enabled at connection time (see workoutdb_server.db).

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS app_user (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- Claude owns exercise IDs; no UNIQUE on name. Server never canonicalizes.
CREATE TABLE IF NOT EXISTS exercise (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    notes TEXT,
    demo_url TEXT
);

CREATE TABLE IF NOT EXISTS workout (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    scheduled_date TEXT,
    status TEXT NOT NULL CHECK (status IN ('planned', 'active', 'completed', 'skipped')),
    source TEXT NOT NULL CHECK (source IN ('claude', 'manual')),
    notes TEXT,
    tags_json TEXT,
    created_at TEXT NOT NULL,
    completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_workout_user_scheduled ON workout(user_id, scheduled_date);
CREATE INDEX IF NOT EXISTS idx_workout_user_status ON workout(user_id, status);

CREATE TABLE IF NOT EXISTS block (
    id TEXT PRIMARY KEY,
    workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
    parent_block_id TEXT REFERENCES block(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    name TEXT,
    timing_mode TEXT NOT NULL CHECK (timing_mode IN (
        'straight_sets', 'superset', 'circuit', 'emom', 'amrap',
        'for_time', 'intervals', 'tabata', 'continuous', 'custom', 'rest'
    )),
    timing_config_json TEXT NOT NULL,
    rounds INTEGER,
    rounds_rep_scheme_json TEXT,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_block_workout ON block(workout_id);
CREATE INDEX IF NOT EXISTS idx_block_parent ON block(parent_block_id);

CREATE TABLE IF NOT EXISTS workout_item (
    id TEXT PRIMARY KEY,
    block_id TEXT NOT NULL REFERENCES block(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    exercise_id TEXT NOT NULL REFERENCES exercise(id),
    prescription_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_workout_item_block ON workout_item(block_id);

CREATE TABLE IF NOT EXISTS exercise_alternative (
    id TEXT PRIMARY KEY,
    workout_item_id TEXT NOT NULL REFERENCES workout_item(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL REFERENCES exercise(id),
    reason TEXT NOT NULL,
    parameter_overrides_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_exercise_alt_item ON exercise_alternative(workout_item_id);

CREATE TABLE IF NOT EXISTS set_log (
    id TEXT PRIMARY KEY,
    workout_item_id TEXT NOT NULL REFERENCES workout_item(id) ON DELETE CASCADE,
    set_index INTEGER NOT NULL,
    reps INTEGER,
    weight REAL,
    weight_unit TEXT CHECK (weight_unit IN ('kg', 'lb')),
    duration_sec REAL,
    distance_m REAL,
    rpe REAL,
    is_warmup INTEGER NOT NULL DEFAULT 0 CHECK (is_warmup IN (0, 1)),
    started_at TEXT,
    completed_at TEXT NOT NULL,
    hr_avg_bpm INTEGER,
    hr_max_bpm INTEGER,
    cadence_avg_spm INTEGER,
    motion_samples_ref TEXT,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_set_log_item ON set_log(workout_item_id);

-- Append-only log. Multiple rows per (user_id, key) over time; latest = MAX(updated_at).
-- No unique constraint on (user_id, key) — that's the point.
CREATE TABLE IF NOT EXISTS user_parameters (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('claude', 'app_log', 'manual'))
);

CREATE INDEX IF NOT EXISTS idx_user_param_latest ON user_parameters(user_id, key, updated_at DESC);
