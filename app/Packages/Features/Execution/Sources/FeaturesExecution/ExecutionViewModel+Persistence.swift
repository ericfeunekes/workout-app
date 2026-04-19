// ExecutionViewModel+Persistence.swift
//
// Persistence helpers and the private `apply` / `findItem` plumbing, split
// out of `ExecutionViewModel.swift` so the class body stays under
// SwiftLint's `type_body_length` cap. The methods remain module-internal.
//
// Write ordering:
//   All `save` and `clear` writes funnel through
//   `SessionPersistencePipeline` (see `+PersistencePipeline.swift`). Each
//   enqueued op carries a monotonic revision number so a save that
//   resolves after a newer save / clear is dropped at the actor boundary
//   instead of clobbering newer bytes on disk. This fixes the bug where
//   fire-and-forget `Task { store.save(…) }` calls landed out of order.
//
// Restore normalization:
//   `restoreIfPossible()` runs the same helpers `start()` runs
//   (`enterRestIfZeroItemBlock`, `enterBlockTimerIfNeeded`,
//   `enterTabataWorkWindowIfNeeded`) so a kill-then-relaunch mid-rest
//   can't land on `.active` for a zero-item block, and can't return to a
//   Tabata active screen missing `workEndsAt`. The normalized state is
//   persisted before the VM is exposed to the UI, so the first render
//   and the on-disk copy agree.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession

extension ExecutionViewModel {

    /// Restore state from the session store, if any. Called by the
    /// app shell on launch. A missing/garbled payload silently returns
    /// the seeded state — offline-first + never-crash posture.
    ///
    /// After decoding, runs the same normalization `start()` runs so a
    /// cold-launch mid-session can't leave the VM in an invalid route
    /// (e.g. `.active` on a zero-item block) or missing timer anchors
    /// (e.g. a Tabata block without `workEndsAt`). The normalization is
    /// idempotent — re-entering a block with existing anchors is a no-op
    /// — so running it every restore is safe even for clean states.
    ///
    /// Workout-ID guard (qa-024): a persisted snapshot whose `workoutID`
    /// doesn't match the current `context.workout.id` is discarded. The
    /// normalization pass reads block/item data off `context`; applying
    /// it to a state whose cursor indexes into a DIFFERENT workout's
    /// structure would corrupt timer anchors and routing. Mismatch can
    /// happen when the shell's `TodayLoader` picks a workout different
    /// from the one the snapshot captured (e.g. cross-day relaunch where
    /// a newer scheduled `.planned` row outranks the in-flight one).
    /// Discarding is the safe cutover — a fresh seeded state for the
    /// TodayLoader-selected workout is better than a corrupted restore.
    public func restoreIfPossible() async {
        guard let store = sessionStore else { return }
        do {
            guard let data = try await store.load() else { return }
            guard let restored = try? JSONDecoder().decode(
                SessionStateCodable.self, from: data
            ) else {
                return
            }
            guard restored.state.workoutID == context.workout.id else { return }
            self.state = restored.state
            normalizeRestoredState()
        } catch {
            // Silent — a failed load means "no saved state", not "crash".
        }
    }

    /// Reapply the invariants `start()` establishes so a restored session
    /// matches what a fresh entry into the same cursor would look like.
    /// Order matches `start()`: zero-item rest → block timer → (Tabata
    /// work window is a no-op unless `.active`, handled implicitly).
    ///
    /// Routes that don't represent live execution (`.today`, `.complete`)
    /// skip normalization — those aren't mid-block states.
    ///
    /// Each helper calls `persist()` on mutation, so the normalized state
    /// lands on disk before the UI renders it.
    private func normalizeRestoredState() {
        switch state.route {
        case .today, .complete:
            return
        case .active, .rest:
            backfillEMOMIntervalAnchorIfNeeded()
            enterRestIfZeroItemBlock()
            enterBlockTimerIfNeeded()
            enterTabataWorkWindowIfNeeded()
        }
    }

    /// Back-compat for EMOM payloads persisted before the R2.1 cutover —
    /// those decode with `intervalAnchorAt == nil`. Without this backfill,
    /// `enterBlockTimerIfNeeded()` (called next in `normalizeRestoredState`)
    /// would see a nil anchor on an EMOM block and re-stamp it to
    /// `clock.now` at relaunch time, sliding every future minute boundary
    /// forward and destroying the original minute grid.
    ///
    /// The anchor is deterministic from the block cap: `blockEndsAt` was
    /// stamped on block entry as `now + total_minutes * 60`, so
    /// `blockEndsAt - total_minutes * 60 = original anchor`. We only
    /// backfill when `blockEndsAt` is present — a pre-R2.1 payload with
    /// neither anchor nor cap has no way to recover the grid, and
    /// `enterBlockTimerIfNeeded` will re-stamp both as a fresh entry.
    private func backfillEMOMIntervalAnchorIfNeeded() {
        guard state.intervalAnchorAt == nil,
              let blockEndsAt = state.blockEndsAt else {
            return
        }
        let b = state.cursor.blockIndex
        guard let block = context.block(at: b),
              block.timingMode == .emom,
              let cap = emomTotalSeconds(for: block) else {
            return
        }
        state.intervalAnchorAt = blockEndsAt.addingTimeInterval(-cap)
        persist()
    }

    /// Pull `total_minutes * 60` off an EMOM block's timing config. Returns
    /// nil on parse failure or when the block isn't EMOM — callers treat
    /// that as a sentinel to skip the backfill (the fresh-entry stamp in
    /// `enterBlockTimerIfNeeded` handles pathological inputs).
    private func emomTotalSeconds(for block: Block) -> TimeInterval? {
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            if case .emom(_, let totalMinutes) = config {
                return Double(totalMinutes) * 60
            }
            return nil
        case .failure:
            return nil
        }
    }

    func apply(_ mutations: [SessionMutation]) {
        var next = state
        for m in mutations {
            next = SessionReducer.reduce(next, m)
            // Capture the rest-window start time off the .enterRest
            // mutation's `now`. The VM uses this in `restDurationSeconds`
            // (EMOM branch) to render the ring total as the real log-to-
            // boundary window rather than the raw `interval_sec`. See the
            // `restWindowStartedAt` doc. Non-persisted — the restore path
            // intentionally loses this and falls back to `interval_sec`.
            if case .enterRest(_, let now) = m {
                restWindowStartedAt = now
            }
            // Clear the tracker when rest ends so a later driver.restDuration
            // read (e.g. an Active-screen meta line refresh) doesn't see a
            // stale rest-window total from the previous interval.
            //
            // Also stamp `workStartedAt` on the rest-end transition so the
            // NEXT set's `startedAt` carries "when rest ended" rather than
            // "when the previous set completed". Without this, rest time
            // would fold INTO the set's duration (a 10s bench press after
            // a 90s rest would appear to be a 100s set). See
            // `SessionState.workStartedAt`. Stamping here (rather than in
            // the reducer) keeps the reducer pure — the wall-clock source
            // is the VM's injected `clock`, same pattern as `workEndsAt` /
            // `intervalAnchorAt` stamps in `enterBlockTimerIfNeeded`.
            //
            // Includes the buildLogMutations zero-rest path (AMRAP / ForTime
            // / Continuous) where `.advanceFromRest` is dispatched inline
            // after `.logSet` — those transitions never round-trip through
            // `advance()`, so the stamp MUST be here.
            if case .advanceFromRest = m {
                restWindowStartedAt = nil
                next.workStartedAt = clock.now
            }
            // `.start` is the first-set anchor — matches `.advanceFromRest`
            // semantics ("work has begun"). The very first SetPlan.startedAt
            // thus reflects session-start rather than the nil fallback.
            if case .start = m {
                next.workStartedAt = clock.now
            }
        }
        state = next
        persist()
    }

    /// Enqueue a save of the current in-memory state. Routes through the
    /// serial `SessionPersistencePipeline` — ops are tagged with a
    /// monotonic revision at enqueue time and stale ops are dropped by
    /// the pipeline before touching the store. In-memory state is
    /// authoritative for this session; the on-disk copy catches up.
    ///
    /// The snapshot is passed in unencoded; the pipeline does the JSON
    /// encode INSIDE the chained task, after deciding whether this
    /// revision is still the latest pending save. Bursts of rapid
    /// `apply()` (log set → advance → edit etc.) therefore produce at
    /// most one encode + one disk write for the final snapshot rather
    /// than N encodes + N writes. See perf-001 in the 2026-04-19 perf
    /// sweep.
    func persist() {
        guard let pipeline = persistencePipelineHandle() else { return }
        let snapshot = SessionStateCodable(state: state)
        let revision = nextPersistenceRevision()
        // swiftlint:disable:next no_direct_task_unstructured
        Task { [pipeline, snapshot, revision] in
            await pipeline.enqueue(op: .save(snapshot), revision: revision)
        }
    }

    /// Enqueue a clear of the stored session bytes. Must be used instead
    /// of touching `sessionStore.clear()` directly — the clear has to
    /// ride the same serial channel as `persist()` or a still-in-flight
    /// save will land AFTER the clear and resurrect stale state on the
    /// next launch.
    func clearPersistedSession() {
        guard let pipeline = persistencePipelineHandle() else { return }
        let revision = nextPersistenceRevision()
        // swiftlint:disable:next no_direct_task_unstructured
        Task { [pipeline, revision] in
            await pipeline.enqueue(op: .clear, revision: revision)
        }
    }

    func findItem(id: UUID, in context: WorkoutContext) -> WorkoutItem? {
        for row in context.itemsByBlock {
            if let hit = row.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    /// If the cursor now sits on a zero-item block (standalone `rest`),
    /// dispatch `.enterRest` with the driver's rest duration so the view
    /// goes to `.rest` instead of the (defensive empty) `.active`. No-op
    /// for work blocks. Called after `start()` and `advance()` — see
    /// `RestBlockDriver` for the cursor-model rationale. Lives here rather
    /// than on the main class so the class body stays under
    /// SwiftLint's `type_body_length` cap.
    ///
    /// The `restEndsAt == nil` guard makes this idempotent for restore.
    /// Live entry into a zero-item block always has `restEndsAt` nil
    /// (the reducer clears it on `.advanceFromRest`), so the guard is
    /// transparent in the live path. On a kill-then-relaunch mid-rest
    /// the anchor is already populated, so we leave it alone instead of
    /// re-stamping `now + duration` and extending the rest every relaunch.
    /// Matches the nil-anchor convention used by `enterBlockTimerIfNeeded`.
    func enterRestIfZeroItemBlock() {
        let b = state.cursor.blockIndex
        guard b < state.structure.itemsPerBlock.count,
              state.structure.itemsPerBlock[b] == 0 else {
            return
        }
        guard state.restEndsAt == nil else { return }
        let duration = driver.restDuration(state: state, context: context)
        apply([.enterRest(durationSec: duration, now: clock.now)])
    }

    /// When entering a time-capped block (AMRAP / ForTime / EMOM / Tabata),
    /// set `blockEndsAt` on the session state so the VM can auto-route to
    /// `.complete` on expiry. Called on every cursor transition where the
    /// block may have changed — `start()`, `advance()`, and the post-log
    /// auto-advance path. No-op when `blockEndsAt` is already set for the
    /// current block (re-entering the same block mid-session during resume)
    /// or when the block isn't time-capped.
    ///
    /// For Tabata, also sets `workEndsAt = now + 20` at entry into each
    /// round's work window (the active phase). The 10s rest window is
    /// handled via the existing `.enterRest` path in `buildLogMutations`.
    func enterBlockTimerIfNeeded() {
        let b = state.cursor.blockIndex
        guard b < state.structure.itemsPerBlock.count else { return }
        guard let block = context.block(at: b) else { return }
        // Skip zero-item blocks entirely — rest blocks handle themselves.
        if state.structure.itemsPerBlock[b] == 0 { return }

        let now = clock.now

        // Tabata: per-round 20s work window. Set on every block entry;
        // when the VM's round advances (round-robin cursor bumps
        // `setIndex`), the VM re-enters .active and calls this helper
        // again — so work windows refresh per round. Also set the total
        // block cap (8 × 30s = 240s) so it terminates on time even if
        // the user never logs (defensive).
        if block.timingMode == .tabata {
            if state.workEndsAt == nil {
                state.workEndsAt = now.addingTimeInterval(TabataDriver.workSec)
            }
            if state.blockEndsAt == nil {
                let total = Double(TabataDriver.rounds)
                    * (TabataDriver.workSec + TabataDriver.restSec)
                state.blockEndsAt = now.addingTimeInterval(total)
            }
            persist()
            return
        }

        // AMRAP / ForTime / EMOM: parse the time cap from the block's
        // timing config. The cap is a property of the block — once set
        // it stays set until advanceFromRest clears it (which it does on
        // block change in the reducer).
        var mutated = false
        if state.blockEndsAt == nil,
           let cap = timeCapSeconds(for: block) {
            state.blockEndsAt = now.addingTimeInterval(cap)
            mutated = true
        }

        // EMOM: stamp the interval-grid anchor once per block entry. The
        // anchor is load-bearing for boundary-driven advance — `tickBlockTimer`
        // and `emomBoundaryAdvanceDuration` both read it to compute the fixed
        // minute-mark boundaries regardless of log-time. Clearing happens on
        // block change in the reducer (alongside `blockEndsAt`).
        //
        // Idempotent for restore — like `blockEndsAt` / `workEndsAt`, the
        // nil-guard means a kill-then-relaunch mid-EMOM leaves the anchor
        // alone rather than re-stamping `now` and sliding every subsequent
        // boundary forward.
        if block.timingMode == .emom, state.intervalAnchorAt == nil {
            state.intervalAnchorAt = now
            mutated = true
        }

        if mutated { persist() }
    }

    /// On entering `.active` inside a Tabata block (new round), refresh
    /// `workEndsAt = now + 20s`. `enterBlockTimerIfNeeded` only sets
    /// when the field is nil (block entry), so per-round refresh needs
    /// its own helper. No-op outside Tabata or when route isn't active.
    ///
    /// The `workEndsAt == nil` guard makes this idempotent for restore:
    /// a live mid-round always enters this helper with `workEndsAt` nil
    /// (the reducer clears it on `.enterRest` and it's nil on first
    /// entry), so the guard doesn't change live behavior. On restore
    /// the anchor is already populated, so we leave it alone instead of
    /// re-stamping `now + 20s` and extending the window every relaunch.
    func enterTabataWorkWindowIfNeeded() {
        guard state.route == .active else { return }
        let b = state.cursor.blockIndex
        guard let block = context.block(at: b),
              block.timingMode == .tabata else { return }
        guard state.workEndsAt == nil else { return }
        state.workEndsAt = clock.now.addingTimeInterval(TabataDriver.workSec)
        persist()
    }

    /// Called from the ActiveView + RestView `.onReceive(tickTimer)` every
    /// second (bug-042). Three responsibilities, in order:
    ///
    ///   1. **Tabata work window.** If `workEndsAt` elapsed while the user
    ///      is on `.active`, auto-log a placeholder 0-rep set and enter
    ///      the 10s rest.
    ///   2. **EMOM boundary catchup.** Walk the cursor through every
    ///      overdue EMOM minute boundary in a single tick (qa-047) —
    ///      one tick per boundary is wrong because iOS suspends
    ///      `Timer.publish` while backgrounded, so on foreground the
    ///      publisher fires a single tick regardless of elapsed time.
    ///   3. **Block cap.** If `blockEndsAt` elapsed, route out of the
    ///      capped block via `routeOutOfCappedBlock` — advance to the
    ///      next block when one exists, else `.complete`.
    ///
    /// Ordering (regression: "Tabata placeholder log dropped after long
    /// suspend past block cap"): the Tabata work-window auto-log MUST run
    /// BEFORE the block-cap path. A long suspend (phone locked through
    /// both the 8th work window and the full 240s block cap) lands here
    /// with both anchors overdue. If we early-returned on the cap first,
    /// the final placeholder log never got written — the user ended the
    /// tabata with 7 logged rounds instead of 8. Running the work-window
    /// path first preserves the 8th-round log; the block-cap path then
    /// still routes out on the same tick (the auto-log flips the route
    /// to `.rest` — the cap guard excludes only `.complete` / `.today`).
    ///
    /// Ordering (qa-047): the EMOM catchup loop runs BEFORE the cap path
    /// so the final interval's placeholder lands while the cursor is
    /// still inside the authored window. A cap that lands exactly at the
    /// final boundary is consumed by the catchup loop; the cap path then
    /// handles the routing-out. A cap with no pending boundary (e.g. a
    /// late-log inline-advance that walked the cursor past the authored
    /// window) still needs the cap path to terminate the block — hence
    /// the separate post-catchup guard.
    ///
    /// Safe to call at any tempo — no-ops when nothing is due. The view-
    /// side guard on `state.blockEndsAt != nil` is an optimization (don't
    /// wake the VM on non-time-capped blocks) but not a correctness
    /// requirement; this method is idempotent and cheap.
    public func tickBlockTimer() {
        tickCallCount &+= 1
        let now = clock.now
        // Tabata work window expired → log placeholder + enter rest.
        // Run BEFORE the EMOM catchup / block-cap paths so a suspend-past-cap
        // scenario still writes the final round's placeholder.
        if let workEnds = state.workEndsAt, now >= workEnds, state.route == .active {
            autoLogAndRestForTabata()
            // Fall through to the block-cap check — if the cap is also
            // overdue (long suspend case) we still need to flip to
            // `.complete`, and the auto-log path just flipped us to
            // `.rest` which the cap guard allows.
        }
        // EMOM boundary catchup. iOS suspends `Timer.publish` while the app
        // is backgrounded; on foreground return the publisher fires ONCE,
        // regardless of how many minute boundaries have elapsed. Without a
        // catchup loop, a 90-second background on a 2-item EMOM advances
        // the cursor exactly once — leaving the user staring at interval 2
        // when the wall clock is already deep inside interval 2's next
        // boundary (qa-047). The loop walks every overdue boundary in one
        // tick: `.rest` → `advance()` (user's log is already committed);
        // `.active` → `autoLogPlaceholderForEMOM()` + `advance()` (skipped
        // interval still produces a server-visible row, matching the
        // "capture the most user data" contract in timing-modes.md). Runs
        // BEFORE the block-cap path so the final interval's placeholder
        // lands while the cursor is still inside the authored window; the
        // cap path then routes out of the block.
        catchUpEMOMBoundaries(now: now)
        // Block cap expired → advance out of the time-capped block. Before
        // routing, capture the final EMOM interval's log if the user is
        // still on `.active` inside the authored window (qa-005). Running
        // the autolog here as well as inside the catchup loop is necessary
        // because a cap that lands exactly at the FINAL boundary is
        // consumed by the catchup loop (ordinal = N, boundary passed), but
        // a cap with no pending boundary (e.g. late-log inline-advance that
        // walked the cursor to the next sentinel row) still needs to
        // terminate the block.
        if let ends = state.blockEndsAt, now >= ends,
           state.route != .complete, state.route != .today {
            if state.route == .active,
               let block = context.block(at: state.cursor.blockIndex),
               block.timingMode == .emom,
               emomCursorIsWithinAuthoredIntervals() {
                autoLogPlaceholderForEMOM()
            }
            routeOutOfCappedBlock()
        }
    }

    /// Walk the cursor through every EMOM minute boundary that has elapsed
    /// since the last tick. The loop terminates when the cursor either
    /// catches up to `now` (next boundary still in the future) OR walks
    /// past the block's authored intervals (sentinel seed row). Each
    /// iteration either advances on a live `.rest` or auto-logs +
    /// advances on `.active`; no other route reaches this helper (the
    /// guard excludes `.today` / `.complete`).
    ///
    /// qa-047: pre-fix, `tickBlockTimer` handled a single boundary per
    /// call. `Timer.publish` is suspended while the app is backgrounded,
    /// so a 90s background fired exactly one tick on resume — walking
    /// the cursor by one interval while the wall clock had already moved
    /// past two. The user saw the cursor lag behind the clock and the
    /// block cap would then dispatch `.complete`, dropping every
    /// subsequent block in the workout.
    ///
    /// Defensive iteration cap: `unboundedRoundsSentinel * 4` — the
    /// seeder's 100-row cap times a safety factor. Under normal inputs
    /// the loop exits via `emomCursorIsWithinAuthoredIntervals == false`
    /// (ordinal past authored) long before this cap; the guard exists
    /// only to prevent a buggy reducer from spinning. No-op when the
    /// current block isn't EMOM — `emomBoundaryReached` returns false.
    private func catchUpEMOMBoundaries(now: Date) {
        let maxIterations = SessionSeeder.unboundedRoundsSentinel * 4
        var guardCount = 0
        while emomBoundaryReached(now: now),
              emomCursorIsWithinAuthoredIntervals(),
              state.route == .active || state.route == .rest {
            if state.route == .active {
                autoLogPlaceholderForEMOM()
            }
            advance()
            guardCount += 1
            if guardCount > maxIterations { break }
        }
    }

    /// Called when a time-capped block's `blockEndsAt` has elapsed. If
    /// there is a subsequent block, jump the cursor to its first
    /// position, clear the capped-block's timer anchors, and re-enter
    /// via the normal block-entry helpers (`enterRestIfZeroItemBlock`,
    /// `enterTabataWorkWindowIfNeeded`, `enterBlockTimerIfNeeded`). If
    /// there is no next block, dispatch `.complete` — the workout is
    /// done.
    ///
    /// qa-047: pre-fix, `tickBlockTimer` unconditionally dispatched
    /// `.complete` when the cap elapsed. That's correct for a
    /// single-block workout (AMRAP finisher, solo Tabata) but drops
    /// every remaining block when the capped block sits in the middle
    /// of a longer session. A 10-minute EMOM as block 3 of 12 would
    /// terminate the whole workout at block 3's cap; the user never saw
    /// blocks 4-11. The cursor-walk-to-next-block shape here mirrors the
    /// reducer's `advanceCursor` end-of-block behavior — same exit, same
    /// cleanup, just dispatched from the VM because the sentinel-seeded
    /// round-robin cursor (AMRAP / EMOM) never naturally reaches its
    /// block's last position.
    ///
    /// `workStartedAt` is re-stamped so the first log in the new block
    /// carries "when this block started" as its `startedAt` anchor —
    /// matching the semantics of `.advanceFromRest` / `.start` via
    /// `apply(_:)`.
    private func routeOutOfCappedBlock() {
        let currentBlock = state.cursor.blockIndex
        let nextBlock = currentBlock + 1
        guard nextBlock < state.structure.itemsPerBlock.count else {
            apply([.complete])
            return
        }
        state.restEndsAt = nil
        state.blockEndsAt = nil
        state.workEndsAt = nil
        state.intervalAnchorAt = nil
        state.cursor = SessionState.Cursor(
            blockIndex: nextBlock,
            itemIndex: 0,
            setIndex: 1
        )
        state.route = .active
        state.workStartedAt = clock.now
        persist()
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
    }

    /// Helper invoked from `tickBlockTimer` when the Tabata work window
    /// elapses. v1 logs a placeholder `(reps: 0, rir: nil)` — a later
    /// slice can prompt the user for a real per-round count.
    private func autoLogAndRestForTabata() {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        let now = clock.now
        apply([
            .logSet(itemID: item.id, setIndex: c.setIndex, loggedReps: 0, loggedRir: nil, now: now),
            .enterRest(durationSec: TabataDriver.restSec, now: now),
        ])
    }

    /// Helper invoked from `tickBlockTimer` when the EMOM block cap elapses
    /// while the user is still on `.active` for the final interval. Logs a
    /// placeholder `(reps: 0, rir: nil)` so the interval is captured before
    /// the route flips to `.complete`. Unlike Tabata, no `.enterRest`
    /// follows — the block is terminating on this tick, not entering
    /// another round. Matches the "capture the most user data" contract
    /// (timing-modes.md) for time-capped modes.
    private func autoLogPlaceholderForEMOM() {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        let now = clock.now
        apply([
            .logSet(itemID: item.id, setIndex: c.setIndex, loggedReps: 0, loggedRir: nil, now: now),
        ])
    }

    /// True when the current EMOM cursor points to one of the block's
    /// authored intervals, rather than a past-end sentinel row. A late log
    /// (user logs after the interval boundary has passed) inline-advances
    /// the cursor via `.advanceFromRest` to the next seeded row, which for
    /// an unboundedRoundsSentinel seed can walk past the authored
    /// `total_minutes` cap. The cap-auto-log must NOT fire on a past-end
    /// cursor — the user's final log already landed and we'd double-commit
    /// a placeholder onto a spurious position. Ordinal math matches the
    /// round-robin cursor:
    /// `(setIndex-1) * items.count + itemIndex + 1 ∈ [1, totalIntervals]`.
    private func emomCursorIsWithinAuthoredIntervals() -> Bool {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else { return false }
        guard c.blockIndex >= 0, c.blockIndex < context.itemsByBlock.count else {
            return false
        }
        let items = context.itemsByBlock[c.blockIndex]
        guard !items.isEmpty else { return false }
        let parser = PrescriptionParser()
        guard case .success(let config) = parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ), case .emom(let intervalSec, let totalMinutes) = config,
            intervalSec > 0 else { return false }
        let totalIntervals = Int((Double(totalMinutes) * 60.0) / intervalSec)
        let ordinal = (c.setIndex - 1) * items.count + c.itemIndex + 1
        return ordinal >= 1 && ordinal <= totalIntervals
    }

    /// Pull the authored `time_cap_sec` (or EMOM `total_minutes * 60`)
    /// from a block's `timing_config_json`. Returns nil when the block
    /// isn't time-capped or parsing fails.
    private func timeCapSeconds(for block: Block) -> TimeInterval? {
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            switch config {
            case .amrap(let cap):
                return cap
            case .forTime(let cap):
                return cap
            case .emom(let intervalSec, let totalMinutes):
                _ = intervalSec  // not used here — cap is total, not interval
                return Double(totalMinutes) * 60
            default:
                return nil
            }
        case .failure:
            return nil
        }
    }

    /// Compose the ordered mutation list for a set-log event. Kept separate
    /// so `logSet` stays under SwiftLint's `function_body_length` cap.
    func buildLogMutations(
        logMutation: SessionMutation,
        outcome: DriverLogOutcome,
        item: WorkoutItem,
        postLogState: SessionState
    ) -> [SessionMutation] {
        var mutations: [SessionMutation] = [logMutation]
        // Accept-by-default: if the driver surfaced a proposal, apply
        // it immediately. User can Undo from the banner.
        if let proposal = outcome.proposal {
            mutations.append(.applyAutoregProposal(itemID: item.id, proposal: proposal))
        }
        let now = clock.now
        let restSec = resolvedRestDuration(for: postLogState, now: now)
        if restSec > 0 {
            mutations.append(.enterRest(durationSec: restSec, now: now))
        } else {
            // No rest configured (or the EMOM boundary already passed) —
            // advance straight to the next active position. Edge case for
            // straight_sets (rests are authored) and EMOM with a late log.
            mutations.append(.advanceFromRest)
        }
        mutations.append(contentsOf: outcome.mutations)
        return mutations
    }

    /// Resolve the rest duration to stamp onto `.enterRest`, branching for
    /// EMOM so the rest window ends at the fixed minute-mark boundary
    /// (`intervalAnchorAt + cursor.setIndex * interval_sec - now`) rather
    /// than at log-time + `interval_sec`. Other modes fall through to the
    /// driver's native `restDuration` — straight_sets / circuit / tabata
    /// all stamp log-time-relative rests and are correct as-is.
    ///
    /// Returns 0 when the EMOM boundary has already passed (late log) so
    /// the caller advances immediately instead of stamping a past `restEndsAt`.
    private func resolvedRestDuration(
        for postLogState: SessionState,
        now: Date
    ) -> TimeInterval {
        let b = postLogState.cursor.blockIndex
        if let block = context.block(at: b), block.timingMode == .emom {
            return emomBoundaryRestDuration(for: postLogState, now: now)
        }
        return driver.restDuration(state: postLogState, context: context)
    }

    /// Compute the rest duration for an EMOM log — the wall-clock time until
    /// the END of the current interval. Anchored to the block's
    /// `intervalAnchorAt`, NOT the log-time. A log at 0:15 inside interval
    /// 1 rests 45s; a log at 0:55 rests 5s; a late log that blew past the
    /// boundary rests 0s (caller advances immediately).
    ///
    /// Multi-item EMOM: the 1-based interval ordinal is
    /// `(setIndex - 1) * items.count + itemIndex + 1`; boundary of interval
    /// N is `anchor + N * intervalSec`. For single-item EMOM the ordinal
    /// collapses to `setIndex` so the pre-fix formula is preserved.
    ///
    /// Falls back to the driver's native `interval_sec` when the anchor is
    /// missing (e.g. the config is malformed so the VM didn't stamp on
    /// entry) — that preserves pre-fix behavior for pathological inputs
    /// rather than crashing with a nil-unwrap.
    private func emomBoundaryRestDuration(
        for postLogState: SessionState,
        now: Date
    ) -> TimeInterval {
        guard let anchor = postLogState.intervalAnchorAt else {
            return driver.restDuration(state: postLogState, context: context)
        }
        let intervalSec = emomIntervalSec(for: postLogState)
        guard intervalSec > 0 else { return 0 }
        let b = postLogState.cursor.blockIndex
        guard b >= 0, b < context.itemsByBlock.count else { return 0 }
        let items = context.itemsByBlock[b]
        guard !items.isEmpty else { return 0 }
        let c = postLogState.cursor
        // `postLogState.cursor` is the interval the user just logged (the
        // reducer does NOT advance on `.logSet`). The boundary is the END
        // of that interval.
        let ordinal = (c.setIndex - 1) * items.count + c.itemIndex + 1
        let boundary = anchor.addingTimeInterval(Double(ordinal) * intervalSec)
        return max(0, boundary.timeIntervalSince(now))
    }

    /// True when the current EMOM interval's boundary has elapsed relative
    /// to `now`. Read by `tickBlockTimer` to auto-advance on the minute
    /// mark regardless of the user's interaction with the rest screen.
    /// Returns false outside EMOM or when the anchor is missing.
    ///
    /// Multi-item EMOM: the cursor is round-robin — `setIndex` is the ROUND,
    /// `itemIndex` is the position within the round. Each interval maps to
    /// a unique `(setIndex, itemIndex)` pair; the 1-based interval ordinal
    /// is `(setIndex - 1) * items.count + itemIndex + 1` and the boundary
    /// of interval ordinal N is `anchor + N * intervalSec`. For single-
    /// item EMOM the ordinal collapses to `setIndex` and the math matches
    /// the pre-fix formula, preserving single-item semantics. qa-018
    /// pre-fix used `setIndex * intervalSec`, which for a 2-item EMOM
    /// reported interval 2's boundary identical to interval 1's (both
    /// setIndex=1) and interval 3's identical to interval 2's (both
    /// setIndex=2), causing `tickBlockTimer` to either fire too early on
    /// advance-into-an-interval or never fire at the authored boundary.
    private func emomBoundaryReached(now: Date) -> Bool {
        let b = state.cursor.blockIndex
        guard let block = context.block(at: b), block.timingMode == .emom else {
            return false
        }
        guard let anchor = state.intervalAnchorAt else { return false }
        let intervalSec = emomIntervalSec(for: state)
        guard intervalSec > 0 else { return false }
        guard b >= 0, b < context.itemsByBlock.count else { return false }
        let items = context.itemsByBlock[b]
        guard !items.isEmpty else { return false }
        let c = state.cursor
        let ordinal = (c.setIndex - 1) * items.count + c.itemIndex + 1
        let boundary = anchor.addingTimeInterval(Double(ordinal) * intervalSec)
        return now >= boundary
    }

    /// Pull `interval_sec` off the current block's timing config. Returns 0
    /// on parse failure or when the block isn't EMOM — callers use that as
    /// a sentinel to skip the boundary math.
    private func emomIntervalSec(for s: SessionState) -> TimeInterval {
        let b = s.cursor.blockIndex
        guard let block = context.block(at: b) else { return 0 }
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            if case .emom(let intervalSec, _) = config {
                return intervalSec
            }
            return 0
        case .failure:
            return 0
        }
    }
}
