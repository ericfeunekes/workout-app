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

Do this exactly once per physical machine. From here on, `make deploy` (once implemented) takes over.

```bash
# 1. Install uv (no root required)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. Install Tailscale and join the tailnet
#    (Distro-specific; see https://tailscale.com/download/linux)
sudo tailscale up

# 3. Create the layout
sudo mkdir -p /opt/workoutdb/{releases,shared/db}
sudo useradd --system --home-dir /opt/workoutdb --shell /usr/sbin/nologin workoutdb
sudo chown -R workoutdb:workoutdb /opt/workoutdb

# 4. Seed the shared .env (survives every deploy)
sudo -u workoutdb tee /opt/workoutdb/shared/.env > /dev/null <<'EOF'
WORKOUTDB_BEARER_TOKEN=<paste-generated-token>
WORKOUTDB_USER_ID=<paste-generated-uuid>
WORKOUTDB_DB_PATH=/opt/workoutdb/shared/db/workout.db
WORKOUTDB_HOST=0.0.0.0
WORKOUTDB_PORT=8080
WORKOUTDB_DEBUG=false
EOF
sudo chmod 600 /opt/workoutdb/shared/.env

# Generate a bearer token:
#   python -c "import secrets; print(secrets.token_urlsafe(48))"
# Generate the user UUID (once per user ever — the app_user row is auto-created on startup):
#   python -c "import uuid; print(uuid.uuid4())"
# Paste both into the iOS app's first-run settings.

# 5. Install the systemd unit (user-scope to avoid root; enable linger so it starts at boot).
#    The unit template below reads EnvironmentFile=/opt/workoutdb/shared/.env and
#    ExecStart=/opt/workoutdb/current/.venv/bin/uvicorn workoutdb_server.main:app.
sudo loginctl enable-linger workoutdb
sudo -u workoutdb mkdir -p /opt/workoutdb/.config/systemd/user
sudo -u workoutdb tee /opt/workoutdb/.config/systemd/user/workoutdb-server.service > /dev/null <<'EOF'
[Unit]
Description=WorkoutDB home server
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=exec
WorkingDirectory=/opt/workoutdb/current
EnvironmentFile=/opt/workoutdb/shared/.env
ExecStart=/opt/workoutdb/current/.venv/bin/uvicorn workoutdb_server.main:app --host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
sudo -u workoutdb systemctl --user daemon-reload
# Unit is installed but not started — the first `make deploy` will populate `current/` and start it.

# 6. Get the tailnet hostname for the app's first-run setup:
tailscale status | grep $(hostname)
```

After bootstrap, `/opt/workoutdb/current` doesn't exist yet; the first deploy creates it.

## First-time setup (legacy, pre-release-dir layout)

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
WORKOUTDB_USER_ID=<paste-generated-uuid>
WORKOUTDB_DB_PATH=/var/lib/workoutdb/workout.db
WORKOUTDB_HOST=0.0.0.0
WORKOUTDB_PORT=8080
WORKOUTDB_DEBUG=false
EOF
sudo chmod 600 /etc/workoutdb/env
sudo chown root:workoutdb /etc/workoutdb/env

# Generate a bearer token:
#   python -c "import secrets; print(secrets.token_urlsafe(48))"
# Generate the user UUID (once per user ever — the app_user row is auto-created on startup):
#   python -c "import uuid; print(uuid.uuid4())"
# Paste both into the iOS app's first-run settings.

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
- The token already encodes *which* user the app is acting as (`WORKOUTDB_USER_ID` on the server). The app never sends `user_id` on the wire.

No TLS — the tailnet is the trust boundary. If that changes (e.g., exposing to the public internet), the design needs revisiting; see `docs/decisions/ADR-2026-04-17-ux-scope.md`.

## Deploy cycle

No CI/CD. `make deploy HOST=<tailnet-hostname>` from a laptop will (once implemented) run the full flow. The current Makefile target is a stub that prints the planned steps; fleshing it out is tracked separately.

Planned flow (once the target is real):

1. `git push origin <branch>` — make the ref reachable from the server.
2. SSH to `$HOST` and, as the `workoutdb` user:
   1. `make db-backup` → online SQLite snapshot into `/opt/workoutdb/shared/backups/`. The server keeps running.
   2. `git fetch --all && git checkout <branch>` in a working checkout.
   3. Sync the working tree into `/opt/workoutdb/releases/<short-sha>/`.
   4. `uv sync --no-dev` inside the new release dir (builds its own `.venv`).
   5. `ln -sfn releases/<short-sha> current` — atomic symlink flip.
   6. `systemctl --user restart workoutdb-server`.
   7. `curl -fsSL http://localhost:8080/health/ready` — the lifespan hook runs migrations on startup; a failed migration keeps the prior release running because the symlink still points at the old dir if the restart fails (systemd backs off; see `journalctl --user -u workoutdb-server`).
3. Print the deployed sha + timestamp locally for the deploy log.

Until `make deploy` exists, fall back to the manual flow:

```bash
# On the home server (release-dir layout):
cd /opt/workoutdb/current
sudo -u workoutdb git pull       # only if the release dir is a git clone; usually rsync'd instead
sudo -u workoutdb uv sync --no-dev
sudo -u workoutdb systemctl --user restart workoutdb-server
curl http://localhost:8080/health/ready
```

Migrations run automatically on startup via the lifespan hook. A failed migration keeps the prior version running (systemd restart loop backs off; `journalctl --user -u workoutdb-server` shows the error).

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
# Option 1: via the Makefile target (once implemented)
make deploy-rollback HOST=<tailnet-hostname>

# Option 2: manual
ssh <tailnet-hostname> '
  cd /opt/workoutdb &&
  ls -1t releases/ | head -5 &&                     # pick the previous known-good sha
  ln -sfn releases/<prev-sha> current &&
  systemctl --user restart workoutdb-server &&
  curl -fsSL http://localhost:8080/health/ready
'
```

Because each release dir carries its own `.venv` and source tree, a rollback is a single atomic symlink update plus a restart. Keep at least the previous 3 release dirs around so multi-step rollback is possible.

If the rollback leaves the DB schema ahead of the code (i.e., a migration was applied by the new version but the old code doesn't know about new columns), see `docs/MIGRATIONS.md` § "Recovering when things go sideways" for the set_log preservation flow.

## Observability

- **Logs**: `journalctl -u workoutdb-server -f` — JSON-structured in prod, plain in debug mode. Every request carries a `request_id` log field and `X-Request-ID` response header for client-side correlation.
- **Health**: `/health` is unauthenticated and cheap; `/health/ready` does a DB round-trip and returns the schema version.
- **Metrics**: none built-in. Add Prometheus or similar only when the need is real — for a single user it usually isn't.
