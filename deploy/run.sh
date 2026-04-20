#!/usr/bin/env bash
set -euo pipefail

# Wrapper for launchd: source the shared .env then exec uvicorn.
# launchd doesn't have an EnvironmentFile directive, so this script bridges the gap.
# TLS is handled by `tailscale serve` (reverse proxy on port 443 -> localhost:8080).

ENV_FILE="/opt/workoutdb/shared/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

exec /opt/workoutdb/current/.venv/bin/uvicorn \
  workoutdb_server.main:app \
  --host "${WORKOUTDB_HOST:-0.0.0.0}" \
  --port "${WORKOUTDB_PORT:-8080}"
