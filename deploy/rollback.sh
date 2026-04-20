#!/usr/bin/env bash
set -euo pipefail

# Rollback WorkoutDB server to the previous release on the home machine.
#
# Usage:
#   ./deploy/rollback.sh <host> [release-sha]
#
# Without a release-sha, picks the second-most-recent release dir (the one
# before current). With a sha, rolls back to that specific release.

HOST="${1:?usage: rollback.sh <host> [release-sha]}"
TARGET_SHA="${2:-}"
REMOTE_BASE="/opt/workoutdb"
PORT="${WORKOUTDB_PORT:-8080}"

if [ -z "$TARGET_SHA" ]; then
  echo "==> Finding previous release on $HOST"
  CURRENT_SHA=$(ssh "$HOST" "readlink $REMOTE_BASE/current | xargs basename")
  TARGET_SHA=$(ssh "$HOST" "ls -1t $REMOTE_BASE/releases/ | grep -v '$CURRENT_SHA' | head -1")
  if [ -z "$TARGET_SHA" ]; then
    echo "ERROR: no previous release found to roll back to."
    exit 1
  fi
  echo "    Current: $CURRENT_SHA"
  echo "    Rolling back to: $TARGET_SHA"
fi

REMOTE_RELEASE="$REMOTE_BASE/releases/$TARGET_SHA"

# Verify the target release dir exists
ssh "$HOST" "test -d $REMOTE_RELEASE" || {
  echo "ERROR: release dir not found: $REMOTE_RELEASE"
  exit 1
}

# Flip symlink
echo "==> Flipping symlink: current -> releases/$TARGET_SHA"
ssh "$HOST" "sudo -u workoutdb ln -sfn $REMOTE_RELEASE $REMOTE_BASE/current"

# Restart
echo "==> Restarting workoutdb-server"
ssh "$HOST" "sudo systemctl restart workoutdb-server"

# Health check
echo "==> Verifying health"
for i in 1 2 3; do
  if ssh "$HOST" "curl -fsSL http://localhost:$PORT/health/ready" 2>/dev/null; then
    echo ""
    echo "==> Rollback complete: now running $TARGET_SHA on $HOST"
    exit 0
  fi
  sleep 2
done

echo "ERROR: health check failed after rollback. Check logs:"
echo "  ssh $HOST 'sudo journalctl -u workoutdb-server -n 50'"
exit 1
