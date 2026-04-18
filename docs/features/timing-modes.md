---
title: timing-modes
status: living
purpose: Behavioral contract + QA scenarios for timing-modes
covers:
  - app/Packages/Core/Prescription/Sources/CorePrescription/TimingConfig.swift
  - app/Packages/Core/Prescription/Sources/CorePrescription/PrescriptionParser+TimingConfig.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/DriverRegistry.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/StraightSetsDriver.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/RestBlockDriver.swift
---

# timing-modes

## What it does
`TimingMode` is an 11-case enum (`CoreDomain/Enums.swift:21-33`) on every `Block`. Each mode has (a) a `TimingConfig` variant parsed from `block.timing_config_json` by `PrescriptionParser+TimingConfig.swift`, and (b) a `TimingDriver` looked up from `DriverRegistry` (inline in `ExecutionViewModel.swift`). The driver answers three questions per block: what the Active screen shows, how long rest is after a set, and what mutations (+ autoreg proposal) a set-log produces. Per the authoritative `docs/prescription.md` § "Per-timing-mode prescription shapes", each mode has a defined shape. **All 11 modes are built + tested.** Mode-aware cursor advancement lives on `SessionState.Structure.advancementByBlock` (`.setMajor` vs `.roundRobin` vs `.zeroItem`) — the seeder populates it per-block, the reducer's `nextCursor` branches on it. Time-capped modes (AMRAP / ForTime / EMOM / Tabata) are driven by VM-level `blockEndsAt` / `workEndsAt` timers persisted on `SessionState`. Both `ActiveView` and `RestView` carry a 1-second `Timer.publish(...).autoconnect()` publisher (`.onReceive(tickTimer)`) that calls `viewModel.tickBlockTimer()` every second while `state.blockEndsAt != nil`; the VM then dispatches `.complete` (or, for Tabata, an auto-log + `.enterRest`) when wall-clock elapses. The Rest view carries its own tick because block caps can expire during rest — e.g., an EMOM's total_minutes cap elapsing between intervals, or a For-Time cap while the user is still resting. See bug-042 for the wiring history.

## State surface
- **Inputs per mode:** `block.timingMode` (enum) + `block.timingConfigJSON` (mode-specific fields); item prescriptions.
- **Outputs per mode:** `ActiveContent` (exercise name, set counter, load/reps display); rest duration in seconds; `DriverLogOutcome` (optional autoreg proposal + extra mutations).
- **Registry:** `DriverRegistry.init(drivers:)` — defaults to all 11 drivers registered. Unknown (future) modes still fall back to `StraightSetsDriver` so the app doesn't crash.
- **Advancement:** `SessionState.Structure.advancementByBlock: [BlockAdvancement]` — `.setMajor` / `.roundRobin` / `.zeroItem`, populated per-block by the seeder. Reducer's `nextCursor` branches on it.
- **Time-cap timers:** `SessionState.blockEndsAt: Date?` (AMRAP / ForTime / EMOM / Tabata total); `SessionState.workEndsAt: Date?` (Tabata's 20s work window). Persisted in `SessionStateCodable` so backgrounding survives.

## What it deliberately doesn't do
- The driver does not dispatch mutations itself — returns them for `ExecutionViewModel` to apply (`TimingDriver.swift:19-22`).
- Registry does not throw on unknown mode — falls back to straight_sets so the app never crashes on an authored-but-not-implemented mode (`ExecutionViewModel.swift:442-444`, per HS-2).
- Timing config is strict about *reading* keys (only documented keys read, extras ignored) but parse failures return `.failure` — the driver treats them as zero rest (`StraightSetsDriver.swift:120-122`).

## Edge cases handled in code
- `straight_sets` last-set-of-item with next item in block uses `rest_between_exercises_sec` instead of `rest_between_sets_sec` (`StraightSetsDriver.swift:99-119`).
- Zero-item blocks (standalone `rest`) LAND on the cursor `(blockIndex, 0, 1)`; the view model flips the route to `.rest` with the driver's `restDuration` on arrival (`RestBlockDriver.swift` header + `ExecutionViewModel.swift` § `enterRestIfZeroItemBlock`). Advancing FROM a zero-item block jumps straight to the next block (or to `.complete` if trailing).
- Tabata's timing config is a hard-coded sentinel (`.tabata` case, no fields; see `TimingConfig.swift:62-63`, `PrescriptionParser+TimingConfig.swift:37`). The 20/10 interval + 8-round definition is in `docs/prescription.md`; the app has no tabata driver to enforce it.
- EMOM `interval_sec` + `total_minutes` — parsed as typed fields; no driver logic consumes them yet (`TimingConfig.swift:36-39`).

## Known issues / gaps
- All 11 drivers built + registered + unit-tested. Integration coverage: `testAMRAPBlockCompletesAtTimeCap`, `testEMOMCursorRoundRobinsPerInterval`, `testCircuitRoundsWalkItemsThenRoundBumps`, `testForTimeRoundSchemeRendersEachRoundReps`, `testContinuousSingleItemCompletesAfterLog`. Reducer round-robin: 4 new cases in `CoreSessionTests/main.swift`.
- **Tabata work-expiry auto-logs a placeholder `(reps: 0, rir: nil)`.** The 20s / 10s / 8-round cadence is enforced; prompting the user for a real per-round rep count is a later slice. Documented in `TabataDriver.swift` and `ExecutionViewModel+Persistence.swift` (`autoLogAndRestForTabata`).
- **Intervals distance-based** (`work_distance_m` / `rest_distance_m`) renders correctly but GPS-driven lap advancement is out of scope for v1 — the user taps next-lap. Time-based intervals auto-cadence via `IntervalsDriver.restDuration`.
- **Custom segment-walker UI** is deferred — v1 treats `custom` as a thin renderer: the seeder uses set-major advancement reading the item's own `sets`, the user ticks through without the driver imposing segment cadence.
- **Superset autoreg** is off in v1 — the reducer needs "applies to remaining rounds of the superset" semantics before autoreg proposals make sense for round-robin modes. Flagged in `SupersetDriver.swift` header.
- **AMRAP / EMOM sentinel.** Seeded at 100 rows per item; the VM's time-cap path (`blockEndsAt` + `tickBlockTimer`) terminates the block well before the cursor hits row 100.

---

## Per-mode table

### `straight_sets` — BUILT
- **File:** `StraightSetsDriver.swift` (the only real driver).
- **Config fields:** `rest_between_sets_sec` (Double, required), `rest_between_exercises_sec` (Double, required). (`PrescriptionParser+TimingConfig.swift:47-65`)
- **Autoreg:** YES — straight_sets, repRange, setsDetail prescriptions with `target_rir` + `autoreg` config (`StraightSetsDriver.swift:200-221`).
- **Scenario:** 4x5 @ 100 kg with `rest_between_sets_sec: 120, rest_between_exercises_sec: 180`. Log set 4 → rest ring shows 2:00 if next item exists in block, else 2:00 (between-sets). Log set 4 with RIR 4 → no proposal (last set).

### `superset` — BUILT + TESTED
- **File:** `SupersetDriver.swift`.
- **Config fields:** `rest_between_rounds_sec` (Double, required).
- **Cursor:** round-robin — item 0 → item 1 → ... within a round, then bump setIndex (= round). Seeded via `SessionSeeder+RoundBased.swift` at `block.rounds` rows per item.
- **Autoreg:** off in v1 — "applies to remaining rounds of the superset" semantics not yet in reducer. Flagged in `SupersetDriver.swift` header.
- **Tests:** `SupersetDriverTests` (9 cases).
- **Scenario:** 2 items (bench + row), 3 rounds — rest between items within a round = 0; rest after last item of non-last round = `rest_between_rounds_sec`; last item of last round rests 0 (VM routes to complete).

### `circuit` — BUILT + TESTED
- **File:** `CircuitDriver.swift`.
- **Config fields:** `rest_between_exercises_sec`, `rest_between_rounds_sec` (both required).
- **Cursor:** round-robin, same shape as superset.
- **Autoreg:** off per spec ("typically unused for circuits").
- **Tests:** `CircuitDriverTests` (10 cases); integration: `testCircuitRoundsWalkItemsThenRoundBumps` walks a 3×3 grid and verifies cursor path then completion.
- **Scenario:** 3 items × 5 rounds, RBE=0, RBR=120. Log 15 sets → block completes on the 15th advance.

### `emom` — BUILT + TESTED
- **File:** `EMOMDriver.swift`.
- **Config fields:** `interval_sec` (Double, required — usually 60), `total_minutes` (Int, required).
- **Cursor:** round-robin — items rotate per interval. `restDuration` returns `interval_sec`; VM's `blockEndsAt = start + total_minutes*60` terminates the block on elapse.
- **Autoreg:** not applicable per spec.
- **Tests:** `EMOMDriverTests` (8 cases); integration: `testEMOMCursorRoundRobinsPerInterval` walks 2 items × 3 intervals verifying the round-robin path.
- **Scenario:** 10-minute EMOM with 2 items rotating. Each `advanceFromRest` moves to the next item in the same round; after the last item, the next advance bumps to round N+1 item 0.

### `amrap` — BUILT + TESTED
- **File:** `AMRAPDriver.swift`.
- **Config fields:** `time_cap_sec` (Double, required).
- **Cursor:** round-robin with a 100-row sentinel per item (the wall clock, not set count, terminates).
- **Timer:** VM sets `blockEndsAt = start + time_cap_sec`; `tickBlockTimer()` dispatches `.complete` on elapse.
- **Autoreg:** not applicable.
- **Unbounded-rounds rendering contract (bug-037):** AMRAP's `ActiveContent.totalSets = 0` (exposed as `AMRAPDriver.unboundedRoundsCount`). This is the `ActiveView` contract for "no bound": the progress-dot row is hidden and the meta line renders `ROUND N · REST mm:ss` instead of `SET N OF M · REST mm:ss`. The 100-row cursor sentinel is a seeder internal (`SessionSeeder.unboundedRoundsSentinel`) that never surfaces to the view — if an AMRAP ever exceeds 100 rounds, re-seed; do NOT raise the view sentinel. See `docs/features/execute-loop.md` § "Progress-dot contract".
- **Tests:** `AMRAPDriverTests` (11 cases) + `AMRAPDriverBug037Tests` (2 cases pinning `totalSets == 0` across rounds + the exported constant); integration: `testAMRAPBlockCompletesAtTimeCap` seeds a 30s AMRAP, logs twice, advances the clock 35s, ticks — route becomes `.complete`.

### `for_time` — BUILT + TESTED
- **File:** `ForTimeDriver.swift`.
- **Config fields:** `time_cap_sec` (Double, optional); block-level `rounds_rep_scheme` read from `block.roundsRepSchemeJSON` (e.g. `[21, 15, 9]`).
- **Cursor:** round-robin; driver reads the scheme for the current round's rep count.
- **Timer:** VM sets `blockEndsAt` from `time_cap_sec` when present.
- **Autoreg:** not applicable.
- **Tests:** `ForTimeDriverTests` (14 cases); integration: `testForTimeRoundSchemeRendersEachRoundReps` — cursor walks Fran (3 rounds × 2 items, scheme `[21, 15, 9]`) and each round's driver render reports the scheme's reps.

### `intervals` — BUILT + TESTED
- **File:** `IntervalsDriver.swift`.
- **Config fields:** `work_sec` OR `work_distance_m`; `rest_sec` OR `rest_distance_m`; `interval_count` (Int, required); `target_pace_sec_per_km` (Double, optional).
- **Cursor:** set-major — single item, `interval_count` rows. Seeded via `intervalCount(from:parser:)`.
- **Rest:** time-based uses `rest_sec`; distance-based derives rest from `rest_distance_m * pace`. GPS-driven lap advancement deferred — v1 uses next-lap taps.
- **Autoreg:** not applicable.
- **Tests:** `IntervalsDriverTests` (11 cases).

### `tabata` — BUILT + TESTED
- **File:** `TabataDriver.swift`.
- **Config fields:** NONE — `timing_config_json: {}` by design. Constants hardcoded: 20s work / 10s rest / 8 rounds.
- **Cursor:** round-robin (8 rows per item; multi-item blocks alternate items per round).
- **Timer:** VM sets `blockEndsAt = start + 240s` (8 × 30s total) + per-round `workEndsAt = start + 20s`. When `workEndsAt` elapses, `tickBlockTimer` auto-logs `(reps: 0, rir: nil)` and dispatches `.enterRest` for 10s. Placeholder log documented in `ExecutionViewModel+Persistence.swift` § `autoLogAndRestForTabata`.
- **Autoreg:** not applicable.
- **Tests:** `TabataDriverTests` (11 cases).

### `continuous` — BUILT + TESTED
- **File:** `ContinuousDriver.swift`.
- **Config fields:** `target_duration_sec`, `target_distance_m`, `target_pace_sec_per_km`, `target_hr_zone` (all optional).
- **Cursor:** single-item, single-row — one log completes the block.
- **Autoreg:** not applicable.
- **Tests:** `ContinuousDriverTests` (10 cases); integration: `testContinuousSingleItemCompletesAfterLog`.

### `custom` — BUILT + TESTED (thin renderer)
- **File:** `CustomDriver.swift`.
- **Config fields:** `segments: [{type, duration_sec, label?, target_hr_zone?}]`. Segments parse but v1 does not walk them — the seeder uses set-major advancement reading the item's `sets`, and the user ticks through without the driver imposing segment cadence.
- **Autoreg:** off by default; opt-in per item is a later slice.
- **Tests:** `CustomDriverTests` (9 cases).

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

### S5. AMRAP — time cap routes to complete
- **setup:** `timing_mode: amrap`, `time_cap_sec: 30`, 2 items.
- **steps:** start → log sets → clock advances past 30s → TimelineView tick fires `tickBlockTimer`.
- **expected:** VM dispatches `.complete`; route becomes `.complete`. Verified by `testAMRAPBlockCompletesAtTimeCap`.

### S6. EMOM — interval cadence + round-robin
- **setup:** `timing_mode: emom`, `interval_sec: 60, total_minutes: 3`, 2 items.
- **steps:** log item 0 → enter rest (60s interval) → advance → log item 1 → advance → ...
- **expected:** cursor walks (item 0, 1) → (item 1, 1) → (item 0, 2) → (item 1, 2) → (item 0, 3). `blockEndsAt = start + 180s` terminates on elapse. Verified by `testEMOMCursorRoundRobinsPerInterval`.

### S7. Tabata — hardcoded 20/10/8 with auto-logged placeholder
- **setup:** `timing_mode: tabata`, `timing_config_json: {}`, one item.
- **steps:** start → work window elapses (20s) without user log.
- **expected:** `tickBlockTimer` auto-dispatches `.logSet(0, nil)` + `.enterRest(10s)`. After 10s rest elapses and user advances, the next work window starts. Total block completes at 8 × 30s = 240s via `blockEndsAt`.

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

### S11. Custom — set-major (v1 renderer)
- **setup:** `timing_mode: custom`, item prescribed as `{sets: 3, reps: 10, load_kg: 40}`, segments array in timing config.
- **steps:** execute.
- **expected:** seeder reads the item's `sets` (set-major advancement); segment-walker UI deferred. The user ticks through 3 sets without app-imposed segment cadence.

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
- **expected:** `== 11` (`CoreDomain/Tests/main.swift:9-12`). Regression guard against a dropped mode.
