# Codex Session Handoff — 2026-05-19

Snapshot of where the two in-flight Codex threads landed before they stopped
on 2026-05-19 afternoon. Companion to the active remediation plans:

- `scratch/healthkit-personal-archive-export-review-remediation.md`
- `scratch/workoutkit-structural-remediation-plan.md`

Neither plan captured the precise stopping point, so this note exists to make
the next pickup unambiguous. Once the next implementer commits the next slice
of either thread, delete this note.

## Thread 1 — HealthKit personal archive export

Active plan: `healthkit-personal-archive-export-review-remediation.md`
(remediation against the review that blocked the archive export slice).
Plan covers five clusters: app runtime state and recovery, request-set
identity, wire types, ownership boundaries, and proof/doc truthfulness.

### What landed (uncommitted at session stop, now committed with this note)

Partial Cluster 1 + a Cluster 2 correctness fix + Cluster 5 doc work:

- **Settings rows are XCTest-addressable.** `SettingsView+Rows.swift` —
  `infoRow`, `pickerRow`, `actionRow`, `toggleRow` now take an `id` parameter
  and apply `.accessibilityIdentifier`. `infoRow` and `pickerRow` also wrap
  with `.accessibilityElement(children: .contain)` / a row-level identifier.
  Required before any XCUITest probe of the archive Settings section can
  even reference its controls.
- **Settings refreshes on mount.** `SettingsView.swift` gained
  `.task { await viewModel.refreshAsync() }` so the archive section reflects
  current state on first render instead of stale model state.
- **Scope changes re-arm the automatic export.** Cluster 2 work:
  `HealthArchiveExportCoordinator.shouldRunAutomaticExport` now derives a
  `requestSetKey(serverNamespace, scope)` from descriptor fingerprint + scope
  slug + namespace, and returns `true` whenever the stored snapshot key does
  not match. Prevents stale snoozes after a same-server descriptor edit.
- **Regression test for the scope-change path.** `HealthArchiveExportTests`
  case `"next attempt is scoped by request set on the same server"` proves
  the first request set runs, identical scope is suppressed until
  `nextAttemptAt`, and a scope change on the same server re-fires
  immediately with `trigger == .foregroundCatchUp`.
- **bug-101 logged.** `docs/bugs.md` open P2 entry: Settings export rows
  render and are now addressable, but descriptor/automatic toggles and
  Export Now do not produce a deterministic UI-level state change in
  simulator QA. Next ID bumped to 102.
- **bootstrap doc corrected.** `docs/features/bootstrap.md` —
  `PersistenceFactory.makeDefault` throw is a production hard-fail; DEBUG
  launch fast-paths use explicit in-memory stores. Replaces the older "fall
  back to in-memory; if that also throws → fatalError" text.

### Still open per the remediation plan

Cluster 1: truthful Settings status on first render after refresh, manual
export refresh, concurrent-attempt prevention/report, token-rejection routed
through sync recovery, stale `running` cannot survive relaunch. The
`.task` refresh is a partial down payment — single-flight semantics and
relaunch cleanup of `running` are not done.

Cluster 2: server must enforce request-set identity across shared schema
and Sync result types; coordinator must verify request-set match before
advancing cursors; request-set-keyed cursor in `HealthArchiveStore` must
become the production resume authority. Only the coordinator-side
re-arm-on-mismatch is implemented.

Clusters 3 (wire types), 4 (composition ownership), 5 (real-HTTP archive
upload proof through `app/Integration/sync_real_http/` and matching doc
truthfulness sweep across `docs/healthkit-data-access.md`,
`docs/features/settings.md`, `docs/feature-gap-map.md`, `docs/backlog.md`,
`docs/ARCHITECTURE.md`, `docs/TESTING.md`): not started.

### Immediate next step

Pick one root cause for bug-101 and prove it:

1. Add an XCUITest against the now-addressable Settings rows that toggles
   automatic + flips descriptor scope + presses Export Now and asserts the
   visible status/next-attempt/scope text changes.
2. If the XCUITest fails, the suspect ranking from the session is:
   (a) toggle/on-pick callbacks not dispatched to `@MainActor`,
   (b) state-store mutation not observable through the view model
       (`SettingsViewModel` publishes only after `refreshAsync` reads it
       back; mutations must trigger a refresh),
   (c) `refreshAsync` is not awaited on the same task that fires the toggle.

Do not claim bug-101 closed without the XCUITest evidence under
`scratch/qa-runs/<run-id>/`.

## Thread 2 — WorkoutKit structural remediation

Active plan: `workoutkit-structural-remediation-plan.md` (dated 2026-05-19,
responds to the latest review on the WorkoutKit remediation).

### What landed

No uncommitted code. The May 19 morning–early-afternoon sessions stayed in
planning/review territory and produced the structural remediation plan plus
the user-facing push impl plan (`workoutkit-user-facing-push-impl-plan.md`)
and the phase-1 export classification plan
(`workoutkit-phase1-export-classification-impl-plan.md`). All committed
WorkoutKit work in trunk is still the foundations from `1b3e79d`.

### Still open per the remediation plan

The plan's "Next Implementation Route" is the work queue:

1. Promote the SDK-free resolved descriptor vocabulary into
   `WorkoutKitExportProfile` as the canonical production descriptor contract.
2. Reshape `WorkoutKitExportPlan` around one production descriptor state
   (resolved or blocked-with-reasons). Remove production use of
   `descriptorCompleteness` compatibility.
3. Rewrite classifier row builders to produce the canonical descriptor state
   directly.
4. Rewrite admission/category derivation from the canonical descriptor +
   explicit proof state. Stop synthesizing `unsupported` from
   source-choice or misleading states.
5. WorkoutKit adapter production entrypoints accept only resolved
   descriptors; diagnostic fixtures stay distinct from production plans.
6. Update docs for source-authority decisions (environment, source-choice,
   loaded carry, proof-blocked product export).
7. Update tests so helpers construct plans through classifier-owned
   fixtures or resolved descriptor contracts.

### Capability gap (named, not closed)

No real iPhone + paired Apple Watch is currently available to prove Apple
Workout app visibility, startability, permissions, or duplicate/update
behavior. Plan explicitly does not close this gap; product user-facing
WorkoutKit export remains proof-blocked until
`docs/runbooks/watch-workoutkit-proof.md` runs on hardware.

### Immediate next step

Step 1 of the Next Implementation Route — promote the SDK-free resolved
descriptor vocabulary into `WorkoutKitExportProfile`. Keep WorkoutKit SDK
enum translation inside the adapter. Do not attempt the user-facing push
button until at least steps 1–4 land, otherwise the canonical descriptor
contract gets re-litigated under user-facing pressure.

## Cross-thread notes

- `scratch/reviews/` is empty (mtime 2026-05-19 08:28) — no open review
  handoff. Next review on either thread starts fresh.
- Most recent QA run: `scratch/qa-runs/` mtime 2026-05-19 13:48 — that's
  the HealthKit export Settings QA that surfaced bug-101.
- Pre-push hooks (import-linter + pytest) cover the Python boundaries
  only. Swift package tests are not in the pre-push gate; the next slice
  on either thread should run `make test-app-packages` locally before
  pushing.
