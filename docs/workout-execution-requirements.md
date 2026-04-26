---
title: workout-execution-requirements
status: draft
purpose: Athlete-facing requirements for how WorkoutDB should execute, time, transition, log, and summarize workout blocks.
covers:
  - docs/workout-taxonomy.md
  - docs/prescription.md
  - docs/features/execute-loop.md
  - docs/features/timing-modes.md
---

# workout-execution-requirements

## Purpose

This document captures athlete/coach intent for workout execution. It deliberately avoids schema design. The implementation can choose the data model later, but it must preserve these behavior contracts.

This is a target-behavior document. Current simulator-verifiable behavior lives in `docs/features/execute-loop.md` and `docs/features/timing-modes.md`. When those feature docs conflict with this document, treat the conflict as a target-vs-current implementation gap until a build plan closes it.

Use this document with `docs/workout-taxonomy.md`:

- `workout-taxonomy.md` names domains, execution archetypes, goal types, and current timing-mode mappings.
- This document defines how those concepts should feel in the app: timers, transitions, logging, edit surfaces, and summaries.

## Core Principles

### Blocks Carry Intent

Blocks should have human-authored titles. The title explains the purpose, while the block goal explains what result matters.

Examples:

- `Easy Run` with target `2 km at 5:06/km`.
- `Fran` with goal `complete prescribed work for time`.
- `Leg Press Finisher` with goal `complete prescribed composite sets`.

The app should display the thing that answers the block's goal. A strength block may care about load/reps/RIR, a for-time block cares about elapsed time, and an AMRAP cares about rounds plus reps.

### Domains Are Lenses, Not Execution Contracts

Strength, CrossFit/metcon, running/endurance, skill, mobility, and recovery are domains. They help planning and analysis, but they do not determine behavior by themselves.

The execution contract comes from the block archetype and goal type. Example: VO2 intervals can appear in running or CrossFit, but both use scheduled interval behavior.

### Goal Type Drives Behavior

Goal type drives:

- Primary timer.
- Manual vs automatic transition.
- Primary result display.
- Completion summary.

Secondary targets are guidance unless promoted to the primary goal. Pace, HR zone, cadence, tempo, and cues can be shown during the block and summarized later, but they should not change transitions or scoring unless the author explicitly makes them the goal.

### Visible Boundaries Follow Purpose

Visible boundaries should appear when purpose, score, or set boundary changes.

Movement changes alone do not always need heavy visual boundaries. A hybrid task like `50 squats -> run 2K -> 50 squats -> run 2K` can feel like one continuous task, while `strength -> AMRAP -> run` should feel like separate pieces.

Inside set-based work, boundaries appear around sets. A set can be simple or composite.

### Active Screen Contract

Every active state should answer:

- What am I doing now?
- What target matters right now?
- What happens next?

Avoid analysis-heavy displays during the workout. Detailed stats belong primarily at the end of the workout.

### Completion Summary Contract

At completion, show:

- Per-block results first.
- Overall session stats second.
- Non-scored blocks as completed/not completed by default.

For scored blocks, show the result matching the goal. For non-scored blocks, preserve details but do not visually compete with scored work.

### Block Result Contract

Each block needs a result object conceptually, even if the first implementation reconstructs it from set logs and notes.

A block result should answer:

- Was the block completed, skipped, capped, or ended early?
- What was the primary result for the authored goal?
- What secondary details explain the result?
- Which set/station/chunk logs support the result?

Examples:

- Strength block: completed, top relevant load/reps, set logs, RIR actuals when authored.
- For-time block: completed or capped, total time, split/station details when tracked, cap partial if unfinished.
- AMRAP block: cap elapsed, completed rounds, extra reps/current partial station.
- Accumulate block: accumulated total, chunk rows, whether target was reached.
- Continuous block: completed target or continued beyond it, duration/distance, pace/zone details.

This contract is schema-neutral. Build planning can decide whether the result is stored as a first-class entity, derived from logs, or temporarily recorded in structured notes.

## Goal Types

### Complete Prescribed Work

Use when the main outcome is doing the prescribed work, not producing a competitive score.

Behavior:

- Guide the user through the work.
- Capture actuals when they differ.
- Summarize completion.
- Preserve progression details when useful, especially strength logs.

Examples:

- `4 x 10 incline DB press @ RIR 2`.
- Accessory circuit not for time.
- Mobility flow.
- Easy recovery work when completion is all that matters.

### Complete Prescribed Work For Time

Use when a fixed body of work is scored by elapsed time.

Behavior:

- One primary running clock for the block.
- Primary result is elapsed time.
- Rest inside the block counts toward elapsed time.
- Transitions are automatic only for detectable goals such as time or distance.
- Reps or user-judged stations require user transition.
- End summary shows total time first, then splits or station details.
- User usually wants lap/split/station tracking, but the author can allow whole-task tracking without detailed laps.

Examples:

- `21-15-9 thrusters/pull-ups`.
- `5 rounds: 400m run + 15 KB swings`.
- `50 squats -> run 2K -> 50 squats -> run 2K`.

### Max Work In Fixed Time

Use when the time cap is fixed and the result is work completed.

Behavior:

- One primary global countdown for the block.
- The countdown belongs to the block, not the current station.
- Rest inside the cap counts because the timer never stops.
- For station/round blocks, the app tracks completed stations and captures the partial current station at the buzzer.
- For a single repeated effort, result is total reps, sets, calories, distance, or other authored work unit.
- At buzzer, ask only for unfinished or partial work the app cannot infer.

Examples:

- `12 min AMRAP: 5 pull-ups, 10 push-ups, 15 squats`.
- `15 min density bench: as many 5-rep sets as possible`.
- `Max calories in 10 min`.

### Hit Duration Or Distance Target

Use when the goal is reaching a duration or distance.

Behavior:

- Active screen shows progress toward target plus current context.
- If the target is detectable, the app may notify and auto-transition/complete depending on context.
- Auto-transition makes sense when the target is part of a larger prescribed sequence.
- Standalone efforts may notify and allow the user to continue.
- User should have the option to continue when appropriate.
- Result is actual duration, distance, pace, HR, and cadence where available, or completion-only if non-scored/easy.

Examples:

- `Run 10K easy`.
- `Ride 60 min Z2`.
- `Row 2K`.
- `Walk 30 min recovery`.

### Hit Pace Or Zone Target

Use as a primary goal only when the author intends compliance to be the main purpose. Otherwise treat pace/zone as guidance.

Behavior:

- Show current vs target when useful.
- Drifting from pace or HR zone does not automatically fail or transition the block.
- Result can summarize actual average pace/HR and time-in-zone later.
- Transition is controlled by duration, distance, time, or work completion, not by perfect compliance.

Examples:

- `45 min Z2`.
- `Tempo 20 min @ 5:15/km`.
- `Run 2K at 5:06/km`.
- `Keep HR under zone 4`.

### Repeat Intervals

Use when repeated work/rest or repeated start boundaries define the block.

Behavior:

- Current interval timer is primary.
- Show interval number, target, and next interval/rest.
- Auto-transition when the boundary is time-based or sensor-detectable.
- Manual transition when the interval goal is reps or user-judged completion.
- Manual override, skip, and advance are always available.
- Summary shows interval completion plus splits/details.
- When relevant, show all splits first and highlight best and average.

Intervals can carry attached goals:

- Max reps in a work interval.
- Best split for a fixed distance.
- Pace target.
- HR target or HR floor/ceiling.
- Prescribed reps/load in EMOM-style work.

Example: `6 x 400m for min time` is repeat intervals plus max-effort scoring per repeat.

### Max Effort Test

Use when the primary result is the best achieved metric.

Behavior:

- Primary result is the tested metric: load, reps, duration, distance, or time.
- App should make the tested metric obvious during and after the block.
- Attempts or sets can be logged normally.
- Summary surfaces the best/top achieved result.
- This can be an overlay on a normal block; it does not require a separate exotic mode.

Examples:

- Work up to a 1RM.
- Max reps at 225.
- Max dead hang duration.
- Cooper test: max distance in 12 min.
- 5K time trial.

### Practice Or Quality Work

Use when completion and quality focus matter more than score.

Behavior:

- Completion-first unless the author explicitly marks a metric.
- Active screen emphasizes cue/quality focus and next action.
- Logs can be lightweight: completed, duration, attempts if useful, notes.
- Completion summary should not over-emphasize these compared with scored blocks.

Examples:

- Handstand attempts.
- Double-under practice.
- Technique work.
- Mobility practice.

### Accumulate Target

Use when the user can break the target into bouts however needed.

Behavior:

- Active screen shows accumulated / target.
- Chunk or bout rows appear underneath.
- Rest between bouts is free/unprescribed by default.
- `Break` creates a bout/chunk row.
- If the app can detect the amount, it fills the row automatically.
- If the app cannot detect the amount, the row is empty/editable.
- User can fill chunks inline or at the end.
- Avoid heavy modal sheets for every chunk.

Examples:

- `1:17 / 2:00 hang`.
- `65 / 100 push-ups`.
- `50 / 100 ft carry`.

## Execution Archetypes

### `set_based`

Use for strength, hypertrophy, load-bearing skill, and any block where the authored set is the main boundary.

Primary user promise:

- The user always knows whether they are preparing, working, or resting.
- Starting a set is explicit.
- Ending a set immediately starts the next rest.
- Logging/editing happens while rest continues in the background.
- The timer is never absent after the workout starts.

Default flow:

1. Ready for set.
2. User taps `Set Start`.
3. Set timer runs.
4. User taps `Done`.
5. Set timer stops.
6. Next rest starts immediately.
7. User enters/edits reps, load, RIR when authored, and notes while rest runs.
8. Rest reaches zero, then over-rest counts up until the next `Set Start`.

States:

- **Ready / pre-set:** shown after workout start and before `Set Start`. Primary timer is a low-pressure ready/prep count-up so the active workout is never timerless. Main action is `Set Start`; `Done` is unavailable.
- **Active set:** primary timer is set elapsed time. Primary action is `Done`. The current target is visually co-equal with the timer: load/reps/tempo/RIR target when authored. Next exercise or next set appears smaller.
- **Rest / log:** primary timer is rest countdown or over-rest count-up. The just-finished set appears as editable row content. The next target is visible and updates if edits or autoreg change it.
- **Over-rest:** rest timer turns red and counts up from zero. Add-time controls remain available. Starting the next set records the actual rest duration implicitly.
- **Complete block:** block contributes a completion/result card to the workout summary; strength progression details remain available below the primary block result.

Rules:

- All set-based sets require explicit `Set Start` for now.
- `Done` is not available before `Set Start`.
- If the user forgot to start, recovery is simple: tap `Set Start`, then `Done`; no special correction path is required for now.
- Starting early truncates the current rest and starts the set timer.
- Add-time controls are available during rest countdown and over-rest.
- Adding enough time during over-rest can return the timer to countdown.
- Rest screen is the main place to edit the just-finished set.
- Rest screen should show the just-finished set and the next set target.
- Next target should update when edits/autoreg affect it.
- RIR is primarily a strength/hypertrophy target.
- Different exercises and sets can have different RIR targets.
- Do not force RIR onto non-strength stations or work types unless authored.

Natural interactions:

- Tap `Set Start` to begin work.
- Tap `Done` to end work.
- Tap load/reps/RIR cells in rest to edit inline or open the smallest possible sheet.
- Tap next target for read-only preview.
- Long-press current exercise for swap/substitution where alternatives exist.
- Add time from rest countdown or over-rest without leaving the rest screen.

Composite sets:

- A set can be simple or composite.
- The author chooses what counts as a set.
- A composite set is a flat list of slots. Do not recurse into sets inside sets.
- Slot transitions can be guided or collapsed.
- "Collapsed" only hides slot transitions inside a composite set. It does not hide transitions between sets, stations, blocks, or workout pieces.
- Guided/collapsed default is authored per set.
- User can override guided/collapsed for that set during the workout.
- If guided transitions are on, internal work/rest slots behave like mini transitions: start work, stop work, rest, start next work.
- If guided transitions are off, the app tracks the whole composite set as complete.
- RIR is always one value per set, not per slot.
- For composite sets, RIR is anchored to the final work slot / end of the set.
- Composite slot actuals default from prescription but can be expanded and edited after the set.

Composite examples:

- Simple set: `10 reps @ 40 lb`.
- Composite set: `10 reps -> rest 15s -> 7 reps -> rest 15s -> 5 reps`.
- Mixed set block: sets 1-5 are `5 reps`; set 6 is `10 + 7 + 5 + 4`.

Set-based QA acceptance:

- Starting a workout on a set-based block shows a visible running ready/prep timer before the first `Set Start`.
- `Done` cannot be triggered before `Set Start`.
- `Done` immediately starts rest without waiting for the log edit to complete.
- Rest expiry turns into red over-rest count-up.
- Starting the next set records/uses the true rest elapsed rather than the prescribed rest.
- Editing load/reps/RIR during rest updates the just-finished row and does not pause rest.
- If autoreg changes the next target, the next target display updates before the next `Set Start`.
- Composite collapsed mode logs the whole authored set as one set-level result.
- Composite guided mode exposes internal rest/work slot transitions, but still records one set-level RIR at the end.
- Expanding a completed composite set allows slot actuals to be corrected after the set.

Assumptions:

- Strength-like round-robin stations can use set-level RIR only when authored; do not ask RIR for every station by default.
- Failure is represented by RIR 0 unless a later requirement introduces a separate intentional-failure flag.

### `round_robin`

Use for repeated stations across rounds where the block is not primarily scored by time.

Behavior:

- Show current station, current round, and next station.
- Transition behavior follows goal detectability.
- Reps/manual stations require user transition.
- Time/distance/detectable stations may auto-transition if authored that way.
- Rest between stations or rounds is explicit and visible.
- If not scored, completion is the main result and details are preserved underneath.

Assumptions:

- Supersets and circuits share this archetype. Superset is the 2-exercise convention; circuit/giant set is the N-station convention.
- Strength-like stations can show/edit load/reps/RIR as authored, but RIR should not be forced on every station unless useful.
- If the author wants one shared rest after a pair/group, the app should present the group clearly but still transition through stations as authored.

States:

- **Ready:** show block title, round count, station list, and whether logging is station-by-station or batch-at-rest.
- **Active station:** show current station target, next station, round progress, and one primary action: `Done` / `Next Station`.
- **Between-station rest:** optional short rest when authored between stations.
- **Round rest/log:** shared rest after the last station in a round. Batch logging appears here when authored that way.
- **Complete block:** all authored rounds are complete, or the athlete ends the block early with completed station/round details preserved.

Natural interactions:

- Tap `Next Station` / `Done` to complete the current station and move on.
- Tap `Skip Rest` only when manual override is available.
- Correct just-finished station actuals during station rest or shared round rest.
- Batch-edit all stations from the completed round during shared rest when authored.
- Long-press station/exercise for swap where alternatives exist.
- End early and preserve completed station/round details.

Round-robin QA acceptance:

- A two-station superset and an N-station circuit use the same ordered-stations-inside-rounds state machine.
- In batch-log mode, no station actual sheet is forced mid-round; the round rest screen exposes all stations from the completed round.
- Supersets default to `batch_at_round_rest`; circuits default to `station_by_station`. Either can be overridden by `timing_config_json.logging_mode`.
- In station-log mode, each `Next Station` marks or creates one completed station row.
- Between-station rest and between-round rest are independently visible when authored.
- RIR controls appear only for authored strength-like stations.
- Completion summary shows rounds/stations completed first, then station details.

### `task_for_time`

Use for fixed work scored by elapsed time.

Behavior:

- One overall count-up timer.
- Show current station, target, and next station.
- Detectable stations can auto-transition.
- Reps/manual stations use user transition.
- Rest inside the block counts toward elapsed time.
- If a time cap exists, warn/stop at cap and capture partial work.
- Summary shows total time first, then station splits/details.
- User usually wants laps/splits/station tracking.
- Author can allow tracking the whole task as done without detailed laps.

Assumptions:

- For capped task-for-time, capture current station and partial progress at cap, similar to AMRAP, unless the station's progress is detectable.
- If a scored task contains rest, the rest counts toward the score.

States:

- **Ready:** show work list, scoring rule, optional cap, and whether the block is finish-only or split-tracked.
- **Active finish-only:** show one elapsed clock, the work list, and a primary `Finish` action.
- **Active split-tracked:** show one elapsed clock, current station/split highlighted, next target visible, and a `Next Split` / `Next Station` action.
- **Detectable transition:** duration/distance stations may auto-advance or prompt when the target is detected.
- **Cap partial:** if the cap expires before finish, capture completed splits/stations and the current partial.
- **Finished:** athlete explicitly finishes, or the final detectable target completes.

Natural interactions:

- Tap `Finish` for whole-task completion.
- Tap `Next Split` / `Next Station` when split tracking is enabled.
- Accept sensor-detected duration/distance transitions when available.
- Undo the most recent split/station advance before final save.
- Enter partial completion only when a cap stops the block before the work is done.

Task-for-time QA acceptance:

- Finish-only for-time can complete with exactly one athlete action after start: `Finish`.
- Split-tracked for-time records total elapsed time plus ordered splits/stations.
- Total time remains the primary result even when split/station rows exist.
- Rest inside the block counts toward elapsed time.
- Detectable duration/distance targets can transition without requiring manual station taps.
- Rep/user-judged stations require manual transition.
- A capped unfinished block saves `capped`, cap elapsed time, completed station/split details, and current partial.
- A capped completed block summarizes as completed before cap, not as AMRAP rounds/reps.

### `time_boxed_max_work`

Use for AMRAP/density-style fixed-cap work.

Behavior:

- One global countdown.
- Show current station/round and next station.
- `Next` means current station completed.
- At buzzer, capture partial current station only.
- User can end early.
- Summary shows rounds + reps first, then details.

Assumptions:

- For a single repeated effort, show accumulated completed work over the cap.
- Rest inside the cap counts; the cap never pauses.
- Ask only for what the app cannot infer at the cap.

States:

- **Ready:** show cap duration, scoring unit, and round/station structure or single-effort target.
- **Active station:** show global countdown, current station, round count, and `Next` to mark the station completed.
- **Active single effort:** show global countdown plus quick-add/log controls for the authored unit such as reps, calories, distance, or completed sets.
- **Buzzer partial:** cap expires; capture only the current unfinished work the app cannot infer.
- **Ended early:** athlete stops before cap; preserve elapsed time and work completed so far.
- **Summary:** show rounds plus reps/stations, total work, or authored-unit total depending on the goal.

Natural interactions:

- Tap `Next` to stamp a completed station.
- Add completed sets/reps/calories/distance for single-effort variants.
- Let the buzzer open a focused partial sheet.
- End early and keep the work completed so far.
- Correct the current partial before saving the block result.

Time-boxed max-work QA acceptance:

- The primary timer is always the global cap countdown.
- Station-based AMRAP `Next` logs the current station as completed and advances the cursor.
- Completed rounds are derived from completed station rows, not from a separate manually entered round count.
- At cap expiry, the result sheet captures only unfinished/current partial work the app cannot infer.
- Prior completed stations are checkmarked/locked on the partial sheet; unreached stations are locked.
- Single-effort variants summarize the authored total work unit, not rounds plus reps.
- Ending early records elapsed time and completed work with `ended_early`, distinct from `capped`.
- RIR controls appear only when explicitly authored for strength-like density work.

### `scheduled_intervals`

Use for repeated time/distance/start-boundary work.

Behavior:

- Current interval timer is primary.
- Show interval number, target, and next interval/rest.
- Auto-transition for time/distance-detectable boundaries.
- Manual transition for reps/user-judged boundaries.
- Manual override is always available.
- Attached goals decide what is emphasized/logged for each work interval.
- Summary shows all intervals/splits; highlight best/average when relevant.

Rest and transitions:

- Rest/transition inside scheduled intervals can auto-transition at zero.
- Auto-transition is immediate and not padded with an implicit grace period.
- Notify the user at the transition.
- If more time is needed, the author should prescribe a rest/transition slot.

Assumptions:

- Missed rep-based interval work should create an editable row rather than silently logging success.
- Time-based work can auto-log duration when the timer owns the boundary.
- Distance-based work can auto-transition when sensor support exists; otherwise manual transition is acceptable.

Current implementation note:

- Until a first-class missed/partial interval row exists, manually judged scheduled work that expires without `Done` advances the clock schedule but does not create a completed `0 reps` set. This is intentional: no row is better than a false success row.
- Distance intervals currently degrade to elapsed-time + manual lap/advance. Target pace is displayed as guidance only and is not used to infer completion.

States:

- **Ready / interval preview:** show full interval count, first interval target, and what follows.
- **Active interval:** primary display is the current interval timer or detectable progress target.
- **Set-like interval awaiting start:** for EMOM/E2MOM strength-style work, the interval clock may already be running, but the set row still requires `Set Start` before `Done` can log that set as completed.
- **Rest / transition slot:** primary display is the rest/transition countdown. The next interval is visible before auto-transition.
- **Manual boundary pending:** reps or user-judged completion waits for `Done`, `Next`, or `Skip`; success is not inferred.
- **Missed / partial interval:** if manually judged work is not completed before the next scheduled boundary, create an editable missed/partial row instead of silently logging success.

Natural interactions:

- Tap `Start Block` to begin the scheduled sequence.
- Tap `Set Start` for set-like interval work when actual work timing matters.
- Tap `Done` or `Next` for reps/user-judged interval completion.
- Tap `Skip` to mark an interval as skipped or missed.
- Tap an interval row during rest or after the block to correct reps, load, distance, split, or missed/partial status.
- Use manual override to advance early while preserving actual elapsed/split detail.

Scheduled-interval QA acceptance:

- A time-based interval auto-transitions exactly at zero with no hidden grace period.
- A prescribed rest/transition slot auto-transitions exactly at zero and notifies the user.
- A reps/user-judged interval does not auto-complete when its scheduled time expires.
- EMOM-style set work requires `Set Start` before `Done` can log the set as completed.
- If a manual interval expires without completion, the target state is an editable missed/partial row; current implementation leaves the set unlogged rather than fabricating a `0 reps` completion until that row type exists.
- Distance intervals auto-transition only when sensor detection is available; otherwise the user must manually advance.
- Manual override advances the sequence while preserving actual split/elapsed detail.
- Summary shows every interval row and highlights best/average when relevant.

### `continuous_target`

Use for sustained work toward a target.

Behavior:

- Show progress toward target and current context.
- Target completion can auto-transition if part of a larger sequence.
- Standalone target efforts may notify and allow the user to continue.
- If non-scored, summary is completed.
- If scored/test, summary shows the result.
- Secondary pace/HR targets are guidance.

Assumptions:

- Segmented continuous does not need a separate archetype for now. Compose it from multiple continuous target blocks that can auto-transition.
- When a larger composed thing is timed, the UI can show an overall timer alongside the current block/set timer.

States:

- **Ready / target preview:** show target duration or distance, secondary guidance, and whether reaching the target completes or continues the block.
- **Active target:** primary display is progress toward the duration/distance target. Secondary pace, HR, cadence, or zone guidance is visible but not completion logic.
- **Target reached / continue prompt:** standalone efforts notify at target and offer `Complete` or `Continue`.
- **Auto-transition target reached:** composed sequence efforts notify and transition automatically when the target is time-based or sensor-detectable.
- **Continuing beyond target:** progress remains visible, but the display makes clear the authored target has already been met.
- **Complete block:** summary records actual duration/distance plus secondary details where available.

Natural interactions:

- Tap `Start` to begin the effort.
- Tap `Complete` at the target for standalone efforts.
- Tap `Continue` to keep recording beyond the authored target.
- Tap `End Early` to stop before the target and record an incomplete/ended-early result.
- Tap secondary target details to view guidance without changing transition behavior.
- In composed sequences, use manual override when the detectable target failed or the athlete needs to move on early.

Continuous-target QA acceptance:

- Active display always shows progress toward the authored duration or distance target.
- Pace/HR/zone drift never auto-fails or auto-transitions the block.
- A standalone duration/distance target notifies at completion and allows the athlete to continue.
- A composed duration/distance target auto-transitions only when completion is time-based or sensor-detectable.
- Continuing beyond target records actual work beyond the authored target.
- Ending early records an incomplete/ended-early result instead of pretending the target was met.
- Summary shows target status first, then actual duration/distance and secondary pace/HR/cadence details where available.

### `accumulate_target`

Use for target totals that can be broken into free bouts.

Behavior:

- Show accumulated / target as the primary display.
- Show bout/chunk rows underneath.
- `Break` creates a chunk and starts free rest.
- Detectable chunks fill automatically.
- Non-detectable chunks create editable rows.
- User can resume until target is reached.
- Summary shows total target completed and the chunk breakdown.

Assumptions:

- Dead hang duration is detectable by the app timer after user break/resume.
- Push-up reps are manually entered into chunk rows.
- Carry distance may be sensor-detected or manually entered depending on implementation.

States:

- **Ready / accumulate preview:** show total target, current accumulated amount, and expected chunk unit.
- **Active bout:** primary display is current bout plus accumulated / target. Detectable bout amount fills automatically; non-detectable work waits for entry.
- **Break / free rest:** `Break` closes the current bout, creates a chunk row, and starts unprescribed rest.
- **Chunk editing:** current and previous chunk rows are editable inline without a heavy modal flow.
- **Resume:** starts the next bout and keeps accumulated total visible.
- **Target reached:** notifies the athlete and offers completion.
- **Complete block:** summary shows total accumulated amount and chunk breakdown.

Natural interactions:

- Tap `Start` or `Resume` to begin a bout.
- Tap `Break` to end the current bout and create a chunk row.
- Edit chunk amount inline when reps, distance, duration, or load cannot be inferred.
- Tap a chunk row to correct a detected or manually entered value.
- Tap `Complete` once the target is reached.
- Tap `End Early` to preserve partial accumulated work.

Accumulate-target QA acceptance:

- Active display always shows accumulated / target as the primary result.
- `Break` creates a visible chunk row and starts free rest.
- Timer-detectable chunks, such as hang duration, fill their row automatically.
- Non-detectable chunks, such as push-up reps, create editable empty or draft rows.
- Editing a chunk updates the accumulated total immediately.
- `Resume` starts a new bout without deleting or overwriting prior chunks.
- Reaching the target notifies the athlete and allows completion.
- Ending early records the partial accumulated total and all completed chunk rows.
- Summary shows total accumulated amount first and chunk breakdown second.

### `rest_transition`

Use for explicit non-work time.

Behavior depends on context:

- Strength between-set rest: countdown reaches zero, then over-rest counts up until `Set Start`.
- Clock-driven rest/transition: auto-transition immediately at zero.
- Rest inside scored work counts toward the score.
- Rest outside scored work is completion/guidance only.
- Transition is rest with a purpose label, not a separate athlete action.

Display:

- `REST 1:30` for recovery.
- `TRANSITION 0:15` for moving/setup.
- `EASY 2:00` for jogging recovery, if authored that way.

States:

- **Strength-style rest:** starts immediately after `Done`, counts down to zero, then becomes over-rest until the next `Set Start`.
- **Interval-style rest / transition:** starts as a scheduled clock-owned slot and auto-transitions immediately at zero.
- **Manual-start rest:** used only when the athlete must explicitly begin a rest block or standalone recovery period.
- **Scored-work rest:** rest is visible but the parent scored timer continues to run.
- **Standalone recovery:** primary result is completion or elapsed recovery time, not a scored performance result.
- **Over-rest:** applies to strength-style rest only; countdown turns into count-up past zero until the next work start.

Natural interactions:

- Tap `Add Time` during manual strength/recovery countdown or over-rest.
- Tap `Set Start` to end strength-style rest and begin the next set.
- Tap `Skip Rest` or `Next` only when manual override is available.
- Tap rest label/details to distinguish `REST`, `TRANSITION`, `EASY`, or `RECOVERY`.
- In scored work, use rest controls without pausing the parent score timer.

Rest-transition QA acceptance:

- Strength between-set rest starts immediately after `Done`.
- Strength rest reaches zero and becomes over-rest until `Set Start`.
- Starting the next set records the actual rest duration, including over-rest.
- Interval-style rest auto-transitions exactly at zero with no hidden grace period.
- Rest inside scored work does not pause the parent scored timer.
- Add-time changes a manual recovery countdown and can move over-rest back into countdown.
- Clock-owned rest/transition slots do not expose add-time controls and ignore direct add-time requests.
- Transition labels are visible and distinguish setup/movement time from recovery rest.
- Standalone recovery can be completed without creating a scored result.

## Transition Rules

Transition mode follows goal detectability:

- If the app/watch can detect completion, it may auto-transition.
- If completion depends on reps or user judgment, the user transitions.
- The user can always override.

Examples:

- `Run 2K`: auto-transition when distance is detected; user can transition early.
- `Work 45s`: auto-transition when timer hits.
- `Rest 90s` before a strength set: over-rest until user starts.
- `50 squats`: manual transition.
- `EMOM`: automatic boundary because time owns the transition.

Automatic transition:

- Switches immediately.
- Notifies the user.
- Does not add hidden transition time.

## Logging And Editing

During execution:

- Keep focus on current target and next action.
- Do not overload active/rest screens with analysis.

Rest/log surface:

- For set-based work, rest is the primary log/correction moment.
- Rest timer keeps running during edits.
- User can edit reps, load, RIR when authored, composite slot actuals, and notes.

Completion surface:

- Show per-block goal results first.
- Show overall session stats second.
- Preserve details for later analysis.
- Non-scored blocks show completed/not completed by default.

## Completion And Result Flow

The completion flow should summarize the workout at the same conceptual level the athlete used during execution: block first, details second.

States:

- **Block finished:** a block reaches its authored completion, cap, early-end, or skipped state.
- **Workout complete:** all blocks are finished or intentionally ended.
- **Summary review:** show per-block result cards, then overall session stats.
- **Detail drill-down:** show set logs, station rows, interval rows, chunks, notes, and corrections beneath the block card.
- **Correction mode:** allow post-workout corrections without re-running live timers or autoreg unless explicitly designed later.

Result card rules:

- Scored blocks lead with the score: time, rounds plus reps, total accumulated work, best/max metric, or interval result.
- Non-scored blocks lead with completion state: completed, partial, skipped, or ended early.
- Strength/hypertrophy blocks are usually progression-detail blocks, not single-score blocks, unless authored as a max-effort or top-metric goal.
- Mixed workouts show block results in workout order, not sorted by score importance.
- Overall session stats are secondary: total duration, work/rest balance, total volume, distance, calories, and other cross-block metrics when available.

Natural interactions:

- Tap a block result card to expand details.
- Tap a row to correct actuals.
- Add or edit notes at workout, block, set/station, or chunk level where supported.
- Save corrections without changing authored workout targets.
- Export/push result data after corrections are saved.

Completion QA acceptance:

- Every finished block has a visible completion state.
- Scored blocks show their goal-matching result before supporting details.
- Non-scored blocks do not compete visually with scored blocks.
- Capped, ended-early, skipped, and completed states are distinguishable.
- Corrections update summaries without restarting timers or applying live-transition behavior.
- Composite sets, AMRAP partials, for-time cap partials, intervals, continuous efforts, and accumulate chunks can all be inspected after completion.
- Workout-level stats never hide the per-block result cards.

## QA Coverage Matrix

Simulator QA should separate current implementation coverage from target-flow coverage. A target-flow scenario can exist before implementation, but it must be labeled as blocked until the app supports the required state.

| Archetype / flow | Happy path | Boundary path |
|---|---|---|
| `set_based` | Start set, finish, edit load/reps/RIR during rest, start next set. | Rest expires into over-rest; composite guided/collapsed set; forgotten start recovery. |
| `round_robin` | Complete a superset/circuit through all stations and shared rest. | Batch-log vs station-log; between-station rest; early end mid-round. |
| `task_for_time` | Finish-only block completes with total time. | Split-tracked capped block captures current partial and preserves total elapsed cap time. |
| `time_boxed_max_work` | AMRAP global cap, station `Next`, summary rounds plus reps. | Buzzer partial sheet; single-effort accumulation; end early distinct from capped. |
| `scheduled_intervals` | Timed intervals auto-transition with rest slots. | Rep/user-judged interval expires into missed/partial row; manual override preserves split. |
| `continuous_target` | Standalone target notifies and allows complete/continue. | Composed target auto-transitions only when detectable; end early records incomplete result. |
| `accumulate_target` | Bout/break/resume reaches accumulated target. | Manual chunk edit updates total; end early preserves partial accumulated work. |
| `rest_transition` | Strength rest counts down, over-rests, next `Set Start` records true rest. | Interval rest auto-transitions; rest inside scored work does not pause parent timer. |
| Completion/results | Scored and non-scored block cards summarize correctly. | Corrections update result cards without live timer/autoreg side effects. |

Coverage rules:

- Every active route must expose one visible primary timer.
- Every automatic transition must have a paired manual override scenario.
- Every manual transition must prove the app does not infer success silently.
- Every result type must be visible at completion and inspectable after save.
- Every target-vs-current gap discovered in QA belongs in `docs/bugs.md` if it is a current bug, or the implementation backlog if it is not built yet.

## Current Timing Mode Mapping

| Timing mode | Target archetype | Notes |
|---|---|---|
| `straight_sets` | `set_based` | Needs explicit `Set Start`, set elapsed, automatic rest start, over-rest, and composite-set support. |
| `superset` | `round_robin` | Two-station convention; shared round rest when authored. |
| `circuit` | `round_robin` | N-station convention; supports mixed targets as authored. |
| `for_time` | `task_for_time` | Needs total-time result and optional station/split tracking. |
| `amrap` | `time_boxed_max_work` | Global cap; station completion via `Next`; partial current station at buzzer. |
| `emom` | `scheduled_intervals` | Time-owned boundary; per-interval target. |
| `intervals` | `scheduled_intervals` | Time/distance repeats; splits and attached goals. |
| `tabata` | `scheduled_intervals` | Fixed 20/10 structure with interval goals. |
| `continuous` | `continuous_target` | Target duration/distance/pace/zone and continue/transition behavior. |
| `rest` | `rest_transition` | Context controls manual vs automatic transition. |
| `custom` | Escape hatch | Should not be a primary authoring concept when a stricter archetype fits. |

## Assumptions To Carry Into Build Planning

- The current schema may not support every requirement cleanly; implementation planning must decide whether to extend JSON shapes or add first-class results later.
- A first-class block result is likely useful, but not required to define athlete behavior.
- Calories, side-specific work, per-hand vs total load, sled/carry load basis, attempts/success, and quality notes need concrete authoring conventions.
- Sensor-driven distance/pace/HR behavior can degrade to manual transition/editing until Watch/GPS support is built.
- The app should prefer simple inline edits over modal chains during workouts.

## Hard Open Questions

These are intentionally left open because they are implementation/data-model choices or require later product tradeoffs:

- Whether to add a first-class `block_result` entity or reconstruct scores from set logs plus notes.
- How to persist composite set slot actuals.
- How to represent calories and machine work.
- How to represent side/per-hand/load-basis for carries and unilateral work.
- How much sensor support is v1 vs later: GPS distance, pace, HR, cadence, splits.
- Whether attempts/success/quality deserve structured fields or notes-only at first.
