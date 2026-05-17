---
title: Setmark — product overview and release evidence
status: living
last_reviewed: 2026-05-17
purpose: Product overview and release-evidence matrix. Active work routing lives in docs/backlog.md; durable requirements live in owning docs.
covers:
  - whole project
---

# Setmark

**One-liner.** Dumb iOS workout app + smart home server. Claude authors
sessions; the app shows, times, and logs; the server stores and syncs. Single
user. Single home deployment.

This is a product overview and release-evidence matrix. It is not the active
work router. Use `docs/sdlc.md` for the lifecycle, `docs/backlog.md` for active
lanes, `docs/feature-gap-map.md` for unresolved gaps, and the owning
feature/domain/aspect docs for durable requirements.

**Authoritative architecture spec:** `docs/specs/v2-architecture.md`. Read it before touching schema, sync, or the app shell.

**Feature behavior specs:** `docs/features/` (per-feature target behavioral contracts + QA scenarios). Start at `docs/features/INDEX.md`; use `docs/feature-gap-map.md` for current gaps and `docs/backlog.md` for the lane router.

**Unresolved design questions:** `docs/open-questions.md`.

**Active bug tracker:** `docs/bugs.md`.

**Observability map:** `docs/observability-map.md` — for each user action, which layers (`SessionState` / local cache / push queue / server DB / `event_log`) record it. Use this to answer "did X actually land?" during QA without re-reading every layer's code.

---

## v1 scope — what ships first

Target: "first workout in the gym, basically no bugs, just works." The scope has to cover Eric's actual training patterns (hypertrophy, CrossFit, running) and the ability to author any exercise + any timing mode.

### In-scope — must work

- **Execution loop** across **all 12 timing modes:** `straight_sets`, `superset`, `circuit`, `emom`, `amrap`, `for_time`, `intervals`, `tabata`, `continuous`, `accumulate`, `custom`, `rest`.
- **Per-exercise autoreg** with accept-by-default + undo (hold session-scoped per-item). Negative-load clamp.
- **Exercise swap** mid-workout via long-press → alternatives sheet.
- **Alternative overrides** applied at runtime (`parameter_overrides_json`).
- **Past-set edit** local + server push (same-UUID idempotent).
- **Save & done** → local cache + server status push (one enqueue, both paths).
- **Body-weight + workout-note capture** on completion.
- **History** list + session detail + by-exercise trend. Auto-refresh after save & done.
- **FirstRun** URL/token entry.
- **Bootstrap** pull + cache fallback.
- **Push queue** with retry, 401 handling, idempotent UUIDs.
- **Session persistence** across backgrounding.
- **Telemetry** with lazy sync to server.
- **Smart defaults** — exercise-library default prescriptions, server-resolved + snapshotted on ingest (ADR pending).

### Deferred — v1.1+

- Watch app
- FirstRun QR scan
- Settings "export telemetry bundle" share sheet
- On-device debug overlay
- Cross-exercise autoreg downscaling
- History session-detail edit sheet (direct-tap edit from history surface)
- `apply_to` values beyond `remaining` (`next`, `all-future`)

---

## Feature status matrix

Status ladder — **a feature only advances to a higher state with evidence, cited in the Evidence column.** No optimism.

This matrix is the product-level release tracker. Feature docs use section-level
states (`planned`, `building`, `built`, `verified`) for target-contract slices.
A feature-doc section reaching `verified` does not automatically promote the
product matrix; this matrix moves only when the evidence below is strong enough
for the whole feature row.

| State | Meaning | Evidence required |
|---|---|---|
| `draft` | Feature doc exists, intent clear. Code may or may not compile. | Feature doc path. |
| `built` | Code merged, compiles, lint clean. | Commit SHA, entry-point file, build-clean timestamp. |
| `tested` | Unit + integration tests pass and target the *intended behavior*. | Test names, last pass timestamp, coverage of the scenarios in the feature doc. |
| `validated` | MCP-driven E2E run confirms behavior against scenarios. Telemetry event log captured. Visual QA reviewed. | Committed QA summary, telemetry query or event-log verdict, scenario-coverage checklist, and optional raw recording provenance. |
| `shipped` | In regular use by Eric. Stable for ≥1 week. | First-real-use timestamp, week of uneventful use. |

**Status is downgradable.** If a test breaks, a regression returns, or a scenario demonstrates wrong behavior: demote and open a bug. No status persists without active evidence.

| Feature | Doc | State | Evidence |
|---|---|---|---|
| firstrun | [firstrun](features/firstrun.md) | `tested` | `FeaturesFirstRunTests` — re-entrancy + transport tests. After bug-048 cutover, FirstRun only hits `/api/version`; `testFirstRunHandsOffToBootstrapWithoutSecondPull` pins the scope boundary. Not yet MCP-validated against real server. |
| bootstrap | [bootstrap](features/bootstrap.md) | `tested` | `ShellTests.AppBootstrapTests` including `testBootstrapFiresExactlyOnePullPerRun`. MCP E2E 2026-04-18 validated token→pull→ready path. `.empty` gained a "change server" route with URL+token pre-fill (bug-048). |
| today | [today](features/today.md) | `tested` | `FeaturesTodayTests.TodayLoaderTests` + `TodayViewModelTests` — includes post-save reload, plan queue grouping, UTC scheduled-date handling, detail sheet read models, adjustment draft generation, start-specific-workout action, and refresh-state tests. Shell `testTodayRefreshRunsPullAndKeepsReadyState` pins the refresh pull/reload/rebuild path; `testTodayCanStartNonSelectedPlannedWorkout` pins starting a missed/future queued card. MCP E2E 2026-04-18 validated "start workout" after the holder fix. |
| execute-loop | [execute-loop](features/execute-loop.md) | `tested` | 149+ tests in FeaturesExecutionPackageTests + 34 in CoreSessionTests. **MCP E2E 2026-04-18**: Push A hypertrophy end-to-end (13 set_logs pushed, workout status → completed, History auto-refreshed, autoreg overshoot banner applied to remaining sets). Durable proof is the test list and dated QA summary here; raw local recordings are not a durable source of truth. Restore-time normalization pass runs zero-item / timer helpers (bug-043); cardio blocks routed through `logCurrentSet` → `.logCardioSet` with elapsed-wins duration (bug-049). Timer boundary regression pinned by `testForTimeStartExposesCapTimerPresentationImmediately`, `testAMRAPStartExposesGlobalCapTimerPresentationImmediately`, and `testStraightSetStartExposesElapsedTimerWhenNoCountdownExists`; next-up context pinned by `testForTimeStartExposesNextExerciseContext`, `testStraightSetStartExposesNextSetContext`, and `testRestBlockStartExposesNextBlockContext`; simulator QA on 2026-04-24 confirmed Active renders a visible global AMRAP cap timer. Other 10 modes unit+integration tested; no MCP E2E yet. |
| timing-modes | [timing-modes](features/timing-modes.md) | `tested (all 12 modes)` | Per-mode driver tests (Straight / Superset / Circuit / EMOM / AMRAP / ForTime / Intervals / Tabata / Continuous / Accumulate / Custom / RestBlock). Integration: `testAMRAPNextLogsCompletedStationThenPartialResultRoutesToNextBlock`, `testAMRAPCapPresentsResultSheetInsteadOfAutoCompleting`, `testEMOMCursorRoundRobinsPerInterval`, `testCircuitRoundsWalkItemsThenRoundBumps`, `testForTimeRoundSchemeRendersEachRoundReps`, `testContinuousSingleItemCompletesAfterLog`, `AccumulateDriverTests`, `CompleteViewLedgerSwapTests.testBlockResultsSummarizeAccumulatedRepsAgainstTarget`, and `EMOMBoundaryTests` (bug-050 minute-boundary advance via `intervalAnchorAt`). Tabata narrowed to strength-only for v0; multi-item Tabata collapses to `items[0]` with telemetry (bug-055). Time-cap tick wiring pinned by `testActiveViewWiresTickBlockTimerViaPeriodicTimer` + rest view counterpart (bug-042). |
| autoreg | [autoreg](features/autoreg.md) | `validated (overshoot) / tested (other branches)` | `CoreAutoregTests` (19+ cases, clamp + per-unit step). MCP E2E 2026-04-18 overshoot applied. `apply_to` parse failure now isolated by `parseTolerantOfAutoreg` so the base prescription survives an unknown value (bug-052). Autoreg step defaults per unit (5 lb / 1.25 kg, bug-059). `execution.autoreg_proposed` carries typed payload with `step_kg` + canonical reason tokens (bug-060). |
| save-and-done | [save-and-done](features/save-and-done.md) | `tested` | `testSaveAndDoneInvokesLocalCompletionWriterOnce`, `testSaveAndDoneEnqueuesStatusExactlyOnce`, `testCompleteAloneDoesNotEnqueueStatus`, `testSaveAndDoneWritesNoteToCompletedWorkout`, `testSaveAndDoneEmptyNoteCollapsesToNil`, `testSaveAndDoneEnqueuesBodyweightUserParameter`, `testSaveAndDoneNilBodyweightDoesNotFire`, `testSaveAndDoneReEntrancyGuardDropsDoubleTap` (bug-044). Server `test_append_accepts_app_shaped_bodyweight_payload` + `test_user_parameter_tenant_guard_returns_403`. Server persists workout notes on status push (previously overwritten on next pull). Dictation-mic on the note deferred. |
| history | [history](features/history.md) | `tested` | `FeaturesHistoryTests.HistoryViewModelTests` + `TrendComputationTests` + `HistoryViewModelEditPastSetTests` (bug-015 sheet landed). EditSetSheet is unit-aware (bug-051 — labels lb/kg per source unit via `formatLoad(weight:unit:)`); reps capped at 999; RIR explicit-clear via new enum. Recent-sessions grouping keyed by `workoutID` (denormalized per bug-047 V3 migration). SessionDetail bodyweight surfaces via `loadUserParameters(key:)` ±2min window (bug-060). HistoryPreviewSeed now includes a bodyweight sample. |
| exercise-swap | [exercise-swap](features/exercise-swap.md) | `validated` | `ExecutionViewModelSwapTests` + 3 CoreSessionTests + swap-override parser tests. **MCP E2E 2026-04-18** confirmed long-press → SwapSheet → tap → override values applied → server records `performed_exercise_id`. `AlternativeOverrides.parse` now reads the full target key set (sets, reps, load_kg, weight_unit, target_rir, autoreg) returning `Result<Overrides, ParseError>` (all-or-nothing); sets override honored only on set-major blocks — round-robin drops it and emits `execution.swap_sets_override_rejected` (bug-057). |
| past-set-edit | [past-set-edit](features/past-set-edit.md) | `tested` | `testEditPastSetEnqueuesSameUUIDAsOriginalLog`, `testEditPastSetEnqueuesWithUpdatedValues`, `testEditPastSetEmitsTelemetry`, `testMultipleEditsOfSameSetAllUseSameUUID`. `enqueueEditedSet` now preserves the original `completedAt` instead of stamping edit time (bug-054). Per-set `startedAt` is captured via `SessionState.workStartedAt` anchor (stamped on `.start` + `.advanceFromRest`, consumed by the reducer in `.logSet` / `.logCardioSet`). History-screen edit sheet shipped unit-aware (bug-051). |
| persistence | [persistence](features/persistence.md) | `tested` | `SessionStateCodable` round-trip tests + restore normalization (bug-043). SwiftData V3 migration (`SchemaMigrationTests` — `SetLog.workoutID` + `plannedExerciseID` denormalized with lightweight-stage backfill, bug-047). `WorkoutCacheReconcileTests` + `WorkoutCacheReconcilePreservationTests` pin local subtree reconcile + detach-before-delete so client-side SetLogs survive app cache edits. Server whole-tree replacement currently cascade-deletes old SetLogs when parent blocks/items are replaced. |
| push-queue | [push-queue](features/push-queue.md) | `tested` | `SyncTests` (dedup, priority FIFO, backoff, dead-letter) + `PushQueueStoreTests.tolerantPeekSkipsForwardVersionedRow` + `PushQueueStoreImpl.pruneUndecodableRows()` on startup (bug-055). Priority-weighted FIFO (results=0 before telemetry=1, bug-056). `PushBackoff.schedule = [10,30,60,120,300]`s; dead-letter after 5 consecutive non-401 4xx emits `execution.push_item_dead_lettered` with `setLogID` / `workoutID` / `userParameterID` correlation (bug-060). Deterministic client-owned UUIDs on every payload (bug-044 / bug-045). |
| telemetry | see `CoreTelemetry` package | `tested` | `CoreTelemetryTests` + `tests/server/test_api_telemetry.py` + fixture parity. Emitter attach awaited by AppBootstrap before first emit (bug-056). Server `UtcDatetimeIn` rejects non-`Z` datetime suffixes (bug-056). `event_log` retention 90-day default with daily periodic sweep + startup-safe exception handling (bug-060). Typed `Encodable` payloads replace hand-built JSON (bug-045). New events: `execution.tabata_multi_item_collapsed`, `execution.swap_sets_override_rejected`, `execution.push_item_dead_lettered`, typed `execution.autoreg_proposed`. |
| cardio-logging | [execute-loop](features/execute-loop.md) / [timing-modes](features/timing-modes.md) | `tested` | `.logCardioSet` mutation on `CoreSession.SessionMutation` carries `durationSec` / `distanceM` / `hrAvgBpm` / `cadenceAvgSpm` / `startedAt`. `SetPlan` grew the matching cardio fields. VM-level `logCurrentSet()` branches on `isCurrentBlockCardio` so ActiveView routes cardio blocks to `logCardioSet(...)` with elapsed-wins duration (not authored target pace × distance). IntervalsDriver suppresses trailing rest on the final interval. Pinned by `ExecutionViewModelLogCardioSetTests`, `ExecutionViewModelLogCurrentSetTests`, `EMOMBoundaryTests` (bug-049). Schema was already cardio-ready at every layer. |
| pound-default | cross-cutting (prescription + drivers + server merge) | `tested` | Default weight unit is `.lb`. `PrescriptionParser` defaults to `.lb`. All 9 drivers render via centralized `formatLoad(weight:unit:)` in `WorkoutCoreFoundation`. Autoreg step defaults per unit (5 lb / 1.25 kg). Server `prescription_merge` defaults to `.lb`. `RestView` / `CompleteView+Ledger` render unit from data, not hardcoded. `SetPlan.loadKg: Double?` optional cascade so loadless rows render "BW" instead of "0 lb"; CompleteView+Ledger treats only nil (not 0) as BW. Pinned by `PostLogUnitDisplayTests`, `WorkoutCoreFoundationTests`, server `test_prescription_merge_defaults_lb` (bug-059 / bug-053). |

_Product-level validation evidence exists today for execute-loop straight_sets and exercise-swap. The execute-loop row remains `tested` overall until the broader feature has MCP E2E coverage; everything else has unit + integration coverage but awaits MCP E2E runs against the real server to promote to `validated`._

---

## How status moves

**When you believe a feature has advanced, don't update this doc alone.** The
update requires durable proof in the same PR / commit:

1. **Evidence summary.** The thing that proves it — a test name, committed QA
   summary, telemetry event-log query, or visual-review note. Raw scratch files
   are optional supporting material, not durable evidence.
2. **The feature doc.** Each scenario covered gets `(tested: <test_name>)`, `(verified: <qa-run-id>)`, or product-matrix validation evidence next to its heading.
3. **This matrix.** Only then update the State column.

**Demotions** don't need the same ceremony — anyone observing a regression updates the state down and files a bug. Evidence for demotion is the failing test / failing E2E / reported defect.

---

## Architecture snapshot

Terse — the detailed architecture lives in `docs/specs/v2-architecture.md`.

- Python FastAPI + SQLite server (home-server deployment over Tailscale). Stores workouts, exercises, set_logs, user_parameters, event_log.
- iOS app (SwiftUI + SwiftData), offline-first: pull from server → cache → execute → push back when connected.
- Local SwiftPM package graph under `app/Packages/`: Core packages,
  `DesignSystem`, `Persistence`, `Sync`, named bridges, feature packages, and
  `Shell`. See `docs/architecture/swift-packages.md` for the authoritative
  package list and allowed dependencies.
- `Features/*` packages own the view models; `Shell` is the only place allowed to wire Features together.
- Import-linter (Python) + SwiftLint rules enforce architectural boundaries at CI time.

## Conventions

- **All UUIDs lowercase on the wire.** Client routes every outbound UUID through `UUID.wireID`; server's `_UuidInputBase` validates + lowercases on input, `_UuidReadBase` lowercases on egress (trusts the DB). See bug-030 / bug-031 / bug-045.
- **All datetimes ISO-8601 UTC with `Z` suffix.** Server's `UtcDatetime` serializer on egress + `UtcDatetimeIn` validator rejecting non-`Z` on input (bug-056).
- **Prescription is per-item JSON blob** — no schema change needed for new shapes. Claude authors sparse prescriptions; server merges library defaults at ingest and snapshots the raw shape (ADR-2026-04-18-smart-defaults).
- **Client-owned deterministic UUIDs everywhere.** `SetLog.id = MD5(itemID|setIndex)`; `UserParameter.id = MD5(userID|key|observedAt)`. Server upserts by id within the authenticated tenant; edits and replays are idempotent. See bug-010 / bug-040 / bug-044.
- **Default weight unit is `.lb`.** Parser, server merge, and seeder all default to pounds. Autoreg step defaults per unit (5 lb / 1.25 kg). Centralized `formatLoad(weight:unit:)` in `WorkoutCoreFoundation` (bug-059).
- **`SetPlan.loadKg: Double?` — nil means bodyweight / loadless.** Only nil renders as "BW"; a genuine 0-weight authored row renders with the unit (bug-053).
- **Push queue is durable, priority-weighted FIFO, logical dedup, exponential backoff, dead-letter after 5 persistent 4xx.** Priority: results (set_log / status / user_parameter) = 0, telemetry = 1. Backoff: `[10, 30, 60, 120, 300]`s. Dedup keys: `SetLog.id`, `(workoutID, status)`, `UserParameter.id`. Dead-letter emits `execution.push_item_dead_lettered` with correlation id. See bug-055 / bug-056 / bug-060.
