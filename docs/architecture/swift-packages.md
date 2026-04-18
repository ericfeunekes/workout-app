---
title: Swift package graph
status: accepted
date: 2026-04-17
purpose: The authoritative list of Swift packages, their responsibilities, and their declared dependencies. When the Xcode project lands, each Package.swift file mechanically implements a row here. Drift from this doc is an architectural regression, not a refactor.
covers:
  - app/
---

# Swift package graph

Every package is a local SwiftPM package under `app/Packages/`. The shell targets (`WorkoutDB/`, `WorkoutDBWatch/`) are thin — they compose packages and host the root view.

**Rule:** a package may only declare dependencies listed in its Row. Any other dependency is a compile-time error (SwiftPM enforces).

**Rule:** when a package is created, its `Package.swift` has to include `supportedPlatforms: [.iOS(.v17), .watchOS(.v10)]` if it appears in the Watch column. Core packages support both; edge packages vary.

| Package | Dependencies (may import) | Purpose | iOS | watchOS |
|---|---|---|:---:|:---:|
| `Core/Domain` | (none) | Plain Swift structs for the domain entities: `Workout`, `Block`, `WorkoutItem`, `SetLog`, `Exercise`, `ExerciseAlternative`, `UserParameter`. No SwiftData, no Foundation-network, no persistence. | ✅ | ✅ |
| `Core/Prescription` | `Core/Domain` | Per-shape parsers for `prescription_json` and `timing_config_json`. Returns typed `Result` values. No computation — parsers only. See HS-3. | ✅ | ✅ |
| `Core/Autoreg` | `Core/Domain`, `Core/Prescription` | Pure functions that compute autoreg proposals. `propose(prescribed:, logged:) -> AutoregProposal?`. No state, no I/O. | ✅ | ✅ |
| `Core/Session` | `Core/Domain`, `Core/Prescription`, `Core/Autoreg` | Live-session state machine. Cursor, route, log, `autoregHeld`, `adjust` field, `rest_ends_at`. An `@Observable` store. | ✅ | ✅ |
| `Core/Foundation` | (none) | Pure utilities shared across Core packages: `Clock` protocol, ID generation, kg↔lb conversion, duration formatting. The **only** shared-utilities package allowed. | ✅ | ✅ |
| `Core/Telemetry` | (none) | Pure value type `Event` + `TelemetryEmitter` protocol + process-stable `TelemetrySession.id`. Emitters are implemented in `Persistence`; the shape stays in Core so every layer can accept an emitter without pulling in storage. | ✅ | ✅ |
| `DesignSystem` | `Core/Foundation` (for formatting helpers only) | Visual tokens (colors, type ramp, spacing, motion) and primitives (button, chip, pill, ring, keypad). No routing, no business rules. | ✅ | ✅ |
| `schema` | (external — already at `schema/`) | Wire DTOs. Consumed only by `Sync`. | ✅ | ✅ |
| `Persistence` | `Core/Domain`, `Core/Prescription`, `Core/Foundation`, `Core/Telemetry`, `Sync` | SwiftData stack, migrations, keychain bearer-token storage, `UserDefaults` URL storage, and the SwiftData-backed `TelemetryEmitterImpl`. Exposes protocols (`SessionStore`, `WorkoutCache`, `TokenStore`) used by Features and Sync. | ✅ | ✅ |
| `Sync` | `Core/Domain`, `Core/Foundation`, `Core/Telemetry`, `schema`, `Persistence` | `PullService`, `PushQueue`, `ConnectionManager`. The only package that imports URLSession (enforced by SwiftLint FF-13). Maps DTOs → Domain at the boundary — nothing outside `Sync` imports `schema`. Push queue routes telemetry batches to `/api/telemetry/events`. See HS-1. | ✅ | — |
| `HealthKitBridge` | `Core/Domain`, `Core/Foundation` | HR, cadence, body-weight queries. Protocols exposed for Features; HealthKit imports confined here (FF-13). | ✅ | ✅ |
| `WatchBridge` | `Core/Domain`, `Sync` | iPhone ↔ Watch IPC via WatchConnectivity. Watch taps on "log set" travel through WatchBridge → Sync.PushQueue. | ✅ | ✅ |
| `Features/Today` | `Core/Domain`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence`, `Sync`, `HealthKitBridge` | Today screen: workout card, exercise list, last-session chip, plan sheet, history drawer. | ✅ | — |
| `Features/Execution` | `Core/Domain`, `Core/Session`, `Core/Prescription`, `Core/Autoreg`, `Core/Telemetry`, `DesignSystem`, `Persistence`, `HealthKitBridge`, `WatchBridge` | Active + rest screens, per-mode TimingDriver strategies (HS-2), RIR picker, numpad sheets, autoreg banner, swap sheet. | ✅ | — |
| `Features/History` | `Core/Domain`, `DesignSystem`, `Persistence`, `Sync` | History tab: list, session detail, by-exercise view. | ✅ | — |
| `Features/Settings` | `Core/Foundation`, `DesignSystem`, `Persistence`, `Sync`, `HealthKitBridge`, `WatchBridge` | Settings screen as data-driven sections (HS-4). | ✅ | — |
| `Features/FirstRun` | `DesignSystem`, `Persistence`, `Sync` | Welcome + connection-string entry + first-sync progress. | ✅ | — |
| `Features/WatchFaces` | `Core/Domain`, `Core/Session`, `DesignSystem`, `WatchBridge` | The watchOS faces (v1.1+ full grammar; v1 minimal: HR, rest countdown, start/end tap). | — | ✅ |
| `Shell` | `Core/Domain`, `Core/Session`, `Core/Foundation`, `Core/Telemetry`, `Persistence`, `Sync`, `Features/Today`, `Features/Execution` | Launch-time composition root: builds `SyncAPI`, runs `pullLatest`, writes to `WorkoutCache`, constructs `TodayViewModel` + `ExecutionViewModel`, threads the persisted `TelemetryEmitter` through each of them. The **one** package allowed to see multiple `Features/*` at once (that's its job). Lives at `app/Packages/Shell/` — **not** under `Features/` — because the SwiftLint rule `no_feature_cross_import` only covers the `Features/` directory. Thin: one `AppBootstrap` type, no SwiftUI views. | ✅ | — |

## Shell targets

| Target | Dependencies | Purpose |
|---|---|---|
| `WorkoutDB` (app) | All `Features/*` (iOS), `Shell`, `Persistence`, `Sync`, `Core/Session`, `DesignSystem`, `HealthKitBridge`, `WatchBridge` | Root view, app lifecycle, navigation router (route enum switch), bootstrap glue via `Shell.AppBootstrap`. Thin. |
| `WorkoutDBWatch` (watchOS) | `Features/WatchFaces`, `Core/Session`, `DesignSystem`, `WatchBridge` | Watch app lifecycle and face routing. Thin. |

## Forbidden

- Any `Core/*` package declaring a dep on an edge package.
- Any `Features/*` package declaring a dep on another `Features/*`.
- Any package named `Utils`, `Helpers`, `Common`, `Shared`, or `Misc`.
- Any package importing `schema` outside `Sync` or `schema` itself.
- `DesignSystem` importing `Features/*` or edge services.

## How to add a new package

1. Add a row to this doc with dependencies and purpose.
2. Create the directory under `app/Packages/`.
3. Write the minimal `Package.swift` declaring only the dependencies listed.
4. If a new edge (new external service, new platform capability) — add a SwiftLint custom rule in `.swiftlint.yml` restricting the relevant imports to that package.
5. Add the package to the appropriate shell target.

## How to split an existing package

Splitting is preferable to letting a package sprawl — see HS-1, HS-2.

1. Identify the responsibility to extract.
2. Create the new package in this doc and `app/Packages/`.
3. Move the relevant types. Update imports in consumer packages.
4. Update the SwiftPM dependency declarations.
5. Remove the exceptions register entry in `docs/architecture/boundaries.md` if one was in place.
