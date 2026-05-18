// ExecutionViewModel.swift
//
// The `@Observable` wrapper around the pure `SessionReducer`. Owns:
//   - the live `SessionState` (seeded via `SessionSeeder`)
//   - the workout context (for renders and driver lookups)
//   - the current autoreg proposal (derived, per-log)
//   - a `TimingDriver` resolved per the current block's `timingMode`
//   - session persistence via `SessionStore` (opaque-bytes bucket)
//
// Every state mutation funnels through one entry point — `apply(_:)` —
// which dispatches the mutation through the pure reducer, persists the
// result, and updates derived state. Keeping a single write path keeps
// tests simple and makes "what just changed?" obvious in the view hierarchy.
//
// Concurrency:
//   - The view model is `@MainActor` — it is read and mutated from
//     SwiftUI views only.
//   - Live-session persistence writes are fire-and-forget `Task` launches.
//     Completion publication is awaited before the session is cleared so the
//     app does not lose the only completion artifact on process death.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import CoreTelemetry
import Persistence
import WorkoutCoreFoundation

// MARK: - Push wiring

/// Fire-and-forget hook invoked when a set is logged. Shell supplies this so
/// the just-logged `SetLog` is enqueued to `PushQueue` on its way to the
/// server. `nil` (the default) preserves the pure-offline test path — tests
/// that don't exercise push can omit this dependency entirely.
public typealias SetLogEnqueuer = @Sendable (SetLog) async -> Void
public typealias PrimitiveSetLogEnqueuer = @Sendable (PrimitiveSetLog) async -> Void

/// Hook invoked when Save & Done has produced the canonical app-owned
/// completion record. Shell supplies this so REST sync can durably enqueue
/// one grouped results payload. Future replication surfaces should consume the
/// same record rather than re-derive completion from SessionState.
public typealias CompletionEnqueuer = @Sendable (WorkoutCompletionRecord) async throws -> Void

/// Hook invoked after the completion record is durably enqueued. Shell
/// supplies this so the push queue drains immediately rather than waiting
/// for the next ~60s tick of the foreground flusher.
public typealias PushFlushKick = @Sendable () async -> Void

/// Awaited hook invoked when `saveAndDone` fires — BEFORE the reducer
/// clears the in-memory session. Shell supplies this so the completed
/// workout + result logs are attempted in the local `WorkoutCache`
/// immediately, populating the History tab without waiting for a server
/// round-trip when the best-effort cache writes succeed. `nil` (the
/// default) preserves the pure-offline test path.
public typealias LocalCompletionWriter = @Sendable (WorkoutCompletionRecord) async -> Void

/// Fire-and-forget hook invoked when a `UserParameter` is captured during
/// `saveAndDone` — typically a just-entered bodyweight. Shell supplies
/// this so the row is enqueued to `PushQueue` on its way to the server
/// (`POST /api/user-parameters`). `nil` (the default) preserves the
/// pure-offline test path.
public typealias UserParameterEnqueuer = @Sendable (UserParameter) async -> Void

/// Bundle of push hooks injected into `ExecutionViewModel`. Grouping the
/// closures into a struct keeps the view-model's init surface narrow and,
/// more importantly, keeps the class body under `type_body_length`.
/// `nil` fields preserve the pure-offline test path; the view model's
/// persistence extension reads `push` directly.
public struct ExecutionPushHooks: Sendable {
    public let onSetLogged: SetLogEnqueuer?
    public let onPrimitiveSetLogged: PrimitiveSetLogEnqueuer?
    public let onWorkoutCompleted: CompletionEnqueuer?
    public let onPushKick: PushFlushKick?
    public let onUserParameterChanged: UserParameterEnqueuer?

    public init(
        onSetLogged: SetLogEnqueuer? = nil,
        onPrimitiveSetLogged: PrimitiveSetLogEnqueuer? = nil,
        onWorkoutCompleted: CompletionEnqueuer? = nil,
        onPushKick: PushFlushKick? = nil,
        onUserParameterChanged: UserParameterEnqueuer? = nil
    ) {
        self.onSetLogged = onSetLogged
        self.onPrimitiveSetLogged = onPrimitiveSetLogged
        self.onWorkoutCompleted = onWorkoutCompleted
        self.onPushKick = onPushKick
        self.onUserParameterChanged = onUserParameterChanged
    }

    public static let none = ExecutionPushHooks()
}

@Observable
@MainActor
public final class ExecutionViewModel {

    // MARK: - State

    /// The live session state. Mutated via `apply(_:)` only.
    ///
    /// `internal(set)` rather than `private(set)` so the persistence
    /// extension in `ExecutionViewModel+Persistence.swift` can write to it.
    public internal(set) var state: SessionState

    /// The current autoreg proposal, if any. Set by `logSet` when the
    /// driver returns one; cleared by `acceptAutoreg` / `undoAutoreg` /
    /// `advance`. `internal(set)` so the `+LogCardioSet.swift` extension
    /// can clear a stale proposal when a cardio log fires — cardio
    /// drivers never surface a new one, so the cleanup is unconditional.
    public internal(set) var currentProposal: AutoregProposal?

    /// Item the current proposal targets. Kept alongside the proposal
    /// so `acceptAutoreg`/`undoAutoreg` operate on the right item.
    public internal(set) var currentProposalItemID: UUID?

    /// Primitive result rows recorded by the primitive execution path.
    /// Included in the app-owned completion record at Save & Done so local
    /// cache and sync consume the same primitive facts.
    public internal(set) var primitiveSetLogs: [PrimitiveSetLog] = []

    /// Test-observable counter incremented every time `tickBlockTimer()`
    /// fires. Used by bug-042 regression tests to prove the view's
    /// periodic tick actually invokes the VM. Not `@Observable` — tests
    /// read it synchronously after driving the timer publisher; regular
    /// view rendering shouldn't depend on it.
    internal(set) public var tickCallCount: Int = 0

    /// Wall-clock stamp of the most recent `.enterRest` mutation dispatched
    /// through `apply(_:)`. Used by `restDurationSeconds` in the EMOM case
    /// to compute the ring's TOTAL as `restEndsAt - restWindowStartedAt`
    /// (the real rest window between log-time and the next minute boundary)
    /// rather than the raw `interval_sec`, which would start the ring
    /// visually depleted for any non-zero log offset inside the minute.
    ///
    /// Intentionally NOT persisted (lives only on the VM). A kill-then-
    /// relaunch that lands mid-EMOM-rest has no log-time to recover; the
    /// getter falls back to `interval_sec` so the ring still renders,
    /// matching pre-fix behavior for that rare path.
    var restWindowStartedAt: Date?

    public let context: WorkoutContext

    /// The driver to use for the block the cursor is currently in.
    /// Re-derived on every read — drivers are cheap value types.
    public var driver: TimingDriver {
        let bi = state.cursor.blockIndex
        let mode = context.block(at: bi)?.timingMode ?? .straightSets
        return driverRegistry.driver(for: mode)
    }

    /// Latest Active-screen content for the current cursor, or nil if
    /// the cursor is out of range.
    public var activeContent: ActiveContent? {
        driver.activeContent(state: state, context: context)
    }

    /// The pending SetPlan at the active cursor. Used by log-time UI so a
    /// user can correct load before committing the set; the reducer remains
    /// the source of truth for the value that push/history later read.
    public var activeSetPlan: SetPlan? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }
        return itemLog.sets.first(where: { $0.setIndex == c.setIndex })
    }

    /// Rest duration for the current cursor (in seconds). Used by the
    /// view model itself to fire `.enterRest`; exposed here so the view
    /// can render the ring's total.
    ///
    /// EMOM branch: the REAL rest window for an EMOM log is
    /// `restEndsAt - log_time` — not the raw `interval_sec` the driver
    /// returns. A log at 0:15 has a 45s window, not 60s; using the driver's
    /// `interval_sec` for the ring total makes the ring render already-
    /// partially-depleted at log-time (elapsed = total - remaining = 60 -
    /// 45 = 15 → 25% at t=0). Branching here keeps the fix narrow — the
    /// VM's internal use of `driver.restDuration` for non-EMOM modes is
    /// untouched, and other modes fall through to the driver's native value.
    ///
    /// Fallback: when `restWindowStartedAt` is nil (no rest has been
    /// entered in this VM's lifetime, or the VM was just restored from
    /// disk), the EMOM path falls through to the driver's `interval_sec`.
    /// This preserves pre-fix rendering for the restored-mid-rest case
    /// where we can't recover the real log-time.
    public var restDurationSeconds: TimeInterval {
        let b = state.cursor.blockIndex
        if let block = context.block(at: b),
           block.timingMode == .emom,
           let endsAt = state.restEndsAt,
           let startedAt = restWindowStartedAt {
            return max(0, endsAt.timeIntervalSince(startedAt))
        }
        return driver.restDuration(state: state, context: context)
    }

    /// The last-logged SetPlan for the current cursor (used by the Rest
    /// screen's just-logged pills). Finds the most recently completed
    /// set that's ≤ cursor.setIndex; returns nil before any set logs.
    public var lastLoggedSet: SetPlan? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }
        return itemLog.sets
            .filter { $0.done && $0.setIndex <= c.setIndex }
            .max(by: { $0.setIndex < $1.setIndex })
    }

    // MARK: - Dependencies
    //
    // `internal` (default) so the Persistence extension in
    // `ExecutionViewModel+Persistence.swift` can read them.

    let clock: any Clock
    let sessionStore: SessionStore?
    let driverRegistry: DriverRegistry

    /// Push hooks bundle. `.none` (the default) means "no-op" — the view
    /// model still mutates `SessionState` normally. Shell wires the real
    /// hooks at bootstrap; tests that don't exercise push can rely on
    /// the default. `internal` (default) so the `+Push` extension can
    /// read it without re-exporting a helper.
    let push: ExecutionPushHooks

    /// Local-cache writer invoked on `saveAndDone`. `nil` (the default)
    /// is a no-op; Shell wires the real writer at bootstrap so the just-
    /// completed workout is visible in History without waiting for a
    /// pull. See the `LocalCompletionWriter` doc.
    let localCompletionWriter: LocalCompletionWriter?

    /// Telemetry emitter for execution.* events. `NoopTelemetryEmitter` by
    /// default so tests and previews don't need to wire one.
    let telemetry: TelemetryEmitter

    // MARK: - Persistence pipeline (owned by +PersistencePipeline.swift)
    //
    // These stored properties are owned and driven exclusively by the
    // `+PersistencePipeline.swift` extension. They live on the VM instead
    // of in a module-level `[ObjectIdentifier: …]` side-table so a
    // deallocated VM can't strand entries keyed on an address that the
    // allocator later reuses for a different VM (which would bind a
    // fresh VM to a destroyed `SessionStore` and inherit a stale
    // revision counter). `internal` matches the access level of the
    // other dependency-ish properties above so the extension can read
    // and write them.

    /// Lazy-built serial channel for `SessionStore` writes. Nil until
    /// `persistencePipelineHandle()` materializes it on first use; stays nil
    /// forever for VMs constructed without a `sessionStore` (test path).
    var persistencePipeline: SessionPersistencePipeline?

    /// Monotonic revision stamped on every enqueued persistence op.
    /// Read/written on the main actor only (the VM is `@MainActor`),
    /// so increments are race-free without a lock.
    var persistenceRevision: UInt64 = 0

    // MARK: - Save & done re-entrancy guard
    //
    // Owned and driven by `+SaveAndDone.swift`. Lives on the VM (rather
    // than in a module-level side-table) because the shell now rebuilds
    // the VM per workout — a per-instance stored flag is naturally fresh
    // for each new workout. Previously this was a process-global
    // `NSMapTable` whose weak-key auto-eviction assumed the VM died after
    // save; that lifetime model was wrong for the live shell (same VM
    // retained across multiple workouts), which produced a nil-map crash
    // as observed in QA runs. See `+SaveAndDone.swift` header for history.

    /// Whether a `saveAndDone` call is currently mid-flight. Flipped `true`
    /// by the guard in `+SaveAndDone.swift` before `performSaveAndDone`
    /// runs and left `true` for the rest of this VM's life — by then the
    /// reducer's `.save` has flipped the route to `.today` and the
    /// Complete screen is unmounted. A fresh workout gets a fresh VM
    /// (built by `AppBootstrap.buildExecutionViewModel`), which resets
    /// the flag to `false` naturally.
    var saveAndDoneInFlightStorage: Bool = false

    /// Pending tabata multi-item collapse records captured at seed time.
    /// Held until `.start()` actually fires — qa-035 showed emitting at
    /// seed time fires during the PREVIOUS workout's save transition
    /// (when the shell rebuilds this VM for the NEXT workout), not when
    /// the user starts the Tabata session. Per `docs/features/telemetry.md`
    /// the collapse event is a "user actually started this workout"
    /// signal, so `.start()` is the correct fire point. `nil` after
    /// emit so subsequent `.start()` calls (if any) are no-ops.
    var pendingTabataCollapses: [SessionSeeder.TabataCollapse]?

    // MARK: - Init

    public init(
        context: WorkoutContext,
        clock: any Clock = SystemClock(),
        sessionStore: SessionStore? = nil,
        driverRegistry: DriverRegistry = DriverRegistry(),
        push: ExecutionPushHooks = .none,
        localCompletionWriter: LocalCompletionWriter? = nil,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        self.context = context
        self.clock = clock
        self.sessionStore = sessionStore
        self.driverRegistry = driverRegistry
        self.push = push
        self.localCompletionWriter = localCompletionWriter
        self.telemetry = telemetry
        // Seed through the normalization-aware path so any seed-time drops
        // (tabata multi-item collapse today) surface as telemetry. The
        // pure `SessionSeeder.seed(context:)` stays side-effect-free for
        // tests that exercise the seeder directly; the telemetry emit is
        // deferred to `.start()` — emitting at seed time fires during the
        // PREVIOUS workout's save transition (qa-035), which misreports
        // "user started a collapsed Tabata workout" on every VM rebuild.
        let seed = SessionSeeder.seedWithNormalization(context: context)
        self.state = seed.state
        self.pendingTabataCollapses = seed.tabataCollapses.isEmpty ? nil : seed.tabataCollapses
    }

    // MARK: - Intents

    /// Route from Today → Active. Persists.
    ///
    /// If the very first block is a zero-item block (a standalone `rest`
    /// block authored at position 0 — unusual but valid), we skip
    /// `.active` and enter `.rest` directly with the rest-block driver's
    /// duration. See `RestBlockDriver` for the cursor-model rationale.
    public func start() {
        emitSessionMutation("start")
        // Deferred seed-normalization telemetry fires here — NOT at
        // `init` — so the Tabata multi-item collapse event is anchored
        // to the moment the user actually started THIS workout. See
        // qa-035 + the `pendingTabataCollapses` doc.
        if let pending = pendingTabataCollapses, !pending.isEmpty {
            emitSeedNormalizationTelemetry(pending)
        }
        pendingTabataCollapses = nil
        // `apply(_:)` stamps `state.workStartedAt = clock.now` on the
        // `.start` mutation — so the FIRST set's `startedAt` anchor is
        // the session-start instant, not nil. See `SessionState.workStartedAt`.
        apply([.start])
        enterRestIfZeroItemBlock()
        enterBlockTimerIfNeeded()
        prepareExplicitSetStartIfNeeded()
    }

    /// Log the current set with the given reps + optional RIR. Fires
    /// the driver's `onSetLogged`, which may return an autoreg proposal.
    /// Then transitions to `.rest` via `.enterRest(...)`.
    ///
    /// Autoreg proposals are NOT auto-applied — the reducer stores the
    /// log first, the view model surfaces the banner, and the user's
    /// "Accept" / "Undo" choice determines whether `.applyAutoregProposal`
    /// fires. This matches the contract in
    /// `CoreSession/SessionMutation.swift`.
    public func logSet(reps: Int, rir: Int?) {
        guard canLogCurrentWork() else { return }
        let c = state.cursor
        let previousBlockIndex = c.blockIndex
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        if isCurrentCompositeSet {
            logCompositeSet(item: item, reps: reps, rir: rir)
            return
        }
        let event = SetLogEvent(
            itemID: item.id,
            setIndex: c.setIndex,
            loggedReps: reps,
            loggedRir: rir
        )
        let logMutation: SessionMutation = .logSet(
            itemID: item.id,
            setIndex: c.setIndex,
            loggedReps: reps,
            loggedRir: rir,
            now: clock.now
        )
        let prescribedLoadKg = prescribedLoadForLog(itemID: item.id, setIndex: c.setIndex)
        // Compute autoreg proposal against the *pre-log* state so the
        // driver sees the prescribed reps/load (the log mutation
        // overwrites those with the observed values).
        let outcome = driver.onSetLogged(state: state, context: context, event: event)
        let postLogState = SessionReducer.reduce(state, logMutation)
        apply(buildLogMutations(
            logMutation: logMutation,
            outcome: outcome,
            item: item,
            postLogState: postLogState
        ))
        completeAccumulateIfTargetReached()
        if !enterBlockTransitionIfNeeded(from: previousBlockIndex) {
            prepareExplicitSetStartIfNeeded()
        }
        handleLogSetSideEffects(
            item: item,
            event: event,
            outcome: outcome,
            prescribedLoadKg: prescribedLoadKg
        )
    }

    /// Correct the active set's load and then log it. This keeps the
    /// log-time sheet row-based without creating a separate logged-load
    /// channel: the existing SetPlan remains authoritative for push,
    /// history, rest "just did" pills, and completion ledger.
    public func logSet(loadKg: Double?, reps: Int, rir: Int?) {
        guard canLogCurrentWork() else { return }
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        if activeSetPlan?.loadKg != loadKg {
            editPendingSet(
                itemID: item.id,
                setIndex: c.setIndex,
                loadKg: loadKg,
                reps: nil,
                rir: nil
            )
        }
        logSet(reps: reps, rir: rir)
    }

    /// Accept the current proposal. The apply has already happened in
    /// `logSet` — Accept just dismisses the banner. Exposed for symmetry
    /// with `undoAutoreg` and as the hook for future proposals that
    /// require explicit confirmation before apply.
    public func acceptAutoreg() {
        emitAutoreg("execution.autoreg_accepted")
        currentProposal = nil
        currentProposalItemID = nil
    }

    /// Undo the current proposal: revert the applied load on remaining
    /// sets and set `autoregHeld` on the item so subsequent logs don't
    /// re-propose. Per `docs/prescription.md` § "Autoreg + manual edit".
    /// The reversal body lives in `ExecutionViewModel+Autoreg.swift` so
    /// the class stays under SwiftLint's `type_body_length` cap.
    public func undoAutoreg() {
        runAutoregUndo()
    }

    /// Advance the cursor: rest → active (next set) or rest → complete.
    ///
    /// If the advance lands on a zero-item block (standalone `rest`),
    /// we flip the route from the post-reducer `.active` back to `.rest`
    /// with the rest-block driver's duration. See `RestBlockDriver` for
    /// the cursor-model rationale.
    public func advance() {
        emitSessionMutation("advance")
        let previousBlockIndex = state.cursor.blockIndex
        if isRoundRobinBatchRoundRest {
            commitRoundRobinBatchRoundIfNeeded()
        }
        // An active proposal at advance time is an implicit accept — the
        // user dismissed the banner by moving on rather than tapping undo.
        // Per `docs/features/telemetry.md`, analytics needs the
        // `execution.autoreg_accepted` signal for BOTH the explicit-accept
        // code path (future UI) and this implicit-advance path. The
        // production "next" button wires to `advance()`, NOT
        // `acceptAutoreg()`; qa-034 showed the event never fired in the
        // field because no production path emitted from here. Emit
        // before clearing the proposal so the tagging (workoutID) still
        // matches. `acceptAutoreg()` continues to exist for symmetry
        // and for a potentially-explicit future accept button.
        if currentProposal != nil {
            emitAutoreg("execution.autoreg_accepted")
        }
        // `apply(_:)` stamps `state.workStartedAt = clock.now` on the
        // `.advanceFromRest` mutation — next set's `startedAt` reflects
        // "when rest ended", NOT "when prior set completed". See
        // `SessionState.workStartedAt`.
        apply([.advanceFromRest])
        if enterBlockTransitionIfNeeded(from: previousBlockIndex) {
            currentProposal = nil
            currentProposalItemID = nil
            return
        }
        // Any lingering proposal is moot on advance — the next set is a
        // fresh log.
        currentProposal = nil
        currentProposalItemID = nil
        enterRestIfZeroItemBlock()
        // On block change (reducer clears blockEndsAt), re-derive timers.
        // Also re-derives Tabata's per-round work window when the cursor
        // wraps back to item 0 in a new round.
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
        prepareExplicitSetStartIfNeeded()
    }

    /// Add recovery time to the current rest window. This is intentionally
    /// session-state, not view-local display state, so persistence / restore
    /// and the visible timer agree after the user opts into more rest.
    public func extendRest(by seconds: TimeInterval) {
        guard seconds > 0, !currentRestShouldAutoAdvance else { return }
        emitSessionMutation("extend_rest")
        apply([.extendRest(durationSec: seconds)])
    }

    /// Force-complete. Available via an "End" affordance in the nav bar.
    ///
    /// Does NOT publish the completion record here. The terminal
    /// server-side push is the responsibility of `saveAndDone()` — which
    /// fires for every path into `.complete` (both auto-advance and this
    /// explicit End button). Publishing here *and* in `saveAndDone`
    /// produces a double completion for the same workout. Session state
    /// is persisted, so if the user force-completes and kills the app
    /// before tapping save & done, the complete screen restores on next
    /// launch and the user can still commit from there.
    public func complete() {
        apply([.complete])
    }

    // `saveAndDone` lives in `ExecutionViewModel+SaveAndDone.swift`.
    // Extracting the public entry point there lets the re-entrancy guard
    // (bug: double-tap on End enqueues bodyweight twice) sit next to the
    // function it protects without bloating this class body or colliding
    // with the persistence-ordering work in `+Persistence.swift`.

    /// Correctively edit a past (logged) set. Does NOT retrigger autoreg.
    /// After the reducer mutation applies, pushes the updated `SetLog`
    /// with the SAME deterministic UUID as the original log so the server
    /// upserts in place. Fixes bug-010 + bug-017. The post-apply push +
    /// telemetry work lives in `handlePastSetEditSideEffects` so the
    /// class body stays under SwiftLint's `type_body_length` cap.
    public func editPastSet(
        itemID: UUID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?,
        rir: Int?
    ) {
        apply([.editPastSet(
            itemID: itemID, setIndex: setIndex,
            loadKg: loadKg, reps: reps, rir: rir
        )])
        handlePastSetEditSideEffects(itemID: itemID, setIndex: setIndex)
    }

    /// Edit a pending (not-yet-logged) set. Marks it `.manual` — autoreg
    /// won't touch it afterward.
    public func editPendingSet(
        itemID: UUID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?,
        rir: Int? = nil,
        startedAt: Date? = nil
    ) {
        apply([.editPendingSet(
            itemID: itemID,
            setIndex: setIndex,
            loadKg: loadKg,
            reps: reps,
            rir: rir,
            startedAt: startedAt
        )])
    }

    // Persistence helpers (`restoreIfPossible`, `apply`, `persist`,
    // `findItem`) live in `ExecutionViewModel+Persistence.swift`; the
    // telemetry emit helpers in `ExecutionViewModel+Push.swift`; and the
    // `swap` intent in `ExecutionViewModel+Swap.swift`. Keeps this class
    // body under SwiftLint's `type_body_length` cap.
}

// MARK: - Driver registry

/// Maps a `TimingMode` to a `TimingDriver`. All 11 modes are registered
/// by default; unknown (future) modes still fall back to the straight_sets
/// driver so the app doesn't crash on a mode that's authored but not yet
/// implemented. (See HS-2: adding a mode is a new file + a registry entry,
/// not an edited switch in the view model.)
public struct DriverRegistry: Sendable {
    private let drivers: [TimingMode: any TimingDriver]

    public init(
        drivers: [TimingMode: any TimingDriver] = [
            .straightSets: StraightSetsDriver(),
            .superset: SupersetDriver(),
            .circuit: CircuitDriver(),
            .emom: EMOMDriver(),
            .amrap: AMRAPDriver(),
            .forTime: ForTimeDriver(),
            .intervals: IntervalsDriver(),
            .tabata: TabataDriver(),
            .continuous: ContinuousDriver(),
            .accumulate: AccumulateDriver(),
            .custom: CustomDriver(),
            .rest: RestBlockDriver(),
        ]
    ) {
        self.drivers = drivers
    }

    public func driver(for mode: TimingMode) -> TimingDriver {
        drivers[mode] ?? StraightSetsDriver()
    }
}
