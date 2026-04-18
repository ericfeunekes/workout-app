---
title: WorkoutDB — product spec & status tracker
status: living
purpose: Single source of truth for what we're building, what's done, and how we know.
covers:
  - whole project
---

# WorkoutDB

**One-liner.** Dumb iOS workout app + smart home server. Claude authors sessions; the app shows, times, and logs; the server stores and syncs. Single user. Single home deployment.

**Authoritative architecture spec:** `docs/specs/v2-architecture.md`. Read it before touching schema, sync, or the app shell.

**Feature behavior specs:** `docs/features/` (per-feature behavioral contract + QA scenarios). Start at `docs/features/INDEX.md`.

**Unresolved design questions:** `docs/open-questions.md`.

**Active bug tracker:** `docs/bugs.md`.

**Observability map:** `docs/observability-map.md` — for each user action, which layers (`SessionState` / local cache / push queue / server DB / `event_log`) record it. Use this to answer "did X actually land?" during QA without re-reading every layer's code.

---

## Current focus

_One paragraph, kept current as work moves. Update when starting a new slice; mark stale if untouched > 1 week._

**2026-04-18 (v1 build-out pass, 2nd validation wave):** **22 bugs fixed this session** (001-014, 016, 017, 020, 024, 026, 030-033, 035, 036, 037 — plus 015/018/034 with regression coverage). All 11 timing modes built+tested. Telemetry, smart-defaults, body-weight/note, swap UI, past-set-edit push, autoreg clamp, DSRadius, LogSetSheet, UX polish (021/022/023/027/028), Today auto-refresh on completion (bug-036) all landed. **MCP E2E validated:** Push A hypertrophy full 13-set workout (autoreg overshoot banner, save & done → server `status=completed`, 13 set_logs pushed, 40 telemetry events, History auto-refresh, img-ask visual QA green on all 5 polish bugs); Metcon AMRAP active screen + round-robin through 3 items after bug-037 fix ("ROUND N · REST 0:00" clean, no overflow); Tabata round advance 1→2 of 8. Bugs found **during** validation and fixed: **bug-035** (LogSetSheet @Observable), **bug-036** (Today VM stale after save), **bug-037** (AMRAP progress dots overflow). Filed and open: **bug-038** (Tabata rest timer renders 0:00 instead of ticking from 10). 96 files uncommitted awaiting explicit user go-ahead; proposed commit plan in scratch. Remaining MCP work (all have unit+integration test coverage; need live runs): time-cap expiry on AMRAP/For-Time, EMOM interval tick, exercise-swap long-press, past-set edit from History, persistence kill/relaunch, Tabata rest-timer after bug-038 fix, Superset round-robin, Intervals / Continuous / Custom single-item modes.

---

## v1 scope — what ships first

Target: "first workout in the gym, basically no bugs, just works." The scope has to cover Eric's actual training patterns (hypertrophy, CrossFit, running) and the ability to author any exercise + any timing mode.

### In-scope — must work

- **Execution loop** across **all 11 timing modes:** `straight_sets`, `superset`, `circuit`, `emom`, `amrap`, `for_time`, `intervals`, `tabata`, `continuous`, `custom`, `rest`.
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

| State | Meaning | Evidence required |
|---|---|---|
| `draft` | Feature doc exists, intent clear. Code may or may not compile. | Feature doc path. |
| `built` | Code merged, compiles, lint clean. | Commit SHA, entry-point file, build-clean timestamp. |
| `tested` | Unit + integration tests pass and target the *intended behavior*. | Test names, last pass timestamp, coverage of the scenarios in the feature doc. |
| `validated` | MCP-driven E2E run confirms behavior against scenarios. Telemetry event log captured. Visual QA reviewed. | Recording path, telemetry query, img-ask report, scenario-coverage checklist. |
| `shipped` | In regular use by Eric. Stable for ≥1 week. | First-real-use timestamp, week of uneventful use. |

**Status is downgradable.** If a test breaks, a regression returns, or a scenario demonstrates wrong behavior: demote and open a bug. No status persists without active evidence.

| Feature | Doc | State | Evidence |
|---|---|---|---|
| firstrun | [firstrun](features/firstrun.md) | `tested` | `FeaturesFirstRunTests` — FirstRun re-entrancy + transport tests. Not yet validated E2E against real server with MCP. |
| bootstrap | [bootstrap](features/bootstrap.md) | `tested` | `ShellTests.AppBootstrapTests`. MCP E2E 2026-04-18 validated token→pull→ready path for one workout; full scenario coverage pending. |
| today | [today](features/today.md) | `tested` | `FeaturesTodayTests.TodayLoaderTests` + `TodayViewModelTests` — now includes `testTodayViewModelReloadPicksNextPlannedAfterCompletion` + `testTodayViewModelReloadToEmptyWhenNoPlannedWorkouts` pinning the bug-036 post-save reload. MCP E2E 2026-04-18 validated "start workout" after holder fix. last-session chip is pass-through stub. |
| execute-loop | [execute-loop](features/execute-loop.md) | `validated (straight_sets) / tested (other 10 modes)` | 149 tests in `FeaturesExecutionPackageTests` + 34 in `CoreSessionTests`. **MCP E2E 2026-04-18 validated Push A hypertrophy end-to-end:** 13 set_logs pushed to server with deterministic UUIDs (bug-010), workout status flipped to `completed`, History auto-refreshed (bug-016), autoreg overshoot banner fired on RIR 4 and applied 102.5 → 105.0 kg to remaining sets. Validation recording: `scratch/e2e/recordings/validation-01-hypertrophy.mp4`. Other 10 modes have unit+integration tests but no MCP E2E run yet. Bug found + fixed during validation: `bug-035` (LogSetSheetModel missing `@Observable`). |
| timing-modes | [timing-modes](features/timing-modes.md) | `tested (all 11 modes)` | Per-mode driver tests: `StraightSetsDriverTests`, `SupersetDriverTests`, `CircuitDriverTests`, `EMOMDriverTests`, `AMRAPDriverTests`, `ForTimeDriverTests`, `IntervalsDriverTests`, `TabataDriverTests`, `ContinuousDriverTests`, `CustomDriverTests`, `RestBlockDriverTests`. Integration: `testAMRAPBlockCompletesAtTimeCap`, `testEMOMCursorRoundRobinsPerInterval`, `testCircuitRoundsWalkItemsThenRoundBumps`, `testForTimeRoundSchemeRendersEachRoundReps`, `testContinuousSingleItemCompletesAfterLog`. Reducer round-robin: 4 new `CoreSessionTests` cases. All drivers wired in `DriverRegistry`; round-robin cursor advancement + time-cap timers land per mode. |
| autoreg | [autoreg](features/autoreg.md) | `validated (overshoot) / tested (other branches)` | `CoreAutoregTests` (19 cases, including clamp tests). **MCP E2E 2026-04-18: RIR 4 on bench logged → overshoot banner "↑ next set: 105 kg / rir 4 > target 2" rendered → applied to sets 3+4 (102.5 → 105.0). `execution.autoreg_proposed` event landed on server.** Undershoot / hit-failure / undo paths not MCP-validated. |
| save-and-done | [save-and-done](features/save-and-done.md) | `tested` | `ExecutionViewModelTests.testSaveAndDoneInvokesLocalCompletionWriterOnce`, `testSaveAndDoneEnqueuesStatusExactlyOnce`, `testCompleteAloneDoesNotEnqueueStatus`, `testSaveAndDoneWritesNoteToCompletedWorkout`, `testSaveAndDoneEmptyNoteCollapsesToNil`, `testSaveAndDoneEnqueuesBodyweightUserParameter`, `testSaveAndDoneNilBodyweightDoesNotFire`. SyncTests `PushQueue — userParameter routes to /api/user-parameters`. Server `test_append_accepts_app_shaped_bodyweight_payload`. Dictation-mic on the note deferred (see save-and-done.md § S12). |
| history | [history](features/history.md) | `tested` | `FeaturesHistoryTests.HistoryViewModelTests` + `TrendComputationTests`. MCP E2E 2026-04-18 validated list → row-tap → detail after row-tap bug fix. Session-detail edit sheet: `draft` — stubbed. |
| exercise-swap | [exercise-swap](features/exercise-swap.md) | `validated` | Code: `SwapSheet`, `ExecutionViewModel.swap(itemID:alternativeID:)`, `AlternativeOverrides.parse`. Tests: `ExecutionViewModelSwapTests` (10) + 3 CoreSessionTests (overrides round-trip, manual preserved, empty). **MCP E2E 2026-04-18**: Interaction-test workout → long-press card → SwapSheet opens (medium haptic + card scale feedback confirmed by img-ask at 01:58) → tap "Overhead Press" → Active flips to OHP with override values 55 kg × 6 reps (from `parameter_overrides_json`) → 3 sets logged → save & done → server records all 3 set_logs with `performed_exercise_id = Overhead Press` (not the planned Bench) + status=completed. Recording: `scratch/e2e/recordings/validation-04-interactions.mp4`. Closes bug-008 + bug-009. |
| past-set-edit | [past-set-edit](features/past-set-edit.md) | `tested` | `ExecutionViewModelEditPastSetTests.testEditPastSetEnqueuesSameUUIDAsOriginalLog`, `testEditPastSetEnqueuesWithUpdatedValues`, `testEditPastSetEmitsTelemetry`, `testMultipleEditsOfSameSetAllUseSameUUID`. `editPastSet` enqueues a corrected `SetLog` via `onSetLogged`; both `enqueueLoggedSet` and `enqueueEditedSet` derive the `SetLog.id` deterministically from `(itemID, setIndex)` so the server upserts in place. Telemetry emits `execution.past_set_edited`. History-screen edit sheet still stubbed (bug-015) — push path is available once the UI lands. |
| persistence | [persistence](features/persistence.md) | `tested` | `SessionStateCodable` round-trip tests + `testRestoreIfPossiblePullsSavedState`. MCP re-launch scenario not explicitly validated this session. |
| push-queue | [push-queue](features/push-queue.md) | `tested` | `SyncTests` + `ExecutionViewModelPushTests`. MCP E2E 2026-04-18 observed set_log pushes landing after UUID-case fix. Telemetry-events routing: `tested` (3 new Sync tests) — not yet E2E validated. |
| telemetry | see `CoreTelemetry` package | `tested` | `CoreTelemetryTests` + `tests/server/test_api_telemetry.py` (6 tests) + fixture parity. **Emit coverage: partial** — bootstrap/today/execute/network only. History/Settings/FirstRun: not yet. |

_No feature is at `validated` today._ The closest is the hypertrophy happy-path on `execute-loop`, but that covered one timing mode and one RIR value. A real `validated` claim needs full scenario coverage + telemetry + visual QA.

---

## How status moves

**When you believe a feature has advanced, don't update this doc alone.** The update requires three things in the same PR / commit:

1. **Evidence artifact.** The thing that proves it — a test name, a recording path, a telemetry event-log query, an img-ask report.
2. **The feature doc.** Each scenario covered gets `(tested: <test_name>)` or `(validated: <session-id>)` next to its heading.
3. **This matrix.** Only then update the State column.

**Demotions** don't need the same ceremony — anyone observing a regression updates the state down and files a bug. Evidence for demotion is the failing test / failing E2E / reported defect.

---

## Architecture snapshot

Terse — the detailed architecture lives in `docs/specs/v2-architecture.md`.

- Python FastAPI + SQLite server (home-server deployment over Tailscale). Stores workouts, exercises, set_logs, user_parameters, event_log.
- iOS app (SwiftUI + SwiftData), offline-first: pull from server → cache → execute → push back when connected.
- 11 Swift packages, each narrow: `Core/Domain`, `Core/Session`, `Core/Prescription`, `Core/Autoreg`, `Core/Telemetry`, `Core/Foundation`, `Persistence`, `Sync`, `Shell`, `DesignSystem`, feature packages.
- `Features/*` packages own the view models; `Shell` is the only place allowed to wire Features together.
- Import-linter (Python) + SwiftLint rules enforce architectural boundaries at CI time.

## Conventions

- **All UUIDs lowercase on the wire.** Swift emits uppercase by default — server's `_UuidNormalizingBase` Pydantic mixin lowercases on input.
- **All datetimes ISO-8601 UTC with `Z` suffix.** Server's `UtcDatetime` serializer enforces.
- **Prescription is per-item JSON blob** — no schema change needed for new shapes. Claude authors full resolved prescription on push; server snapshots on ingest (ADR pending for smart defaults).
- **Local SetLog UUIDs are stable from creation** — same UUID on create + edit pushes = idempotent on server.
- **Push queue is FIFO, durable, retry-on-transient-failure.** One cadence (~60s foreground); telemetry, set_logs, status_updates all flow through it.
