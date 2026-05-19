CREATE TABLE IF NOT EXISTS health_archive_record (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    external_id TEXT NOT NULL,
    descriptor_id TEXT NOT NULL,
    sample_kind TEXT NOT NULL,
    source_bundle_identifier TEXT,
    start_at DATETIME,
    end_at DATETIME,
    unit TEXT,
    value_json TEXT NOT NULL,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    first_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, descriptor_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_health_archive_record_user_descriptor
    ON health_archive_record(user_id, descriptor_id);

CREATE INDEX IF NOT EXISTS idx_health_archive_record_user_start
    ON health_archive_record(user_id, start_at);

CREATE TABLE IF NOT EXISTS health_archive_tombstone (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    descriptor_id TEXT NOT NULL,
    external_id TEXT NOT NULL,
    observed_at DATETIME NOT NULL,
    UNIQUE(user_id, descriptor_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_health_archive_tombstone_user_descriptor
    ON health_archive_tombstone(user_id, descriptor_id);

CREATE TABLE IF NOT EXISTS health_archive_request_set (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    request_set_key TEXT NOT NULL,
    server_namespace TEXT NOT NULL,
    descriptor_fingerprint TEXT NOT NULL,
    acknowledged_cursor TEXT,
    records_received INTEGER NOT NULL DEFAULT 0,
    tombstones_received INTEGER NOT NULL DEFAULT 0,
    last_uploaded_at DATETIME NOT NULL,
    UNIQUE(user_id, request_set_key)
);

CREATE INDEX IF NOT EXISTS idx_health_archive_request_set_user
    ON health_archive_request_set(user_id, request_set_key);
