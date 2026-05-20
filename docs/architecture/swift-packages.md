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
| `Core/Domain` | `Core/Foundation` | Plain Swift structs for active primitive domain entities (`PrimitiveWorkout`, `PrimitiveBlock`, `PrimitiveSet`, `PrimitiveSlot`, `PrimitiveSetLog`, `Exercise`, `UserParameter`) plus temporary legacy projection values (`Workout`, `Block`, `WorkoutItem`, `SetLog`, `ExerciseAlternative`) used by bridge/history surfaces until the residual runtime cutover removes them. No SwiftData, no Foundation-network, no persistence. | ✅ | ✅ |
| `Core/Prescription` | `Core/Foundation`, `Core/Domain` | Legacy projection parsers for `prescription_json` and `timing_config_json` while current execution bridge code still projects primitives into old execution shapes. Primitive-native execution semantics live in `Core/Session`; this package is not the active authoring contract. | ✅ | ✅ |
| `Core/Autoreg` | `Core/Foundation`, `Core/Domain`, `Core/Prescription` | Pure functions that compute autoreg proposals. `propose(prescribed:, logged:) -> AutoregProposal?`. No state, no I/O. | ✅ | ✅ |
| `Core/Session` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Autoreg` | Live-session state machine and canonical primitive runtime contract. Owns executable session state, cursor/route/log reducer behavior, primitive `ExecutionPlan`, primitive execution block/set/slot runtime values, seed-time primitive load resolution, pre-start `SessionPreviewProjection` semantics, log coordinates, and deterministic log identity helpers. No I/O and no feature presentation strings. | ✅ | ✅ |
| `Core/Foundation` | (none) | Pure utilities shared across Core packages: `Clock` protocol, ID generation, kg↔lb conversion, duration formatting. The **only** shared-utilities package allowed. | ✅ | ✅ |
| `Core/Telemetry` | (none) | Pure value type `Event` + `TelemetryEmitter` protocol + process-stable `TelemetrySession.id`. Emitters are implemented in `Persistence`; the shape stays in Core so every layer can accept an emitter without pulling in storage. | ✅ | ✅ |
| `DesignSystem` | `Core/Foundation` (for formatting helpers only) | Visual tokens (colors, type ramp, spacing, motion) and primitives (button, chip, pill, ring, keypad). No routing, no business rules. | ✅ | ✅ |
| `ExportProfile` | `Core/Foundation`, `Core/Domain`, `Core/Session` | Pure export planning package split into `PrimitiveExportProfile` for vendor-neutral primitive facts and `WorkoutKitExportProfile` for SDK-free WorkoutKit row classification and path prerequisite assessment. No target side effects: no WorkoutKit scheduling/opening, no HealthKit readback, no WatchConnectivity, no persistence. | ✅ | ✅ |
| `WorkoutKitAdapter` | `Core/Foundation`, `Core/Domain`, `ExportProfile` | Target-side WorkoutKit boundary. Owns SDK-backed plan construction, schedule/open clients, proof-gated push coordination, payload fingerprints, and DEBUG/test diagnostic probes. WorkoutKit imports stay here. May import HealthKit only for WorkoutKit-required activity/location enum construction (`HKWorkoutActivityType`, `HKWorkoutSessionLocationType`). No HealthKit data access/readback, no WatchConnectivity, no persistence, no SwiftUI, no feature logic. | ✅ | ✅ |
| `schema` | (external — already at `schema/`) | Wire DTOs. Consumed only by `Sync`. | ✅ | ✅ |
| `Persistence` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Telemetry`, `Sync` | SwiftData stack, migrations, keychain bearer-token storage, `UserDefaults` URL storage, and the SwiftData-backed `TelemetryEmitterImpl`. Mirrors active primitive workouts/logs and exposes protocols (`SessionStore`, `WorkoutCache`, `TokenStore`) used by Features and Sync. Legacy projection storage remains only where the current execution/history bridge still consumes it. | ✅ | ✅ |
| `Sync` | `Core/Foundation`, `Core/Domain`, `Core/Telemetry`, `schema` | `PullService`, `PushQueue`, `ConnectionManager`. The only package that imports URLSession (enforced by SwiftLint FF-13). Maps primitive DTOs -> Domain at the boundary — nothing outside `Sync` imports `schema`. Push queue routes primitive result rows and telemetry batches to server endpoints. See HS-1. | ✅ | — |
| `HealthKitBridge` | `Core/Foundation`, `Core/Domain` | Typed HealthKit data-access boundary for batch archive, post-workout readback, and live metric consumers. Owns descriptors, units, permissions, HealthKit query mapping, and fakes; HealthKit imports confined here (FF-13). | ✅ | ✅ |
| `HealthArchiveExport` | `Core/Foundation`, `Core/Telemetry`, `Persistence`, `Sync`, `HealthKitBridge` | App-level personal HealthKit archive export coordinator. Owns descriptor selection policy, current-server delivery namespace, manual export orchestration, foreground catch-up decisions, and future scheduler abstraction. Maps `Persistence` archive projection values into `Sync` upload calls; `Sync` remains the only package that imports `schema` or owns HTTP transport. No SwiftUI, no HealthKit imports, no URLSession. | ✅ | — |
| `WatchBridge` | `Core/Domain`, `Sync` | iPhone ↔ Watch IPC via WatchConnectivity. Watch taps on "log set" travel through WatchBridge → Sync.PushQueue. | ✅ | ✅ |
| `Features/Today` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence` | Today screen: workout card, exercise list, last-session chip, workout preview/detail surface. Does not import sibling Features; Shell owns cross-feature routing. | ✅ | — |
| `Features/Execution` | `Core/Foundation`, `Core/Domain`, `Core/Prescription`, `Core/Autoreg`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence` | Active + rest screens, per-mode TimingDriver strategies (HS-2), RIR picker, numpad/log sheets, autoreg banner, swap sheet, completion ledger. | ✅ | — |
| `Features/History` | `Core/Foundation`, `Core/Domain`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence`, `Sync` | History tab: list, session detail, by-exercise view, and reset/correction shell. Imports `CoreSession` only for presentation-neutral primitive result semantics so slot, set-result, and block-result rows are classified the same way as Execution; History owns the reader-facing grouping/copy. | ✅ | — |
| `Features/Settings` | `DesignSystem`, `Persistence` | Settings screen as data-driven sections (HS-4): server controls, local reset, units, autoreg defaults, diagnostics entry points. | ✅ | — |
| `Features/FirstRun` | `Core/Foundation`, `DesignSystem`, `Persistence`, `Sync` | Welcome + connection-string entry + first-sync progress. | ✅ | — |
| `Features/WatchFaces` | `Core/Session`, `DesignSystem`, `HealthKitBridge`, `WatchBridge` | The watchOS faces (v1.1+ full grammar; v1 minimal: HR, rest countdown, start/end tap). Consumes the typed `WorkoutMetricSource` seam; it does not import HealthKit directly. | — | ✅ |
| `Shell` | `Core/Foundation`, `Core/Domain`, `Core/Session`, `Core/Telemetry`, `DesignSystem`, `Persistence`, `Sync`, `WatchBridge`, `Features/Today`, `Features/Execution`, `Features/History`, `Features/Settings` | Launch-time and root-navigation composition package: builds `SyncAPI`, runs `pullLatest`, writes to `WorkoutCache`, constructs feature view models, owns `RootTabView`, and routes Today/Execution/History/Settings. The **one** package allowed to see multiple `Features/*` at once. Lives at `app/Packages/Shell/` — **not** under `Features/` — because the SwiftLint rule `no_feature_cross_import` only covers the `Features/` directory. Thin: composition, routing, and bootstrap orchestration only; no feature logic. | ✅ | — |

## Shell targets

| Target | Dependencies | Purpose |
|---|---|---|
| `WorkoutDB` (app) | Core packages, `DesignSystem`, `Persistence`, `Sync`, `HealthKitBridge`, `HealthArchiveExport`, `WatchBridge`, `WorkoutKitAdapter`, iOS `Features/*`, `Shell` | App lifecycle, first-run gate, persistence factory, HealthKit archive lifecycle triggers, debug launch routes, and `Shell.RootTabView` hosting. Thin; cross-feature tab routing belongs in Shell. HealthKit archive triggers stay here because they are scene-phase and app-entitlement lifecycle wiring; export mechanics remain in `HealthArchiveExport` and HealthKit access remains in `HealthKitBridge`. |
| `WorkoutDBWatch` (watchOS) | Core packages, `DesignSystem`, `Persistence`, `HealthKitBridge`, `WatchBridge`, `WorkoutKitAdapter`, `Features/WatchFaces` | Watch app lifecycle and face routing. Thin; phone remains the only server actor. `HealthKitBridge` is present for the DEBUG live-workout simulator probe and future typed metric-source wiring; WorkoutKitAdapter is present only for the watchOS open-in-Workout-app proof path. |

## Forbidden

- Any `Core/*` package declaring a dep on an edge package.
- Any `Features/*` package declaring a dep on another `Features/*`.
- Any package named `Utils`, `Helpers`, `Common`, `Shared`, or `Misc`.
- Any package importing `schema` outside `Sync` or `schema` itself.
- Any package importing `WorkoutKit` outside `WorkoutKitAdapter`.
- Any package importing HealthKit for data access outside `HealthKitBridge`.
  `WorkoutKitAdapter` is the only exception, and only for HealthKit enum types
  required by WorkoutKit plan construction.
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
- executable-session semantics, pre-start preview facts, primitive seed
  resolution, and deterministic log identity -> `Core/Session`
- live execution timers, route copy, and feature presentation read models ->
  `Features/Execution`
- cross-feature route selection -> `Shell`
- feature-local sheet selection -> one `Identifiable` enum per feature surface,
  not multiple booleans in the view body

If a change needs a sibling Feature import to share UI or state, stop and move
the shared contract to the correct package instead.
