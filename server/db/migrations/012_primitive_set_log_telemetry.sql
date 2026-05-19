-- Primitive result rows now carry the same user/result telemetry fields the
-- execution UI can produce locally. Duplicate-column replay is treated as
-- already applied by the migration runner, matching migration 010.

ALTER TABLE primitive_set_log ADD COLUMN hr_avg_bpm INTEGER;
ALTER TABLE primitive_set_log ADD COLUMN hr_max_bpm INTEGER;
ALTER TABLE primitive_set_log ADD COLUMN skipped INTEGER NOT NULL DEFAULT 0;
ALTER TABLE primitive_set_log ADD COLUMN side TEXT NOT NULL DEFAULT 'bilateral';
ALTER TABLE primitive_set_log ADD COLUMN notes TEXT;
