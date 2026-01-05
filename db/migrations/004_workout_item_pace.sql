PRAGMA foreign_keys = ON;

ALTER TABLE workout_item ADD COLUMN pace_sec_per_m_target REAL;
ALTER TABLE workout_item ADD COLUMN pace_sec_per_m_min REAL;
ALTER TABLE workout_item ADD COLUMN pace_sec_per_m_max REAL;

ALTER TABLE workout_item_set_prescription ADD COLUMN pace_sec_per_m_target REAL;
ALTER TABLE workout_item_set_prescription ADD COLUMN pace_sec_per_m_min REAL;
ALTER TABLE workout_item_set_prescription ADD COLUMN pace_sec_per_m_max REAL;
