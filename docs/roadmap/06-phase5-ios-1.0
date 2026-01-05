# Phase 5 — iOS 1.0 (full application)

## Objective
A fast iOS client for:
- browsing the library
- following a scheduled workout
- logging sets/results
- capturing minimal stimulus check-ins
- syncing data

## Suggested scope (v1.0)
### Must-have
- Authentication (if cloud sync exists) OR device-only mode
- Workout library browser (templates + tags + search)
- Today view (planned workout)
- Workout execution:
  - shows blocks/items
  - quick set logging
  - end-of-block check-ins (2–3 taps)
- History view (sessions)
- Export/share (JSON and/or CSV)

### Should-have
- Substitution suggestions when equipment is missing/busy
- Simple personalization:
  - remember last-used loads
  - progression suggestions (very light rules)

### Could-have
- Wearable/sensor import (heart rate)
- Cloud multi-device sync
- Gym mode / trainer mode

## Architecture notes (keep flexible)
- Prefer a clean boundary:
  - “Workout Core” (data + rules) usable by both CLI and iOS
  - iOS UI as a separate module/client
- Sync options (choose later):
  - local-only SQLite in app
  - iCloud/CloudKit
  - your own backend API

## Definition of done (v1.0)
- A user can complete a scheduled workout end-to-end on iPhone in < 30 seconds of total typing.