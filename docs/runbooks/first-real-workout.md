---
title: Critical path to the first real workout
status: living
purpose: The steps between "the codebase is ready" and "Eric completes a real workout logged to his server." Everything below is a human action or a decision; everything above is already shipped.
covers:
  - server/
  - app/
  - docs/infrastructure/home-server.md
---

# Critical path to the first real workout

This is the list of things that must happen outside the codebase before the system is exercised end-to-end. Each step is **Eric-action** (requires a decision or credential only Eric has) or **Claude-action** (can be done autonomously once the prior steps are clear). Tracked here so the hand-off from "build" to "use" is explicit.

## Current state (as of this doc)

- iOS app builds for iOS Simulator, renders Today / Active / Rest / Complete / FirstRun / History / Settings end-to-end.
- watchOS target builds and shows three stub faces (further watch work on hold per `docs/open-questions.md`).
- Server builds, 120 tests pass, migrations idempotent, push + pull protocols fully specified and tested.
- Architecture enforcement live: ruff, import-linter, SwiftLint strict, fitness-function structural tests.
- Deployment runbook drafted; `make deploy` stubbed with the intended flow; `make db-backup` + `make server-status` + `make server-logs` functional today.

## Remaining gates between now and first real workout

### 0. Push-queue wiring (Claude-action, in flight)

The last v1 functional gap. Completed logs currently stay in-memory; after this slice lands, logging a set enqueues it to `PushQueue` and the flusher drains to the server.

**Blocks:** everything below. You cannot complete a real workout without it.

### 1. Systemd unit scope decision (Eric-action, ~1 minute)

See `docs/open-questions.md` § "Systemd unit scope — user vs system (server deploy)". Two viable options:

- **User-scope** (`systemctl --user`, `loginctl enable-linger workoutdb`, `/opt/workoutdb/current/.venv/...`): matches the release-dir layout in `docs/infrastructure/home-server.md`, no `sudo` in deploy path, logs via `journalctl --user`.
- **System-scope** (`systemctl`, `User=workoutdb` in unit file, `WantedBy=multi-user.target`): matches the existing checked-in `deploy/workoutdb-server.service`, survives lingering edge cases, but requires `sudo` for every operation.

Eric picks. Claude updates either the unit file OR the docs to match.

### 2. First-time server bootstrap (Eric-action, ~20 minutes)

Follow `docs/infrastructure/home-server.md` § "First-time server bootstrap":

1. Provision a machine on the Tailscale mesh (already done per earlier conversation — your "other machine").
2. Install `uv`.
3. `mkdir -p /opt/workoutdb/shared/db /opt/workoutdb/releases`.
4. Generate a bearer token (`openssl rand -hex 32`) and write to `/opt/workoutdb/shared/.env` as `WORKOUTDB_BEARER_TOKEN=...`.
5. Drop the systemd unit per the decision from step 1, `systemctl enable --now workoutdb-server`.
6. Confirm `curl http://localhost:<port>/api/version` returns `{"version":"..."}` from the server.

Once these steps pass, the server is ready to accept pushes from the app.

### 3. `make deploy` flesh-out (Claude-action)

Currently `make deploy` prints the planned flow. After step 1 is decided, Claude fills in the real shell: ssh + git clone to release dir + uv sync + DB backup + migrations + symlink flip + systemctl restart + verify + rollback-on-fail.

**Time:** ~30 minutes of scripting, with an end-to-end dry run against the Tailscale host. Scope-creep risks: retry/backoff policy, release pruning, migration-failure rollback — all documented in the runbook but worth keeping minimal for the first pass.

### 4. Apple Developer Team ID paste (Eric-action, 30 seconds)

`app/project.yml` has `DEVELOPMENT_TEAM: ""`. Replace with Eric's 10-character team ID, re-run `make xcodegen`.

Without this, device deploy (next step) fails with a signing error. Simulator builds don't need it.

### 5. Device install via Xcode (Eric-action, ~5 minutes)

1. Plug iPhone into the Mac.
2. Open `app/WorkoutDB.xcodeproj` in Xcode.
3. Select the WorkoutDB target, choose "Signing & Capabilities", confirm the team ID picked up.
4. Select the phone as the destination.
5. Cmd-R. Xcode builds + installs + launches.
6. First launch on the phone: trust the developer certificate under iOS Settings → General → VPN & Device Management → Developer App.

### 6. First-run connection (Eric-action, 30 seconds)

In the installed app:
1. FirstRunView welcome screen appears.
2. Paste server URL (`https://<tailnet-host>`) and bearer token from step 2.
3. Tap "connect". App validates + persists to keychain + pulls initial workouts.

At this point the app is live against the real server.

### 7. Claude authors a workout (Eric-action via conversation, ~5 minutes)

1. Start a conversation with Claude (outside this repo's agent sessions).
2. Claude calls `POST /api/exercises` + `POST /api/workouts` against the server with a real Push A / Pull A / etc. session.
3. App pulls on next foregrounding; Today shows the new workout.

See `docs/prescription.md` for the authoring vocabulary Claude uses.

### 8. First real workout (Eric-action, 45–90 minutes in gym)

Execute the workout. Every set tap logs to `SessionState`, enqueues to `PushQueue`, pushes to server. Rest timer runs. Autoreg fires. On complete, status update + any residual set logs flush to the server.

Post-workout: verify via `curl https://<host>/api/workouts/<id>` that set_logs landed with correct rir / weight / reps / performed_exercise_id.

### 9. Post-workout feedback cycle (Eric-action, variable)

Eric reviews the real usage for friction points. Findings land in `docs/open-questions.md`. Claude addresses in the next session. This is the feedback loop that justified holding further watch work until now — real iOS UX patterns inform watch UX patterns.

---

## What's NOT on this list (intentionally deferred)

- Watch real wiring beyond the stub (watch hold per `docs/open-questions.md`; revisit after step 9).
- CI/CD for the server (per WORKFLOW.md — no CI/CD pipeline, single-user, home server on Tailscale).
- TestFlight distribution (Eric is the only user; direct Xcode install suffices).
- History's corrective-edit sheet (stubbed; fill in after first round of use).
- Settings UI entry point from a specific place in the app (currently reachable only via the tab bar in `RootTabView`).
- Multi-user / sharing surfaces.
- Unified QR connection-string format (FirstRun uses two fields today; fine).

Each of these has its own entry in `docs/open-questions.md` with a disposition.

## The explicit decision list

Eric, before the first real workout:

- [ ] Decide systemd scope (step 1 — user vs system).
- [ ] Bootstrap the server machine (step 2).
- [ ] Paste Apple Developer Team ID into `app/project.yml` (step 4).
- [ ] Install the app on the physical phone (step 5).
- [ ] Trigger Claude to author the first workout (step 7).
- [ ] Run the workout (step 8).

Claude, in between:

- [ ] Finish push-queue wiring (step 0, in flight).
- [ ] Flesh out `make deploy` after step 1 decided (step 3).
- [ ] Drive end-to-end simulator verification of the tap-through path (still pending — will run after push-queue slice lands).
- [ ] Final cross-link sweep of docs after the last wave of changes.
- [ ] Stage a commit that groups the four waves sensibly so git history reflects the delivery cadence.

---

## Why this runbook exists

So the hand-off from build to use is explicit. The codebase can get to "alpha-ready" autonomously; the step from "alpha-ready" to "first real workout" requires credentials and physical hardware that only Eric controls. Lists the thin sequence so no step slips.
