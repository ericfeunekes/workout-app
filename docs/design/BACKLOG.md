# Setmark Design Backlog

Design backlog for prototype and visual-design follow-up. It is not the active product tracker; use `docs/spec.md` for feature status and `docs/bugs.md` for open QA issues.

---

## ✅ Done — hi-fi interactive

The core straight-sets workout loop.

### Screens
- **Today** — workout card, exercise list, last-session chip, start button
- **Active set** — load/reps/RIR entry, numpad sheets, RIR picker, last-time chip, longpress-to-swap (stub sheet)
- **Rest** — countdown timer, just-logged summary, autoreg proposal card, edit-last-set affordance, next action
- **Complete** — ledger summary per exercise (tappable to expand), dictation note field, save & done

### Interactions
- **RIR autoreg** — overshoot/undershoot rules, apply to remaining sets, user can hold
- **Tap-to-edit past sets** — any done row, any cell (load/reps/RIR), corrective only — no autoreg rerun
- **Tap-to-edit pending sets** — load/reps cells on upcoming rows, opens numpad sheet
- **Plan sheet** — Today → tap exercise → edit sets/reps/load for this session, add/remove sets, start from here
- **History drawer** — Today's "Last session" chip → all recent sessions; Active's "Last time" chip → filtered to this exercise
- **Numpad variants** — simple, scoped (this set vs remaining), RIR picker
- **Persistence** — log, cursor, route, note all survive reload
- **Tweaks panel** — rest style, load display, RIR input style, show/hide last-time, accent color

### Design system surface
- Dark theme, terracotta accent, IBM Plex Mono + Inter
- Device frame, status bar, tab bar (decorative)
- Sheet + backdrop pattern
- Ledger (load/reps/RIR grid) component
- Card, button (primary/ghost), chip, keypad
- App icon master + generated iOS app icon catalog
- Exercise/block icon SVG grammar + SwiftUI DesignSystem primitive

---

## 📐 Wireframed — see `Wireframes v2.html`

These have been thought through at wireframe fidelity. Not hi-fi yet. Claude should reference them before designing from scratch.

### Workout schemes (beyond straight sets)
- Superset — NEXT-only, defer logging to rest
- Circuit — single NEXT per round
- EMOM — timed, post-round log
- AMRAP — station-by-station `next`, partial-station picker on end
- For Time — big NEXT on group complete
- Intervals — work/rest cycles
- Tabata — fixed 20/10
- Continuous — Z2 ride, HR-centric
- Custom — multi-segment
- Rest block — standalone timer

### Rest variants
- Inline rest (bottom sheet over active)
- Catch-up rest (missed sets flow)
- Section context

### Swap / substitution
- Longpress on active exercise → swap menu
- Swap sheet (exercise picker)

### Completion variants
- Review RIR (post-workout)
- Group edit (expand exercise, edit all sets at once)

### Watch faces
- Set face (current set / target)
- Rest face (countdown)
- Superset face (single + dual-action)
- EMOM face (round counter)

### Prescription display
- Per-scheme RIR card (what each mode shows for Rx)

### Onboarding / first run
- FirstRun screen

### Connectivity
- Today, quiet-offline state (offline as a pill, not a banner)

### History
- List view
- Session detail view
- Exercise history detail (in hi-fi via the drawer — other views still wireframed)

---

## 🟡 Next up — candidates to promote to hi-fi

Ranked by value for a v1 ship. Pick top 3-4.

1. **Superset flow** — the #2 most-used scheme for strength training after straight sets
2. **Onboarding / first run** — without it, the product has no start
3. **Program picker / browser** — how do users get to a workout in the first place? Currently Today just shows "Push A"
4. **Exercise swap** — longpress interaction is stubbed in hi-fi, needs real picker
5. **History** — session list + detail
6. **EMOM / AMRAP** — popular conditioning modes
7. **Settings / account** — minimum viable surface

---

## 🔜 TODO — not designed at any fidelity

**Blocking for v1**
- **App launch / cold start / sync states** — what you see when the app opens, server-connecting states
- **Rest day / nothing-scheduled screen** — Today when there's no workout
- **Settings** — server address, watch pairing, units, reset local data, autoreg defaults

**Important**
- **History surface (full)** — list, session detail, per-exercise chart (the drawer covers the inline case)
- **Week peek** — tap from Today to see the rest of this week's planned sessions
- **Watch hi-fi** — v2 wireframe exists; promote to hi-fi because the surface is different enough

**Dropped from scope** (upstream via Claude)
- Program picker / builder / library — authored upstream, synced down
- Exercise library — upstream DB
- Body weight log — ask Claude
- Per-exercise charts beyond the in-app history view — ask Claude
- Auth — none; server address is identity
- Program detail as a full browser — replaced by light week peek

**Nice-to-have, not blocking**
- Plate math / warmup calculator
- Deload prompts / fatigue detection
- Notifications / reminders
- Data export (app is the source of truth for logs; user can dump via server)

---

## ❓ Open questions

All program-authoring / auth / library questions from before are **resolved by the upstream-Claude model**. What's left:

1. **Sync cadence** — on app open only? Periodic? On every log write? (Recommend: on open + on log write, with retry queue for offline)
2. **Conflict resolution** — if the user logs a set, then the server re-publishes a different prescription for that session mid-workout, what wins? (Recommend: live session is frozen; changes apply to next occurrence)
3. **First-run server connection** — QR code? Paste URL? Both?
4. **Watch — paired or independent?** — does the watch talk to the server directly, or only to the phone?
5. **RIR 0 meaning** — failure vs. just-barely. Affects autoreg undershoot.
6. **Exercise swap persistence** — if I swap mid-workout, does it persist to next week? (Probably: logs reflect what was done; prescriptions come from server next time. So no local persistence.)
7. **"Hold autoreg" scope** — this exercise / this session / until re-enabled?

---

## 🚫 Out of scope for v1

Be explicit so Claude doesn't build these.

- Social features (follow, share, comment, leaderboards)
- AI coach / AI program generation
- Nutrition, hydration, sleep tracking
- Wearable pairing beyond the single watch face (no HRV, no recovery scores)
- Marketplace / paid programs
- Video demos for exercises (placeholder only)
- Multi-language — English only
- Dark/light toggle — dark only (reflects gym lighting)
