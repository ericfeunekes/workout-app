CREATE TABLE IF NOT EXISTS intent_taxonomy (
    intent_id TEXT PRIMARY KEY,
    parent_intent_id TEXT,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (parent_intent_id) REFERENCES intent_taxonomy(intent_id)
);

CREATE INDEX IF NOT EXISTS idx_intent_taxonomy_parent ON intent_taxonomy(parent_intent_id);

CREATE TRIGGER IF NOT EXISTS tr_intent_taxonomy_updated_at AFTER UPDATE ON intent_taxonomy
BEGIN
    UPDATE intent_taxonomy SET updated_at = datetime('now') WHERE intent_id = OLD.intent_id;
END;
