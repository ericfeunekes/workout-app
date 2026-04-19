---
title: persistence
status: living
purpose: Behavioral contract + QA scenarios for persistence
covers:
  - app/Packages/Persistence/Sources/Persistence/SessionStore.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/ExecutionViewModel+Persistence.swift
  - app/Packages/Features/Execution/Sources/FeaturesExecution/SessionStateCodable.swift
  - app/Packages/Core/Session/Sources/CoreSession/SessionState.swift
  - app/Packages/Persistence/Sources/Persistence/WorkoutCache.swift
  - app/Packages/Persistence/Sources/Persistence/WorkoutCache+History.swift
---

# persistence

## What it does
Live-session state is stored as one opaque-bytes row in SwiftData. Every `apply(_:)` call in `ExecutionViewModel` runs the reducer, writes `state` back in-memory, then fires a detached `Task` that JSON-encodes `SessionStateCodable(state:)` and calls `sessionStore.save(payload)` (`ExecutionViewModel+Persistence.swift:37-54`). On app launch the shell calls `restoreIfPossible()` which loads the bytes, decodes to `SessionState`, and replaces the seeded state (`ExecutionViewModel+Persistence.swift:16-26`). `SessionStoreImpl` is a one-row-ever store (upsert, single `SessionSnapshotModel`) implemented as a `@ModelActor` (`SessionStore.swift:35-60`). The Persistence package deliberately does NOT import CoreSession — the Features layer owns encoding, Persistence is the opaque bucket (`SessionStore.swift:7-13`).

The persisted snapshot captures everything needed to resume: `workoutID`, `route`, `cursor` (block/item/set), `items[].sets` (load/reps/rir/done/adjust), `items[].autoregHeld`, `items[].performedExerciseID`, `restEndsAt` (absolute Date), `note`, and `structure` (`SessionStateCodable.swift:27-66`). Rest timer uses an absolute `Date` not a remaining-seconds count, so reload re-derives remaining time without drift (`SessionState.swift:19-25`).

## State surface
- **Inputs:** `SessionState` (pure value), `SessionStore` protocol (load/save/clear).
- **Outputs / side effects:** One `SessionSnapshotModel` row in SwiftData. `save` replaces `encodedJSON` + `savedAt`; `clear` deletes all rows of that model (`SessionStore.swift:43-59`). Every `apply` fires one background `Task` (`ExecutionViewModel+Persistence.swift:44`).
- **State transitions:** Each reducer dispatch re-persists; `.save` in `saveAndDone` fires an additional `clear()` (`ExecutionViewModel.swift:354`). Failures during encode/save are silently swallowed — in-memory state is authoritative.

## What it deliberately doesn't do
- Does NOT block the UI on disk writes — all persistence is fire-and-forget (`ExecutionViewModel+Persistence.swift:42-54`).
- Does NOT version the codable payload explicitly — a schema drift just fails to decode, which `restoreIfPossible` treats as "no saved state" (`ExecutionViewModel+Persistence.swift:23`).
- Does NOT import `CoreSession` from Persistence — boundary enforced by `docs/architecture/boundaries.md` (`SessionStore.swift:10-13`).
- Does NOT use `ModelContext.transaction { }` in `WorkoutCache` — see SwiftData caveat below.
- Does NOT store elapsed rest seconds — only absolute `restEndsAt` (`SessionState.swift:19-25`).

## Edge cases handled in code
- **SwiftData `ModelContext.transaction` does NOT roll back on throw in iOS 17.x** (`docs/architecture/hotspots.md:167`). `WorkoutCache.save`, `saveWorkout`, `saveSetLogs` all use an explicit `do { ... try modelContext.save() } catch { modelContext.rollback(); throw error }` pattern (`WorkoutCache+History.swift:139-148`, `:150-163`). **Any new multi-insert Persistence method MUST follow this pattern.** `transaction { }` is a trap until iOS 18+ fixes it.
- Failed decode silently returns "no saved state" rather than crashing (`ExecutionViewModel+Persistence.swift:23`) — offline-first + never-crash posture.
- `SessionStore` is one-row-ever: save overwrites the existing row (`SessionStore.swift:47-52`).
- `saveAndDone` fires `.save` (empties `state.items`) BEFORE the async `sessionStore.clear()` — if clear races ahead or behind the final persist, both paths end up at Today with no zombie session (`ExecutionViewModel.swift:349-356`).
- `restoreIfPossible` only runs when `sessionStore` is non-nil — tests inject nil for pure-offline paths (`ExecutionViewModel+Persistence.swift:17`).
- Rapid `logSet` calls each fire their own persist `Task` — the in-memory state is authoritative; disk may lag by a few writes but the LATEST encoded snapshot is always the LATEST in-memory state (`ExecutionViewModel+Persistence.swift:38-54`).

## Known issues / gaps
- `docs/architecture/hotspots.md` SwiftData transaction caveat — documented, enforced by convention + `WorkoutCacheTests`, but not lint-enforced.
- No explicit schema version for `SessionStateCodable` bytes — if the shape changes we rely on decode failure + fresh session; data loss is bounded to the one live session.
- **SwiftData schema is versioned** (bug-047, perf-002): `WorkoutDBSchemaV1` → `V2` (exercise defaults) → `V3` (`SetLog.workoutID` + `plannedExerciseID` denormalization) → `V4` (`PushItemModel.priority` + `dedupKey` for perf-002). V2→V3 uses a lightweight stage with a backfill that walks the surviving-items map so logs keep their workoutID reference. V3→V4 uses a lightweight stage with a backfill that decodes each row's envelope and populates the two new columns. Pinned by `SchemaMigrationTests`.
- **Subtree reconcile** (bug-046): `WorkoutCache.save` reconciles per workout id — diff incoming vs cached blocks/items/alternatives, detach children before deleting the orphan, re-upsert. SetLogs explicitly preserved via detach-before-delete. New `loadOrphanedSetLogs()` API returns logs whose item was removed so History can still surface them.
- **Session-persistence pipeline** (bug-043): every `apply(_:)` enqueues a monotonic-revision snapshot on a VM-owned `SessionPersistencePipeline` handle (replaced the `Task {}` + `ObjectIdentifier` static table). FIFO preserved; restore applies a normalization pass that re-runs `enterRestIfZeroItemBlock` / `enterBlockTimerIfNeeded` / `enterTabataWorkWindowIfNeeded` so a timer-midflight kill can't restore malformed.
- Persist pipeline swallows encode/save errors. In-memory state wins; bounded loss ≤ 1 mutation.

## QA scenarios

### S1. Happy path — mid-workout relaunch
- **setup:** Log 2 sets of a 4-set exercise; background the app; `SessionStore` has the latest snapshot.
- **steps:** Kill the app; relaunch.
- **expected:** Shell calls `restoreIfPossible()`; `ExecutionViewModel.state` matches pre-kill: cursor on set 3, first 2 sets done, route preserved (`.active` or `.rest`).
- **notes:** AppBootstrap must await `restoreIfPossible` before rendering — verify no flash of seeded state.

### S2. Rest-timer relaunch — absolute time survives
- **setup:** Log a set; enter `.rest` with `restEndsAt = now + 90s`. Background the app for 30s.
- **steps:** Foreground.
- **expected:** Ring reflects `restEndsAt - now() ≈ 60s`. No drift, no reset. Matches the spec rationale at `SessionState.swift:19-25`.

### S3. Rest-timer across device-time change
- **setup:** Mid-rest (60s remaining). User opens Settings → moves system clock forward 5 min.
- **steps:** Return to the app.
- **expected:** `restEndsAt - now()` is now negative → rest elapsed. Timer completes or advances.
- **notes:** Honors wall clock per the absolute-timestamp design. If user moves clock backward, rest ring shows MORE remaining time — acceptable artifact.

### S4. Save & done clears the bucket
- **setup:** Normal completion.
- **steps:** Tap save & done; kill the app; relaunch.
- **expected:** `SessionStore.load()` returns nil (cleared in `ExecutionViewModel.swift:354`). No resume — app lands on Today with a fresh seeded state.

### S5. Crash mid-set
- **setup:** About to log set 3; simulate a hard kill (SIGKILL) between `apply([.logSet])` and the persist Task completing.
- **steps:** Relaunch.
- **expected:** The most recent persisted snapshot — possibly missing set 3's write but including set 2 — is restored. User re-logs set 3. No crash.
- **notes:** Because `persist()` is fire-and-forget, there is a race window where `apply` returned but the encoded bytes aren't on disk. Bounded loss ≤ 1 mutation.

### S6. Corrupt persisted bytes
- **setup:** Manually mutate `SessionSnapshotModel.encodedJSON` to invalid JSON.
- **steps:** Relaunch.
- **expected:** `JSONDecoder().decode(...)` returns nil (the optional try); `restoreIfPossible` silently leaves `state` at the seeded value (`ExecutionViewModel+Persistence.swift:20-22`). Fresh session.

### S7. Schema-version mismatch (future)
- **setup:** Persist bytes from an older `SessionStateCodable` shape (e.g., missing a future field).
- **steps:** Relaunch on newer app.
- **expected:** Decode fails → fresh session. Loss bounded to the one live session (`SessionStateCodable.swift:10-13`).
- **notes:** No migration path exists. Acceptable per the offline-first + single-live-session design.

### S8. `autoregHeld` survives relaunch
- **setup:** User Undo'd an autoreg proposal mid-workout → `items[i].autoregHeld = true`.
- **steps:** Background, relaunch.
- **expected:** Flag survives; subsequent `logSet` on that item does NOT re-propose (Features gates on the flag).

### S9. Mid-workout swap survives relaunch
- **setup:** User swapped item 2's exercise → `items[1].performedExerciseID = exerciseY`.
- **steps:** Background, relaunch.
- **expected:** Swap preserved (`SessionStateCodable.swift:110-127`). Active screen shows exerciseY.

### S10. WorkoutCache transaction rollback (the hotspot)
- **setup:** Force `saveSetLogs` to throw mid-loop (e.g., invalid UUID on the 3rd log).
- **steps:** Call `saveSetLogs([a, b, bad, d])`.
- **expected:** Explicit `modelContext.rollback()` fires; NO rows from that call end up in the context (`WorkoutCache+History.swift:144-147`). Rethrows to caller.
- **notes:** This is the `docs/architecture/hotspots.md:167` caveat. The test `WorkoutCacheTests::testSaveRollsBackOnThrowMidLoop` pins it. Any new mutator must follow this pattern — `transaction { }` is banned.

### S11. Rapid logSet writes
- **setup:** Fire 10 `logSet` calls in rapid succession (scripted via test harness).
- **steps:** Observe in-memory `state` vs last persisted bytes.
- **expected:** In-memory is always latest. Persisted bytes converge to the latest within a few ticks — each `Task` encodes from its captured `snapshot` (`ExecutionViewModel+Persistence.swift:44`). Intermediate snapshots may be overwritten before ever touching disk; that's fine.
- **notes:** Task execution order is not strictly serialized via the actor hop; kill-and-relaunch could return any recent snapshot. Acceptable.

### S12. `ExecutionViewModel.apply` with no sessionStore
- **setup:** Test init with `sessionStore: nil`.
- **steps:** Log sets, advance, complete.
- **expected:** `persist()` returns early (`ExecutionViewModel+Persistence.swift:38`). No disk writes. No crash.
- **notes:** Pure-offline test path.

### S13. Cold launch with no persisted row
- **setup:** Fresh install or post-`clear()` state.
- **steps:** Launch.
- **expected:** `SessionStore.load()` returns nil → `restoreIfPossible` bails at the guard (`ExecutionViewModel+Persistence.swift:19`). VM stays on seeded state.

### S14. Backgrounding during rest
- **setup:** Rest ring showing 45s remaining.
- **steps:** Swipe up to Home; wait 30s; return.
- **expected:** Ring shows ~15s remaining (wall-clock math off absolute `restEndsAt`). Rest completes at the original absolute time regardless of background duration.

### S15. Persist write fails silently
- **setup:** Simulate a SwiftData write error (e.g., full disk).
- **steps:** Log a set.
- **expected:** `persist()`'s `do/catch` swallows (`ExecutionViewModel+Persistence.swift:49-52`). In-memory state proceeds. A relaunch may restore a stale snapshot (≤ 1 mutation behind).
- **notes:** No user-visible error. Watchlist: if disk writes fail repeatedly on a real device, the delta grows — consider surfacing a diagnostic.

### S16. Restore race vs `saveAndDone` clear
- **setup:** `saveAndDone` fires `.save` (empties state, persists empty) AND `sessionStore.clear()` concurrently.
- **steps:** Kill between the two.
- **expected:** Either the persist wrote empty state (restore gives Today with empty items) OR the clear ran (restore returns nil, seed gives Today). Both land at Today. No zombie session.

### S17. Encoding failure (future-proofing)
- **setup:** Inject a `SessionState` that fails to encode (e.g., non-finite Double somewhere downstream).
- **steps:** Log the offending set.
- **expected:** `try JSONEncoder().encode(snapshot)` throws → swallowed at `ExecutionViewModel+Persistence.swift:49`. In-memory state still authoritative; disk is stale but not corrupted.
- **notes:** The current schema is all `Int / Double / String / Date / UUID / Bool` — hard to hit. Scenario exists for future fields.
