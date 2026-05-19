---
title: settings
status: built
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for app settings, recovery, local reset, units, and diagnostics surfaces.
covers:
  - app/Packages/Features/Settings/
  - app/WorkoutDB/WorkoutDBApp.swift
  - docs/sync.md
  - docs/features/firstrun.md
  - docs/features/telemetry.md
---

# settings

## Target behavior

Settings is the recovery and local-control surface for the dumb app. It lets
Eric inspect and change app-local configuration without creating a programming
surface. It owns server connection recovery, destructive local reset actions,
units preferences, autoreg default display/editing, and diagnostic affordances
that help prove what happened.

Settings must stay section-based. New surfaces add a small section model and
row contract rather than extending a single mega-view.

## State surface

- **Inputs:** stored server URL/token state, local cache/reset actions, units
  preference, autoreg defaults, diagnostics/telemetry availability.
- **Outputs / side effects:** refresh/pull trigger, token/server update,
  destructive cache reset, units/defaults writes, optional diagnostic export or
  debug surface when those gaps are implemented.
- **State authority:** server URL + bearer token live in Keychain/TokenStore;
  units and defaults are local app preferences; workout plans and history remain
  server/app data per `docs/sync.md`.

## Current contract

Settings is already a feature package and is mounted through `Shell.RootTabView`.
It should present rows as explicit sections: server, local data, units, autoreg
defaults, and diagnostics. Destructive actions require confirmation and should
leave the app in a recoverable route.

Settings does not choose workouts, modify programming, or analyze history.
If a control would change the workout plan itself, it belongs in Claude or a
future accepted app-side proposal workflow, not Settings.

## Current gaps

- `SETTINGS-GAP-002`: Sync now, change server, reset confirmation, units,
  telemetry export/debug, token-rejected recovery, and autoreg defaults need one
  visible behavioral surface with scenario proof.
- `SETTINGS-GAP-003`: Section-as-type architecture is documented as a hotspot
  preventative, but feature-level acceptance and QA scenarios are not yet
  proven for each section.
- `SETTINGS-GAP-004`: Diagnostics/export rows are target behavior only where
  telemetry gaps call for them; no broad debug dashboard is accepted.

## QA scenarios

### S1. Sync now

- **setup:** saved valid connection, pending server change or normal online
  state.
- **steps:** open Settings, tap sync/refresh if available.
- **expected:** pull runs once, visible state reflects success/failure, no
  duplicate bootstrap or route reset occurs.

### S2. Change server confirmation

- **setup:** saved connection and local cached workouts.
- **steps:** open Settings, choose change server, cancel, then repeat and
  confirm.
- **expected:** cancel preserves local state; confirm wipes the authoritative
  local server-owned state as documented in `docs/sync.md`, routes to FirstRun
  or connection entry only after the clear succeeds, preserves HealthKit archive
  data, and never leaves mixed old/new server data visible.

### S3. Reset local data

- **setup:** cached workouts and/or completed local history.
- **steps:** open Settings, choose reset local data, cancel, then confirm.
- **expected:** destructive confirmation is clear; confirm clears only the
  intended server-owned local data, preserves the current connection and
  HealthKit archive data, and leaves credential behavior as specified by the
  row.

### S4. Units and autoreg defaults

- **setup:** Settings visible.
- **steps:** change units and autoreg defaults.
- **expected:** preferences persist across relaunch. Autoreg precedence follows
  `docs/features/autoreg.md`; Settings does not silently override authored
  prescription values.

### S5. Section accessibility

- **setup:** smallest supported phone and AX3/AX5 Dynamic Type.
- **steps:** open each Settings section.
- **expected:** rows remain reachable, labels describe side effects, destructive
  rows are distinguishable, and no section requires hidden gestures.
