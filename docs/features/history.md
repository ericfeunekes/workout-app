---
title: history
status: built
last_reviewed: 2026-05-17
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

## Target behavior

History is the completed-workout review and correction surface. It should show
completed sessions, let the user inspect work by session or exercise, and allow
post-workout correction for every logged field that the app can capture during
execution.

Corrections update the existing logical log row, mark the row as a manual
correction where that field exists, and never retrigger autoreg. They are not
audit-grade today: the current server contract overwrites the row in place and
does not store a field-level edit trail.

## Current implementation
`HistoryViewModel.load()` pulls completed workouts (limit 200) from `WorkoutCache.loadCompletedWorkouts` newest-first by `completedAt` (`WorkoutCache+History.swift:39`), plus their set_logs and item lookups, into `rawSessions` (`HistoryViewModel+Load.swift:34`). Derivation filters by `activeSplit`, groups by `(year, weekOfYear)` into `WeekGroup`s with headers "THIS WEEK" / "LAST WEEK" / "APR · WEEK 15" (`HistoryViewModel+Derivation.swift:198`). `HistoryListView` renders groups in a `DSCard` of `NavigationLink(value: workoutID)` rows (`HistoryListView.swift:74`). Tap → `HistorySessionDetailView` bound to a `SessionDetailViewModel` that buckets set_logs by `performedExerciseID ?? plannedExerciseByItem[itemID] ?? workoutItemID` (`SessionDetailViewModel.swift:116`) and renders set rows using the logged shape: strength rows include load/reps/RIR, cardio and carry rows include duration/distance/load where present, and skipped rows render `SKIPPED`. Tapping a set row opens `EditSetSheet`, which emits the shared `SetEditIntent` and lets History correct load/unit, reps, duration, distance, RIR set/clear, skipped/performed state, side round-trip, and notes on the existing set-log row. A "BY EXERCISE →" chip flips `tab` to `.byExercise` → current-program-first picker → per-exercise detail with `TrendComputation.compute` producing "↑ 12.5 KG / 12 WK" (`TrendComputation.swift:82`). Skipped rows are excluded from by-exercise picker, top-set, trend, and average-RIR aggregation.

## State surface
- **Inputs:** `WorkoutCache` (completed workouts, blocks, items, set_logs, exercises, planned workouts), `calendar`, `now`, `telemetry: TelemetryEmitter`, `onSetLogEdited: HistorySetLogEditHook?` (shell-wired to `SyncAPI.pushLog`), `onWorkoutReset: HistoryWorkoutResetHook?` (shell-wired to `SyncAPI.resetWorkout`).
- **Outputs / side effects:** `groups: [WeekGroup]`, `pickerRows: [ExercisePickerRow]`, `isLoading: Bool`, `tab: Tab`, `activeSplit: SplitFilter`. History has two write paths: `editPastSet(...)` writes the updated SetLog to `WorkoutCache.saveSetLogs`, emits `history.past_set_edited`, fires `onSetLogEdited`, and reloads; `resetWorkout(workoutID:)` is same-day-only, deletes local logs via `WorkoutCache.resetWorkout`, emits `history.workout_reset`, fires `onWorkoutReset`, and reloads so the row leaves History.
- **State transitions:** `setSplit` → re-derive groups only (no reload). `setTab` → flip list/byExercise (no reload). `load()` → set `isLoading`, re-pull everything, re-derive. `editPastSet(...)` → local write, push enqueue, telemetry emit, reload. `resetWorkout(...)` → local reset, server reset enqueue, telemetry emit, reload. Errors during load leave cached shapes as-is (`HistoryViewModel+Load.swift:25`).

## What it deliberately doesn't do
- Does NOT show charts, body-weight trends, volume/RIR heatmaps, PR detection (`app/README.md:153`).
- Does NOT search exercises in the picker (`HistoryByExerciseView.swift:8`).
- Does NOT render trend line when only 1 session exists. Two distinct sessions — keyed off `workoutItemID`, not calendar day — always render (bug qa-006: same-day circuit + AMRAP for one exercise counts as two sessions).
- Does NOT retrigger autoreg on a corrective edit — History edits mark the SetLog directly via `saveSetLogs` and never pass through the live `SessionReducer` (completed workouts have no live state). Mirrors `SessionReducer.applyEditPastSet`'s `.manual` semantics on the execution side.

## Edge cases handled in code
- **`HistoryRow` tap regression** (fixed 2026-04-18, `docs/open-questions.md:270`): `HistoryRow` used to be a `Button(action: onTap)` nested inside `NavigationLink(value:)` — the inner Button swallowed the tap. Flattened to a plain VStack (`HistoryRow.swift:16-51`). **Watchlist: any new row variant that re-introduces an inner `Button` will re-break this.**
- `completedAt == nil` falls back to `scheduledDate` for sort (`WorkoutCache+History.swift:40`, `SessionDetail.swift:152`). Undated sessions bucket under an "UNDATED" group (`HistoryViewModel+Derivation.swift:124`).
- Cross-entity SwiftData `#Predicate` joins are avoided — two-step walks for workout → blocks → items → set_logs (`WorkoutCache+History.swift:52`).
- By-exercise union covers both planned items with `exerciseID == exerciseID` AND set_logs with `performedExerciseID == exerciseID` (mid-workout swap), de-duped by id (`WorkoutCache+History.swift:99-128`).
- Unknown-exercise fallback: `exerciseName[id] ?? "(unknown exercise)"` (`SessionDetailViewModel.swift:135`).
- Tag parser accepts `push`, `push_day`, `PushDay`, `pushday` case-insensitively (`SessionDetail.swift:28`).
- Session detail card order is "first set_log appears" order — cache returns in (block position, item position, setIndex) so deterministic per pull (`SessionDetailViewModel.swift:99`).

## Current gaps

- `HISTORY-GAP-001`: Unilateral history display uses exercise-level identity
  unless a later taxonomy requirement adds a stronger canonical link between
  left/right variants. `set_log.side` is shipped/reserved, not the active
  grouping model.
- `HISTORY-GAP-002`: Post-workout correction is same-row overwrite and is not
  audit-grade. There is no `set_log.updated_at`, field-diff telemetry event, or
  durable History edit log.
- `HISTORY-GAP-003`: Block intent display depends on `block.intent`; surfaces
  should render nothing when intent is null.
- `SETEDIT-GAP-003`: Bodyweight correction is a separate `user_parameters`
  editing problem, not a set-log correction.

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

### S4. Set index display
- **setup:** Any completed session with ≥2 sets on one exercise.
- **steps:** Tap row → session detail.
- **expected:** Rows render with their stored 1-based `setIndex`: "1, 2, 3, ...".
- **notes:** bug-020 closed; keep this scenario as a regression guard.

### S5. By-exercise picker — current program first
- **setup:** Planned workout includes bench press; past history includes bench + discontinued exercise.
- **steps:** Tap BY EXERCISE chip.
- **expected:** "IN YOUR PROGRAM" section lists bench; "PAST PROGRAMS" section lists the discontinued exercise (muted styling, `HistoryByExerciseView.swift:115`).

### S6. Trend requires ≥2 sessions
- **setup:** Exercise with only one completed session.
- **steps:** Tap that exercise.
- **expected:** Per-session rows render; trend line string is `nil`. No "↑ X KG / Y WK" header. **Session** means a distinct `workoutItemID` — two separate workouts on the same calendar day (e.g. Burpee in a circuit block + Burpee in a later AMRAP block) count as two sessions, not one (bug qa-006).

### S7. Trend with flat delta
- **setup:** Same exercise, same top weight across 2 sessions 3 weeks apart.
- **steps:** Open exercise detail.
- **expected:** `displayString == "→ 0 KG / 3 WK"`. Same-day case: two distinct sessions logged on the same day render `→ 0 KG / 0 WK` (weeks collapses to 0 but the trend line still appears).

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
- **expected:** Row flashes accent highlight; `EditSetSheet` slides up. Sheet exposes the row's applicable fields: reps, load/unit, duration, distance, skipped/performed state, side round-trip, notes, and RIR set/clear. Commit calls `HistoryViewModel.editPastSet(...)`, which (1) writes the updated SetLog via `WorkoutCache.saveSetLogs([edited])` with the SAME UUID as the original (server-side upsert-in-place), (2) emits `history.past_set_edited` telemetry, (3) fires the shell-wired `onSetLogEdited` hook → `SyncAPI.pushLog([edited])`, (4) calls `load()` so the detail view re-renders with the corrected row. Dismissing without commit leaves the row untouched.
- **notes:** Fields left untouched by the user (empty numpad buffer, no RIR tap) are passed as `nil` and `editPastSet` preserves the existing value. Edits do NOT retrigger autoreg (completed workouts have no live SessionState).

### S12A. Skipped correction clears metrics and aggregates
- **setup:** Completed workout with one logged strength row.
- **steps:** Open History → session detail → tap the set row → mark it skipped → save → open BY EXERCISE.
- **expected:** The session detail row renders `N · SKIPPED`; performance metrics and RIR no longer render for that row. If that row was the exercise's only performed row, the exercise is absent from the by-exercise picker and trend/top-set aggregation.

### S13. Post-save refresh (R1.6 / R1.3b)
- **setup:** Complete a workout via save & done.
- **steps:** Switch to History tab.
- **expected:** The just-completed workout appears at the top of "THIS WEEK" without a manual pull-to-refresh. The `afterLocalCompletion` hook wired in `AppBootstrap+Hooks.swift:66-83` calls `historyViewModel.load()` after the local-cache write and the today-loader rerun, so `groups` re-derives before the user can navigate.
- **notes:** Ordering guarantee: cache write → TodayLoader reload → History reload. If the hook is ever unwired, this scenario degrades to the pre-R1.6 "stale until .task re-fires" behaviour — keep the hook in `AppBootstrap` plumbed.

### S14. Same-day reset
- **setup:** A workout completed today appears in History.
- **steps:** Open the session detail, tap "reset workout", confirm.
- **expected:** The app deletes that workout's local set_logs, flips the local workout back to planned, queues `workout_resets: [{workout_id}]` through `/api/sync/results`, emits `history.workout_reset`, dismisses the detail screen, and removes the row from History after reload. The next pull must not resurrect the completed workout.
- **notes:** The reset affordance is intentionally same-day-only. Older history remains editable at the set level but not erasable through this v1 surface.

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
