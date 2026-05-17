---
title: timing-modes
status: verified
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for timing-modes
covers:
  - app/Packages/Core/Prescription/Sources/CorePrescription/TimingConfig.swift
  - app/Packages/Core/Prescription/Sources/CorePrescription/PrescriptionParser+TimingConfig.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/DriverRegistry.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/StraightSetsDriver.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/RestBlockDriver.swift
---

# timing-modes

> **Status (2026-05-17):** This doc describes the current implemented
> 12-case `TimingMode` execution contract. It remains the baseline for current
> app behavior and regression proof. It is not the target model for the accepted
> primitives cutover; target primitives work uses
> `docs/specs/primitives-data-model.md`, where timing becomes composition over
> primitive timing/traversal/repeat cells.

## What it does
`TimingMode` is a 12-case enum (`CoreDomain/Enums.swift`) on every `Block`. Each mode has (a) a `TimingConfig` variant parsed from `block.timing_config_json` by `PrescriptionParser+TimingConfig.swift`, and (b) a `TimingDriver` looked up from `DriverRegistry` (inline in `ExecutionViewModel.swift`). The driver answers three questions per block: what the Active screen shows, how long rest is after a set, and what mutations (+ autoreg proposal) a set-log produces. Per the authoritative `docs/prescription.md` § "Per-timing-mode prescription shapes", each mode has a defined shape. All 12 modes are implemented and covered by local tests. Mode-aware cursor advancement lives on `SessionState.Structure.advancementByBlock` (`.setMajor` vs `.roundRobin` vs `.zeroItem`) — the seeder populates it per-block, the reducer's `nextCursor` branches on it. Time-capped / work-window modes are driven by VM-level `blockEndsAt` / `workEndsAt` timers persisted on `SessionState`. Both `ActiveView` and `RestView` carry a 1-second `Timer.publish(...).autoconnect()` publisher (`.onReceive(tickTimer)`) that calls `viewModel.tickBlockTimer()` every second while a cap/work window is active; `RestView` also ticks when `currentRestShouldAutoAdvance` is true so clock-owned rests move at zero. The VM then dispatches the mode-native timeout behavior when wall-clock elapses. Strength recovery rests are intentionally excluded from auto-advance so over-rest can count up until the next `Set Start`. See bug-042 for the wiring history.

## State surface
- **Inputs per mode:** `block.timingMode` (enum) + `block.timingConfigJSON` (mode-specific fields); item prescriptions.
- **Outputs per mode:** `ActiveContent` (exercise name, set counter, load/reps display); rest duration in seconds; `DriverLogOutcome` (optional autoreg proposal + extra mutations).
- **Registry:** `DriverRegistry.init(drivers:)` — defaults to all 12 drivers registered. Unknown (future) modes still fall back to `StraightSetsDriver` so the app doesn't crash.
- **Advancement:** `SessionState.Structure.advancementByBlock: [BlockAdvancement]` — `.setMajor` / `.roundRobin` / `.zeroItem`, populated per-block by the seeder. Reducer's `nextCursor` branches on it.
- **Time-cap timers:** `SessionState.blockEndsAt: Date?` (AMRAP / ForTime / EMOM / Tabata total); `SessionState.workEndsAt: Date?` (Tabata, intervals, and custom timed work windows). Persisted in `SessionStateCodable` so backgrounding survives.
- **Visible timer contract:** `blockEndsAt` / `workEndsAt` are not just completion triggers. Execution must surface a primary visible timer from the moment a workout starts; see `docs/features/execute-loop.md` § "Timer boundary contract".

## What it deliberately doesn't do
- The driver does not dispatch mutations itself — returns them for `ExecutionViewModel` to apply (`TimingDriver.swift:19-22`).
- Registry does not throw on unknown mode — falls back to straight_sets so the app never crashes on an authored-but-not-implemented mode (`ExecutionViewModel.swift:442-444`, per HS-2).
- Timing config is strict about *reading* keys (only documented keys read, extras ignored) but parse failures return `.failure` — the driver treats them as zero rest (`StraightSetsDriver.swift:120-122`).

## Edge cases handled in code
- `straight_sets` last-set-of-item with next item in block uses `rest_between_exercises_sec` instead of `rest_between_sets_sec` (`StraightSetsDriver.swift:99-119`).
- Zero-item blocks (standalone `rest`) LAND on the cursor `(blockIndex, 0, 1)`; the view model flips the route to `.rest` with the driver's `restDuration` on arrival (`RestBlockDriver.swift` header + `ExecutionViewModel.swift` § `enterRestIfZeroItemBlock`). Advancing FROM a zero-item block jumps straight to the next block (or to `.complete` if trailing).
- Tabata's timing config is a hard-coded sentinel (`.tabata` case, no fields; see `TimingConfig.swift:62-63`, `PrescriptionParser+TimingConfig.swift:37`). The 20/10 interval + 8-round definition is enforced by `TabataDriver` + VM `workEndsAt` handling.
- EMOM `interval_sec` + `total_minutes` — parsed as typed fields; the driver renders interval content and the VM uses them for `intervalAnchorAt`, boundary catchup, and block cap timing.

## Current gaps

- `TIMING-GAP-001`: Superset, circuit, and custom drivers do not propose
  autoreg. Round-robin autoreg needs explicit "remaining rounds" semantics
  before it can be enabled.
- `TIMING-GAP-002`: Distance-based intervals do not infer work/rest timers from
  target pace without GPS/sensor support; they show elapsed time and require
  manual lap/advance.
- `TIMING-GAP-003`: Active/Rest view distortion on background/resume has been
  observed but is not reproducible in automated tests. Capture visual evidence
  before changing timer or scene-phase code.

---

## Per-mode table

### `straight_sets` — BUILT
- **File:** `StraightSetsDriver.swift` (the only real driver).
- **Config fields:** `rest_between_sets_sec` (Double, required), `rest_between_exercises_sec` (Double, required). (`PrescriptionParser+TimingConfig.swift:47-65`)
- **Autoreg:** YES — straight_sets, repRange, setsDetail prescriptions with `target_rir` + `autoreg` config (`StraightSetsDriver.swift:200-221`).
- **Scenario:** 4x5 @ 100 kg with `rest_between_sets_sec: 120, rest_between_exercises_sec: 180`. Log set 4 → rest ring shows 2:00 if next item exists in block, else 2:00 (between-sets). Log set 4 with RIR 4 → no proposal (last set).

### `superset` — BUILT + TESTED
- **File:** `SupersetDriver.swift`.
- **Config fields:** `rest_between_rounds_sec` (Double, required), `logging_mode` (`batch_at_round_rest` default, optional).
- **Cursor:** round-robin — item 0 → item 1 → ... within a round, then bump setIndex (= round). Seeded via `SessionSeeder+RoundBased.swift` at `block.rounds` rows per item.
- **Logging:** default batch mode. Active advances station-to-station without opening the set sheet; the shared round rest exposes every station from that round for load/reps/RIR correction; `next` commits the round. The final round commits before completion even though no rest screen appears.
- **Autoreg:** off in v1 — "applies to remaining rounds of the superset" semantics not yet in reducer. Flagged in `SupersetDriver.swift` header.
- **Tests:** `SupersetDriverTests` (10 cases); integration: `testSupersetBatchModeAdvancesWithoutLoggingUntilRoundRest`, `testSupersetBatchModeCommitsFinalRoundBeforeComplete`.
- **Scenario:** 2 items (bench + row), 3 rounds — rest between items within a round = 0; rest after last item of non-last round = `rest_between_rounds_sec`; last item of last round rests 0 (VM routes to complete).

### `circuit` — BUILT + TESTED
- **File:** `CircuitDriver.swift`.
- **Config fields:** `rest_between_exercises_sec`, `rest_between_rounds_sec` (both required), `logging_mode` (`station_by_station` default, optional).
- **Cursor:** round-robin, same shape as superset.
- **Logging:** default station mode. Each station log writes one row before the cursor advances; authoring `logging_mode: "batch_at_round_rest"` opts into the same batch rest UI as supersets for strength-shaped stations.
- **Work targets:** stations may be reps, duration, or distance via `target.kind/value/unit`; duration/distance stations route through the cardio logging path and can still carry load.
- **Autoreg:** off per spec ("typically unused for circuits").
- **Tests:** `CircuitDriverTests` (10 cases); integration: `testCircuitRoundsWalkItemsThenRoundBumps` walks a 3×3 grid and verifies cursor path then completion, `testCircuitDefaultsToStationLoggingMode`.
- **Scenario:** 3 items × 5 rounds, RBE=0, RBR=120. Log 15 sets → block completes on the 15th advance.

### `emom` — BUILT + TESTED
- **File:** `EMOMDriver.swift`.
- **Config fields:** `interval_sec` (Double, required — usually 60), `total_minutes` (Int, required).
- **Cursor:** round-robin — items rotate per interval. `restDuration` returns `interval_sec`; VM's `blockEndsAt = start + total_minutes*60` terminates the block on elapse.
- **Autoreg:** not applicable per spec.
- **Tests:** `EMOMDriverTests` (9 cases); integration: `testEMOMCursorRoundRobinsPerInterval` walks 2 items × 3 intervals verifying the round-robin path.
- **Scenario:** 10-minute EMOM with 2 items rotating. The visible interval number is global (`round 2, item 2` renders `INTERVAL 4 OF N`), while set logs still use the item-local round index. Each boundary moves to the next item in the same round; after the last item, the next boundary bumps to round N+1 item 0. Strength-shaped EMOM rows require `Set Start` before logging.

### `amrap` — BUILT + TESTED
- **File:** `AMRAPDriver.swift`.
- **Config fields:** `time_cap_sec` (Double, required).
- **Cursor:** round-robin with a 100-row sentinel per item (the wall clock, not set count, terminates).
- **Logging:** Active's primary `next` logs the current station and advances round-robin with zero rest. When the cap elapses, `ActiveView` opens the AMRAP result sheet instead of auto-completing; rows before the cursor are completed/checkmarked, the current row accepts extra reps, and later rows are locked. Saving logs only the current partial row (when extra reps > 0), appends an `AMRAP result: N rounds + M reps` note, then routes out of the capped block.
- **Timer:** VM sets `blockEndsAt = start + time_cap_sec`; the view gates the elapsed tick so AMRAP opens the partial-result sheet instead of dropping straight to completion.
- **Autoreg:** not applicable.
- **Unbounded-rounds rendering contract (bug-037):** AMRAP's `ActiveContent.totalSets = 0` (exposed as `AMRAPDriver.unboundedRoundsCount`). This is the `ActiveView` contract for "no bound": the progress-dot row is hidden and the meta line renders `ROUND N` instead of `SET N OF M`. The 100-row cursor sentinel is a seeder internal (`SessionSeeder.unboundedRoundsSentinel`) that never surfaces to the view — if an AMRAP ever exceeds 100 rounds, re-seed; do NOT raise the view sentinel. See `docs/features/execute-loop.md` § "Progress-dot contract".
- **Tests:** `AMRAPDriverTests` + `AMRAPDriverBug037Tests` pin driver/rendering semantics; `ExecutionViewModelMetconResultTests.testAMRAPNextLogsCompletedStationThenPartialResultRoutesToNextBlock` pins station logging + partial-result routing; `ActiveViewMetaLineTests.testAMRAPCapPresentsResultSheetInsteadOfAutoCompleting` pins the cap-to-sheet gate.

### `for_time` — BUILT + TESTED
- **File:** `ForTimeDriver.swift`.
- **Config fields:** `time_cap_sec` (Double, optional); block-level `rounds_rep_scheme` read from `block.roundsRepSchemeJSON` (e.g. `[21, 15, 9]`).
- **Cursor:** round-robin; driver reads the scheme for the current round's rep count.
- **Timer:** VM sets `blockEndsAt` from `time_cap_sec` when present. Current M2 contract treats an expired For Time cap as a warning boundary: the low-level tick must not auto-complete because cap-partial capture is not built yet. The athlete taps `finish` once, which immediately logs the total elapsed duration.
- **Autoreg:** not applicable.
- **Tests:** `ForTimeDriverTests` (14 cases); integration: `testForTimeRoundSchemeRendersEachRoundReps` — cursor walks Fran (3 rounds × 2 items, scheme `[21, 15, 9]`) and each round's driver render reports the scheme's reps. `ExecutionViewModelMetconResultTests.testForTimeCapDoesNotAutoCompleteBeforeFinish` pins the no-silent-cap-completion contract.

### `intervals` — BUILT + TESTED
- **File:** `IntervalsDriver.swift`.
- **Config fields:** `work_sec` OR `work_distance_m`; `rest_sec` OR `rest_distance_m`; `interval_count` (Int, required); `target_pace_sec_per_km` (Double, optional).
- **Cursor:** set-major — single item, `interval_count` rows. Seeded via `intervalCount(from:parser:)`.
- **Timer / rest:** time-based intervals stamp `workEndsAt = work_sec` for the active interval, then rest uses `rest_sec`; both boundaries auto-transition at zero. Distance-based intervals show elapsed time and require manual lap/advance until GPS/sensor detection exists. Target pace is guidance, not a fake completion timer.
- **Autoreg:** not applicable.
- **Tests:** `IntervalsDriverTests` (13 cases).

### `tabata` — BUILT + TESTED
- **File:** `TabataDriver.swift`.
- **Config fields:** NONE — `timing_config_json: {}` by design. Constants hardcoded: 20s work / 10s rest / 8 rounds.
- **Cursor:** round-robin (8 rows per item; multi-item blocks alternate items per round).
- **Timer:** VM sets `blockEndsAt = start + 240s` (8 × 30s total) + per-round `workEndsAt = start + 20s`. When `workEndsAt` elapses, `tickBlockTimer` dispatches `.enterRest` for 10s. Cardio-shaped rounds also log duration; strength-shaped rounds do not auto-log fake reps.
- **Autoreg:** not applicable.
- **Tests:** `TabataDriverTests` (13 cases).

### `continuous` — BUILT + TESTED
- **File:** `ContinuousDriver.swift`.
- **Config fields:** `target_duration_sec`, `target_distance_m`, `target_pace_sec_per_km`, `target_hr_zone` (all optional).
- **Cursor:** single-item, single-row — one log completes the block.
- **Timer:** duration targets stamp a `TARGET` countdown. A standalone target at zero waits for `complete` or `continue`; a composed target auto-transitions to the next block only when detectable. Distance targets stay manual until sensor-derived distance exists.
- **Autoreg:** not applicable.
- **Tests:** `ContinuousDriverTests` (10 cases); integration: `testContinuousSingleItemCompletesAfterLog`.

### `accumulate` — BUILT + TESTED
- **File:** `AccumulateDriver.swift`.
- **Config fields:** `target_duration_sec`, `target_reps`, `target_distance_m` (all optional; author exactly one).
- **Cursor:** round-robin with one item and target sentinel rows. This preserves the target sentinel against item-level `sets` overrides while behaving like a single-item chunk list. Each chunk requires `Set Start`; logging a chunk advances to a ready state for free rest. Target completion routes to the next block when one exists, otherwise to `.complete`.
- **Autoreg:** not applicable by default.
- **Tests:** `AccumulateDriverTests` covers reps and duration chunks reaching target. Distance target is represented in schema/display but still needs metric-entry UI or sensors for useful carry logging.

### `custom` — BUILT + TESTED
- **File:** `CustomDriver.swift`.
- **Config fields:** `segments: [{type, duration_sec, label?, target_hr_zone?}]`. Empty-placeholder custom blocks seed one row per segment, render as cardio timed segments (`WORK`, `REST`, label / HR-zone text), and stamp `workEndsAt` per segment. Strength-shaped custom blocks still use the authored item sets.
- **Autoreg:** off by default; opt-in per item is a later slice.
- **Tests:** `CustomDriverTests` (11 cases).

### `rest` — BUILT (standalone rest block)
- **File:** `RestBlockDriver.swift`.
- **Config fields:** `duration_sec` (Double, required). Parser: `PrescriptionParser+TimingConfig.swift:139-149`.
- **Autoreg:** not applicable.
- **Cursor model:** Decision A1 (see `RestBlockDriver.swift` header). Zero-item block carries cursor `(blockIndex, 0, 1)` as a sentinel; the reducer lands the cursor there, the view model flips route to `.rest` with `restEndsAt = now + duration_sec`. `advanceFromRest` from a zero-item block advances to the next block (or `.complete`). No new `Cursor` case, no per-mutation churn.
- **Handling:** `SessionReducer+Handlers.swift` § `nextCursor` no longer skips empty blocks — it lands on them. `ExecutionViewModel.start()` / `advance()` call `enterRestIfZeroItemBlock()` on every cursor transition. `RestView` hides the "just logged" pills when on a zero-item block and relabels the sub-header to "BETWEEN BLOCKS".
- **Tests:** `RestBlockDriverTests` (6 cases — `restDuration`, `activeContent`, `onSetLogged`). `ExecutionViewModelTests.testRestBlockEnterAndAdvance`, `testRestBlockAtStartPositionEntersRestOnStart`. `CoreSessionTests` § "advanceFromRest · last set of work block → cursor lands on zero-item rest block", "from zero-item rest block → next block", "from trailing zero-item rest block → .complete".
- **Authoring — `rest` must have zero `workout_items`.** If a `rest` block ships with items, the driver still returns nil for Active and empty for onSetLogged, but the VM's zero-item check will not fire and the user will see an empty Active screen. Don't author that way.

---

## QA scenarios

### Composed simulator scenarios
DEBUG builds expose composed launch fixtures for simulator QA:
- `--debug-scenario=timer_gauntlet_strength --start-active` — rest block → straight_sets → superset → circuit.
- `--debug-scenario=timer_gauntlet_clocked --start-active` — EMOM → AMRAP → For Time → Tabata.
- `--debug-scenario=timer_gauntlet_endurance --start-active` — intervals → continuous → custom → accumulate → rest.

These are intentionally short so a QA pass can observe cross-block timer handoffs without waiting through a real workout. Use them in addition to the single-mode fixtures (`--debug-mode <mode> --start-active`) because several UX problems only appear when the app transitions from one timer contract to another.

### S1. Happy path — straight_sets (the only real path)
- **setup:** 3-set item, straight_sets block, `rest_between_sets_sec: 90, rest_between_exercises_sec: 120`.
- **steps:** log set 1 (reps 5, RIR 2) → rest shows 1:30 → next → log set 2 → rest 1:30 → next → log set 3 → rest 1:30 (no next item, still RBS) → next → complete.
- **expected:** normal flow; autoreg proposal only on sets 1 & 2.

### S2. Boundary — straight_sets last set of item with next item in block
- **setup:** 2 items in one block, `rest_between_sets_sec: 60, rest_between_exercises_sec: 180`. Item A has 3 sets.
- **steps:** log set 3 of item A.
- **expected:** rest duration = 180s (RBE, not RBS) (`StraightSetsDriver.swift:99-119`).

### S3. Failure — unknown / misspelled timingMode
- **setup:** `block.timing_mode = "unknown"` (from Swift side: `TimingMode(rawValue:)` returns nil, DTO mapping defaults to `.straightSets`; see `Persistence/DomainMapping.swift:74`).
- **steps:** execute normally.
- **expected:** no crash; falls through to straight_sets driver.

### S4. Superset — round-robin within a round
- **setup:** one block, `timing_mode: superset`, two items (bench + row), `rounds: 3`, `rest_between_rounds_sec: 120`, each item `{reps: 10, load_kg: 60}`.
- **steps:** start → log item 0 → advance → log item 1 → advance.
- **expected:** after first advance cursor is on (item 1, round 1); after second it's on (item 0, round 2). Rest between items within a round = 0; rest after last item of non-last round = 120s. Covered by `testCircuitRoundsWalkItemsThenRoundBumps` pattern (circuit shares the round-robin reducer path).

### S5. AMRAP — next logs stations, cap asks for partial station
- **setup:** `timing_mode: amrap`, `time_cap_sec: 30`, 2 items.
- **steps:** start → tap `next` on item 0 → cursor advances to item 1 → clock advances past 30s → Active tick opens the AMRAP result sheet → enter partial reps for item 1 → save.
- **expected:** item 0 has a normal completed set log; item 1 gets only the entered partial reps; the result sheet shows item 0 completed, item 1 editable, and later rows locked; route moves to the next block or complete after save. Verified by `testAMRAPNextLogsCompletedStationThenPartialResultRoutesToNextBlock` and `testAMRAPCapPresentsResultSheetInsteadOfAutoCompleting`.

### S6. EMOM — interval cadence + round-robin
- **setup:** `timing_mode: emom`, `interval_sec: 60, total_minutes: 3`, 2 items.
- **steps:** log item 0 → enter rest (60s interval) → advance → log item 1 → advance → ...
- **expected:** cursor walks (item 0, 1) → (item 1, 1) → (item 0, 2) → (item 1, 2) → (item 0, 3). `blockEndsAt = start + 180s` terminates on elapse. Verified by `testEMOMCursorRoundRobinsPerInterval`.

### S7. Tabata — hardcoded 20/10/8 with mode-shaped timeout
- **setup:** `timing_mode: tabata`, `timing_config_json: {}`, one item.
- **steps:** start → work window elapses (20s) without user log.
- **expected:** strength-shaped rows dispatch `.enterRest(10s)` without a fake `0 reps` log; cardio-shaped rows auto-dispatch `.logCardioSet(durationSec: 20)` + `.enterRest(10s)`. After 10s rest elapses, the next work window starts automatically. Total block completes at 8 × 30s = 240s via `blockEndsAt`.

### S8. Standalone rest block — drives a countdown between work blocks
- **setup:** three blocks: work (straight_sets, 2 sets) → rest (`duration_sec: 30`, zero items) → work (straight_sets, 2 sets).
- **steps:** finish both sets of block 0; advance through block 0's last rest.
- **expected:** cursor lands on block 1 `(1, 0, 1)`; route flips to `.rest` with `restEndsAt = now + 30s`. "JUST LOGGED" pill row hidden; sub-header reads "BETWEEN BLOCKS". Advance from that rest → route = `.active`, cursor `(2, 0, 1)`. Verified by `ExecutionViewModelTests.testRestBlockEnterAndAdvance`.

### S9. Circuit — round counter wraps
- **setup:** `timing_mode: circuit`, 3 items, `rounds: 3`, `rest_between_exercises_sec: 1`, `rest_between_rounds_sec: 30`.
- **steps:** walk all 9 (item × round) positions.
- **expected:** cursor path is (0,1) → (1,1) → (2,1) → (0,2) → ... → (2,3) → complete. RBR fires only on the last item of non-last round. Verified by `testCircuitRoundsWalkItemsThenRoundBumps`.

### S10. ForTime — rounds_rep_scheme drives per-round reps
- **setup:** `timing_mode: for_time`, `rounds: 3`, `rounds_rep_scheme: [21, 15, 9]`, 2 items (thruster + pull-up).
- **steps:** start → inspect `vm.activeContent.repsDisplay` at each round.
- **expected:** round 1 → "21", round 2 → "15", round 3 → "9" for both items. Verified by `testForTimeRoundSchemeRendersEachRoundReps`.

### S11. Custom — strength sets or timed segments
- **setup:** `timing_mode: custom`, either an authored strength item (`{sets: 3, reps: 10, load_kg: 40}`) or an empty placeholder item with a `segments` array in timing config.
- **steps:** execute.
- **expected:** strength-shaped custom uses the item's set count; empty-placeholder timed custom seeds one row per segment, renders `SEGMENT n OF m`, shows `WORK mm:ss` for timed work windows, logs cardio duration, and advances through the segment list.

### S12. Intervals distance-based
- **setup:** `timing_mode: intervals`, `work_distance_m: 400, rest_sec: 90, interval_count: 6, target_pace_sec_per_km: 240`.
- **steps:** execute.
- **expected:** 6 rows seeded for the single item. Driver's active display reads "400 m" + "4:00 / km". Rest = 90s between intervals. Next-lap advancement is manual (GPS deferred).

### S13. Config parse failure → zero rest
- **setup:** straight_sets block with malformed `timing_config_json` (missing required key).
- **steps:** log a set.
- **expected:** `parseTimingConfig` returns `.failure`; driver returns `restDuration = 0`; flow collapses into immediate auto-advance (`StraightSetsDriver.swift:120-122`, `ExecutionViewModel.swift:262-268`).

### S14. Extra keys in timing_config_json are ignored
- **setup:** straight_sets block with `{rest_between_sets_sec: 90, rest_between_exercises_sec: 120, foo: "bar"}`.
- **steps:** execute.
- **expected:** parses cleanly, "foo" ignored per `docs/prescription.md` § "Conventions".

### S15. TimingMode enum count
- **setup:** contract test `TimingMode.allCases.count`.
- **expected:** `== 12` (`CoreDomain/Tests/main.swift:9-12`). Regression guard against a dropped mode.
