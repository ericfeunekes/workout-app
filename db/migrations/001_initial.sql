PRAGMA foreign_keys = ON;

-- 1. Users
CREATE TABLE IF NOT EXISTS app_user (
    user_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TRIGGER IF NOT EXISTS tr_app_user_updated_at AFTER UPDATE ON app_user
BEGIN
    UPDATE app_user SET updated_at = datetime('now') WHERE user_id = OLD.user_id;
END;

-- 2. Gyms
CREATE TABLE IF NOT EXISTS gym (
    gym_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TRIGGER IF NOT EXISTS tr_gym_updated_at AFTER UPDATE ON gym
BEGIN
    UPDATE gym SET updated_at = datetime('now') WHERE gym_id = OLD.gym_id;
END;

-- 3. Workout Sources
CREATE TABLE IF NOT EXISTS workout_source (
    source_id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    title TEXT,
    author TEXT,
    original_url TEXT,
    license_note TEXT,
    imported_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TRIGGER IF NOT EXISTS tr_workout_source_updated_at AFTER UPDATE ON workout_source
BEGIN
    UPDATE workout_source SET updated_at = datetime('now') WHERE source_id = OLD.source_id;
END;

-- 4. Workout Templates
CREATE TABLE IF NOT EXISTS workout_template (
    template_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_by_user_id TEXT,
    description TEXT,
    intent_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (created_by_user_id) REFERENCES app_user(user_id)
);

CREATE TRIGGER IF NOT EXISTS tr_workout_template_updated_at AFTER UPDATE ON workout_template
BEGIN
    UPDATE workout_template SET updated_at = datetime('now') WHERE template_id = OLD.template_id;
END;

-- 5. Raw Workouts
CREATE TABLE IF NOT EXISTS raw_workout (
    raw_workout_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    external_ref TEXT,
    workout_date TEXT,
    raw_text TEXT NOT NULL,
    raw_format TEXT NOT NULL,
    parse_status TEXT NOT NULL DEFAULT 'new',
    parsed_json TEXT,
    linked_template_id TEXT,
    imported_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (source_id) REFERENCES workout_source(source_id),
    FOREIGN KEY (linked_template_id) REFERENCES workout_template(template_id)
);

CREATE TRIGGER IF NOT EXISTS tr_raw_workout_updated_at AFTER UPDATE ON raw_workout
BEGIN
    UPDATE raw_workout SET updated_at = datetime('now') WHERE raw_workout_id = OLD.raw_workout_id;
END;

-- 6. Workout Blocks
CREATE TABLE IF NOT EXISTS workout_block (
    block_id TEXT PRIMARY KEY,
    template_id TEXT NOT NULL,
    block_index INTEGER NOT NULL,
    name TEXT,
    block_type TEXT,
    structure_type TEXT,
    intent_json TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (template_id) REFERENCES workout_template(template_id),
    UNIQUE (template_id, block_index)
);

CREATE TRIGGER IF NOT EXISTS tr_workout_block_updated_at AFTER UPDATE ON workout_block
BEGIN
    UPDATE workout_block SET updated_at = datetime('now') WHERE block_id = OLD.block_id;
END;

-- 7. Exercises
CREATE TABLE IF NOT EXISTS exercise (
    exercise_id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    modality TEXT,
    movement_pattern TEXT,
    is_unilateral INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    notes TEXT,
    extra_json TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TRIGGER IF NOT EXISTS tr_exercise_updated_at AFTER UPDATE ON exercise
BEGIN
    UPDATE exercise SET updated_at = datetime('now') WHERE exercise_id = OLD.exercise_id;
END;

-- 8. Workout Items
CREATE TABLE IF NOT EXISTS workout_item (
    item_id TEXT PRIMARY KEY,
    block_id TEXT NOT NULL,
    item_index INTEGER NOT NULL,
    exercise_id TEXT,
    prescription_json TEXT,
    notes TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (block_id) REFERENCES workout_block(block_id),
    FOREIGN KEY (exercise_id) REFERENCES exercise(exercise_id),
    UNIQUE (block_id, item_index)
);

CREATE TRIGGER IF NOT EXISTS tr_workout_item_updated_at AFTER UPDATE ON workout_item
BEGIN
    UPDATE workout_item SET updated_at = datetime('now') WHERE item_id = OLD.item_id;
END;

-- 9. Tags
CREATE TABLE IF NOT EXISTS tag (
    tag_id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    kind TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TRIGGER IF NOT EXISTS tr_tag_updated_at AFTER UPDATE ON tag
BEGIN
    UPDATE tag SET updated_at = datetime('now') WHERE tag_id = OLD.tag_id;
END;

-- 10. Entity Tags (Polymorphic Join)
CREATE TABLE IF NOT EXISTS entity_tag (
    tag_id TEXT NOT NULL,
    entity_kind TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (tag_id, entity_kind, entity_id),
    FOREIGN KEY (tag_id) REFERENCES tag(tag_id)
);

CREATE TRIGGER IF NOT EXISTS tr_entity_tag_updated_at AFTER UPDATE ON entity_tag
BEGIN
    UPDATE entity_tag SET updated_at = datetime('now') 
    WHERE tag_id = OLD.tag_id AND entity_kind = OLD.entity_kind AND entity_id = OLD.entity_id;
END;

-- 11. User Goals
CREATE TABLE IF NOT EXISTS user_goal (
    user_goal_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    goal_kind TEXT NOT NULL,
    focus_muscles_json TEXT,
    sessions_per_week INTEGER,
    minutes_per_session INTEGER,
    notes TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
);

CREATE TRIGGER IF NOT EXISTS tr_user_goal_updated_at AFTER UPDATE ON user_goal
BEGIN
    UPDATE user_goal SET updated_at = datetime('now') WHERE user_goal_id = OLD.user_goal_id;
END;

-- 12. Planned Workouts
CREATE TABLE IF NOT EXISTS planned_workout (
    planned_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    date TEXT NOT NULL,
    template_id TEXT,
    status TEXT NOT NULL DEFAULT 'planned',
    notes TEXT,
    generated_by TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id),
    FOREIGN KEY (template_id) REFERENCES workout_template(template_id),
    UNIQUE (user_id, date)
);

CREATE TRIGGER IF NOT EXISTS tr_planned_workout_updated_at AFTER UPDATE ON planned_workout
BEGIN
    UPDATE planned_workout SET updated_at = datetime('now') WHERE planned_id = OLD.planned_id;
END;

-- 13. Workout Sessions
CREATE TABLE IF NOT EXISTS workout_session (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    gym_id TEXT,
    template_id TEXT,
    started_at TEXT,
    ended_at TEXT,
    notes TEXT,
    rpe INTEGER,
    summary_json TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id),
    FOREIGN KEY (gym_id) REFERENCES gym(gym_id),
    FOREIGN KEY (template_id) REFERENCES workout_template(template_id)
);

CREATE TRIGGER IF NOT EXISTS tr_workout_session_updated_at AFTER UPDATE ON workout_session
BEGIN
    UPDATE workout_session SET updated_at = datetime('now') WHERE session_id = OLD.session_id;
END;

-- 14. Session Items
CREATE TABLE IF NOT EXISTS session_item (
    session_item_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    exercise_id TEXT,
    sequence INTEGER NOT NULL,
    template_item_id TEXT,
    context_json TEXT,
    notes TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (session_id) REFERENCES workout_session(session_id),
    FOREIGN KEY (exercise_id) REFERENCES exercise(exercise_id),
    FOREIGN KEY (template_item_id) REFERENCES workout_item(item_id)
);

CREATE TRIGGER IF NOT EXISTS tr_session_item_updated_at AFTER UPDATE ON session_item
BEGIN
    UPDATE session_item SET updated_at = datetime('now') WHERE session_item_id = OLD.session_item_id;
END;

-- 15. Set Logs
CREATE TABLE IF NOT EXISTS set_log (
    set_id TEXT PRIMARY KEY,
    session_item_id TEXT NOT NULL,
    set_index INTEGER NOT NULL,
    reps INTEGER,
    weight REAL,
    weight_unit TEXT,
    duration_sec INTEGER,
    distance_m REAL,
    calories REAL,
    rpe INTEGER,
    is_warmup INTEGER NOT NULL DEFAULT 0,
    extra_json TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (session_item_id) REFERENCES session_item(session_item_id),
    UNIQUE (session_item_id, set_index)
);

CREATE TRIGGER IF NOT EXISTS tr_set_log_updated_at AFTER UPDATE ON set_log
BEGIN
    UPDATE set_log SET updated_at = datetime('now') WHERE set_id = OLD.set_id;
END;

-- Indices
CREATE INDEX IF NOT EXISTS idx_raw_workout_source ON raw_workout(source_id);
CREATE INDEX IF NOT EXISTS idx_raw_workout_status ON raw_workout(parse_status);
CREATE INDEX IF NOT EXISTS idx_workout_block_template ON workout_block(template_id);
CREATE INDEX IF NOT EXISTS idx_workout_item_block ON workout_item(block_id);
CREATE INDEX IF NOT EXISTS idx_entity_tag_entity ON entity_tag(entity_kind, entity_id);
CREATE INDEX IF NOT EXISTS idx_planned_workout_user_date ON planned_workout(user_id, date);
CREATE INDEX IF NOT EXISTS idx_session_user ON workout_session(user_id);
CREATE INDEX IF NOT EXISTS idx_session_item_session ON session_item(session_id);
CREATE INDEX IF NOT EXISTS idx_set_log_item ON set_log(session_item_id);