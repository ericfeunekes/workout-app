# WorkoutDB — Handoff

This is the top-level index for continuing this design. Another Claude (or engineer) should start here.

## Architecture (important)

**Programs are authored upstream.** The user does not build programs in-app. The workflow is:

1. User collaborates with Claude (via API / local server) to draft programs
2. Drafts live in a local/server database
3. The app connects to that server address and syncs down what to do today

Implications:
- **No auth** — the server address IS the identity
- **No program picker, builder, or library in-app** — all authored upstream
- **No body weight logs, no charts in-app** — ask Claude upstream for analysis
- **App is a logging/execution client**, not a management tool
- **History IS in-app** — because you need yesterday's RIR and load to execute today properly

## What this is

A mobile-first workout logger, opinionated about programming. Key differentiators:

- **Autoregulation** — load auto-adjusts based on RIR (Reps In Reserve) feedback
- **Multiple training modes** — straight sets, supersets, EMOM, AMRAP, for-time, intervals, tabata, continuous, custom, rest blocks
- **RIR-first** — not RPE. Simpler scale, matches how strength athletes actually think
- **Watch-first workflow** — most interactions happen on the watch during the set; phone is for logging, setup, review
- **Forgiving logging** — catch-up flow if you forget to log sets; tap to edit anything, any time

## The core loop we've designed to hi-fi

`Today → Active set → Rest → (repeat) → Complete`

Scheme: **straight_sets** only. Workout: Push A (bench, row, OHP, dip).
Every other scheme is wireframed but not built.

## Files — where to find what

| File | Purpose | Status |
|---|---|---|
| `WorkoutDB Hi-Fi.html` + `src/hifi.jsx` + `styles/hifi.css` | Hi-fi interactive prototype of the core loop | ✅ Working |
| `WorkoutDB Wireframes v2.html` | Wireframes — RIR-first, covers modes, prescription, watch, history, first-run. **Primary reference for un-built flows.** | ✅ Canonical |
| `_archive/WorkoutDB Wireframes v1.html` | Superseded · ignore unless archaeology | Archive |
| `components/*.jsx` | Wireframe component source (used by the Wireframes HTMLs) | Reference |
| `styles/wireframe.css` | Wireframe visual language (greybox) | Reference |
| `HANDOFF.md` | This file | — |
| `BACKLOG.md` | What's done, what's next, open questions, out-of-scope | Start here after this file |
| `RULES.md` | Behavior/logic rules extracted from the prototype | Must-read before extending |
| `FLOWS.html` | Visual map of every screen and how they connect | — |

## Recommended read order

1. **This file** — you are here
2. **`BACKLOG.md`** — the task list
3. **`FLOWS.html`** — the map
4. **`RULES.md`** — the rules, so you don't re-derive them wrong
5. **`WorkoutDB Wireframes v2.html`** — every screen that isn't hi-fi yet
6. **`WorkoutDB Hi-Fi.html`** + source — the reference for visual style, components, interaction patterns

## Principles

- **The app is a client, not a CMS.** Programs, exercise DB, analytics all live upstream. The app executes and logs.
- **Tap to edit any value, any time** — no separate edit modes. Load, reps, RIR, set count, plan values, past values — all tappable.
- **Autoreg is advisory, not prescriptive** — user can override, user can disable ("hold") per exercise.
- **Past edits don't retrigger autoreg** — they correct the record.
- **Persist everything** — cursor, log, route, note all survive reload.
- **RIR not RPE** — 0 = failure, N = N reps left in the tank.
- **No motivational copy** — this is a tool, not a coach.
