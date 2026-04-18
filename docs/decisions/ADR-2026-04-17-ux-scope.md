---
title: UX scope decisions for v2
status: accepted
date: 2026-04-17
covers:
  - docs/specs/v2-architecture.md
  - server/
  - app/
---

# ADR: UX scope decisions for v2

## Context

The v2 architecture spec (`docs/specs/v2-architecture.md`) was accepted, but four UX ambiguities blocked concrete technical choices for auth, multi-tenancy, query API shape, and wearables integration. A scoped UX-only interview on 2026-04-17 resolved them. This ADR records the UX answers, the technical implications, and the direction to build.

## Decisions

### 1. Network reach: the app must work anywhere

**UX answer:** Eric uses the app at home, at a commercial gym, and while travelling. The server must be reachable wherever his phone is.

**Implication:** The server cannot be a LAN-only service, but also shouldn't be publicly exposed (single-user system, home hardware, no desire to run public TLS + hardened auth).

**Technical direction:**
- **Tailscale mesh VPN.** Server runs on home hardware and joins a tailnet. The iPhone joins the same tailnet. The app reaches the server via its tailnet hostname — no port forwarding, no public cert management, no CDN, no cloud hosting.
- **Single bearer token auth** over the tailnet. The tailnet handles identity at the network layer; the token just distinguishes app traffic from random tailnet traffic.
- **Offline-first behavior during a workout is an invariant.** Cell service fails, gym WiFi fails, hotels do weird DNS things. The app must execute a fully-pulled workout with zero network calls. Results queue locally and push on next connectivity. This is already in the spec; this ADR promotes it to a load-bearing invariant.

**Rejected alternatives:** Cloudflare Tunnel (extra moving parts — edge auth, DNS, tunnel config — for no benefit given single-user). Cloud-hosted server (defeats the "home server" design and adds cost). Direct port-forward (exposes Python server to the internet).

---

### 2. Multi-tenancy: schema is multi-user, auth stays single-user

**UX answer:** Eric is the only user day-one. His wife is a someday-user, friends are hypothetical. No one needs access now.

**Implication:** Fully single-user auth today, but don't make choices that paint us into a corner when a second user appears.

**Technical direction:**
- **Schema already multi-user.** Every entity has `user_id` FKs per the spec. Keep it. No "implicit user" shortcuts.
- **Single bearer token today.** Token maps to Eric's `app_user` row. API endpoints resolve `user_id` from the token, not from a query param.
- **Adding a second user later =** create another `app_user` row, issue another bearer token. No invite flow, no account provisioning UI, no visibility sharing, no OAuth, no Apple Sign In.

**Rejected alternatives:** Apple Sign In day-one (overkill for single-user). Per-user login UI day-one (same). Implicit-single-user shortcuts (painful migration later).

---

### 3. App history: show what I need during a workout + a simple history tab

**UX answer:** While working out, Eric wants to see his last performance of the current exercise inline (load, reps, effort) — live decision support. Outside a workout, he wants a history tab of recent completed workouts and their set_logs. No graphs, no PR analytics, no trend charts in the app. *(Effort field was decided later to be RIR 0–5, not RPE 6–10 — see `ADR-2026-04-17-rir-autoreg-sync.md`.)*

**Implication:** Two distinct queries. The inline "last time" must be available offline during a workout (can't depend on network). The history tab can be online-only.

**Technical direction:**
- **Piggyback `last_performed` onto `GET /api/sync/pull`.** For every exercise in the pulled workouts, include a `last_performed` snapshot: most recent set_logs + the prescription from that set. App caches this with the workout. Zero extra roundtrips during the workout.
- **`GET /api/workouts?status=completed&limit=N&offset=M`** for the history tab. Extends the spec's existing list endpoint. Returns workouts with nested set_logs eager-loaded.
- **No aggregation endpoints** (1RM estimates, volume-over-time, PR detection). Claude does that in conversation by reading raw set_logs.

**Rejected alternatives:** Separate `GET /api/exercises/:id/last-performed` (extra roundtrip during workout, breaks offline-first). Full history sync to device (unbounded growth).

---

### 4. Apple Watch: haptic + HR + easy set start/end

**UX answer:** Eric wants the watch to (a) buzz when timers end (rest, EMOM, interval), (b) record HR into set_logs automatically, and (c) make starting and ending a set very easy — tap to start, tap to end, without pulling the phone out.

**Implication:** The watch is part of the v1 app, not an optional later add-on. The `set_log` schema needs to capture the set's start time (not just completion) and HR. The watch and phone share state via WatchConnectivity; the server sees them as one client.

**Technical direction:**
- **Watch is in-scope for v1.** Update `docs/specs/v2-architecture.md` to make this explicit. WatchKit companion app under `app/`.
- **`set_log` schema additions:**
  - `started_at Timestamp?` — when the user tapped "start set" (or the set began in timed modes)
  - `hr_avg_bpm Integer?` — average HR during the set
  - `hr_max_bpm Integer?` — peak HR during the set
- **`hr_samples_json` deferred.** Avg + max is enough until Claude asks for HR curves.
- **Haptic buzz at timer transitions** is a phone-app concern using WatchConnectivity. No server change.
- **Start/end set on watch:** watch toggles `started_at` / `completed_at` on the active set in local SwiftData. Rest timer (mode-driven) auto-starts on set end.

**Rejected alternatives:** `hr_samples_json` with full timeseries (premature — no caller). Watch as an independent sync client (double roundtrip problem — phone and watch race to push the same set). Full-logging-from-watch without a phone (too ambitious for v1; watch-first is "easy set start/end + HR", not "replace the phone").

## Spec updates this ADR drives

These changes get applied to `docs/specs/v2-architecture.md`:
1. `app_user` and auth section: note bearer-token-over-Tailscale design; multi-user-later is explicit.
2. `set_log` entity: add `started_at`, `hr_avg_bpm`, `hr_max_bpm` fields.
3. API contract: add `last_performed` payload to `GET /api/sync/pull` response; note `?status` + pagination on `GET /api/workouts`.
4. New section: "Offline-first invariants during a workout" (promoted from implicit to load-bearing).
5. Build order / scope note: Apple Watch companion is part of v1 app, not a future enhancement.

## Done when

- This ADR is committed.
- `docs/specs/v2-architecture.md` is updated with the five changes above.
- Root `AGENTS.md` has a one-liner invariant: "App must execute a fully-pulled workout with zero network calls."

## Out of scope

- Multi-user provisioning UI, invite flows, shared visibility
- Cloud hosting / public internet exposure
- HR sample curves, PR analytics, trend charts in the app
- Watch-only logging without a phone present
- Nutrition, body photos, readiness assessment (these stay in conversation with Claude per v2 philosophy)

## Open questions

None that block implementation. When a second user (likely Eric's wife) is added, revisit multi-tenancy to decide whether bearer tokens need rotation/scoping beyond "one token per user_id".
