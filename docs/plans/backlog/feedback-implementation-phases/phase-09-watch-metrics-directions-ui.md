---
title: Phase 9 — watch metrics and proven directions UI implementation plan
status: provisional backlog / deferred
last_reviewed: 2026-05-17
purpose: Build the final three-view watch UI, metric slot resolver, target windows, HR slot, and route/directions surface only where route proof exists.
covers:
  - docs/watch-metrics.md
  - app/Packages/Features/WatchFaces/
  - app/Packages/WatchBridge/
  - app/Packages/HealthKitBridge/
---

# Phase 9 — Watch Metrics And Directions UI

> **Planning note (2026-05-17):** This is only for the later custom Setmark
> Watch app. Apple's Workout app owns the live UI in the WorkoutKit handoff
> lane, so this phase does not define early delivery requirements.

## Unit Statement

Implement the watch three-view grammar, persistent HR slot, metric resolver,
target windows, and directions quadrant on top of the authority substrate, with
route/directions shown only for proven route packages or honest unavailable
states.

## Boundaries Touched

- Watch UI renderer and view models.
- Metric slot resolver and display fallback model.
- HealthKit/GPS sources and route sources only when route package proof exists.
- WatchBridge snapshots/packages for metric data.

## Dependencies And Preconditions

- Phase 7 protocol foundation is complete.
- Phase 8 watch-primary authority is complete for disconnected route/metric
  ownership.
- `docs/watch-metrics.md` remains the source of truth for fixed slots.

## Approach

Build the metric system before adding many metric variants. Keep slot positions
stable, make unavailable sensor states explicit, and do not overclaim route
guidance before GPS/route ownership has been proven.

## Steps

1. Define metric IDs, roles, sources, detectability, fallback, target windows.
2. Implement resolver for session/prescription/sensor/derived/route metrics.
3. Build Main/Data/Quadrant watch views.
4. Preserve persistent HR top-right slot on every view.
5. Add target delta color/arrows from authored windows.
6. Add route/direction quadrant package and renderer only for proven route
   packages; otherwise render the locked unavailable/future state.
7. Add watch UI tests, snapshots/screenshots, and device/simulator QA.

## Good

- The Watch always answers "what now?" and shows HR.
- Data views use fixed positions and do not waste labels like "next."
- Auto-trackable and manual goals render honestly.
- Directions preserve at least one primary effort metric.
- Route/directions UI never implies guidance is available before route data and
  GPS ownership are proven.

## Done

- Main/Data/Quadrant views work across strength, rest, tempo run, interval,
  and route scenarios.
- HR slot remains present for live, pending, missing-permission, unavailable.
- Target-window colors/arrows match authored data.
- Route/directions either work against a proven route package or show the
  explicit unavailable state.
- Simulator/device screenshots prove layout.

## Proof Map

- Check: metric resolver unit/property tests.
  - Boundary: pure computation.
  - Proves: slot resolution, fallback, target windows, inverse pace arrows,
    mixed-circuit resolver precedence, and distance-interval GPS fallback.
- Check: Watch UI view tests or screenshot QA.
  - Boundary: user-facing visual.
  - Proves: layouts render, text fits, and HR slot never hides.
- Check: HealthKit/GPS/route recorded or real-device scenarios.
  - Boundary: external platform.
  - Proves: sensor metrics populate correctly and route metrics populate only
    when route package proof exists.
- Check: stale double-tap/action rejection scenario from Phase 7/8 fixtures.
  - Boundary: protocol + user interaction.
  - Proves: UI cannot advance a stale cursor even when the view still renders.
- Check: simulator QA for watch views.
  - Boundary: user-facing.
  - Proves: swipe/double-tap basic interaction and layout.

## Independent Review

- Artifact: metric resolver, watch UI, screenshots, docs.
- Reviewer: Codex focused on slot stability, fallback honesty, and layout proof.
- Reopen condition: HR slot hides, labels waste space, or directions crowd out
  primary effort.

## Closeout

- Update `docs/watch-metrics.md` and feature gap map.
- Attach screenshot set.

## Recovery Context

This phase is watch UI/metrics. Do not redesign phone execution here.

## Residual Uncertainty / Accepted Risks

- Route package fidelity may start minimal.
  - Accepted if directions view has correct slots and fallback states.
  - Signal: route view cannot guide a real turn.

## Escalation Triggers

- Sensor APIs cannot support required metric cadence.
- Watch text/layout cannot fit without changing the locked view grammar.
