# Setmark

Setmark is a workout system built on the **"dumb app, smart conversation"** philosophy:

- **Claude is the brain.** Programming, periodization, progression, alternatives, and readiness all happen in conversation.
- **The app is dumb.** It shows the workout, times it, logs what happened. Nothing more.
- **The home server is the exchange layer.** Claude pushes plans in; the app pulls plans and pushes results back.

## Monorepo layout

- `server/` — Python + FastAPI + SQLite home server (schema, API, sync)
- `app/` — SwiftData iOS app (the dumb client)
- `schema/` — shared schema definitions between server and app
- `docs/` — architecture, testing contract, and the v2 spec
- `tests/` — server tests (iOS tests live in `app/`)

Internal repo, package, and server identifiers still use the original
`WorkoutDB` / `workoutdb` names unless changing them would affect the product
surface.

## Status

**Pre-v0.** Architecture is specced and accepted. Implementation has not started yet. See `docs/specs/v2-architecture.md` for the full target; see `docs/ARCHITECTURE.md` for the system map.

## Agents

Start at `AGENTS.md` (root) or `docs/AGENTS.md` (docs navigator).
