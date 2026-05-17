-- Primitive log rows need distance_m so distance completion and observation
-- metrics do not collapse into reps or duration during sync. The migration
-- runner treats duplicate-column replay as already applied so local databases
-- that gained the column during QA do not fail startup before recording this
-- migration.

ALTER TABLE primitive_set_log ADD COLUMN distance_m REAL;
