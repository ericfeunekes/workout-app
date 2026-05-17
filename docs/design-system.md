---
title: DesignSystem
status: planned
last_reviewed: 2026-05-17
purpose: Visual, accessibility, Dynamic Type, and material contract for reusable SwiftUI primitives.
covers:
  - app/Packages/DesignSystem/
  - docs/architecture/swift-packages.md
  - docs/QA.md
---

# DesignSystem

`DesignSystem` is the shared visual layer for the app. It owns reusable tokens
and primitives: colors, typography, spacing, radius, motion, buttons, chips,
pills, cards, rings, keypad controls, icons, and edit-surface visual contracts.
It does not own routing, workout logic, persistence, sync, or feature-specific
state.

The package exists so feature views can stay small and consistent without
importing sibling features. If a shared surface is visual-only, it belongs here.
If it needs execution cursor, timer, or workout state, it belongs in
`Core/Session` or the owning feature projection instead.

## Target contract

- Typography is semantic and scalable. Timer and hero text may have large visual
  treatment, but it must still fit known phone sizes and Dynamic Type settings.
- Interactive primitives expose accessibility label, value, hint, identifier,
  enabled state, and selected state where applicable.
- Tap targets are at least 44 pt unless a feature doc names a narrower
  exception and QA proves it is still reachable.
- Material and future Liquid Glass styling are centralized here or in Shell
  chrome wrappers. High-frequency timer routes, keypad controls, RIR/logging
  controls, History ledgers, and Watch faces do not receive glass/material
  treatment without ETTrace-backed proof.
- Feature views can compose primitives, but they should not redefine button,
  chip, timer, or sheet chrome behavior ad hoc.

## Proof expectations

DesignSystem changes usually need both package tests and simulator evidence.
Use `docs/TESTING.md` for pre-QA proof and `docs/QA.md` for visible evidence.

Required evidence depends on the claim:

- token or primitive behavior -> package tests where the behavior is pure
- tap target or accessibility metadata -> `snapshot_ui` labels, traits, frames,
  and enabled/selected state
- Dynamic Type -> screenshots or snapshots at default, AX3, and AX5 for the
  affected screens
- material/glass on active routes -> ETTrace before/after evidence for the
  focused timer or scroll flow

## Current gaps

- `DS-GAP-001`: Typography tokens are not yet semantic/scalable enough to carry
  Dynamic Type across hero timers, compact labels, and sheet controls.
- `DS-GAP-002`: Interactive primitives do not centrally guarantee
  accessibility label/value/hint/identifier and 44 pt target expectations.
- `DS-GAP-003`: Active, Rest, LogSetSheet, SetEditSheet, and History need
  Dynamic Type and accessibility proof using `snapshot_ui`.
- `DS-GAP-004`: Material/glass usage is not yet centralized behind approved
  Shell/DesignSystem wrappers with no-glass defaults for high-frequency workout
  surfaces.
