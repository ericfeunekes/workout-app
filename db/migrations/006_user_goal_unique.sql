PRAGMA foreign_keys = ON;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_goal_user_id ON user_goal(user_id);
