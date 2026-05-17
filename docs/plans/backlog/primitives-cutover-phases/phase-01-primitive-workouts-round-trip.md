---
title: Phase 1 — Primitive workouts round-trip through storage
status: backlog
last_reviewed: 2026-05-17
purpose: First phase of the primitives-data-model cutover. After this phase, Claude can author workouts in the primitive vocabulary and they persist correctly through the storage pipeline from server ingest through app decode and back.
parent: ./README.md
spec:
  - docs/specs/primitives-data-model.md
  - docs/specs/primitives-data-model/authoring-shape.md
  - docs/specs/primitives-data-model/log-shape.md
---

# Phase 1 — Primitive workouts round-trip through storage

> Historical/source-material note: this is not a standing implementation plan.
> Future work must start from `PDM-GAP-*` rows in the owning primitives spec
> files and create a fresh active plan against the codebase state at pickup
> time.

## Unit statement

After this phase, a workout authored in the primitive vocabulary (Block > Set > Slot, with the seven orthogonal primitives attached at their documented levels) can be pushed to the server, persisted in the server's primitive schema, pulled to the app, decoded into the app's Swift DTOs, persisted to the app's on-device SwiftData store at the primitive schema version, and returned to the server unchanged. Both server and app persistent stores speak the primitive vocabulary end-to-end — no parallel legacy storage paths remain on either side. Nothing executes yet — this phase establishes the wire format and persistent storage shape that everything downstream consumes.

## Why

Claude today authors workouts in the legacy per-timing-mode vocabulary because that's what the server accepts, what the app decodes, and what both stores persist. Every downstream phase depends on the new vocabulary existing as data — Phase 2's execution path has no workouts to run, Phase 3's drivers have no contract to read, Phase 4's new patterns have no way to be expressed — until both the wire format and the persistent storage layer speak primitive-shape workouts from end to end.

The pressure here is not an observed user failure; it's a dependency the rest of the cutover cannot begin without. Phase 1's stakeholders are Claude as author (who can start expressing workouts in the new vocabulary once the full pipeline accepts them) and Phase 2 as named downstream consumer (which cannot build an execution path against a storage contract that is still split between old and new shapes).

The repo's complete-cutover philosophy is authoritative for the final merge, and it applies within each phase's owned surfaces. Per `CLAUDE.md` § "Development philosophy": *"Complete cutovers only. When something changes, change it everywhere in one commit — server, app, schema, tests, docs. No feature flags, no legacy paths, no parallel old+new codepaths."* Phase 1 must therefore cut over both server and app persistent storage together. A state where the server has advanced its schema but the app's SwiftData store still reads/writes the legacy shape is a storage-surface cutover violation. Phase 1 is big enough to hold both sides of the schema cutover; Phase 2 inherits a fully-cut-over storage substrate and adds execution on top. Phase 1 itself is a branch checkpoint, not a deployable release.

## Acceptance criteria

1. **Authoring round-trip.** A workout expressed in the primitive vocabulary, pushed from a conversational authoring surface to the server, is accepted by the server's ingest path, stored intact, returned on pull, decoded by the app's schema layer, and re-encoded back to the server without losing structural fidelity on any of the seven primitives at any hierarchy level.

2. **Legacy rejection.** A workout expressed in the legacy per-timing-mode vocabulary is rejected by the server's ingest path with a validation error that names the missing primitive shape. No legacy-shape workout is accepted after this phase closes.

3. **Contract parity between server and app.** The set of structural shapes the server can produce matches exactly the set of shapes the app's schema layer can decode. A shape that round-trips on one side but fails on the other is a parity break; the phase is not done while any parity break exists.

4. **Fixture coverage of all ten worked examples.** The ten canonical worked examples documented in the authoring-shape aspect are expressible as primitive-vocabulary fixtures, stored on the server, and pulled to the app without error. Each worked example's fixture is a live artifact that later phases read against.

5. **Relative-load resolution is deterministic at app seed time after pull.** When a workout carries a relative-load slot (e.g., "85% of 1RM") and the app's local user-parameter mirror carries a timestamped latest value for the referenced parameter, seeding the pulled workout resolves that relative load to its absolute equivalent deterministically from the latest-by-timestamp parameter row, and pins the source parameter's identity alongside the resolved value. Two seed operations against different local parameter states produce different resolved values.

6. **Node identity is server-assigned.** Every block, set, and slot in a stored workout carries a stable identity that the server generates at authoring time. The app consumes these identities; it does not synthesize them. A workout pulled, edited, and pushed back carries the same identities on unchanged nodes.

7. **App-side persistent storage has cut over to the primitive schema.** The on-device SwiftData schema is bumped to a new version whose persistent model types represent blocks, sets, slots, and alternatives in the primitive shape. The old flattened-workout-item persistent models no longer define the latest schema. Any legacy adapter that flattens a primitive pull into the old storage shape (for example a `MappedWorkout` bridge inside the Sync or Shell packages) is removed. Pulling a primitive workout from the server writes it to the app's local store in the primitive shape; reading it back from the local store returns the same primitive shape.

8. **The complete-cutover invariant holds for storage.** At the close of this phase, the server's reported schema version and the app's latest SwiftData schema version both reflect the primitive cutover. Neither side carries a parallel legacy codepath, adapter, or feature flag to access the pre-cutover shape. The test that would break if a legacy-flattened path were reintroduced exists and runs on the phase gate.

9. **Completed local workout history is preserved.** A pre-cutover local store containing completed set logs can migrate to the primitive SwiftData schema without losing user-observable history facts: workout date/status, exercise identity/name, performed values, notes, skip/performed state, and any available completion summary.

## QA contract

**Phase gate — deterministic, fast, blocks Phase 1 close.**

- **AC1, AC2, AC3** are proven by contract tests that exercise the server ingest + storage + pull + app decode + re-encode cycle against both primitive-vocabulary and legacy-vocabulary inputs. The primitive-vocabulary cases pass end-to-end; the legacy-vocabulary cases are rejected at ingest with a validation error whose shape is asserted. Reverse-patch: a change that accidentally re-accepts legacy-shape workouts breaks the rejection assertion; a change that silently drops a primitive field during storage breaks the fidelity assertion on pull.
- **AC4** is proven by a fixture-decoding test that loads every canonical worked example fixture through both the server's model layer and the app's schema layer and asserts identical decoded structures. Reverse-patch: a fixture that names a primitive the codecs don't handle breaks the test; a codec that drops a field breaks the structure comparison.
- **AC5** is proven by an app seed-time resolution test that seeds two different local user-parameter states, transforms the same pulled relative-load workout against each state, and asserts the resolved absolute values differ and that each resolved value pins the correct source parameter. Reverse-patch: a change that caches resolution across parameter states breaks the test; a change that forgets to pin the source breaks the identity assertion.
- **AC6** is proven by an identity-persistence test: push a workout, pull it, modify a non-structural field on one node, push it back, pull again, and assert the node identity is stable across the round-trip. Reverse-patch: a change that regenerates identities on every push breaks this.
- **AC9** is proven by a SwiftData migration test that starts from a pre-cutover local store with representative completed logs, upgrades it, and asserts the post-cutover history surface can still show the same completed workout facts. Reverse-patch: a destructive migration that clears history breaks the migrated-history assertion.

**RC gate — not applicable for Phase 1.** Phase 1's proof is deterministic; no production-shape stress testing or real-model probing applies.

## Scope

**In scope**:
- The server-side persistent storage vocabulary — server SQL schema, Pydantic ingest models, SQLAlchemy ORM, sync endpoint accepts/produces.
- The shared schema (codegen) layer — the OpenAPI contract + the Swift DTOs in `schema/` that decode server-produced bytes.
- The app's `CoreDomain` / `Sync` in-memory decode surface — Swift-side model types that decode primitive payloads into domain objects and re-encode them.
- The app's on-device SwiftData persistent schema — new version bump with primitive-shape persistent model types (blocks, sets, slots, alternatives) replacing the legacy flattened-workout-item shape.
- The `Shell → Persistence` consumer path — the live pull/save/read flow writes and reads primitive-shape workouts in the app's local store.
- The minimal seed-time transform needed to resolve relative loads from the app's local user-parameter mirror before persisting the pulled primitive workout.
- Removal of any legacy-flattened adapter (e.g. `MappedWorkout`-style bridges inside Sync, Shell, or Persistence) that carries the old shape alongside the new.
- The ingest validation that rejects legacy-vocabulary workouts at the server boundary.
- The relative-load resolution that happens at app seed time after pull.
- Fixtures for the ten canonical worked examples.
- Contract tests that prove server + shared-schema parity by decoding server-produced bytes on the Swift side AND that the app's on-device store round-trips the decoded workout without re-introducing a legacy shape.

**Out of scope**:
- **Execution of any workout.** The app can now pull, decode, seed persistence-only derived values, and persist primitive workouts, but it cannot run them. `SessionState`, executable cursor advancement, rest timing, log-row production, push-queue encoding of log rows, and the execution view-model all remain on the legacy shape in this phase and are Phase 2's scope (straight-sets end-to-end) and Phase 3's scope (all twelve timing modes).
- Corrections, history queries, aggregate-row writes.
- Behavior-preservation baselines needed for later phases' equivalence proofs.
- Any documentation rewrite beyond fixture files themselves. Doc sweep is Phase 6.
- Server-side prescription preservation. Existing server-side prescriptions are dropped and re-pushed by Claude in the primitive shape. Completed local workout history is in scope because this phase owns the SwiftData schema cutover.

## Constraints

- **Complete-cutover applies to the storage surfaces Phase 1 owns.** Phase 1 satisfies this by cutting over server + shared schema + app persistent storage all together. A branch state where only the server has advanced is a Phase 1 failure, not an acceptable intermediate. Execution remains a later branch checkpoint and the overall branch is not mergeable until the full cutover closes.
- **Legacy execution and sync shapes are dropped at every boundary this phase touches.** Server ingest rejects legacy payloads. Shared-schema DTOs speak only primitive. App's CoreDomain + Sync decode only primitive. The latest SwiftData execution schema stores primitive workouts and primitive logs; any migrated historical archive is read-only history data, not a legacy execution/sync path. No `MappedWorkout`-style adapter survives.
- **Shared-schema parity is not deferable.** Any structural shape the server produces must decode through the `schema/` Swift layer. A parity break is a phase failure.
- **The executable session / log-row surface is NOT touched in this phase.** That scope fence is real: Phase 1 changes what workouts LOOK like and where they're STORED, plus the persistence-time derived values needed to store them correctly, not how they EXECUTE. Execution stays on the legacy shape until Phase 2 ports it. The `SessionState` reducer, executable cursor advancement, the driver layer, the log-row encoder, the push queue's log-row wire format — none of these are touched here. That boundary holds even though it means the app can pull a primitive workout but cannot run it yet; a pre-execution app that can correctly store new-shape workouts is Phase 1's honest deliverable.
- **Single-user dev posture holds.** No multi-tenant considerations.
- **Append-only user-parameters invariant holds.** Relative-load resolution reads the latest-by-timestamp row from the existing sync contract; no new history mirror.
- **Completed local logs are the preservation constraint.** No old execution path, legacy authoring payload, or legacy SwiftData model survives as a compatibility lane, but completed workout history must remain visible after migration.

## Ordering within the phase

1. The wire vocabulary is defined first — the server's ingest model, the storage shape, the app's decode surface — in a matched triple so contract parity is provable from the outset.
2. Fixture generation follows: the ten canonical worked examples become live fixtures against the new vocabulary.
3. Relative-load resolution lands after the vocabulary and fixtures, because it consumes the pulled workout shape plus the app's local user-parameter mirror.
4. The rejection path for legacy-vocabulary workouts lands last, because it closes the door on the old shape only after the new shape is verifiably complete.

## Known hazards

- **Parity drift at the codegen boundary.** The server and app share a generated contract. If the server's model layer drifts from the generated contract, or the app's schema layer does, the parity tests catch it — but the failure mode is unhelpful messages pointing at codegen. An implementer should expect parity debugging to require reading generated artifacts and knowing which side is the source of truth for each shape.
- **Fixture authoring complexity.** Some of the ten worked examples (compound work targets, sibling work+rest sets, zero-slot rest sets, AMRAP-with-mixed-strength-and-cardio) are deliberately unusual under the old vocabulary. Expressing them as primitive fixtures requires fluency with the authoring-shape aspect, not just a mechanical shape translation.
- **Relative-load resolution order of operations.** App seed-time resolution must run before the resolved workout is persisted to the app-local store; doing it at execute time instead silently couples parameter state to execution moment rather than pull moment, which changes history semantics. This is a subtle correctness issue that a test-light implementation will not surface.
- **History-preservation mapping.** Preserving completed logs across a hierarchy rewrite may require a compact historical archive rather than pretending every old row has a perfect primitive `slot_id`. The acceptance bar is user-visible history preservation without retaining a legacy execution or sync path.
- **Legacy fixture regeneration touches every timing mode.** Every fixture under the existing fixture trees is rewritten in this phase. Fixture review is a significant portion of the phase's review surface and is where subtle shape errors are easiest to miss.

## Proof commands

Phase-close gate: the repo's full contract + schema + parity test suite runs green. The level is "all contract tests pass" — specific test identifiers belong in the implementation plan.

No RC gate for this phase.

## Handoff to implementation-planning

Do not use this file directly as the implementation-planning input. Use
`PDM-GAP-001`, `PDM-GAP-002`, `PDM-GAP-003`, `PDM-GAP-004`, and `PDM-GAP-005`
from the owning primitives spec files, then consult this phase only for prior
decomposition and hazards.
