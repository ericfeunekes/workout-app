#!/usr/bin/env bash
set -euo pipefail

# Deploy WorkoutDB server to the home machine over SSH.
#
# Usage:
#   ./deploy/deploy.sh <host> [git-ref]
#
# Rsyncs the server code into a new release dir, installs deps, flips the
# symlink, restarts the systemd unit, and verifies health. Rollback is a
# separate script (deploy/rollback.sh).
#
# Requires: rsync, ssh access to <host>, sudo on the remote for systemctl
# and file operations under /opt/workoutdb.

HOST="${1:?usage: deploy.sh <host> [git-ref]}"
REF="${2:-HEAD}"
SHORT_SHA=$(git rev-parse --short "$REF")
REMOTE_BASE="/opt/workoutdb"
REMOTE_RELEASE="$REMOTE_BASE/releases/$SHORT_SHA"
PORT="${WORKOUTDB_PORT:-8080}"

echo "==> Deploying $SHORT_SHA to $HOST"

# 1. Verify local tree is clean at the target ref
if [ "$REF" = "HEAD" ] && [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: working tree has uncommitted changes — deploying HEAD anyway."
fi

# 2. Backup the remote DB before touching anything
echo "==> Backing up remote database"
ssh "$HOST" "
  sudo -u workoutdb mkdir -p $REMOTE_BASE/shared/backups
  sudo -u workoutdb sqlite3 $REMOTE_BASE/shared/db/workout.db \
    \".backup '$REMOTE_BASE/shared/backups/workout-\$(date -u +%Y%m%dT%H%M%SZ).db'\"
" || echo "WARNING: backup failed (DB may not exist yet on first deploy)"

# 3. Create release dir and rsync server code
echo "==> Syncing release $SHORT_SHA"
ssh "$HOST" "sudo -u workoutdb mkdir -p $REMOTE_RELEASE"

rsync -az --delete \
  --include='server/***' \
  --include='pyproject.toml' \
  --include='uv.lock' \
  --include='deploy/***' \
  --exclude='*' \
  ./ "$HOST:$REMOTE_RELEASE/"

# Fix ownership (rsync as Eric's user, files need to be owned by workoutdb)
ssh "$HOST" "sudo chown -R workoutdb:workoutdb $REMOTE_RELEASE"

# 4. Install dependencies in the release dir
echo "==> Installing dependencies"
ssh "$HOST" "sudo -u workoutdb bash -c 'cd $REMOTE_RELEASE && uv sync --no-dev'"

# 5. Atomic symlink flip
echo "==> Flipping symlink: current -> releases/$SHORT_SHA"
ssh "$HOST" "sudo -u workoutdb ln -sfn $REMOTE_RELEASE $REMOTE_BASE/current"

# 6. Restart the service
echo "==> Restarting workoutdb-server"
ssh "$HOST" "sudo systemctl restart workoutdb-server"

# 7. Health check (retry a few times — the lifespan hook runs migrations)
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
echo "  ssh $HOST 'sudo journalctl -u workoutdb-server -n 50'"
exit 1
