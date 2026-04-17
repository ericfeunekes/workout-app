# iOS App

SwiftData (SQLite) + native iOS. The "dumb app" — shows the workout, times it, logs what happened. No programming logic, no exercise selection, no progression.

See `docs/specs/v2-architecture.md` for the philosophy and the data model the app mirrors from the server.

## Layout (target)

Xcode project to be added. The app mirrors the server's schema in SwiftData, pulls workouts/exercises/alternatives/user_parameters on refresh, and pushes completed set logs + status changes.

## Key responsibilities

- Read `block.timing_mode` and drive the right timer UI (see the 10 timing modes in the spec).
- Resolve `percent_1rm` prescriptions against `user_parameters`.
- Let the user swap exercises to pre-computed alternatives.
- Work fully offline; queue pushes for next sync.
