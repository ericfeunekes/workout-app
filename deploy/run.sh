#!/usr/bin/env bash
set -euo pipefail

# Wrapper for launchd: source the shared .env then exec uvicorn.
# launchd doesn't have an EnvironmentFile directive, so this script bridges the gap.

ENV_FILE="/opt/workoutdb/shared/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

HOSTNAME=$(tailscale status --self --json | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))")
CERT_DIR="$HOME"
SSL_CERT="$CERT_DIR/$HOSTNAME.crt"
SSL_KEY="$CERT_DIR/$HOSTNAME.key"

if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
  exec /opt/workoutdb/current/.venv/bin/uvicorn \
    workoutdb_server.main:app \
    --host "${WORKOUTDB_HOST:-0.0.0.0}" \
    --port "${WORKOUTDB_PORT:-8080}" \
    --ssl-certfile "$SSL_CERT" \
    --ssl-keyfile "$SSL_KEY"
else
  exec /opt/workoutdb/current/.venv/bin/uvicorn \
    workoutdb_server.main:app \
    --host "${WORKOUTDB_HOST:-0.0.0.0}" \
    --port "${WORKOUTDB_PORT:-8080}"
fi
