PRAGMA foreign_keys = ON;

ALTER TABLE workout_item ADD COLUMN sets INTEGER;
ALTER TABLE workout_item ADD COLUMN reps_target INTEGER;
ALTER TABLE workout_item ADD COLUMN reps_min INTEGER;
ALTER TABLE workout_item ADD COLUMN reps_max INTEGER;
ALTER TABLE workout_item ADD COLUMN reps_is_per_side INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS workout_item_set_prescription (
    item_id TEXT NOT NULL,
    set_index INTEGER NOT NULL,
    reps_target INTEGER,
    reps_min INTEGER,
    reps_max INTEGER,
    reps_is_per_side INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (item_id, set_index),
    FOREIGN KEY (item_id) REFERENCES workout_item(item_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workout_item_set_prescription_item ON workout_item_set_prescription(item_id);
