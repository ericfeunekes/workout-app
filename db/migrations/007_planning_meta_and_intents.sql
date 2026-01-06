CREATE TABLE IF NOT EXISTS plan (
    plan_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT,
    meta_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
);

CREATE TRIGGER IF NOT EXISTS tr_plan_updated_at AFTER UPDATE ON plan
BEGIN
    UPDATE plan SET updated_at = datetime('now') WHERE plan_id = OLD.plan_id;
END;

ALTER TABLE planned_workout ADD COLUMN plan_id TEXT;
ALTER TABLE planned_workout ADD COLUMN meta_json TEXT;

ALTER TABLE workout_template ADD COLUMN intent_primary_id TEXT;
ALTER TABLE workout_template ADD COLUMN intent_secondary_id TEXT;
ALTER TABLE workout_block ADD COLUMN intent_primary_id TEXT;
ALTER TABLE workout_block ADD COLUMN intent_secondary_id TEXT;
ALTER TABLE workout_item ADD COLUMN intent_primary_id TEXT;
ALTER TABLE workout_item ADD COLUMN intent_secondary_id TEXT;

CREATE INDEX IF NOT EXISTS idx_planned_workout_plan ON planned_workout(plan_id);
CREATE INDEX IF NOT EXISTS idx_workout_template_intent ON workout_template(intent_primary_id, intent_secondary_id);
CREATE INDEX IF NOT EXISTS idx_workout_block_intent ON workout_block(intent_primary_id, intent_secondary_id);
CREATE INDEX IF NOT EXISTS idx_workout_item_intent ON workout_item(intent_primary_id, intent_secondary_id);
