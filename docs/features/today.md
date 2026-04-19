---
title: today
status: living
purpose: Behavioral contract + QA scenarios for today
covers:
  - app/Packages/Features/Today/Sources/FeaturesToday/TodayViewModel.swift
  - app/Packages/Features/Today/Sources/FeaturesToday/TodayView.swift
  - app/Packages/Features/Today/Sources/FeaturesToday/TodayLoader.swift
  - app/Packages/Features/Today/Sources/FeaturesToday/PrescriptionLineFormatter.swift
  - app/Packages/Shell/Sources/Shell/AppBootstrap+Hooks.swift
---

# today

## What it does
Glance screen at the start of a session. `TodayLoader` pulls the `.planned` workouts from the local `WorkoutCache`, picks the one whose `scheduledDate` is closest to "now" (past-or-today ranks ahead of future), and assembles a `TodayContext` (workout + blocks + items + exercise catalog + optional last-performed strings). `TodayViewModel` derives a flat list of `ExerciseSummary` rows (name, pre-formatted prescription line, optional last-time chip) by walking blocks in `position` order and items in `position` order within each block. `TodayView` renders: program-name title, optional `· `-joined tags caption, optional "last session" chip, the exercise card list, and a pinned "start workout" button. Tapping `start` calls `viewModel.start()` which dispatches `.start` via `sessionStateBinding` (flipping the shell's `SessionState.route` to `.active`) and emits a `today.start_tap` telemetry event.

**Reload after save & done (bug-036).** The VM's derived fields are mutable (`internal(set) var`), and `reload(using: TodayLoader)` re-runs the loader and replaces them in place. The shell's `AppBootstrap.makeCompletionWriter` calls `todayVM.reload(using: loader)` after the completed workout lands in `WorkoutCache` (status = `.completed`) and before the History refresh. The loader's `.planned` filter skips the just-finished workout, so Today advances to the next scheduled session with zero network round-trip. When no `.planned` workout remains, `reload` flips `isEmpty = true` and blanks the fields; the shell renders the existing S8 empty glance until the next pull brings in a new plan.

## State surface
- **Inputs:** `WorkoutCache.loadWorkouts(status: .planned, since: nil)`, `loadBlocks`, `loadItems`, `loadExercises`; clock; optional `lastPerformed: [UUID: String]`, `lastSessionSummary: String?`, `programTags: [String]`, `sessionStateBinding`.
- **Outputs / side effects:** read-only render; on start, dispatches `.start` mutation and emits one telemetry Event (`kind: "interaction"`, `name: "today.start_tap"`).
- **State transitions:** none owned here; start → session becomes `.active` via the shell.

## What it deliberately doesn't do
- No network calls (`TodayLoader.swift:1-12` header — reads `Persistence.WorkoutCache` only).
- No history query — `lastPerformed` and `lastSessionSummary` are pass-throughs (`TodayLoader.swift:38-46`). Until history wiring lands, these come from the caller.
- No plan sheet / exercise detail — "glance view, not an interactive screen" (`TodayViewModel.swift:7-10`).
- No empty-state screen — `TodayLoader.load()` returns `nil` and the shell renders the empty-state surface (`TodayLoader.swift:36-39`).
- No interpretation of `tags_json` at this layer — `programTags` is supplied already parsed by the caller (`TodayContext.swift:46-48`).

## Edge cases handled in code
- Missing exercise in catalog renders as `"(unknown exercise)"` (`TodayViewModel.swift:101`).
- `PrescriptionParser` failure renders a neutral empty string, never crashes (`TodayViewModel.swift:106-109`).
- Items whose block is missing (data bug) are silently dropped (`TodayViewModel.swift:87-99`).
- Workouts with no `scheduledDate` sort last; if none are scheduled, `workouts.first` is returned (`TodayLoader.swift:87-103`).
- `bodyweight` prescription renders "N × M BW" (`PrescriptionLineFormatter.swift:45-47`).
- `percent_1rm` renders as integer percent, e.g. "4 × 5 @ 85% 1RM" (`PrescriptionLineFormatter.swift:32-35`, `:106-112`).
- `amrapToken`, `setsDetail`, `empty` get best-effort fallbacks (`PrescriptionLineFormatter.swift:52-74`).

## Known issues / gaps
- Last-session chip + `lastPerformed` not wired to a real history store — fed by preview seed / caller today. See `TodayLoader.swift:10-13`.
- If `tags_json` is malformed upstream the caller's parser must handle it — Today treats `programTags` as already-valid.
- `docs/open-questions.md` § "Today → Active navigation end-to-end" — full tap path now works on prod (holder weak-capture bug fixed this session).

## QA scenarios

### S1. Happy path — single planned workout
- **setup:** one `.planned` workout with `scheduledDate == today`, two blocks, three items across them.
- **steps:** boot app → land on Today tab.
- **expected:** title = workout name; tags caption when present; three exercise rows in block+position order; prescription line matches formatter shape per prescription type; "start workout" enabled.
- **notes:** verify `monospacedDigit()` alignment across "100 kg" and "102.5 kg" rows.

### S2. Boundary — no scheduledDate set
- **setup:** one `.planned` workout with `scheduledDate = nil`.
- **steps:** boot app.
- **expected:** that workout is picked (`workouts.first` fallback, `TodayLoader.swift:102`). Renders normally.
- **notes:** if multiple `.planned` workouts exist and all have `scheduledDate = nil`, order is whatever the cache returns — not contractually defined.

### S3. Boundary — multiple planned workouts
- **setup:** three `.planned` workouts: yesterday, today, tomorrow.
- **steps:** boot app.
- **expected:** today's workout wins. Yesterday ranks ahead of tomorrow (past-or-today cohort first, then abs-distance).
- **notes:** skipping a day → yesterday's wins over tomorrow's until tomorrow becomes today.

### S4. Failure — prescription JSON parse error
- **setup:** seed a workout item with intentionally malformed `prescriptionJSON`.
- **steps:** load Today.
- **expected:** exercise row renders, prescription line is empty string (no crash, no error UI).
- **notes:** log manually — no telemetry emit point for this failure.

### S5. Failure — missing exercise in catalog
- **setup:** workout item referencing an `exerciseID` not in `Exercise` catalog.
- **steps:** load Today.
- **expected:** row renders name "(unknown exercise)". Start still works.

### S6. Adjacency — start button → execute-loop
- **setup:** normal Today render with `sessionStateBinding` wired.
- **steps:** tap "start workout".
- **expected:** `.start` dispatches, shell flips to Active screen of execute-loop, telemetry `today.start_tap` emitted once.
- **notes:** regression watch — `executionVMHolder` weak capture bug previously caused silent no-op on prod path.

### S7. Chaos — `sessionStateBinding == nil`
- **setup:** preview/test path with binding absent.
- **steps:** tap start.
- **expected:** no-op (by design, `TodayViewModel.swift:78`). Button remains tappable; no visible effect.

### S8. Empty / degenerate content
- **setup:** workout with zero blocks, or blocks with zero items.
- **steps:** load Today.
- **expected:** header + optional chip render; exercise list is empty; "start workout" still enabled.
- **notes:** start is not disabled based on a workout having zero exercises — `isEmpty` (the VM's empty-shaped flag) is set by `apply(nil)`, not by `exercises.isEmpty`. A pulled workout with zero items still has `isEmpty == false` and keeps the CTA.

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
- **expected:** loader returns `nil`; `TodayViewModel.isEmpty == true`, `workoutID == nil`, `exercises == []`, `programName == ""`, `lastSessionSummary == nil`, `programTags == []`, `showsStartButton == false`. `TodayView` hides the pinned "start workout" CTA and renders the empty-glance ("no planned workouts / check back after Claude sends a new session") inside the existing `.ready` phase.
- **notes:** The shell does NOT flip `phase` back to `.empty` — the VM's empty-shaped state is rendered inside the existing `.ready` phase. `showsStartButton` is the gate — it returns `!isEmpty`. qa-008 fix: previously the view unconditionally rendered `startButton`, so an empty Today showed only a disconnected CTA over a black screen.
