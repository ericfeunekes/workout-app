-- 005_event_log.sql — structured telemetry event log.
--
-- Purpose: durable server-side trail of app-side events (interactions, state
-- transitions, network calls, timer ticks, errors). When Eric reports a bug
-- after a real workout we pull the event trail from this table and see what
-- happened. MCP-driven test runs surface events here too.
--
-- Design:
--   • id TEXT PK — app-assigned UUID. Idempotent upsert: same id on a retry
--     updates the existing row rather than duplicating.
--   • data_json TEXT NULL — permissive freeform JSON so new event shapes
--     don't require schema migrations. Same pattern as prescription_json /
--     timing_config_json.
--   • workout_id / set_log_id — nullable pointers for convenient filtering
--     when digging into a specific session. Not FK-enforced because the app
--     may emit events against IDs that haven't been synced yet (e.g. a
--     set_log pushed in the same batch).
--   • received_at TEXT NOT NULL — stamped by the server on insert. Lets us
--     distinguish "when the event happened on the device" from "when we saw
--     it", which matters when the device was offline for a while.
--   • Index on (user_id, ts DESC) supports the dominant query shape:
--     "what events has this user's app emitted recently?"

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS event_log (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    ts TEXT NOT NULL,
    session_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    data_json TEXT,
    workout_id TEXT,
    set_log_id TEXT,
    received_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_event_log_user_ts
    ON event_log(user_id, ts DESC);
