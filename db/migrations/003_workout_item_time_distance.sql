PRAGMA foreign_keys = ON;

ALTER TABLE workout_item ADD COLUMN prescription_type TEXT;
ALTER TABLE workout_item ADD COLUMN time_sec_target INTEGER;
ALTER TABLE workout_item ADD COLUMN time_sec_min INTEGER;
ALTER TABLE workout_item ADD COLUMN time_sec_max INTEGER;
ALTER TABLE workout_item ADD COLUMN distance_m_target REAL;
ALTER TABLE workout_item ADD COLUMN distance_m_min REAL;
ALTER TABLE workout_item ADD COLUMN distance_m_max REAL;

ALTER TABLE workout_item_set_prescription ADD COLUMN prescription_type TEXT;
ALTER TABLE workout_item_set_prescription ADD COLUMN time_sec_target INTEGER;
ALTER TABLE workout_item_set_prescription ADD COLUMN time_sec_min INTEGER;
ALTER TABLE workout_item_set_prescription ADD COLUMN time_sec_max INTEGER;
ALTER TABLE workout_item_set_prescription ADD COLUMN distance_m_target REAL;
ALTER TABLE workout_item_set_prescription ADD COLUMN distance_m_min REAL;
ALTER TABLE workout_item_set_prescription ADD COLUMN distance_m_max REAL;

UPDATE workout_item
SET prescription_type = 'reps'
WHERE prescription_type IS NULL
  AND (reps_target IS NOT NULL OR reps_min IS NOT NULL OR reps_max IS NOT NULL);

UPDATE workout_item
SET prescription_type = 'freeform'
WHERE prescription_type IS NULL;

UPDATE workout_item_set_prescription
SET prescription_type = 'reps'
WHERE prescription_type IS NULL
  AND (reps_target IS NOT NULL OR reps_min IS NOT NULL OR reps_max IS NOT NULL);

UPDATE workout_item_set_prescription
SET prescription_type = 'freeform'
WHERE prescription_type IS NULL;
