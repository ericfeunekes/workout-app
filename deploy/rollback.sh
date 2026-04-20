#!/usr/bin/env bash
set -euo pipefail

# Rollback WorkoutDB server to the previous release on a macOS home machine.
#
# Usage:
#   ./deploy/rollback.sh <host> [release-sha]

HOST="${1:?usage: rollback.sh <host> [release-sha]}"
TARGET_SHA="${2:-}"
REMOTE_BASE="/opt/workoutdb"
PORT="${WORKOUTDB_PORT:-8080}"
PLIST_LABEL="com.ericfeunekes.workoutdb"

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

ssh "$HOST" "test -d $REMOTE_RELEASE" || {
  echo "ERROR: release dir not found: $REMOTE_RELEASE"
  exit 1
}

echo "==> Flipping symlink: current -> releases/$TARGET_SHA"
ssh "$HOST" "ln -sfn $REMOTE_RELEASE $REMOTE_BASE/current"

echo "==> Restarting $PLIST_LABEL"
ssh "$HOST" "
  if sudo launchctl list | grep -q $PLIST_LABEL; then
    sudo launchctl bootout system/$PLIST_LABEL 2>/dev/null || true
  fi
  sudo launchctl bootstrap system /Library/LaunchDaemons/$PLIST_LABEL.plist
"

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
echo "  ssh $HOST 'tail -50 $REMOTE_BASE/shared/logs/stderr.log'"
exit 1
