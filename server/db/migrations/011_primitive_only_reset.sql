-- Primitive-only contract cutover.
--
-- Existing authored workouts/logs in this repo are QA data for the old
-- WorkoutItem/SetLog contract. Preserve catalog/profile/config tables and
-- drop old workout-tree execution state so the app/server cannot mix old and
-- primitive result identities after upgrade.

DELETE FROM set_log;
DELETE FROM exercise_alternative;
DELETE FROM workout_item;
DELETE FROM block;
DELETE FROM primitive_set_log;
DELETE FROM workout;
