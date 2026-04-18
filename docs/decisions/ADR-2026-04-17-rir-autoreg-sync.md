---
title: RIR, autoregulation, and sync reconciliation
status: accepted
date: 2026-04-17
covers:
  - docs/specs/v2-architecture.md
  - docs/prescription.md
  - docs/sync.md
  - app/
  - server/
---

# ADR: RIR, autoregulation, and sync reconciliation with the design drop

**Complements:** `ADR-2026-04-17-ux-scope.md` (same day). That ADR decided network reach (Tailscale + bearer), multi-tenancy posture, history strategy, and watch scope. This ADR builds on those by adding (a) the RIR scale + autoreg, (b) formalized sync cadence and conflict rules, (c) the first-run connection-string UX on top of the bearer-over-Tailscale posture, and (d) `set_log.performed_exercise_id` for swap logging. Nothing in the UX scope ADR is superseded.

## Context

A design handoff arrived on 2026-04-17 from Claude Design (`docs/design/`). It is treated as **reference, not spec** (see `docs/design/ORIGIN.md`). Where the design and the v2 architecture spec disagreed, we needed to decide.

Four reconciliations mattered:

1. **Effort scale.** Spec had `set_log.rpe` (Float, 6–10). Design is RIR (Int, 0–5) and explicitly rejects RPE language.
2. **Autoregulation.** Design makes load auto-adjustment based on RIR a first-class feature, with per-item `target_rir` and an `autoreg` config. The existing schema had no representation for either.
3. **Sync cadence and conflict rules.** The spec had a direction-based sync model but no explicit cadence, no conflict rules, and no first-run UX. The design's `RULES.md` supplies those details.
4. **Load granularity.** Design hardcodes 2.5 kg steps. Real equipment varies (barbell, dumbbells, machines, dip belts, fractional plates).

The user directive was clear: *the design is the source of truth for UX, not for backend schemas. Our job is to build the schema and system that best supports what the design needs.*

## Decision

### 1. RIR replaces RPE

- `set_log.rpe: Float? (6–10)` → `set_log.rir: Int? (0–5)` across server SQLAlchemy, Pydantic, Swift DTOs, SQLite CHECK constraint, OpenAPI schema, contract tests, fixtures, and the v2 spec. A new migration adds `rir` and drops `rpe`; v1 data does not need migration because no production data exists yet.
- All user-facing and Claude-facing copy is RIR. "RPE 7" has no meaning in the system.
- Half-step RIR is out of scope. If practitioners need it we revisit; until then, integers only.

### 2. Autoregulation lives in `prescription_json`

- Per-item `target_rir` + an `autoreg: { overshoot_at, overshoot_step_kg, undershoot_at, undershoot_step_kg, apply_to }` subobject. Documented in full in `docs/prescription.md`.
- **The server does not interpret autoreg.** `prescription_json` remains opaque server-side. The app applies the rules; Claude authors them.
- **Hold is session-scoped.** User "Undo" on an autoreg proposal sets a local `autoregHeld` flag on the item for the duration of the session. No persistence across workouts. Next session, autoreg is live again.
- **Past edits do not retrigger.** Editing a completed set (from the rest ledger, completion screen, or history) changes the record but does not fire autoreg. The per-set `adjust` field is preserved and set to `"manual"` on edits that weren't already `"up"` or `"down"`.
- **`apply_to` ships with `"remaining"` only.** The design leaves room for `"next"` and `"all-future"`; we cut them for v1. Claude re-programs next week by reading set_log RIR history — no client-side escalation needed.

### 3. Load step lives in the prescription

- No per-exercise `load_increment` column. The `overshoot_step_kg` and `undershoot_step_kg` values are the source of truth, set by Claude per item based on the equipment. This matches the "prescription is authored with equipment knowledge" posture and avoids a schema column that would drift between the exercise-level default and the per-session reality.

### 4. Sync cadence and conflict rules are formalized

Documented in full in `docs/sync.md`. Key rules:
- **Cadence:** on app open + on log write + ~60s foreground retry. No aggressive polling.
- **Conflicts:** server wins for prescriptions, app wins for logs, live session is frozen (new prescriptions apply to the next occurrence).
- **First-run:** connection string (URL + bearer token) via paste or QR. No login surface. The server URL is the identity; the bearer distinguishes app traffic from other tailnet traffic.
- **Offline:** neutral pill, silent retries, full offline execution once the workout is cached.

### 5. Block/WorkoutItem semantics are unchanged

The design's "block" is a single-exercise unit (with a `scheme` and sets). Our schema's `block` is a container of N `workout_item`s with a shared `timing_mode`. These are compatible: the design's notion maps to our `(Block + 1 WorkoutItem)` for straight_sets, and to `(Block + N WorkoutItems)` for supersets/circuits/EMOM/AMRAP/etc. Our model is a superset of the design's, and the app collapses the degenerate case when N=1.

### 6. Auth posture is unchanged; first-run UX is new

Bearer token over Tailscale from ADR-2026-04-17-ux-scope stands. What changes is the first-run surface: we now explicitly require a connection string input (paste or QR), not an implied "enter credentials" form. Token rotation and multi-user provisioning remain as previously decided.

### 7. Body weight is logged via `user_parameters` at completion

The design's completion screen suggests a session-level body weight. Rather than adding `workout.bodyweight_kg`, the app pushes a `user_parameters` row with key `bodyweight_kg`, value, and the completion timestamp. This stays in the append-only log alongside every other user parameter and feeds trend analysis without a schema change.

### 8. Watch face grammar is deferred to v1.1+

The design's watch work (three JSX sources, two hi-fi HTMLs, widget-based face grammar) is substantive and ahead of v1. The v1 watch stays scoped to HR capture, haptic transitions, and easy start/end-set per ADR-2026-04-17-ux-scope. When we promote watch UX, the design bundle's `watch-grammar.jsx` is the reference.

## Consequences

### Schema cutover

A coordinated cutover ships together per `docs/MIGRATIONS.md`:
- `server/db/migrations/NNN_rpe_to_rir.sql` — add `set_log.rir INTEGER` with CHECK (0..5), drop `rpe`. Add `set_log.performed_exercise_id UUID NULL` (FK to `exercise.id`, nullable) so session-local swaps record the actually-performed exercise without mutating the workout template.
- `server/workoutdb_server/models.py` — SQLAlchemy column rename and type change.
- `server/workoutdb_server/api/schemas.py` — Pydantic field rename; update OpenAPI regeneration target.
- `schema/Sources/WorkoutDBSchema/Entities.swift` — Swift DTO rename.
- `schema/openapi.json` — regenerate.
- `tests/contract/test_openapi_drift.py`, `tests/contract/test_swift_schema_parity.py`, `schema/Tests/WorkoutDBSchemaTests/*` — update assertions and fixtures.
- `docs/specs/v2-architecture.md` — field rename + pointers to `docs/prescription.md` and `docs/sync.md`.

### New docs

- `docs/prescription.md` — authoring vocabulary per timing mode; autoreg configuration and rules; parametric shapes.
- `docs/sync.md` — sync cadence, conflict rules, first-run UX, offline behavior, auth posture.
- `app/README.md` (expanded) — in-app behavior contract (tap-to-edit, swap, autoreg applier, offline pill, completion).

### App implementation responsibilities

The app gains:
- An autoreg applier that reads `target_rir` + `autoreg` from each item's `prescription_json` and proposes load changes on the rest screen.
- A per-session `autoregHeld` flag per item.
- A per-set `adjust` field in the local session state (`"up"`, `"down"`, `"manual"`, or null) rendered as a glyph on current/pending sets.
- A first-run connection-string flow (paste URL, scan QR).
- A silent retry loop for the push queue.
- A body-weight prompt in the completion flow that writes to `user_parameters`.

### What did not change

- The 10 timing modes + `rest` block. The spec list already matched the design.
- Entity list, UUID ownership, `user_parameters` append-only semantics.
- Tailscale + bearer auth posture.
- The offline-first invariant during a workout (already in the ADR-2026-04-17-ux-scope).

## Alternatives considered

- **Keep RPE, translate to RIR for display.** Rejected — two scales in one system is a recipe for confusion, and RIR is simpler analytically anyway (failure = 0, not 10).
- **Add `autoreg` as first-class columns on `workout_item`.** Rejected — it's prescription data, it belongs in `prescription_json` where shape evolution doesn't require migrations.
- **Model load increment per-exercise (`exercise.load_increment_kg`).** Rejected — equipment context isn't exercise-intrinsic (same dumbbell press at different gyms has different steps). Putting it in the prescription where Claude can decide is cleaner.
- **Let "all-future" autoreg escalate load changes back to the server.** Rejected — this creates a client → server prescription feedback loop that conflicts with the "server owns prescriptions" rule. Claude re-programs from RIR history instead.
- **Make the connection URL the only credential (no bearer token).** Rejected — tailnet trust + URL alone would let any tailnet peer hit the server. The bearer keeps app traffic separate from casual probing.

## Done when

- This ADR is committed.
- `docs/prescription.md` and `docs/sync.md` exist and are accepted.
- `docs/specs/v2-architecture.md` reflects the `rpe → rir` rename and links to `prescription.md` and `sync.md`.
- `app/README.md` describes the in-app behavior contract.
- `docs/ARCHITECTURE.md` and `docs/AGENTS.md` route to the new docs.

The actual schema cutover (migration + DTO renames + contract test updates) will be its own scoped unit of work — this ADR records the decision, not the implementation.

## Out of scope

- Implementing the schema cutover or any app/server code.
- Watch face grammar implementation (v1.1+).
- Half-step RIR.
- Autoreg modes beyond `"remaining"`.
- Per-exercise load increment column.
- Sync deletion semantics.

## Open questions

None that block the doc work. Open items deferred to their docs:
- Multiple active workouts at once (`docs/sync.md`).
- Set-log deletion semantics (`docs/sync.md`).
- Watch sync direction if watch ever writes independently (`docs/sync.md`).
