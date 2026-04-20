---
title: Home server setup
status: stable
date: 2026-04-20
purpose: "One-time setup of the Python FastAPI server on a macOS home machine. Tailscale-reachable, launchd-managed, SQLite-backed."
covers:
  - server/
  - deploy/
---

# Home server setup

The WorkoutDB server runs on Eric's iMac (robie-imac), reachable only over Tailscale (per ADR-2026-04-17-ux-scope). This doc is the one-time setup runbook and the ongoing deploy flow.

## Release-dir layout

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
    ├── db/
    │   └── workout.db    # SQLite file; never lives inside a release dir
    ├── backups/
    └── logs/
        ├── stdout.log
        └── stderr.log
```

Rules:

- **`current` is a symlink.** The launchd plist's WorkingDirectory and run.sh both resolve through it. Deploy = rsync a new release dir + `ln -sfn releases/<sha> current` + restart.
- **`shared/.env` holds prod secrets.** Never committed, never inside a release dir. `WORKOUTDB_DB_PATH=/opt/workoutdb/shared/db/workout.db` so every release reads the same file.
- **DB is in `shared/db/`, not a release dir.** A rollback must not stomp on workout data, and backups should be scoped to `shared/`.
- **Old release dirs are kept** until pruned manually (retain at least the previous 3 so rollback is always possible).

## Prerequisites

- macOS (robie-imac, Intel x86_64)
- Tailscale installed and joined to Eric's tailnet
- `uv` installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

## First-time server bootstrap

Do this exactly once per machine. After this, `make deploy HOST=robie-imac` handles everything from your laptop.

**Decision (2026-04-20):** launchd LaunchDaemon (system-scope). Starts on boot without login, survives power outages, runs as `eric`. No separate system user needed on macOS.

```bash
# 1. uv should already be installed; verify:
which uv

# 2. Tailscale should already be joined; verify:
tailscale status

# 3. Create the directory layout
sudo mkdir -p /opt/workoutdb/{releases,shared/db,shared/backups,shared/logs}
sudo chown -R eric:staff /opt/workoutdb

# 4. Seed the shared .env (survives every deploy)
#    Generate values first (run on any machine with python3):
#      python3 -c "import secrets; print(secrets.token_urlsafe(48))"    # bearer token
#      python3 -c "import uuid; print(uuid.uuid4())"                    # user UUID
#    Save these — you'll paste the same token into the iOS app's FirstRun screen.
cat > /opt/workoutdb/shared/.env <<'EOF'
WORKOUTDB_BEARER_TOKEN=<paste-generated-token>
WORKOUTDB_USER_ID=<paste-generated-uuid>
WORKOUTDB_DB_PATH=/opt/workoutdb/shared/db/workout.db
WORKOUTDB_HOST=0.0.0.0
WORKOUTDB_PORT=8080
WORKOUTDB_DEBUG=false
EOF
chmod 600 /opt/workoutdb/shared/.env

# 5. Install the launchd plist (system-scope — starts on boot, no login needed)
#    The plist is deployed with the code, but needs to exist before the first deploy:
sudo cp ~/coding/workout-app/deploy/com.ericfeunekes.workoutdb.plist /Library/LaunchDaemons/
# Don't load yet — /opt/workoutdb/current doesn't exist until the first deploy.
```

After bootstrap, run `make deploy HOST=robie-imac` from your laptop. The first deploy creates the `current` symlink and starts the service.

## Reachability from the iPhone (Tailscale)

The server's tailnet hostname is the address the app uses. Find it with:

```bash
tailscale status | grep $(hostname)
```

In the iOS app's first-run settings, paste:
- **Server URL**: `http://robie-imac:8080` (or `http://100.106.10.41:8080` if MagicDNS isn't configured)
- **Bearer token**: the same value as `WORKOUTDB_BEARER_TOKEN`
- The token already encodes *which* user the app is acting as (`WORKOUTDB_USER_ID` on the server). The app never sends `user_id` on the wire.

No TLS — the tailnet is the trust boundary.

## Deploy cycle

No CI/CD. `make deploy HOST=robie-imac` from a laptop runs the full flow:

```bash
make deploy HOST=robie-imac          # deploy HEAD
make deploy HOST=robie-imac TAG=v1   # deploy a specific ref
```

The flow (`deploy/deploy.sh`):

1. Back up the remote SQLite DB into `/opt/workoutdb/shared/backups/`.
2. Rsync the server code into `/opt/workoutdb/releases/<short-sha>/`.
3. `uv sync --no-dev` inside the new release dir (builds its own `.venv`).
4. Atomic symlink flip: `current -> releases/<short-sha>`.
5. `launchctl bootout` + `launchctl bootstrap` to restart the service.
6. Health check with retries — the lifespan hook runs migrations on startup.

If the health check fails, the previous release is still intact for rollback:

```bash
make deploy-rollback HOST=robie-imac
```

Migrations run automatically on startup. A failed migration keeps the service restarting (launchd `KeepAlive` relaunches it); `tail /opt/workoutdb/shared/logs/stderr.log` shows the error. Roll back, fix the migration, redeploy.

## Backup

SQLite single-file backup — trivial but do it. Use the online backup API (safe while the server is running):

```bash
# From a laptop checkout:
make db-backup                                       # local backup against $WORKOUTDB_DB_PATH

# On the home server (direct sqlite3):
sqlite3 /opt/workoutdb/shared/db/workout.db \
  ".backup '/opt/workoutdb/shared/backups/workout-$(date -u +%Y%m%dT%H%M%SZ).db'"

# Restore (stop the server first):
make db-restore FILE=backups/workoutdb-20260418T134812Z.sqlite
```

## Rollback

Symlink flip — no re-sync, no rebuild:

```bash
# From your laptop:
make deploy-rollback HOST=robie-imac

# Or manually on the server:
ssh robie-imac '
  cd /opt/workoutdb &&
  ls -1t releases/ | head -5 &&
  ln -sfn releases/<prev-sha> current &&
  sudo launchctl bootout system/com.ericfeunekes.workoutdb 2>/dev/null; \
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.ericfeunekes.workoutdb.plist &&
  curl -fsSL http://localhost:8080/health/ready
'
```

Each release dir carries its own `.venv` and source tree, so rollback is instant.

## Observability

- **Logs**: `make server-logs HOST=robie-imac` (tails `/opt/workoutdb/shared/logs/stderr.log`). Every request carries a `request_id` log field and `X-Request-ID` response header.
- **Health**: `/health` is unauthenticated and cheap; `/health/ready` does a DB round-trip and returns the schema version.
- **Service status**: `make server-status HOST=robie-imac` or `sudo launchctl print system/com.ericfeunekes.workoutdb` on the server.
