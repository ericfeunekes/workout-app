---
title: history
status: living
purpose: Behavioral contract + QA scenarios for history
covers:
  - app/Packages/Features/History/Sources/FeaturesHistory/HistoryViewModel.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistoryViewModel+Load.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistoryViewModel+Derivation.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistoryListView.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistoryRow.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistorySessionDetailView.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/HistoryByExerciseView.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/SessionDetailViewModel.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/SessionDetail.swift
  - app/Packages/Features/History/Sources/FeaturesHistory/TrendComputation.swift
  - app/Packages/Persistence/Sources/Persistence/WorkoutCache+History.swift
---

# history

## What it does
`HistoryViewModel.load()` pulls completed workouts (limit 200) from `WorkoutCache.loadCompletedWorkouts` newest-first by `completedAt` (`WorkoutCache+History.swift:39`), plus their set_logs and item lookups, into `rawSessions` (`HistoryViewModel+Load.swift:34`). Derivation filters by `activeSplit`, groups by `(year, weekOfYear)` into `WeekGroup`s with headers "THIS WEEK" / "LAST WEEK" / "APR · WEEK 15" (`HistoryViewModel+Derivation.swift:198`). `HistoryListView` renders groups in a `DSCard` of `NavigationLink(value: workoutID)` rows (`HistoryListView.swift:74`). Tap → `HistorySessionDetailView` bound to a `SessionDetailViewModel` that buckets set_logs by `performedExerciseID ?? plannedExerciseByItem[itemID] ?? workoutItemID` (`SessionDetailViewModel.swift:116`) and renders "N · weight × reps · RIR" set rows (`:146`). A "BY EXERCISE →" chip flips `tab` to `.byExercise` → current-program-first picker → per-exercise detail with `TrendComputation.compute` producing "↑ 12.5 KG / 12 WK" (`TrendComputation.swift:82`).

## State surface
- **Inputs:** `WorkoutCache` (completed workouts, blocks, items, set_logs, exercises, planned workouts), `calendar`, `now`, `telemetry: TelemetryEmitter`, `onSetLogEdited: HistorySetLogEditHook?` (shell-wired to `SyncAPI.pushLog`).
- **Outputs / side effects:** `groups: [WeekGroup]`, `pickerRows: [ExercisePickerRow]`, `isLoading: Bool`, `tab: Tab`, `activeSplit: SplitFilter`. History is mostly read-only; the single write path is `editPastSet(workoutID:setLogID:reps:rir:loadKg:)` — writes the updated SetLog to `WorkoutCache.saveSetLogs`, emits `history.past_set_edited`, fires `onSetLogEdited` for server push (same UUID → upsert-in-place), and re-runs `load()` so the detail view re-derives.
- **State transitions:** `setSplit` → re-derive groups only (no reload). `setTab` → flip list/byExercise (no reload). `load()` → set `isLoading`, re-pull everything, re-derive. `editPastSet(...)` → local write, push enqueue, telemetry emit, reload. Errors during load leave cached shapes as-is (`HistoryViewModel+Load.swift:25`).

## What it deliberately doesn't do
- Does NOT show charts, body-weight trends, volume/RIR heatmaps, PR detection (`app/README.md:153`).
- Does NOT search exercises in the picker (`HistoryByExerciseView.swift:8`).
- Does NOT render trend line when only 1 session exists (`TrendComputation.swift:91`).
- Does NOT retrigger autoreg on a corrective edit — History edits mark the SetLog directly via `saveSetLogs` and never pass through the live `SessionReducer` (completed workouts have no live state). Mirrors `SessionReducer.applyEditPastSet`'s `.manual` semantics on the execution side.

## Edge cases handled in code
- **`HistoryRow` tap regression** (fixed 2026-04-18, `docs/open-questions.md:270`): `HistoryRow` used to be a `Button(action: onTap)` nested inside `NavigationLink(value:)` — the inner Button swallowed the tap. Flattened to a plain VStack (`HistoryRow.swift:16-51`). **Watchlist: any new row variant that re-introduces an inner `Button` will re-break this.**
- `completedAt == nil` falls back to `scheduledDate` for sort (`WorkoutCache+History.swift:40`, `SessionDetail.swift:152`). Undated sessions bucket under an "UNDATED" group (`HistoryViewModel+Derivation.swift:124`).
- Cross-entity SwiftData `#Predicate` joins are avoided — two-step walks for workout → blocks → items → set_logs (`WorkoutCache+History.swift:52`).
- By-exercise union covers both planned items with `exerciseID == exerciseID` AND set_logs with `performedExerciseID == exerciseID` (mid-workout swap), de-duped by id (`WorkoutCache+History.swift:99-128`).
- Unknown-exercise fallback: `exerciseName[id] ?? "(unknown exercise)"` (`SessionDetailViewModel.swift:135`).
- Tag parser accepts `push`, `push_day`, `PushDay`, `pushday` case-insensitively (`SessionDetail.swift:28`).
- Session detail card order is "first set_log appears" order — cache returns in (block position, item position, setIndex) so deterministic per pull (`SessionDetailViewModel.swift:99`).

## Known issues / gaps
- Set-index render bug (bug-020) closed — `formatSetRow` now uses `setIndex` as-is; runtime pipeline is 1-based throughout.
- `SessionDetail.bodyweightKg` now hydrates from `WorkoutCache.loadUserParameters(key: "bodyweight_kg")` with a ±2min window around `completedAt` (bug-060). HistoryPreviewSeed includes a bodyweight sample so the chip exercises in previews too.
- `EditSetSheet` is unit-aware (bug-051): labels per source `weightUnit`, carries the unit through the write path via `formatLoad(weight:unit:)`, caps reps at 999, and exposes RIR clear via an explicit enum state instead of a nil-sentinel.
- Recent-sessions grouping keys off `workoutID` (the R1.3b-v2 denormalized column on `SetLogModel`) rather than `workoutItemID`, so same-day workouts no longer collapse into one session.
- By-exercise detail no longer mixes `lb` and `kg` numerically — top-set and trend deltas render in the source unit (bug-051 / bug-059).
- Post-save refresh is wired end-to-end. The shell's `afterLocalCompletion` closure calls `historyViewModel.load()` after the local cache write + today-loader rerun (ordering: cache write → TodayLoader reload → History reload). Post-pull refresh still relies on `.task` on `HistoryView` re-firing.

## QA scenarios

### S1. Happy path — list renders newest-first grouped by week
- **setup:** Seed 6+ completed workouts across 3 weeks.
- **steps:** Open History tab.
- **expected:** Top group header "THIS WEEK", then "LAST WEEK", then dated headers like "APR · WEEK 15". Within each group, newest first by `completedAt`.

### S2. Row tap pushes session detail (regression fix)
- **setup:** Any populated History list.
- **steps:** Tap a row.
- **expected:** `NavigationLink(value: row.id)` fires → `HistorySessionDetailView` appears.
- **notes:** This is the `docs/open-questions.md:270` regression. If you add a new row variant with an inner `Button`, S2 will fail.

### S3. Split filter chips
- **setup:** 3 workouts tagged `push_day`, `pull_day`, `leg_day` respectively; one untagged.
- **steps:** Tap each chip in order: ALL / PUSH / PULL / LEGS.
- **expected:** ALL shows all 4. PUSH shows only the push_day row. LEGS shows only the leg_day row. **Untagged workout is only visible under ALL** (`SessionDetail.swift:81` — empty tag set).

### S4. Set index cosmetic bug (watchlist)
- **setup:** Any completed session with ≥2 sets on one exercise.
- **steps:** Tap row → session detail.
- **expected:** **Currently renders "2, 3, 4, ..."** instead of "1, 2, 3, ..." (`docs/open-questions.md:285`). Expected-after-fix: "1..N".
- **notes:** Cosmetic; doesn't affect any aggregate math.

### S5. By-exercise picker — current program first
- **setup:** Planned workout includes bench press; past history includes bench + discontinued exercise.
- **steps:** Tap BY EXERCISE chip.
- **expected:** "IN YOUR PROGRAM" section lists bench; "PAST PROGRAMS" section lists the discontinued exercise (muted styling, `HistoryByExerciseView.swift:115`).

### S6. Trend requires ≥2 sessions
- **setup:** Exercise with only one completed session.
- **steps:** Tap that exercise.
- **expected:** Per-session rows render; trend line string is `nil` (`TrendComputation.swift:91`). No "↑ X KG / Y WK" header.

### S7. Trend with flat delta
- **setup:** Same exercise, same top weight across 2 sessions 3 weeks apart.
- **steps:** Open exercise detail.
- **expected:** `displayString == "→ 0 KG / 3 WK"` (`TrendComputation.swift:150`).

### S8. Mid-workout swap — detail uses performed exercise
- **setup:** Completed workout where one item has `performedExerciseID != planned exerciseID`.
- **steps:** Open session detail.
- **expected:** Card for that item shows the performed exercise name. Set rows group under `performedExerciseID` (`SessionDetailViewModel.swift:116`).

### S9. Empty state
- **setup:** Fresh install, zero completed workouts; `load()` completes.
- **steps:** Open History.
- **expected:** "no completed workouts / complete a workout to see it listed here." (`HistoryListView.swift:87`).

### S10. Session with zero set_logs
- **setup:** Force-complete a workout with no sets (see save-and-done.md S3).
- **steps:** Open History → tap the row.
- **expected:** Row still appears in list (cache filter is `status == completed`, not "has set_logs"). Session detail shows zero cards but renders the header + body-weight-nil + no note.
- **notes:** `SessionDetailViewModel.buildCards` returns `[]`.

### S11. Tag-less workout
- **setup:** Workout with `tagsJSON == nil` or `tagsJSON == "[]"`.
- **steps:** Apply PUSH/PULL/LEGS filter.
- **expected:** Workout disappears; only ALL shows it (`SessionDetail.swift:86`).

### S12. Set row tap — opens edit sheet (bug-015 fix)
- **setup:** Any session detail with a completed workout.
- **steps:** Tap a set row.
- **expected:** Row flashes accent highlight; `EditSetSheet` slides up. Sheet has two numpad tiles (REPS / LOAD KG) prefilled with the row's current values, a RIR row, and a "save" commit key on the keypad. Commit calls `HistoryViewModel.editPastSet(...)`, which (1) writes the updated SetLog via `WorkoutCache.saveSetLogs([edited])` with the SAME UUID as the original (server-side upsert-in-place), (2) emits `history.past_set_edited` telemetry, (3) fires the shell-wired `onSetLogEdited` hook → `SyncAPI.pushLog([edited])`, (4) calls `load()` so the detail view re-renders with the corrected row. Dismissing without commit leaves the row untouched.
- **notes:** Fields left untouched by the user (empty numpad buffer, no RIR tap) are passed as `nil` and `editPastSet` preserves the existing value. Edits do NOT retrigger autoreg (completed workouts have no live SessionState).

### S13. Post-save refresh (R1.6 / R1.3b)
- **setup:** Complete a workout via save & done.
- **steps:** Switch to History tab.
- **expected:** The just-completed workout appears at the top of "THIS WEEK" without a manual pull-to-refresh. The `afterLocalCompletion` hook wired in `AppBootstrap+Hooks.swift:66-83` calls `historyViewModel.load()` after the local-cache write and the today-loader rerun, so `groups` re-derives before the user can navigate.
- **notes:** Ordering guarantee: cache write → TodayLoader reload → History reload. If the hook is ever unwired, this scenario degrades to the pre-R1.6 "stale until .task re-fires" behaviour — keep the hook in `AppBootstrap` plumbed.

### S14. Very long exercise name + long note layout
- **setup:** Seed a workout with a 120-char exercise name and a 500-char workout note.
- **steps:** Open session detail.
- **expected:** Exercise name card title truncates or wraps (uppercased, caption font, `HistorySessionDetailView.swift:70`); note block `DSCard` wraps. No layout overflow.

### S15. 200+ completed workouts — fetch cap
- **setup:** Seed 250 completed workouts.
- **steps:** Open History.
- **expected:** Only the newest 200 render (`HistoryViewModel.swift:164`). Oldest 50 are invisible. **Not paginated.**

### S16. Pull-to-refresh / corrective-edit reload
- **setup:** Any populated list.
- **steps:** Call `viewModel.load()` again (simulating pull-to-refresh).
- **expected:** `isLoading = true` during the refetch; shapes re-derive atomically; no duplicate rows (`HistoryViewModel+Load.swift:17`).

### S17. Body-weight chip in session detail
- **setup:** Any completed session with a `bodyweight_kg` `UserParameter` logged within ±2 minutes of `completedAt`.
- **steps:** Open session detail, look at header meta line.
- **expected:** Bodyweight renders (e.g. "BW 82.5 KG"). The loader pulls the nearest `user_parameters` row for `key = "bodyweight_kg"` via `WorkoutCache.loadUserParameters(key:)` with a ±2min window around `completedAt` (bug-060). If no match exists, the chip is omitted. HistoryPreviewSeed seeds a sample so SwiftUI previews exercise the branch.

### S18. Week boundaries + year rollover
- **setup:** Workouts today, 8 days ago (across week boundary), Dec 30 prior year + Jan 2 current year.
- **steps:** Open History.
- **expected:** Today's row under "THIS WEEK"; older row under "LAST WEEK" (`HistoryViewModel+Derivation.swift:198-203`). Dec/Jan rollover uses `yearForWeekOfYear` so ISO-week-53/week-1 groupings don't collide across years (`:169`).

### S20. By-exercise union — swap + planned
- **setup:** Exercise "incline db press" appears as `performedExerciseID` in one session (swap) AND as `plannedExerciseID` in another.
- **steps:** Tap it from the picker.
- **expected:** Both sessions' set_logs appear in recent-sessions; no duplication (`WorkoutCache+History.swift:122`).
