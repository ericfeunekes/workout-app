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

**Rule:** when a package is created, its `Package.swift` has to include
`supportedPlatforms` for every product platform it appears on. Packages also
declare `.macOS(.v14)` where package tests run as command-line Swift tests on
the developer machine. Core packages support iOS, watchOS, and macOS test
execution; edge packages vary.

| Package | Dependencies (may import) | Purpose | iOS | watchOS |
|---|---|---|:---:|:---:|
| `Core/Domain` | `Core/Foundation` | Plain Swift structs for the domain entities: `Workout`, `Block`, `WorkoutItem`, `SetLog`, `Exercise`, `ExerciseAlternative`, `UserParameter`. No SwiftData, no Foundation-network, no persistence. | ✅ | ✅ |
| `Core/Prescription` | `Core/Foundation`, `Core/Domain` | Per-shape parsers for `prescription_json` and `timing_config_json`. Returns typed `Result` values. No computation — parsers only. See HS-3. | ✅ | ✅ |
| `Core/Autoreg` | `Core/Foundation`, `Core/Domain`, `Core/Prescription` | Pure functions that compute autoreg proposals. `propose(prescribed:, logged:) -> AutoregProposal?`. No state, no I/O. | ✅ | ✅ |
| `Core/Session` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Autoreg` | Live-session state machine and canonical primitive runtime contract. Owns executable session state, cursor/route/log reducer behavior, primitive `ExecutionPlan`, primitive execution block/set/slot runtime values, log coordinates, and deterministic log identity helpers. No I/O. | ✅ | ✅ |
| `Core/Foundation` | (none) | Pure utilities shared across Core packages: `Clock` protocol, ID generation, kg↔lb conversion, duration formatting. The **only** shared-utilities package allowed. | ✅ | ✅ |
| `Core/Telemetry` | (none) | Pure value type `Event` + `TelemetryEmitter` protocol + process-stable `TelemetrySession.id`. Emitters are implemented in `Persistence`; the shape stays in Core so every layer can accept an emitter without pulling in storage. | ✅ | ✅ |
| `DesignSystem` | `Core/Foundation` (for formatting helpers only) | Visual tokens (colors, type ramp, spacing, motion) and primitives (button, chip, pill, ring, keypad). No routing, no business rules. | ✅ | ✅ |
| `schema` | (external — already at `schema/`) | Wire DTOs. Consumed only by `Sync`. | ✅ | ✅ |
| `Persistence` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Telemetry`, `Sync` | SwiftData stack, migrations, keychain bearer-token storage, `UserDefaults` URL storage, and the SwiftData-backed `TelemetryEmitterImpl`. Exposes protocols (`SessionStore`, `WorkoutCache`, `TokenStore`) used by Features and Sync. | ✅ | ✅ |
| `Sync` | `Core/Foundation`, `Core/Domain`, `Core/Telemetry`, `schema` | `PullService`, `PushQueue`, `ConnectionManager`. The only package that imports URLSession (enforced by SwiftLint FF-13). Maps DTOs -> Domain at the boundary — nothing outside `Sync` imports `schema`. Push queue routes telemetry batches to `/api/telemetry/events`. See HS-1. | ✅ | — |
| `HealthKitBridge` | `Core/Foundation`, `Core/Domain` | HR, cadence, body-weight queries. Protocols exposed for Features; HealthKit imports confined here (FF-13). | ✅ | ✅ |
| `WatchBridge` | `Core/Domain`, `Sync` | iPhone ↔ Watch IPC via WatchConnectivity. Watch taps on "log set" travel through WatchBridge → Sync.PushQueue. | ✅ | ✅ |
| `Features/Today` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence` | Today screen: workout card, exercise list, last-session chip, workout preview/detail surface. Does not import sibling Features; Shell owns cross-feature routing. | ✅ | — |
| `Features/Execution` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Autoreg`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence` | Active + rest screens, per-mode TimingDriver strategies (HS-2), RIR picker, numpad/log sheets, autoreg banner, swap sheet, completion ledger. | ✅ | — |
| `Features/History` | `Core/Foundation`, `Core/Domain`, `Core/Telemetry`, `DesignSystem`, `Persistence`, `Sync` | History tab: list, session detail, by-exercise view, corrective edit surface. | ✅ | — |
| `Features/Settings` | `DesignSystem`, `Persistence` | Settings screen as data-driven sections (HS-4): server controls, local reset, units, autoreg defaults, diagnostics entry points. | ✅ | — |
| `Features/FirstRun` | `Core/Foundation`, `DesignSystem`, `Persistence`, `Sync` | Welcome + connection-string entry + first-sync progress. | ✅ | — |
| `Features/WatchFaces` | `Core/Session`, `DesignSystem`, `WatchBridge` | The watchOS faces (v1.1+ full grammar; v1 minimal: HR, rest countdown, start/end tap). | — | ✅ |
| `Shell` | `Core/Foundation`, `Core/Domain`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence`, `Sync`, `Features/Today`, `Features/Execution`, `Features/History`, `Features/Settings` | Launch-time and root-navigation composition package: builds `SyncAPI`, runs `pullLatest`, writes to `WorkoutCache`, constructs feature view models, owns `RootTabView`, and routes Today/Execution/History/Settings. The **one** package allowed to see multiple `Features/*` at once. Lives at `app/Packages/Shell/` — **not** under `Features/` — because the SwiftLint rule `no_feature_cross_import` only covers the `Features/` directory. Thin: composition, routing, and bootstrap orchestration only; no feature logic. | ✅ | — |

## Shell targets

| Target | Dependencies | Purpose |
|---|---|---|
| `WorkoutDB` (app) | Core packages, `DesignSystem`, `Persistence`, `Sync`, `HealthKitBridge`, `WatchBridge`, iOS `Features/*`, `Shell` | App lifecycle, first-run gate, persistence factory, debug launch routes, and `Shell.RootTabView` hosting. Thin; cross-feature tab routing belongs in Shell. |
| `WorkoutDBWatch` (watchOS) | Core packages, `DesignSystem`, `Persistence`, `WatchBridge`, `Features/WatchFaces` | Watch app lifecycle and face routing. Thin; phone remains the only server actor. |

## Forbidden

- Any `Core/*` package declaring a dep on an edge package.
- Any `Features/*` package declaring a dep on another `Features/*`.
- Any package named `Utils`, `Helpers`, `Common`, `Shared`, or `Misc`.
- Any package importing `schema` outside `Sync` or `schema` itself.
- `DesignSystem` importing `Features/*` or edge services.
- A feature package importing another feature package. Shared display seams move
  to `DesignSystem` when visual-only, or to `Core/Session` / a named Core
  package when they are execution state.

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

## Current refactor pressure

Several feature views are intentionally split by file length today but still
carry multiple interaction families. Before adding richer preview edits,
pending-set edits, long-press action menus, completion-ledger editing, or large
History filters, create a small seam first:

- visual-only primitives and accessibility behavior -> `DesignSystem`
- execution cursor/timer/read-model behavior -> `Core/Session` or
  `Features/Execution` projection
- cross-feature route selection -> `Shell`
- feature-local sheet selection -> one `Identifiable` enum per feature surface,
  not multiple booleans in the view body

If a change needs a sibling Feature import to share UI or state, stop and move
the shared contract to the correct package instead.
