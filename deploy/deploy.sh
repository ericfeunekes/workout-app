#!/usr/bin/env bash
set -euo pipefail

# Deploy WorkoutDB server to a macOS home machine over SSH.
#
# Usage:
#   ./deploy/deploy.sh <host> [git-ref]
#
# Rsyncs the server code into a new release dir, installs deps, flips the
# symlink, restarts the launchd service, and verifies health.

HOST="${1:?usage: deploy.sh <host> [git-ref]}"
REF="${2:-HEAD}"
SHORT_SHA=$(git rev-parse --short "$REF")
REMOTE_BASE="/opt/workoutdb"
REMOTE_RELEASE="$REMOTE_BASE/releases/$SHORT_SHA"
PORT="${WORKOUTDB_PORT:-8080}"
PLIST_LABEL="com.ericfeunekes.workoutdb"

echo "==> Deploying $SHORT_SHA to $HOST"

if [ "$REF" = "HEAD" ] && [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: working tree has uncommitted changes — deploying HEAD anyway."
fi

# 1. Backup the remote DB before touching anything
echo "==> Backing up remote database"
ssh "$HOST" "
  mkdir -p $REMOTE_BASE/shared/backups
  if [ -f $REMOTE_BASE/shared/db/workout.db ]; then
    sqlite3 $REMOTE_BASE/shared/db/workout.db \
      \".backup '$REMOTE_BASE/shared/backups/workout-\$(date -u +%Y%m%dT%H%M%SZ).db'\"
    echo '    backup complete'
  else
    echo '    no DB yet (first deploy)'
  fi
"

# 2. Create release dir and rsync server code
echo "==> Syncing release $SHORT_SHA"
ssh "$HOST" "mkdir -p $REMOTE_RELEASE"

rsync -az --delete \
  --include='server/***' \
  --include='pyproject.toml' \
  --include='uv.lock' \
  --include='deploy/***' \
  --exclude='*' \
  ./ "$HOST:$REMOTE_RELEASE/"

# 3. Install dependencies in the release dir
echo "==> Installing dependencies"
ssh "$HOST" "cd $REMOTE_RELEASE && uv sync --no-dev"

# 4. Atomic symlink flip
echo "==> Flipping symlink: current -> releases/$SHORT_SHA"
ssh "$HOST" "ln -sfn $REMOTE_RELEASE $REMOTE_BASE/current"

# 5. Restart the launchd service
echo "==> Restarting $PLIST_LABEL"
ssh "$HOST" "
  if sudo launchctl list | grep -q $PLIST_LABEL; then
    sudo launchctl bootout system/$PLIST_LABEL 2>/dev/null || true
  fi
  sudo launchctl bootstrap system /Library/LaunchDaemons/$PLIST_LABEL.plist
"

# 6. Health check
echo "==> Verifying health"
for i in 1 2 3 4 5; do
  if ssh "$HOST" "curl -fsSL http://localhost:$PORT/health/ready" 2>/dev/null; then
    echo ""
    echo "==> Deploy complete: $SHORT_SHA on $HOST"
    echo "    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    exit 0
  fi
  echo "    health check attempt $i failed, retrying in 2s..."
  sleep 2
done

echo "ERROR: health check failed after 5 attempts. Check logs:"
echo "  ssh $HOST 'tail -50 $REMOTE_BASE/shared/logs/stderr.log'"
exit 1
