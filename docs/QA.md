---
title: QA
status: accepted
last_reviewed: 2026-05-17
purpose: The UX QA guide for closing app-facing work with MCP-driven simulator runs, recorded evidence, and independent video-model assessment.
covers:
  - docs/bugs.md
  - docs/features/
  - app/
---

# QA

WorkoutDB uses QA to protect the user experience, not just prove that code
compiled. For app-facing work, closeout should include a simulator run that
exercises the implemented behavior through the same gestures Eric would use in
the gym.

QA evidence can be broad; issue tracking must stay narrow.

## Source of truth

- **Active issues:** `docs/bugs.md`.
- **Closed issues:** git history for `docs/bugs.md`, plus the regression test or invariant added by the fix.
- **Raw evidence:** `scratch/qa-runs/` while the run is active. This directory is gitignored and must not become a second bug tracker.

Do not keep durable issue lists in `scratch/`. A QA run can write temporary notes, screenshots, recordings, JSONL observations, and per-run reports there, but every still-open finding is migrated to `docs/bugs.md` before closeout. Once migration is done, scratch summaries that duplicate the bug list should be deleted or ignored.

## When QA Is Required

Use this guide for every chunk that changes user-visible app behavior:

- Screens, navigation, sheets, menus, preview cards, or empty/loading/error states.
- Timer behavior, workout execution, rest transitions, logging, skip/done flows, or history correction.
- Tap targets, accessibility labels, input handling, persistence, sync status, or offline/auth surfaces.
- Any implementation where a feature doc, design doc, or bug fix claims the app now behaves differently.

Pure server, schema, or documentation-only work does not need simulator UX QA
unless the user-facing behavior depends on it. If a change has no simulator
surface, say that in the closeout and name the proof that replaced it.

## Closeout QA

For each app-facing chunk, run enough simulator QA to be confident the changed
experience works as intended. Keep it practical: read the relevant feature,
spec, or bug note, turn it into the user tasks that matter, and confirm those
tasks work. Do not create formal scenario maps unless a change is large enough
that the coverage would otherwise be hard to reason about.

1. **Name the expectation.** State what was implemented, which feature/spec/bug
   it satisfies, and the user expectation being protected.
2. **Build and launch with XcodeBuildMCP.** Use the canonical `xcodebuildmcp`
   command from `docs/ios-dev-loop.md`. Prefer MCP build/run, UI hierarchy,
   tap, swipe, type, long-press, screenshot, log-capture, and video tools over
   raw shell commands.
3. **Record the run.** Start a simulator video before the first interaction.
   Keep screenshots at meaningful checkpoints. Store raw artifacts under
   `scratch/qa-runs/<YYYY-MM-DD>-<slug>/` while active.
4. **Exercise the real interaction set.** Do not only click the happy path.
   Cover the gestures the feature naturally supports: taps, swipes, scrolls,
   long presses, sheet dismissal, keyboard input, time advancement, back/forward
   navigation, retry/offline surfaces, destructive confirmations, and edge
   states where relevant.
5. **Inspect while running.** Use screenshots and `snapshot-ui` to verify what
   is actually on screen. Check labels, hit targets, enabled/disabled states,
   timers, counters, persisted values, offscreen activatable elements, and
   whether the visible state matches the feature contract.
6. **Ask the video model.** Pass the recording to `img ask --video`. Ask it to
   compare the recording against the implemented contract and the QA steps that
   were supposed to be run.
7. **Route findings.** Fix regressions immediately when they are in scope. Move
   still-open bugs to `docs/bugs.md`. Put unresolved product/design questions in
   `docs/open-questions.md`.

QA is not complete until the recording, screenshots, local observations, and
video-model assessment agree or the disagreement has been explained and routed.

## Match The Proof To The Claim

Do not use the simulator video as proof for things the video cannot show. Pick
the evidence that matches the claim:

- **Visible UX:** simulator recording, screenshots, and `snapshot-ui`.
- **Gestures and navigation:** MCP taps, swipes, long presses, text entry, sheet
  dismissal, back/forward navigation, and replayable user tasks.
- **Accessibility surface:** `snapshot-ui` labels, traits, enabled state, frame
  size, focus order where observable, plus Dynamic Type or VoiceOver checks when
  the change affects critical workout execution.
- **Timer or state-machine behavior:** unit tests or XCUITest where practical,
  plus a visible simulator run for the user-facing flow.
- **Persistence:** navigate away/back, relaunch the app, or inspect the local
  store when the claim is data survival.
- **Sync, offline, auth, or telemetry:** use the relevant queue, API, server DB,
  event log, or error surface. A video can show the UI response, not the backend
  truth.
- **Runtime cost:** symbolicated ETTrace output for one focused flow, with the
  simulator/device, build, route, and caveats recorded in the run notes. Video
  can show jank; it does not prove CPU, render, or layout cost.
- **Object lifetime:** memgraph/leaks summary naming app-owned retained or
  leaked types, plus the ownership path or grouped evidence. Lower memory after
  a run is not enough; the proof needs object identity or ownership evidence.
- **Foreground/background lifecycle:** simulator/device run plus logs,
  telemetry, queue/store readback, or app-hosted tests. A screenshot after
  foregrounding only proves the visible surface, not pull/retry/task behavior.
- **Watch, haptics, HealthKit, physical ergonomics, sleep/wake, or real network
  behavior:** use a real device or a dedicated test path when the claim depends
  on device behavior.

The question at closeout is simple: did the evidence actually prove the thing
we are claiming, or did it only make the screen look plausible?

## Interaction Coverage

Start from the feature contract and write the run as user tasks, not component
checks. A good run includes:

- The normal path from entry state to completion.
- At least one interruption or reversal: dismiss sheet, back out, cancel,
  resume, retry, or undo.
- The non-primary gesture if the feature has one: long press, swipe, drag,
  scroll, keyboard entry, or tap outside to dismiss.
- Boundary states: first item, last item, empty list, disabled action, pending
  sync, offline, auth rejected, timer expired, skipped set, edited past set, or
  partially completed workout where relevant.
- A persistence or state check when the feature claims data survives navigation,
  app relaunch, reload, sync, or route changes.
- A visual check for text clipping, overlap, contrast, inconsistent spacing,
  wrong hierarchy, stale copy, and impossible-to-hit targets.

Do not pad the run with unrelated screens. The goal is enough coverage to protect
the implemented expectation, not a full-app tour every time.

## Video-Model Review

Every recorded app-facing QA run must include an independent `img ask` review.
Use a prompt that gives the model the same contract a human reviewer would use.

Template:

```bash
img ask --video scratch/qa-runs/<run-id>/recording.mp4 \
  --out scratch/qa-runs/<run-id>/video-review.jsonl \
  "This recording is QA for <feature/chunk>. The implemented contract is:
  <short contract>.

  The QA plan was:
  <numbered user-level steps, including taps/swipes/long presses/edge cases>.

  Inspect the video and answer:
  1. What flow did you actually see, in order?
  2. Did the recording demonstrate the implemented contract?
  3. Did QA miss any expected interaction, edge case, or visible state?
  4. Was the QA sufficient for this chunk? If not, what additional checks are needed?
  5. Did you see any blank screens, crashes, clipping, overlap, stale copy, disabled controls, or confusing UX?"
```

Treat the model as an independent reviewer, not an oracle. If it disagrees with
your observation, inspect the recording or rerun a narrower recording until the
evidence is unambiguous.

## Closeout Summary

When a chunk closes, write a short QA summary in the closeout response. If the
run closes a bug or changes durable feature status, update the owning durable
doc where that status already lives. Do not create a separate QA evidence ledger
unless the work is large enough that future readers will realistically need it.

Include:

- What expectation was tested.
- Simulator/device and app route used.
- The main gestures and edge states exercised.
- Whether screenshots, recording, `snapshot-ui`, logs, tests, state readbacks,
  ETTrace, memgraph/leaks, or real-device checks were used.
- `img ask` verdict.
- Bugs filed, questions opened, or reasons no further action was needed.

Raw local artifacts can stay in `scratch/qa-runs/`. Keep the durable repo docs
focused on decisions, open bugs, and feature status.

## What Counts As A QA Issue

File an active bug when QA finds one of these:

- The app does not execute, log, sync, or render behavior promised by the spec or feature docs.
- A runtime workflow that Eric needs has no usable surface.
- A visible UX problem blocks first real use or makes a normal path risky.
- Simulator or visual evidence reveals a recurring instability, even if the underlying code path is not isolated yet.

Do not file a bug for a design decision that is still unresolved. Put that in `docs/open-questions.md` unless the app already promised the behavior.

## Evidence Standard

Each `docs/bugs.md` row should include the strongest practical evidence in the Notes column:

- **Runtime observation:** simulator state, server DB row, API response, app snapshot, or screenshot.
- **Test result:** failing test or reproducible command output.
- **Code inspection:** exact file or behavior that explains the issue.
- **Spec mismatch:** feature/spec section that promised different behavior.

Use absolute dates for QA sessions when relevant. For example, a missed-workout finding should say `2026-04-22` rather than "yesterday."

## What `verified` Means

Feature docs use `verified` only when the behavior has external proof beyond
code inspection. The owning feature doc should say, briefly, what kind of proof
supports the status. It does not need a formal evidence packet.

Acceptable proof includes:

- A pinned UI test or XCUITest that runs in CI.
- An MCP-driven simulator walk with recording, screenshots or `snapshot-ui`, and
  `img ask` review.
- A short durable note in the owning feature doc when the verification changes
  feature status.

UI, layout, contrast, tap-target, and timer-flow behavior cannot be promoted to
`verified` from source inspection alone. High-risk timing surfaces need both the
best practical automated proof for logic and simulator proof for the visible
flow. Schema cutovers need migration, parity, and contract-test proof; simulator
QA only verifies the user-facing behavior that depends on the schema.

## Closeout Rule

At the end of a QA run:

1. Stop the recording and confirm the video file exists.
2. Run the `img ask --video` review and read the result before reporting QA as complete.
3. Add or update `docs/bugs.md` rows for every still-open issue.
4. Delete or ignore scratch-level bug summaries that duplicate `docs/bugs.md`.
5. Keep raw screenshots, recordings, and per-run reports as local support unless
   the owning feature doc needs a brief status note.
6. If a fix closes a row, remove it from `docs/bugs.md` in the same change that adds the proof.

This keeps one active list while preserving enough evidence to reproduce serious findings.
