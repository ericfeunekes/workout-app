---
title: today
status: living
last_reviewed: 2026-04-26
purpose: Behavioral contract + QA scenarios for today
covers:
  - app/Packages/Features/Today/Sources/FeaturesToday/TodayViewModel.swift
  - app/Packages/Features/Today/Sources/FeaturesToday/TodayView.swift
  - app/Packages/Features/Today/Sources/FeaturesToday/TodayLoader.swift
  - app/Packages/Features/Today/Sources/FeaturesToday/PrescriptionLineFormatter.swift
  - app/Packages/Shell/Sources/Shell/AppBootstrap+Hooks.swift
---

# today

## Target behavior

Today is the local plan queue and workout entry surface. It should show the
selected workout and surrounding planned workouts, but opening a workout and
starting a workout are separate actions.

The target entry path is:

1. Tap a workout card body to open `workout-preview.md`.
2. Review blocks, prescriptions, and "what comes next."
3. Use explicit Start to enter `execute-loop.md`.

Today may render a Start affordance where it is visually unambiguous, but no
card-body tap should silently start a session. Preview/setup edits route through
`docs/set-edit-sheet.md`; app-side programming changes still route to Claude.

## Current implementation
Plan surface at the start of a session. `TodayLoader.loadPlan()` pulls `.planned` workouts from the local `WorkoutCache`, picks the one whose `scheduledDate` is closest to "now" (past-or-today ranks ahead of future) as the execution-selected workout, and assembles a `TodayPlanContext` around the full local plan queue. `TodayViewModel` groups the queue into date sections such as `MISSED`, `TODAY`, `TOMORROW`, `UPCOMING`, and `UNSCHEDULED`. Each workout card shows the name, decoded tag line, block-level previews, timing summaries, and grouped exercise prescription lines. Tapping a card opens the workout preview/detail sheet with the full block list, timing configuration summary, notes, all exercise rows, last-time chips, a copyable Claude adjustment request, and the only Start control for that workout.

The selected workout remains the default execution target, but any preview for a visible planned card can be started when Shell has injected a specific-workout start action. Starting the selected workout uses the existing session binding. Starting a missed/future workout asks Shell to rebuild the `ExecutionViewModel` for that workout ID, then starts it. This does not reschedule, reorder, or mutate the plan; it is a one-session execution choice. Both paths emit `today.start_tap`.

**Refresh.** Shell injects a refresh action into `TodayViewModel` after bootstrap. Pull-to-refresh or the header `REFRESH` action calls `SyncAPI.pullLatest(since: lastSyncAt)`, saves the result into `WorkoutCache`, updates `LastPerformedStore` and `SyncMetadataStore`, reloads the existing `TodayViewModel`, and rebuilds the `ExecutionViewModel` for the newly selected planned workout. Pull failures leave the local cache-rendered plan intact and show a small failure caption.

**Reload after save & done (bug-036).** The VM's derived fields are mutable (`internal(set) var`), and `reload(using: TodayLoader)` re-runs `loadPlan()` and replaces them in place. The shell's `AppBootstrap.makeCompletionWriter` calls `todayVM.reload(using: loader)` after the completed workout lands in `WorkoutCache` (status = `.completed`) and before the History refresh. The loader's `.planned` filter skips the just-finished workout, so Today advances the selected workout and queue with zero network round-trip. When no `.planned` workout remains, `reload` flips `isEmpty = true` and blanks the fields; the shell renders the existing S8 empty glance until the next pull brings in a new plan.

## State surface
- **Inputs:** `WorkoutCache.loadWorkouts(status: .planned, since: nil)`, `loadBlocks`, `loadItems`, `loadExercises`; clock; optional `lastPerformed: [UUID: String]`, `lastSessionSummary: String?`, `programTags: [String]`, `sessionStateBinding`; optional shell-injected refresh and start-workout actions.
- **Outputs / side effects:** read-only render; on start, dispatches `.start` or asks Shell to rebuild execution for a specific planned workout, then emits one telemetry Event (`kind: "interaction"`, `name: "today.start_tap"`); on refresh, Shell runs sync pull/cache-save/reload/rebuild; on adjustment request, copies a structured text prompt for Claude.
- **State transitions:** none owned here; start → session becomes `.active` via the shell.

## What it deliberately doesn't do
- No network calls inside `TodayLoader`; refresh network ownership stays in Shell/AppBootstrap.
- No history query from the feature package. `TodayLoader` reads the Shell-populated `LastPerformedStore` snapshot; `lastSessionSummary` remains caller-supplied.
- No plan mutation, reschedule, drag/drop, or delete. Plans flow server → app; app-side reorganization is out of scope.
- No AI infrastructure. The adjustment affordance copies a structured request for Claude; it does not call Claude from the app.
- No app-side programming sheet. Preview/setup edits are scoped execution setup
  only; larger plan changes still route to Claude.
- No empty-state screen — `TodayLoader.load()` returns `nil` and the shell renders the empty-state surface (`TodayLoader.swift:36-39`).
- No planning semantics from `tags_json`; Today only decodes workout tags for display on cards. Conversation/Claude still owns what those tags mean.

## Edge cases handled in code
- Missing exercise in catalog renders as `"(unknown exercise)"` (`TodayViewModel.swift:101`).
- `PrescriptionParser` failure renders a neutral empty string, never crashes (`TodayViewModel.swift:106-109`).
- Items whose block is missing (data bug) are silently dropped (`TodayViewModel.swift:87-99`).
- Workouts with no `scheduledDate` sort last; if none are scheduled, `workouts.first` is returned (`TodayLoader.swift:87-103`).
- `bodyweight` prescription renders "N × M BW" (`PrescriptionLineFormatter.swift:45-47`).
- `percent_1rm` renders as integer percent, e.g. "4 × 5 @ 85% 1RM" (`PrescriptionLineFormatter.swift:32-35`, `:106-112`).
- `amrapToken`, `setsDetail`, `empty` get best-effort fallbacks (`PrescriptionLineFormatter.swift:52-74`).

## Current gaps

- Card-body tap opens the current preview/detail sheet; a richer dedicated
  `WorkoutPreviewView` is still target behavior.
- Card-level Start has been removed. Start is currently only in the
  preview/detail sheet when the workout can be started.
- Preview tap targets and Start affordance need simulator proof before the
  feature can be marked `verified`.
- Current-block remaining work is projection-backed on Execution's next-up
  preview, but not yet rendered in Today's preview/detail sheet.
- Today does not mutate plans locally. Reorganization remains conversation-owned by design.

## QA scenarios

### S1. Happy path — single planned workout
- **setup:** one `.planned` workout with `scheduledDate == today`, two blocks, three items across them.
- **steps:** boot app → land on Today tab.
- **expected:** header shows `Today / planned queue`; one `TODAY` section; the workout card shows workout name, decoded tag line when present, block-level timing previews, and grouped exercise prescription lines in block+position order. Opening the card body leads to preview, not a live session.
- **notes:** verify `monospacedDigit()` alignment across "100 kg" and "102.5 kg" rows.

### S2. Boundary — no scheduledDate set
- **setup:** one `.planned` workout with `scheduledDate = nil`.
- **steps:** boot app.
- **expected:** that workout is picked (`workouts.first` fallback, `TodayLoader.swift:102`). Renders normally.
- **notes:** if multiple `.planned` workouts exist and all have `scheduledDate = nil`, order is whatever the cache returns — not contractually defined.

### S3. Boundary — multiple planned workouts
- **setup:** three `.planned` workouts: yesterday, today, tomorrow.
- **steps:** boot app.
- **expected:** Today renders all three in date sections. Card body taps open preview for the selected workout; any direct Start affordance is visually separate from card opening and routes through the explicit start path. Yesterday appears under `MISSED`; tomorrow appears under `TOMORROW`.
- **notes:** if there is no workout scheduled today, the nearest past workout becomes selected/default before future workouts.

### S4. Failure — prescription JSON parse error
- **setup:** seed a workout item with intentionally malformed `prescriptionJSON`.
- **steps:** load Today.
- **expected:** exercise row renders, prescription line is empty string (no crash, no error UI).
- **notes:** log manually — no telemetry emit point for this failure.

### S5. Failure — missing exercise in catalog
- **setup:** workout item referencing an `exerciseID` not in `Exercise` catalog.
- **steps:** load Today.
- **expected:** row renders name "(unknown exercise)". Start still works.

### S6. Adjacency — preview Start → execute-loop
- **setup:** normal Today render with `sessionStateBinding` wired.
- **steps:** tap a workout card to open preview, then tap explicit Start.
- **expected:** `.start` dispatches, shell flips to Active screen of execute-loop, telemetry `today.start_tap` emitted once.
- **notes:** regression watch — `executionVMHolder` weak capture bug previously caused silent no-op on prod path.

### S7. Chaos — `sessionStateBinding == nil`
- **setup:** preview/test path with binding absent.
- **steps:** tap start.
- **expected:** no-op (by design, `TodayViewModel.swift:78`). Button remains tappable; no visible effect.

### S8. Empty / degenerate content
- **setup:** workout with zero blocks, or blocks with zero items.
- **steps:** load Today.
- **expected:** header + optional chip render; the workout card renders without exercise previews; opening the card still leads to preview, and Start remains an explicit action from there.
- **notes:** start is not disabled based on a workout having zero exercises — `isEmpty` (the VM's empty-shaped flag) is set by `apply(nil)`, not by `exercises.isEmpty`. A pulled workout with zero items still has `isEmpty == false` and keeps the card CTA.

### S9. Same exercise listed twice in one workout
- **setup:** two items referencing the same `exerciseID`.
- **steps:** load Today.
- **expected:** both rows render; `lastPerformed[exerciseID]` shows identical "LAST TIME" chip on both (it's a per-exercise map).

### S10. Reload after save & done advances to the next planned workout (tested: `testTodayViewModelReloadPicksNextPlannedAfterCompletion`)
- **setup:** two planned workouts — "Push A" scheduled today, "Pull A" scheduled yesterday. Both `.planned` in the local cache.
- **steps:** complete "Push A" → tap save & done → shell's `localCompletionWriter` flips the row to `.completed` via `WorkoutCache.saveWorkout` and then calls `todayVM.reload(using:)` → route flips back to `.today`.
- **expected:** `TodayViewModel.workoutID == pullA.id`, `programName == "Pull A"`, and the exercise list re-derives from Pull A's items. `isEmpty == false`.
- **notes:** This is the bug-036 fix. Previously the VM held the completed workout's `TodayContext` forever until relaunch, so the user saw a stale "start workout" screen for the session they just finished.

### S11. Reload to empty when no planned workouts remain (tested: `testTodayViewModelReloadToEmptyWhenNoPlannedWorkouts`, `testTodayViewHidesStartButtonWhenEmpty`)
- **setup:** exactly one `.planned` workout in the cache.
- **steps:** complete it → save & done → reload.
- **expected:** loader returns `nil`; `TodayViewModel.isEmpty == true`, `workoutID == nil`, `exercises == []`, `planSections == []`, `programName == ""`, `lastSessionSummary == nil`, `programTags == []`, `showsStartButton == false`. `TodayView` has no card-level "start workout" CTA and renders the empty-glance ("no planned workouts / check back after Claude sends a new session") inside the existing `.ready` phase.
- **notes:** The shell does NOT flip `phase` back to `.empty` — the VM's empty-shaped state is rendered inside the existing `.ready` phase. `showsStartButton` is the gate — it returns `!isEmpty`. qa-008 fix: previously the view unconditionally rendered `startButton`, so an empty Today showed only a disconnected CTA over a black screen.

### S12. Plan queue read-side
- **setup:** missed, today, and tomorrow planned workouts in local cache.
- **steps:** boot app.
- **expected:** `TodayLoader.loadPlan()` returns a `TodayPlanContext` with the selected workout and all planned workouts; `TodayViewModel.planSections` groups them by date; only the selected/default workout has `isStartable == true`, while Shell-injected `startWorkoutAction` lets the view render start affordances for the sibling cards too.
- **notes:** This closes the first slice of the plan-surface UX gap. Local plan mutation remains deliberately out of scope.

### S13. Workout preview sheet
- **setup:** planned workout with multiple blocks, timing config, notes, and more exercises than the card preview shows.
- **steps:** boot app → tap workout card.
- **expected:** preview opens with section/date label, workout title, tags, notes, every block in position order, timing mode/config summary, block notes, every exercise row in block+item order, last-time chips when supplied, and a visually explicit Start action.
- **notes:** Preview/setup edits are scoped through `docs/set-edit-sheet.md`; larger plan changes still route to Claude.

### S14. Refresh plan
- **setup:** boot app with a saved connection and at least one planned workout.
- **steps:** pull-to-refresh or tap `REFRESH`.
- **expected:** Shell runs one `/api/sync/pull`, saves pulled data, updates `lastSyncAt`, reloads the visible Today VM, and rebuilds the execution VM for the current selected/default workout. On failure, existing local-cache content stays visible and Today shows `refresh failed; showing local cache`.
- **notes:** `testTodayRefreshRunsPullAndKeepsReadyState` pins the Shell-owned pull path.

### S15. Adjustment handoff
- **setup:** planned workout visible in Today.
- **steps:** open workout preview → tap `copy adjustment request`.
- **expected:** app copies a structured prompt containing workout name, schedule label, tags, notes, blocks, timing summaries, and exercise prescriptions. No local workout rows are mutated.
- **notes:** This is the scoped handoff while Claude integration remains out of app infrastructure.
