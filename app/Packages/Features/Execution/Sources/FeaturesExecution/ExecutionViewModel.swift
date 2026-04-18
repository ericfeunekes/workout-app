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
//   - Persistence writes are fire-and-forget `Task` launches; callers
//     do not await them. The in-memory state is authoritative for
//     rendering; the on-disk payload catches up asynchronously.

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

/// Fire-and-forget hook invoked when the workout completes. Shell supplies
/// this so the terminal `status_update` (and its `completed_at`) is enqueued
/// alongside the final set_logs.
public typealias StatusEnqueuer = @Sendable (WorkoutID, WorkoutStatus, Date?) async -> Void

/// Fire-and-forget hook invoked after `.complete` is dispatched. Shell
/// supplies this so the push queue drains immediately rather than waiting
/// for the next ~60s tick of the foreground flusher — the completion's
/// set_logs and status_update hit the server quickly while the user is
/// still looking at the ledger.
public typealias PushFlushKick = @Sendable () async -> Void

/// Fire-and-forget hook invoked when `saveAndDone` fires — BEFORE the
/// reducer clears the in-memory session. Shell supplies this so the
/// completed workout + its set_logs land in the local `WorkoutCache`
/// immediately, populating the History tab without waiting for a server
/// round-trip. See `docs/open-questions.md` § "Execution `save & done`
/// doesn't persist the completed workout to local cache". `nil` (the
/// default) preserves the pure-offline test path.
public typealias LocalCompletionWriter = @Sendable (Workout, [SetLog]) async -> Void

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
    public let onStatusChanged: StatusEnqueuer?
    public let onPushKick: PushFlushKick?
    public let onUserParameterChanged: UserParameterEnqueuer?

    public init(
        onSetLogged: SetLogEnqueuer? = nil,
        onStatusChanged: StatusEnqueuer? = nil,
        onPushKick: PushFlushKick? = nil,
        onUserParameterChanged: UserParameterEnqueuer? = nil
    ) {
        self.onSetLogged = onSetLogged
        self.onStatusChanged = onStatusChanged
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
    /// `advance`.
    public private(set) var currentProposal: AutoregProposal?

    /// Item the current proposal targets. Kept alongside the proposal
    /// so `acceptAutoreg`/`undoAutoreg` operate on the right item.
    public private(set) var currentProposalItemID: UUID?

    /// Test-observable counter incremented every time `tickBlockTimer()`
    /// fires. Used by bug-042 regression tests to prove the view's
    /// periodic tick actually invokes the VM. Not `@Observable` — tests
    /// read it synchronously after driving the timer publisher; regular
    /// view rendering shouldn't depend on it.
    internal(set) public var tickCallCount: Int = 0

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

    /// Rest duration for the current cursor (in seconds). Used by the
    /// view model itself to fire `.enterRest`; exposed here so the view
    /// can render the ring's total.
    public var restDurationSeconds: TimeInterval {
        driver.restDuration(state: state, context: context)
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
        self.state = SessionSeeder.seed(context: context)
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
        apply([.start])
        enterRestIfZeroItemBlock()
        enterBlockTimerIfNeeded()
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
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        let logMutation: SessionMutation = .logSet(
            itemID: item.id,
            setIndex: c.setIndex,
            loggedReps: reps,
            loggedRir: rir
        )
        // Compute autoreg proposal against the *pre-log* state so the
        // driver sees the prescribed reps/load (the log mutation
        // overwrites those with the observed values).
        let outcome = driver.onSetLogged(
            state: state,
            context: context,
            event: SetLogEvent(
                itemID: item.id,
                setIndex: c.setIndex,
                loggedReps: reps,
                loggedRir: rir
            )
        )
        let postLogState = SessionReducer.reduce(state, logMutation)
        apply(buildLogMutations(
            logMutation: logMutation,
            outcome: outcome,
            item: item,
            postLogState: postLogState
        ))
        currentProposal = outcome.proposal
        currentProposalItemID = outcome.proposal == nil ? nil : item.id
        emitSessionMutation("logSet")
        if outcome.proposal != nil {
            emitAutoreg("execution.autoreg_proposed")
        }
        enqueueLoggedSet(item: item, setIndex: c.setIndex, reps: reps, rir: rir)
        // After a log, the cursor may have auto-advanced (restDuration=0
        // → buildLogMutations appended `.advanceFromRest`). Re-derive
        // block / Tabata timers so crossing a block boundary via a
        // zero-rest mode (AMRAP / ForTime / Continuous) refreshes them.
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
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
    public func undoAutoreg() {
        guard let proposal = currentProposal,
              let itemID = currentProposalItemID else { return }
        emitAutoreg("execution.autoreg_undo")

        // To revert, apply the inverse proposal — flip direction and
        // restore the prescribed loads. We derive the original load per
        // set from the prescription seed: anything that was touched by
        // this proposal's apply had `adjust` set to the proposal's
        // direction. We rebuild those sets from the seeded plan.
        guard let itemLog = state.items.first(where: { $0.itemID == itemID }),
              let item = findItem(id: itemID, in: context) else {
            currentProposal = nil
            currentProposalItemID = nil
            return
        }

        let originals = SessionSeeder.seedSets(for: item)
        var revertMutations: [SessionMutation] = []

        let proposalDirection: SetPlan.Adjust = proposal.direction == .up ? .up : .down
        for set in itemLog.sets where !set.done && set.adjust == proposalDirection {
            if let original = originals.first(where: { $0.setIndex == set.setIndex }) {
                // Use editPendingSet to restore load+reps on the
                // non-done rows. Note that editPendingSet marks the set
                // as `.manual` — but we want the revert to look pristine
                // so autoreg can re-trigger later if the hold is ever
                // lifted. We work around this by writing a custom
                // revert via the reducer's direct update path. For now
                // we accept the `.manual` tag as a side-effect: the
                // hold flag makes it moot since no further proposals
                // will fire this session.
                revertMutations.append(.editPendingSet(
                    itemID: itemID,
                    setIndex: set.setIndex,
                    loadKg: original.loadKg,
                    reps: nil
                ))
            }
        }
        revertMutations.append(.holdAutoreg(itemID: itemID))
        apply(revertMutations)

        currentProposal = nil
        currentProposalItemID = nil
    }

    /// Advance the cursor: rest → active (next set) or rest → complete.
    ///
    /// If the advance lands on a zero-item block (standalone `rest`),
    /// we flip the route from the post-reducer `.active` back to `.rest`
    /// with the rest-block driver's duration. See `RestBlockDriver` for
    /// the cursor-model rationale.
    public func advance() {
        emitSessionMutation("advance")
        apply([.advanceFromRest])
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
    }

    /// Force-complete. Available via an "End" affordance in the nav bar.
    ///
    /// Does NOT enqueue the status_update here. The terminal server-side
    /// push is the responsibility of `saveAndDone()` — which fires for
    /// every path into `.complete` (both auto-advance and this explicit
    /// End button). Enqueuing here *and* in `saveAndDone` produces a
    /// double push with the same workout_id + status pair. Session state
    /// is persisted, so if the user force-completes and kills the app
    /// before tapping save & done, the complete screen restores on next
    /// launch and the user can still commit from there.
    public func complete() {
        apply([.complete])
    }

    /// Save & done. Clears the persisted session and returns to Today.
    ///
    /// Before the reducer's `.save` wipes the in-memory log, we hand the
    /// completed workout + set_logs to `localCompletionWriter` (if wired).
    /// That writes them into the local `WorkoutCache` so the History tab
    /// sees the workout immediately — the push queue is the authoritative
    /// server-side path, but the user shouldn't have to wait for a pull
    /// to see their own just-completed workout. See
    /// `docs/open-questions.md` § "Execution `save & done` doesn't persist
    /// the completed workout to local cache".
    ///
    /// Capture inputs from the Complete screen (bug-011 / bug-012):
    ///   - `note`: workout-level note. Trimmed + empty-collapsed; when
    ///     present it replaces the in-memory state's `note` and lands on
    ///     the completed `Workout.notes` in the local cache.
    ///   - `bodyweightKg`: optional body weight captured at completion.
    ///     When present, a fresh `UserParameter` is fired through the
    ///     `onUserParameterChanged` push hook (the push queue routes it
    ///     to `POST /api/user-parameters`). Nil means no capture, no
    ///     enqueue.
    ///
    /// Defaulted parameters preserve the existing call-sites in tests
    /// that predate the capture inputs.
    ///
    /// TODO(open-question): dictation-mic capture for the note is a
    /// deferred polish item; the TextField is the minimum UI that
    /// unblocks bug-011 / bug-012. See `docs/open-questions.md` and
    /// `docs/features/save-and-done.md` § S11 / S12.
    public func saveAndDone(
        note: String? = nil,
        bodyweightKg: Double? = nil
    ) {
        // Emit the terminal status_update BEFORE writing + wiping the
        // session — see `performSaveAndDone` for the ordering rationale.
        // Split out so the class body stays under SwiftLint's cap.
        performSaveAndDone(note: note, bodyweightKg: bodyweightKg)
    }

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
        reps: Int?
    ) {
        apply([.editPendingSet(
            itemID: itemID,
            setIndex: setIndex,
            loadKg: loadKg,
            reps: reps
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
