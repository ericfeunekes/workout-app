---
title: iOS app
status: draft
purpose: What the app does, how it behaves, and what it owes the rest of the system. The iOS app is a local-first renderer + logger; it does not reason about programming.
covers:
  - app/
---

# iOS App

SwiftData (SQLite) + native iOS. The "dumb" client — shows the workout, times it, logs what happened. No programming logic, no exercise selection, no progression, no analysis. All of that lives in conversation with Claude and arrives via the server.

See also:
- `docs/specs/v2-architecture.md` — the entity schema.
- `docs/prescription.md` — the authoring vocabulary Claude uses to compose prescriptions the app reads.
- `docs/sync.md` — sync cadence, conflict rules, first-run UX.
- `docs/design/` — the Claude Design handoff (wireframes, hi-fi prototype, rules). Reference, not spec.
- `docs/decisions/ADR-2026-04-17-rir-autoreg-sync.md` — why RIR, autoreg, and the connection-string first-run UX.

## Status

Xcode project is generated from `app/project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `app/WorkoutDB.xcodeproj/` is gitignored — `project.yml` is the source of truth. CI for iOS is deferred until active feature work lands (see `docs/WORKFLOW.md`).

## First-time setup

```bash
# 1. Install Xcode.app from the App Store (~15GB). Required for iOS / watchOS SDKs.
#    CLT alone is enough for swift-build of Core/Sync packages, but not for the app.

# 2. Point xcode-select at the full Xcode install:
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept

# 3. Install XcodeGen (generates the .xcodeproj from app/project.yml):
brew install xcodegen

# 4. (Optional) Install SwiftLint so the pre-commit hook activates the app
#    architectural rules (FF-13/14/15):
brew install swiftlint

# 5. Generate the Xcode project:
make xcodegen

# 6. Open in Xcode:
open app/WorkoutDB.xcodeproj
```

In Xcode's Signing & Capabilities panel, set your Apple Developer Team. The simulator build works without one; device deploy requires it. Re-run `make xcodegen` after any change to `app/project.yml` or when adding a new SwiftPM package.

## Verify without Xcode

Core + Sync packages build and test on Command Line Tools alone:

```bash
make test-core   # runs all Core + Sync Swift package tests
```

## Agent-driven iOS loop

When a coding agent (Claude Code / Codex CLI) needs to build, launch, interact, and screenshot the iOS app, see `docs/ios-dev-loop.md`. The recommended tool is **XcodeBuildMCP** (npm package; one-time install + Xcode 26.3+ MCP bridge enable). Without it, the fallback stack is `xcrun simctl` + screenshot + `Read` + `#if DEBUG` launch-arg route jumps (`--start-active`, `--jump-rest`, `--jump-complete`).

## Layout (target)

The app mirrors the server's schema in SwiftData, pulls workouts/exercises/alternatives/user_parameters on refresh, and pushes completed set_logs + status changes. A WatchKit companion ships in v1 for HR, haptics, and start/end-set. The full watch face grammar is deferred to v1.1+ (`docs/design/src/watch-grammar.jsx` is the target).

## Core loop

```
Today  →  Active set  →  Rest  →  (repeat)  →  Complete
```

- **Today.** Workout card (program name, duration estimate, exercise list), "last session" chip, start button. Exercises are tappable — tapping opens a plan sheet for session-local edits (adjust sets, reps, load, add/remove sets, "start this exercise" jumps to the first pending set). History drawer accessible from the "last session" chip (recent sessions, per-exercise filter).
- **Active set.** Exercise name, prescription (load × reps × set counter), inline `adjust` glyph (↑ ↓ ✎) when load differs from the block default. Load and reps cells are tap-editable (opens a scoped numpad: "this set" vs "remaining sets"). Longpress on the exercise opens the swap / adjust / change-rest menu. HR and last-time chips are present.
- **Rest.** Ring countdown. Just-logged set shown as editable pills (load, reps, RIR). RIR picker opens on the RIR pill. Autoreg proposal banner (↑/↓ direction, new load, reason) if the rules fired; user taps ✓ to accept (default — already applied) or Undo to revert and hold autoreg for the session. Edit-last-set affordance. Next-action button advances.
- **Complete.** Ledger per exercise (tappable to expand, edit, add sets), workout-level note with dictation mic, "save & done" clears the local session and returns to Today.

## Prescription execution

The app reads `block.timing_mode`, `block.timing_config_json`, and each `workout_item.prescription_json` and drives the right timer UI. The full per-mode vocabulary is in `docs/prescription.md`. Summary of modes: `straight_sets`, `superset`, `circuit`, `emom`, `amrap`, `for_time`, `intervals`, `tabata`, `continuous`, `custom`, `rest`.

The app does not validate prescriptions — malformed shapes fail at execution time when a required key is missing. Claude and the app agree on shape via `docs/prescription.md`; if the app needs a new shape, the doc changes in the same commit.

## Autoregulation

Claude attaches a `target_rir` and an `autoreg` subobject to load-bearing items in `prescription_json`. The app applies them client-side (`docs/prescription.md` § "Autoregulation" for the full rules). Key invariants:

- Autoreg triggers **after** a set is logged, on the rest screen.
- Proposals apply to **remaining** sets in the current item.
- User **Undo** sets a session-scoped `autoregHeld` flag on the item — no further autoreg fires on that item this session. The flag clears on completion.
- **Undo reverts forward, not retroactively.** Remaining sets that the user hasn't manually edited revert to the pre-proposal load. Sets the user manually edited after the proposal keep their manual value.
- **Manual edits win over autoreg.** If autoreg bumped set 3 (`adjust="up"`) and the user manually edits set 3's load, the manual value takes over and `adjust` becomes `"manual"`. Once a set's `adjust` is `"manual"`, subsequent autoreg passes do not overwrite that set.
- Editing a **past (logged) set** is **corrective** — it does not retrigger autoreg. A set counts as "past" once `done=true`. Edits to a pending (not-yet-logged) set are planning adjustments and mark the set `"manual"`.
- The per-set `adjust` field is local session state, surfaced as an inline glyph on current/pending rows. It is not persisted to the server — the set_log records the logged values; the adjustment narrative is derivable from the prescription.
- **RIR is optional on log.** The user can skip RIR; the set logs with `rir=null`. Autoreg overshoot cannot fire when RIR is null, but reps-based undershoot still can.

## Tap-to-edit

Every value in the UI is tappable.

| Surface | What opens | Effect |
|---|---|---|
| Past (logged) set load/reps cell | Numpad | Corrective. No autoreg. |
| Past set RIR cell | RIR picker | Corrective. No autoreg. |
| Pending set load/reps cell | Scoped numpad ("this set" vs "remaining") | Marks `adjust: "manual"`. |
| Pending set RIR cell | — | Not tappable; no RIR exists until logged. |
| Today → tap exercise | Plan sheet (per-set grid, add/remove sets, "start this exercise") | Session-local; template not mutated. |
| Completion ledger row | Group editor | Corrective edits to that exercise's set rows; per-exercise note. |

The subtitle in each sheet reflects whether the edit is corrective ("no autoreg") or a planning adjustment ("just this set").

## Swap

Longpress on the active exercise opens a menu: Swap / Adjust load / Change rest / Skip set / Cancel. Swap presents pre-computed `exercise_alternative` rows (with their recency in history). Tapping an alternative substitutes the exercise for the remainder of the session; the `set_log.performed_exercise_id` records the alternative's UUID. The `workout_item` and workout template are unchanged. Next session's prescription comes from the server unmodified.

## Offline

Offline is the default assumption, not an error. A neutral `· offline` pill appears next to the status bar; during retries it becomes `↻ syncing…`. Workouts execute fully from the local cache. Logs write locally and queue for push; the push retry loop flushes every ~60s while foregrounded. A workout completed entirely offline syncs cleanly on next connection.

## First-run

The app on first launch requires a **connection string** (server URL + bearer token) entered by paste or scanned via QR. There is no login. On success, the token lives in the keychain; the URL in `UserDefaults`. First sync runs and lands the user on Today. See `docs/sync.md` § "First-run UX" for the full flow.

## Persistence (local session)

During a live session the app persists session state so a reload is seamless:

| Store | Contents |
|---|---|
| Log | Per-item sets: `load, reps, rir, done, adjust` |
| Cursor | `{block_idx, set_idx}` — where the user is |
| Route | `today \| active \| rest \| complete` |
| Note | Workout-level free-text / dictated note |
| `autoregHeld` | Per-item session-scoped flag |
| Rest timer | Absolute `rest_ends_at` timestamp (not elapsed) so reload re-derives remaining time without drift |

Everything survives reload. On "save & done" (completion), session state clears and the session flushes to the server.

## Auth failure UX

A 401 from any server call is treated as "token rejected," not a transient error. The app surfaces a distinct prompt ("Token rejected — re-scan QR or paste a new connection string") and pauses the push queue until re-authentication. Silent retry does not apply to 401. Network timeouts and 5xx errors do use silent retry.

## Body weight

The completion flow optionally captures body weight. If the user enters it, the app pushes a `user_parameters` row with key `bodyweight_kg`, the entered value, and the completion timestamp. Body weight is a user_parameter, not a column on `workout`.

## History

Two surfaces:

1. **In-workout drawer** — the "last session" chip from Today (and the "last time" chip on Active) opens a tall sheet with recent sessions, filterable to one exercise. This is live decision support during a workout; it must work offline.
2. **Full history tab** — reverse-chronological session list, grouped by week, filterable by split. Tap a session → detail view with all set rows (editable, corrective). Pivot to "by exercise" → exercise picker → minimal per-exercise view (top-set trend indicator, recent sessions as mono rows).

What the app deliberately does **not** show: charts beyond the per-exercise top-set trend indicator, body-weight trend lines, volume/RIR heatmaps, PR detection, percentile comparisons. Those analyses happen in conversation with Claude (who has access to the full raw history via the server).

## Watch (v1 scope)

- Haptic on timer transitions (rest end, EMOM tick, interval transitions, tabata buzzes).
- Record HR into set_log via HealthKit (`hr_avg_bpm`, `hr_max_bpm`).
- Record cadence silently during runs (`cadence_avg_spm`) — no live target display in v1.
- Start/end a set from the watch (writes `started_at` / `completed_at`).

The watch talks to the iPhone via WatchConnectivity; the iPhone is the sole server actor. Pairing is handled by iOS.

## Watch (deferred to v1.1+)

- Full face grammar (widget-based set / rest / superset / EMOM / AMRAP / for-time / intervals / cardio faces). Target: `docs/design/src/watch-grammar.jsx` and `docs/design/src/watch-hifi-v2.jsx`.
- Live cadence / pace targets on the watch.
- Tempo haptic pulses cueing phases during tempo lifts.
- Raw motion capture (power, bar-speed, bar-path). `set_log.motion_samples_ref` is reserved for when this lands.

## What the app must never do

- Choose exercises, decide programming, or infer stimulus. All programming is upstream of the app, via Claude.
- Compute PRs, volume trends, or progression. That's conversation.
- Reason about muscle groups, movement patterns, or equipment taxonomies. None of those exist in the app.
- Keep a program library / picker / builder. Programs are authored upstream.
- Present charts beyond the minimal per-exercise top-set indicator.
- Depend on network during a workout. Offline-first is load-bearing.
