---
title: Shell package lives outside Features/
status: accepted
date: 2026-04-18
covers:
  - app/Packages/Shell/
  - app/.swiftlint.yml
  - docs/architecture/swift-packages.md
---

# ADR: Shell package lives outside Features/

**Complements:** `ADR-2026-04-17-architecture.md` (establishes the SwiftPM package graph and the `no_feature_cross_import` SwiftLint rule).

## Context

Today's sync-integration slice produced a new package that needs to compose `Features/Today` and `Features/Execution` together: it runs `AppBootstrap.bootstrap(...)` on app launch, pulls from the server, caches to disk, builds both view models, and hands them back to the iOS app shell.

The original architecture called out in `docs/architecture/swift-packages.md` had two invariants that collided:

1. **`no_feature_cross_import`** — SwiftLint custom rule that forbids any file under `app/Packages/Features/` from importing another `Features*` module. The rule exists to prevent feature entanglement (HS-2, HS-4).
2. **The shell target (`WorkoutDB`) must stay thin** — composition logic, view-model wiring, and async bootstrap belong in a library, not in the top-level app target.

Putting composition logic under `Features/Shell/` would require importing Features/Today + Features/Execution from a Features/* module — a direct FF-13 violation. Putting it in the app target inflates the shell. Neither is right.

## Decision

**The Shell package lives at `app/Packages/Shell/`, outside `Features/`.**

It is explicitly allowed to import `FeaturesToday` and `FeaturesExecution` — that's its job. The SwiftLint `no_feature_cross_import` rule is scoped to files under `Features/`, which Shell is not, so no rule loosening is needed.

`docs/architecture/swift-packages.md` records Shell in the package table with the note:

> The **one** package allowed to see multiple `Features/*` at once (that's its job). Lives at `app/Packages/Shell/` — **not** under `Features/` — because the SwiftLint rule `no_feature_cross_import` only covers the `Features/` directory.

## Consequences

- **A new top-level category in `Packages/`.** Previously we had `Packages/Core/*`, `Packages/Features/*`, and top-level edge packages (`Persistence`, `Sync`, `DesignSystem`, `HealthKitBridge`, `WatchBridge`). Shell is now a peer of those.
- **`Shell` is the single composition root.** Anything that needs to wire multiple Features plus edge services plus Core packages goes here. Don't add a second Shell-like package without a clear ownership delineation.
- **WorkoutDB (iOS target) depends on Shell.** WorkoutDB's own code stays near-empty — root scene, `.preferredColorScheme(.dark)`, and the `RootView` that consumes Shell's `BootstrapResult`.

## Alternatives considered

- **Put composition logic directly in `WorkoutDB/` (the iOS target).** Rejected — the target becomes untestable (no library target = no `swift test`) and accumulates untraceable glue.
- **Loosen `no_feature_cross_import` to allow a named exception.** Rejected — once exceptions start, the rule erodes. A structural solution (move the package out of `Features/`) is cleaner.
- **Split Shell into one package per "mode" (e.g., `ShellLaunch`, `ShellNavigation`).** Premature. The current Shell surface is one type (`AppBootstrap`). Split when a second concern appears that actually diverges.
- **Generate the composition via a DI framework (Factory, Swinject, etc.).** Rejected — adds a dependency for negligible benefit at this scale. Hand-wired composition in one `@MainActor` type is legible and testable.

## Done when

- [x] Shell package created at `app/Packages/Shell/`.
- [x] Row added to `docs/architecture/swift-packages.md`.
- [x] WorkoutDB app target depends on Shell via `app/project.yml`.
- [x] This ADR committed.
- [x] SwiftLint passes with the rule unchanged.

## Open question revisit

If Shell grows past ~200 lines or the package count under `app/Packages/` crosses ~20, revisit whether a `Shell/Bootstrap`, `Shell/Navigation`, `Shell/Environment` sub-structure would help. For now: one package, one file, one type.
