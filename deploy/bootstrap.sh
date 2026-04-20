#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for the WorkoutDB server on macOS.
# Run this on the server machine: ./deploy/bootstrap.sh
# Requires sudo (prompts once for password).

BASE="/opt/workoutdb"
PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/com.ericfeunekes.workoutdb.plist"
USER="$(whoami)"
GROUP="staff"

echo "==> WorkoutDB server bootstrap"
echo "    Installing to: $BASE"
echo "    Running as user: $USER"
echo ""

# Prompt for sudo upfront so the rest runs unattended
sudo -v

# 1. Directory layout
echo "==> Creating directory layout"
sudo mkdir -p "$BASE"/{releases,shared/db,shared/backups,shared/logs}
sudo chown -R "$USER:$GROUP" "$BASE"

# 2. Generate credentials
echo "==> Generating credentials"
BEARER_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")
USER_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")

# 3. Write .env
cat > "$BASE/shared/.env" <<EOF
WORKOUTDB_BEARER_TOKEN=$BEARER_TOKEN
WORKOUTDB_USER_ID=$USER_UUID
WORKOUTDB_DB_PATH=$BASE/shared/db/workout.db
WORKOUTDB_HOST=0.0.0.0
WORKOUTDB_PORT=8080
WORKOUTDB_DEBUG=false
EOF
chmod 600 "$BASE/shared/.env"

# 4. Install launchd plist
echo "==> Installing launchd plist"
if [ -f "$PLIST_SRC" ]; then
  sudo cp "$PLIST_SRC" /Library/LaunchDaemons/
else
  echo "WARNING: plist not found at $PLIST_SRC — copy manually after first deploy."
fi

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "Save these credentials — you'll need the bearer token for the iOS app:"
echo ""
echo "    Bearer token: $BEARER_TOKEN"
echo "    User UUID:    $USER_UUID"
echo ""
echo "Next: from your laptop, run:"
echo "    make deploy HOST=robie-imac"
