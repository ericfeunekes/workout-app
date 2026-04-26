-- Add schema foundation for skipped logs, per-side logs, and block intent.

ALTER TABLE set_log ADD COLUMN skipped INTEGER NOT NULL DEFAULT 0 CHECK (skipped IN (0, 1));
ALTER TABLE set_log ADD COLUMN side TEXT NOT NULL DEFAULT 'bilateral' CHECK (side IN ('left', 'right', 'bilateral'));
ALTER TABLE block ADD COLUMN intent TEXT;
