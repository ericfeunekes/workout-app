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

## Release-dir layout

Target layout on the server, once the release-dir deploy is in place:

```
/opt/workoutdb/
├── releases/
│   ├── 3a1f9c2/          # one dir per deployed git sha
│   │   ├── server/
│   │   ├── pyproject.toml
│   │   ├── uv.lock
│   │   └── .venv/        # created by `uv sync --no-dev` inside the release
│   ├── 4b2e0d8/
│   └── 5c3f1e9/
├── current -> releases/5c3f1e9   # symlink; flipped atomically on deploy
└── shared/
    ├── .env              # bearer token, user UUID, DB path — survives deploys
    └── db/
        └── workout.db    # SQLite file; never lives inside a release dir
```

Rules:

- **`current` is a symlink.** The systemd unit's `WorkingDirectory=/opt/workoutdb/current` and ExecStart points at `/opt/workoutdb/current/.venv/bin/uvicorn`. Deploy = rsync a new release dir + `ln -sfn releases/<sha> current` + restart.
- **`shared/.env` holds prod secrets.** Never committed, never inside a release dir. `WORKOUTDB_DB_PATH=/opt/workoutdb/shared/db/workout.db` so every release reads the same file.
- **DB is in `shared/db/`, not a release dir.** A rollback must not stomp on workout data, and backups should be scoped to `shared/`.
- **Old release dirs are kept** until pruned manually (retain at least the previous 3 so rollback is always possible). Pruning is a follow-up automation — not load-bearing for now.

## Prerequisites

- Linux (Debian/Ubuntu assumed; adapt paths for other distros)
- Tailscale installed and joined to Eric's tailnet
- Python 3.11+ available
- `uv` installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- systemd (default on all mainstream distros)

## First-time server bootstrap

Do this exactly once per physical machine. After this, `make deploy HOST=<host>` handles everything from your laptop.

**Decision (2026-04-20):** system-scope systemd. The service starts on boot without any login session, survives power outages, and the `workoutdb` system user has no shell. Eric's SSH user uses `sudo` for service management. See `docs/open-questions.md` (now resolved).

```bash
# 1. Install uv (no root required — installs to ~/.cargo/bin or similar)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. Install Tailscale and join the tailnet
#    (Distro-specific; see https://tailscale.com/download/linux)
sudo tailscale up

# 3. Create the system user and directory layout
sudo useradd --system --home-dir /opt/workoutdb --shell /usr/sbin/nologin workoutdb
sudo mkdir -p /opt/workoutdb/{releases,shared/db,shared/backups}
sudo chown -R workoutdb:workoutdb /opt/workoutdb

# 4. Seed the shared .env (survives every deploy)
#    Generate values first:
#      python3 -c "import secrets; print(secrets.token_urlsafe(48))"    # bearer token
#      python3 -c "import uuid; print(uuid.uuid4())"                    # user UUID
#    Paste both into the iOS app's first-run settings too.
sudo -u workoutdb tee /opt/workoutdb/shared/.env > /dev/null <<'EOF'
WORKOUTDB_BEARER_TOKEN=<paste-generated-token>
WORKOUTDB_USER_ID=<paste-generated-uuid>
WORKOUTDB_DB_PATH=/opt/workoutdb/shared/db/workout.db
WORKOUTDB_HOST=0.0.0.0
WORKOUTDB_PORT=8080
WORKOUTDB_DEBUG=false
EOF
sudo chmod 600 /opt/workoutdb/shared/.env

# 5. Install the systemd unit (system-scope — starts on boot, no login needed)
sudo cp deploy/workoutdb-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable workoutdb-server
# Don't start yet — /opt/workoutdb/current doesn't exist until the first deploy.

# 6. Get the tailnet hostname for the app's first-run setup:
tailscale status | grep $(hostname)
```

After bootstrap, run `make deploy HOST=<tailnet-hostname>` from your laptop. The first deploy creates the `current` symlink and starts the service.

## Reachability from the iPhone (Tailscale)

The server's tailnet hostname is the address the app uses. Find it with:

```bash
tailscale status | grep $(hostname)
```

In the iOS app's first-run settings, paste:
- **Server URL**: `http://<tailnet-hostname>:8080` (or an IP if MagicDNS isn't configured)
- **Bearer token**: the same value as `WORKOUTDB_BEARER_TOKEN`
- The token already encodes *which* user the app is acting as (`WORKOUTDB_USER_ID` on the server). The app never sends `user_id` on the wire.

No TLS — the tailnet is the trust boundary. If that changes (e.g., exposing to the public internet), the design needs revisiting; see `docs/decisions/ADR-2026-04-17-ux-scope.md`.

## Deploy cycle

No CI/CD. `make deploy HOST=<tailnet-hostname>` from a laptop runs the full flow:

```bash
make deploy HOST=workoutdb-server          # deploy HEAD
make deploy HOST=workoutdb-server TAG=v1   # deploy a specific ref
```

The flow (`deploy/deploy.sh`):

1. Back up the remote SQLite DB into `/opt/workoutdb/shared/backups/`.
2. Rsync the server code into `/opt/workoutdb/releases/<short-sha>/`.
3. `uv sync --no-dev` inside the new release dir (builds its own `.venv`).
4. Atomic symlink flip: `current -> releases/<short-sha>`.
5. `sudo systemctl restart workoutdb-server`.
6. Health check with retries — the lifespan hook runs migrations on startup.

If the health check fails, the previous release is still intact for rollback:

```bash
make deploy-rollback HOST=workoutdb-server
```

Migrations run automatically on startup. A failed migration keeps the service in a restart loop (systemd backs off at 3s intervals); `sudo journalctl -u workoutdb-server -n 50` shows the error. Roll back, fix the migration, redeploy.

## Backup

SQLite single-file backup — trivial but do it. Use the online backup API (safe while the server is running):

```bash
# From a laptop checkout (uses scripts/db_backup.py via uv):
make db-backup                                       # local backup against $WORKOUTDB_DB_PATH

# On the home server (direct sqlite3, same semantics):
sudo -u workoutdb sqlite3 /opt/workoutdb/shared/db/workout.db \
  ".backup '/opt/workoutdb/shared/backups/workout-$(date -u +%Y%m%dT%H%M%SZ).db'"

# Restore a snapshot over the live DB (prompts before overwriting; server should be stopped first):
make db-restore FILE=backups/workoutdb-20260418T134812Z.sqlite
```

Both paths go through SQLite's `sqlite3_backup_*` API — the server can keep reading/writing during the backup. Automating the cadence (cron / systemd timer) is a follow-up; for a single user with real logged data, nightly is the eventual target.

## Rollback

With the release-dir layout, rollback is a symlink flip — no re-sync, no rebuild:

```bash
# From your laptop:
make deploy-rollback HOST=<tailnet-hostname>

# Or manually on the server:
ssh <tailnet-hostname> '
  cd /opt/workoutdb &&
  ls -1t releases/ | head -5 &&                     # pick the previous known-good sha
  sudo -u workoutdb ln -sfn releases/<prev-sha> current &&
  sudo systemctl restart workoutdb-server &&
  curl -fsSL http://localhost:8080/health/ready
'
```

Because each release dir carries its own `.venv` and source tree, a rollback is a single atomic symlink update plus a restart. Keep at least the previous 3 release dirs around so multi-step rollback is possible.

If the rollback leaves the DB schema ahead of the code (i.e., a migration was applied by the new version but the old code doesn't know about new columns), see `docs/MIGRATIONS.md` § "Recovering when things go sideways" for the set_log preservation flow.

## Observability

- **Logs**: `sudo journalctl -u workoutdb-server -f` (or `make server-logs HOST=...` from your laptop) — JSON-structured in prod, plain in debug mode. Every request carries a `request_id` log field and `X-Request-ID` response header for client-side correlation.
- **Health**: `/health` is unauthenticated and cheap; `/health/ready` does a DB round-trip and returns the schema version.
- **Metrics**: none built-in. Add Prometheus or similar only when the need is real — for a single user it usually isn't.
