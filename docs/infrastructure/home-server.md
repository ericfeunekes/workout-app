---
title: Home server setup
status: stable
date: 2026-04-17
purpose: "One-time setup of the Python FastAPI server on a Linux home machine. Tailscale-reachable, systemd-managed, SQLite-backed."
covers:
  - server/
  - deploy/
---

# Home server setup

The WorkoutDB server runs on Eric's home machine, reachable only over Tailscale (per ADR-2026-04-17-ux-scope). This doc is the one-time setup runbook and the ongoing deploy flow.

## Prerequisites

- Linux (Debian/Ubuntu assumed; adapt paths for other distros)
- Tailscale installed and joined to Eric's tailnet
- Python 3.11+ available
- `uv` installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- systemd (default on all mainstream distros)

## First-time setup

```bash
# 1. Create a dedicated user + data dir
sudo useradd --system --home-dir /opt/workoutdb --shell /usr/sbin/nologin workoutdb
sudo mkdir -p /opt/workoutdb /var/lib/workoutdb /etc/workoutdb
sudo chown workoutdb:workoutdb /var/lib/workoutdb

# 2. Clone the repo into /opt/workoutdb (or rsync from local)
sudo -u workoutdb git clone <repo-url> /opt/workoutdb
cd /opt/workoutdb

# 3. Install deps (no dev extras on prod)
sudo -u workoutdb uv sync --no-dev

# 4. Configure environment
sudo tee /etc/workoutdb/env > /dev/null <<'EOF'
WORKOUTDB_BEARER_TOKEN=<paste-generated-token>
WORKOUTDB_DB_PATH=/var/lib/workoutdb/workout.db
WORKOUTDB_HOST=0.0.0.0
WORKOUTDB_PORT=8080
WORKOUTDB_DEBUG=false
EOF
sudo chmod 600 /etc/workoutdb/env
sudo chown root:workoutdb /etc/workoutdb/env

# Generate a bearer token:
#   python -c "import secrets; print(secrets.token_urlsafe(48))"
# Then paste the same value into the iOS app's first-run settings.

# 5. Install the systemd unit
sudo cp /opt/workoutdb/deploy/workoutdb-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now workoutdb-server

# 6. Verify
systemctl status workoutdb-server
curl http://localhost:8080/health
curl http://localhost:8080/health/ready     # also reports schema version
```

## Reachability from the iPhone (Tailscale)

The server's tailnet hostname is the address the app uses. Find it with:

```bash
tailscale status | grep $(hostname)
```

In the iOS app's first-run settings, paste:
- **Server URL**: `http://<tailnet-hostname>:8080` (or an IP if MagicDNS isn't configured)
- **Bearer token**: the same value as `WORKOUTDB_BEARER_TOKEN`

No TLS — the tailnet is the trust boundary. If that changes (e.g., exposing to the public internet), the design needs revisiting; see `docs/decisions/ADR-2026-04-17-ux-scope.md`.

## Deploy a new version

No CI/CD for deploy (see `docs/WORKFLOW.md` § "Deploy"). Manual flow:

```bash
# On the home server:
cd /opt/workoutdb
sudo -u workoutdb git pull
sudo -u workoutdb uv sync --no-dev
sudo systemctl restart workoutdb-server

# Verify
curl http://localhost:8080/health/ready
```

Migrations run automatically on startup via the lifespan hook. A failed migration keeps the prior version running (systemd restart loop backs off; `journalctl -u workoutdb-server` shows the error).

## Backup

SQLite single-file backup — trivial but do it.

```bash
# Ad-hoc
sudo -u workoutdb sqlite3 /var/lib/workoutdb/workout.db ".backup '/var/lib/workoutdb/backups/workout-$(date +%F).db'"

# Automate via cron or systemd timer — leaving the cadence as a future concern until
# there's real logged data worth backing up.
```

## Rollback

```bash
cd /opt/workoutdb
sudo -u workoutdb git log --oneline | head         # find the previous good commit
sudo -u workoutdb git checkout <prev-sha>
sudo -u workoutdb uv sync --no-dev
sudo systemctl restart workoutdb-server
```

If the rollback leaves the DB schema ahead of the code (i.e., a migration was applied by the new version but the old code doesn't know about new columns), see `docs/MIGRATIONS.md` § "Recovering when things go sideways" for the set_log preservation flow.

## Observability

- **Logs**: `journalctl -u workoutdb-server -f` — JSON-structured in prod, plain in debug mode. Every request carries a `request_id` log field and `X-Request-ID` response header for client-side correlation.
- **Health**: `/health` is unauthenticated and cheap; `/health/ready` does a DB round-trip and returns the schema version.
- **Metrics**: none built-in. Add Prometheus or similar only when the need is real — for a single user it usually isn't.
