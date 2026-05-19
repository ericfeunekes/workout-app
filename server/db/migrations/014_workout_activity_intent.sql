-- Vendor-neutral workout source facts for export classification.
-- The API exposes this as `activity_intent`, a sibling of primitive_blocks.
-- Server storage keeps one nullable JSON object as the sole source of truth.

ALTER TABLE workout ADD COLUMN activity_intent_json TEXT;
