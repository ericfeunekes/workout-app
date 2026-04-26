// AppBootstrap+Hooks.swift
//
// Push-hook + completion-writer factories for `AppBootstrap.buildReady`.
// Split out of `AppBootstrap.swift` so the parent enum's body stays under
// SwiftLint's `type_body_length` cap. Every closure here is fire-and-
// forget: a network hiccup never blocks the UI mutation path. See
// `docs/sync.md` § "Cadence".

import Foundation
import CoreDomain
import CoreSession
import CoreTelemetry
import FeaturesExecution
import FeaturesToday
import Persistence
import Sync
import WorkoutCoreFoundation

extension AppBootstrap {

    /// qa-027: no planned workout selected. Before returning `.empty`
    /// (which drops the app into the full-screen "No workouts yet"
    /// shell and hides the History tab), check whether the local cache
    /// has any COMPLETED workouts. When it does, stay in `.ready` with
    /// an empty-glance TodayVM so the user can still reach their
    /// History tab. Only caches with zero history warrant `.empty` — a
    /// first-run that pulled nothing, a server-scrubbed user, or a
    /// fresh install with a successful-but-empty pull.
    ///
    /// qa-039: tightened from "any workout at all (any status)" to
    /// "completed workouts specifically." The prior check ran
    /// `loadWorkouts(status: nil, since: nil)` which returns every
    /// status including `.planned` — if a planned workout survived
    /// TodayLoader's filter for some edge reason (e.g. no
    /// `scheduled_date`, or a subtle sort difference), the fallback
    /// returned `.ready_empty_today` instead of `.empty`, stranding
    /// the user on Today with no way back to FirstRun. Keying on
    /// completed-history specifically matches the actual stranded-from-
    /// History use case qa-027 was solving and closes the qa-039 gap
    /// with one narrower query.
    ///
    /// Lives in `+Hooks.swift` so the main enum body in
    /// `AppBootstrap.swift` stays under SwiftLint's `type_body_length`
    /// cap. Marked `static` (not `private static`) so the parent file's
    /// `bootstrap(...)` can call it across the extension boundary.
    static func resolveNoPlannedWorkout(
        persistence: PersistenceFactory,
        syncAPI: SyncAPI,
        telemetry: TelemetryEmitter,
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)?,
        executionHolder: ExecutionVMHolder?,
        onEmptyTodayRefresh: (@Sendable @MainActor () async -> Bool)? = nil
    ) async throws -> BootstrapResult {
        let completed = try await persistence.workoutCache.loadWorkouts(
            status: .completed, since: nil
        )
        if completed.isEmpty {
            emitBootstrap(telemetry, name: "bootstrap.empty")
            return .empty
        }
        emitBootstrap(telemetry, name: "bootstrap.ready_empty_today")
        let todayVM = TodayViewModel.empty(
            telemetry: telemetry,
            sessionStateBinding: sessionStateBinding
        )
        if let onEmptyTodayRefresh {
            todayVM.setRefreshAction {
                await onEmptyTodayRefresh()
            }
        }
        // Leave `executionHolder.vm` as-is (typically nil from the
        // ExecutionVMHolder initializer). No per-workout rebuild path
        // fires here because the completion writer needs a starting VM
        // to hook into — the next workout's VM is assembled the next
        // time the user pulls or restarts the app with a planned row.
        return .ready(
            todayVM: todayVM,
            executionHolder: executionHolder ?? ExecutionVMHolder(),
            pushFlusher: PushFlusher(api: syncAPI)
        )
    }
}

extension AppBootstrap {

    /// Grouped args for `buildReady`. Keeps the function under SwiftLint's
    /// `function_parameter_count` cap.
    struct ReadyInputs {
        let todayPlanContext: TodayPlanContext
        let workoutContext: WorkoutContext
        /// Kept past build time so `makeCompletionWriter` can call
        /// `todayVM.reload(using:)` after save-and-done — the completed
        /// workout is no longer `.planned` and Today must advance to the
        /// next one (bug-036).
        let todayLoader: TodayLoader
        let sessionStore: SessionStore
        let workoutCache: WorkoutCache
        let syncMetadataStore: SyncMetadataStore
        /// "LAST · …" chip map store. Threaded through to the per-
        /// workout rebuild path (qa-001 + qa-020) so the next workout's
        /// `WorkoutContext.lastPerformed` carries the same pulled
        /// snapshot Today is already rendering.
        let lastPerformedStore: LastPerformedStore?
        let syncAPI: SyncAPI
        let telemetry: TelemetryEmitter
        let afterLocalCompletion: (@Sendable () async -> Void)?
        let onManualRefreshTokenRejected: (@Sendable @MainActor () async -> Void)?
        /// Observable holder the shell uses to both (a) route the Today
        /// start binding to the current VM and (b) drive RootTabView's
        /// routing against `holder.vm.state.route`. The completion
        /// writer installs a freshly-built VM here after save-and-done
        /// so the next workout gets a clean slate.
        let executionHolder: ExecutionVMHolder
    }

    /// Late-bound storage for the completion writer closure. Breaks the
    /// chicken-and-egg cycle between the writer (needs to install a new
    /// VM on the holder) and the VM (needs the writer wired into its
    /// `localCompletionWriter`). The writer reads `value` lazily every
    /// time it fires, so replacing `value` before first fire is safe.
    /// Final after buildReady returns — the writer keeps the same
    /// reference for the app's lifetime.
    @MainActor
    final class CompletionWriterBox {
        var value: LocalCompletionWriter?
    }

    /// Compose the `.ready` tuple. Extracted from `bootstrap(...)` so the
    /// parent function body stays under SwiftLint's
    /// `function_body_length` cap. The push wiring is deliberate: every
    /// hook goes fire-and-forget via the view model's own detached
    /// `Task`, so a network hiccup never blocks the UI mutation path
    /// (see `docs/sync.md` § "Cadence" — push is "fire-and-forget from
    /// the UI's perspective").
    ///
    /// Per-workout VM rebuild (qa-002/qa-003 fix): the initial VM is
    /// constructed here, but the `completionWriter` closure captures the
    /// `executionHolder` plus a rebuild factory. After save-and-done
    /// writes the completed workout locally, the writer re-runs
    /// `TodayLoader`, builds a fresh `WorkoutContext`, constructs a NEW
    /// `ExecutionViewModel` (same factory as the initial one → same
    /// push hooks, same completion writer for the subsequent workout),
    /// and installs it on the holder. `RootTabView` observes
    /// `holder.vm` so the swap flips the rendered VM without a relaunch.
    ///
    /// Cold-launch session restore (qa-024 fix): after the initial VM is
    /// constructed, we `await vm.restoreIfPossible()` to rehydrate any
    /// persisted mid-workout state off disk (absolute `restEndsAt`,
    /// logged sets, current cursor). Restore is cold-launch-only; the
    /// per-workout rebuild path MUST NOT call it (the newly-built VM
    /// for the NEXT workout after save-and-done should be a clean
    /// slate). Route-based UI routing in `RootTabView` picks up the
    /// restored state automatically — a snapshot with route `.active`
    /// or `.rest` lands directly on `ExecutionView`, not Today.
    static func buildReady(_ inputs: ReadyInputs) async -> BootstrapResult {
        let todayVM = TodayViewModel(
            planContext: inputs.todayPlanContext,
            telemetry: inputs.telemetry
        )
        let pushFlusher = PushFlusher(api: inputs.syncAPI)
        let hooks = makePushHooks(
            syncAPI: inputs.syncAPI,
            workoutCache: inputs.workoutCache,
            pushFlusher: pushFlusher
        )
        let rebuildVM = makeRebuildVM(
            hooks: hooks,
            sessionStore: inputs.sessionStore,
            telemetry: inputs.telemetry
        )
        rebuildVM.writerBox.value = makeCompletionWriter(
            inputs: CompletionWriterInputs(
                workoutCache: inputs.workoutCache,
                lastPerformedStore: inputs.lastPerformedStore,
                todayViewModel: todayVM,
                todayLoader: inputs.todayLoader,
                afterLocalCompletion: inputs.afterLocalCompletion,
                executionHolder: inputs.executionHolder,
                rebuild: rebuildVM.factory
            )
        )
        let refreshDeps = TodayRefreshDependencies(
            syncAPI: inputs.syncAPI,
            workoutCache: inputs.workoutCache,
            syncMetadataStore: inputs.syncMetadataStore,
            lastPerformedStore: inputs.lastPerformedStore,
            todayLoader: inputs.todayLoader,
            executionHolder: inputs.executionHolder,
            rebuild: rebuildVM.factory,
            telemetry: inputs.telemetry,
            onTokenRejected: inputs.onManualRefreshTokenRejected
        )
        todayVM.setRefreshAction { [weak todayVM, refreshDeps] in
            guard let todayVM else { return false }
            return await refreshTodayPlan(inputs: TodayRefreshInputs(
                syncAPI: refreshDeps.syncAPI,
                workoutCache: refreshDeps.workoutCache,
                syncMetadataStore: refreshDeps.syncMetadataStore,
                lastPerformedStore: refreshDeps.lastPerformedStore,
                todayViewModel: todayVM,
                todayLoader: refreshDeps.todayLoader,
                executionHolder: refreshDeps.executionHolder,
                rebuild: refreshDeps.rebuild,
                telemetry: refreshDeps.telemetry,
                onTokenRejected: refreshDeps.onTokenRejected
            ))
        }
        todayVM.setStartWorkoutAction { [startDeps = refreshDeps] workoutID in
            await startWorkoutFromPlan(
                workoutID: workoutID,
                workoutCache: startDeps.workoutCache,
                lastPerformedStore: startDeps.lastPerformedStore,
                executionHolder: startDeps.executionHolder,
                rebuild: startDeps.rebuild
            )
        }
        let initialVM = rebuildVM.factory(inputs.workoutContext)
        // Cold-launch restore: hydrate any persisted mid-workout state
        // (route / cursor / restEndsAt / logged sets) before publishing
        // the VM. If no snapshot exists, the decoder fails, or the
        // stored workoutID doesn't match the context, this is a silent
        // no-op and the freshly-seeded state stands (see
        // `ExecutionViewModel+Persistence.swift` for the guards).
        await initialVM.restoreIfPossible()
        inputs.executionHolder.vm = initialVM
        return .ready(
            todayVM: todayVM,
            executionHolder: inputs.executionHolder,
            pushFlusher: pushFlusher
        )
    }

    struct TodayRefreshDependencies: Sendable {
        let syncAPI: SyncAPI
        let workoutCache: WorkoutCache
        let syncMetadataStore: SyncMetadataStore
        let lastPerformedStore: LastPerformedStore?
        let todayLoader: TodayLoader
        let executionHolder: ExecutionVMHolder
        let rebuild: @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
        let telemetry: TelemetryEmitter
        let onTokenRejected: (@Sendable @MainActor () async -> Void)?
    }

    struct TodayRefreshInputs: Sendable {
        let syncAPI: SyncAPI
        let workoutCache: WorkoutCache
        let syncMetadataStore: SyncMetadataStore
        let lastPerformedStore: LastPerformedStore?
        let todayViewModel: TodayViewModel
        let todayLoader: TodayLoader
        let executionHolder: ExecutionVMHolder
        let rebuild: @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
        let telemetry: TelemetryEmitter
        let onTokenRejected: (@Sendable @MainActor () async -> Void)?
    }

    static func refreshTodayPlan(inputs: TodayRefreshInputs) async -> Bool {
        do {
            let lastSyncAt = await inputs.syncMetadataStore.getLastSyncAt()
            let result = try await inputs.syncAPI.pullLatest(since: lastSyncAt)
            try await savePull(result, into: inputs.workoutCache)
            if !result.lastPerformed.isEmpty, let store = inputs.lastPerformedStore {
                let lastPerformedMap = LastPerformedFormatter.buildMap(
                    from: result.lastPerformed
                )
                await store.save(lastPerformedMap)
            }
            await inputs.syncMetadataStore.setLastSyncAt(result.serverTime)
            await inputs.todayViewModel.reload(using: inputs.todayLoader)
            await rebuildExecutionVMForNextWorkout(
                workoutCache: inputs.workoutCache,
                lastPerformedStore: inputs.lastPerformedStore,
                todayLoader: inputs.todayLoader,
                executionHolder: inputs.executionHolder,
                rebuild: inputs.rebuild
            )
            return true
        } catch SyncError.tokenRejected {
            inputs.telemetry.emit(Event(
                sessionID: TelemetrySession.id,
                kind: "error",
                name: "today.refresh.token_rejected"
            ))
            await inputs.onTokenRejected?()
            return false
        } catch {
            return false
        }
    }

    static func startWorkoutFromPlan(
        workoutID: WorkoutID,
        workoutCache: WorkoutCache,
        lastPerformedStore: LastPerformedStore?,
        executionHolder: ExecutionVMHolder,
        rebuild: @escaping @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
    ) async -> Bool {
        if executionHolder.vm?.context.workout.id == workoutID {
            executionHolder.vm?.start()
            return true
        }
        let workout: Workout
        do {
            let planned = try await workoutCache.loadWorkouts(
                status: .planned,
                since: nil
            )
            guard let match = planned.first(where: { $0.id == workoutID }) else {
                return false
            }
            workout = match
        } catch {
            return false
        }
        let workoutContext: WorkoutContext
        do {
            workoutContext = try await AppBootstrap.buildWorkoutContext(
                for: workout,
                cache: workoutCache,
                lastPerformedStore: lastPerformedStore
            )
        } catch {
            return false
        }
        executionHolder.vm = rebuild(workoutContext)
        executionHolder.vm?.start()
        return true
    }

    /// Bundle of the rebuild factory closure + the shared
    /// `CompletionWriterBox` the closure reads lazily. Extracted so
    /// `buildReady` stays under SwiftLint's `function_body_length` cap
    /// after the qa-001 `lastPerformedStore` plumbing pushed it over.
    struct RebuildHarness {
        let factory: @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
        let writerBox: CompletionWriterBox
    }

    /// Build the per-workout VM factory closure (used both for the
    /// initial VM and for each save-and-done rebuild). The closure
    /// captures a fresh `CompletionWriterBox` whose `value` is set
    /// immediately after this returns — the late assign is safe because
    /// the box is read lazily inside the closure.
    static func makeRebuildVM(
        hooks: ExecutionPushHooks,
        sessionStore: SessionStore,
        telemetry: TelemetryEmitter
    ) -> RebuildHarness {
        let writerBox = CompletionWriterBox()
        let factory: @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
        factory = { [hooks, sessionStore, telemetry, writerBox] ctx in
            ExecutionViewModel(
                context: ctx,
                sessionStore: sessionStore,
                push: hooks,
                localCompletionWriter: writerBox.value,
                telemetry: telemetry
            )
        }
        return RebuildHarness(factory: factory, writerBox: writerBox)
    }

    /// Build the push-hook bundle handed to `ExecutionViewModel`.
    ///
    /// - `onSetLogged` routes each logged set to `SyncAPI.pushLog`.
    /// - `onStatusChanged` routes status flips (active / completed) to
    ///   `SyncAPI.pushStatus`.
    /// - `onPushKick` drains the push queue as soon as `saveAndDone`
    ///   fires so the user doesn't wait for the ~60s foreground tick.
    /// - `onUserParameterChanged` lands a just-captured user_parameter
    ///   (today: bodyweight) in the local cache AND enqueues the
    ///   `POST /api/user-parameters`. Local write first so latest-per-
    ///   key reads see it immediately; both fail-silent via `try?`.
    static func makePushHooks(
        syncAPI: SyncAPI,
        workoutCache: WorkoutCache,
        pushFlusher: PushFlusher
    ) -> ExecutionPushHooks {
        ExecutionPushHooks(
            onSetLogged: { [syncAPI] log in
                try? await syncAPI.pushLog([log])
            },
            onStatusChanged: { [syncAPI] id, status, at, notes in
                try? await syncAPI.pushStatus(
                    workoutID: id,
                    status: status,
                    completedAt: at,
                    notes: notes
                )
            },
            onPushKick: { [pushFlusher] in
                await pushFlusher.flushNow()
            },
            onUserParameterChanged: { [syncAPI, workoutCache] param in
                try? await workoutCache.saveUserParameter(param)
                try? await syncAPI.pushUserParameter(param)
            }
        )
    }

    /// Build the completion writer injected into `ExecutionViewModel`.
    /// Writes the just-completed workout + its set_logs to the local
    /// cache (so History sees them without a server round-trip), re-runs
    /// `TodayLoader` so the Today tab advances to the NEXT planned
    /// workout (bug-036), runs the optional shell-supplied
    /// `afterLocalCompletion` hook (History `load()`), and — qa-002 /
    /// qa-003 fix — builds a FRESH `ExecutionViewModel` for the next
    /// workout and installs it on `executionHolder.vm` so RootTabView's
    /// routing switch re-evaluates against the new VM.
    ///
    /// Per-workout VM rebuild is load-bearing: the reducer's `.save`
    /// empties the in-memory session (workoutID preserved but items +
    /// structure cleared), so re-using the same VM for the next workout
    /// flips it to `.active` on empty state → ActiveView's defensive
    /// fallback "no active set". The ONLY safe cutover is "new workout
    /// = new VM". See `scratch/qa-runs/_investigations/qa-002-crash.md`.
    ///
    /// Ordering is load-bearing:
    ///   1. Cache write → so the Today loader sees the just-completed
    ///      workout as `.completed` and skips it.
    ///   2. Today reload → populates the Today tab with the NEXT planned
    ///      workout (or empty state if none).
    ///   3. `afterLocalCompletion` → History refresh.
    ///   4. Next-VM rebuild → loads the same next context as step 2,
    ///      constructs an ExecutionViewModel, installs on holder. When
    ///      Today returned `nil` (no next planned workout), `vm` is set
    ///      to `nil` — Today's isEmpty state gates the start button so
    ///      the nil VM is never dispatched to (qa-008).
    ///
    /// All steps are local + fire-and-forget — no network I/O blocks
    /// the UI's route flip back to `.today`.
    static func makeCompletionWriter(
        inputs: CompletionWriterInputs
    ) -> LocalCompletionWriter {
        { [inputs] workout, setLogs in
            try? await inputs.workoutCache.saveWorkout(workout)
            // `workoutID` stamps each log's denormalized column so
            // History's `loadSetLogs(workoutID:)` resolves via a direct
            // predicate even after a future reconcile removes the
            // parent WorkoutItem (R1.4 SetLog denormalization). The
            // completed workout we just wrote carries the id.
            try? await inputs.workoutCache.saveSetLogs(setLogs, workoutID: workout.id)
            await inputs.todayViewModel.reload(using: inputs.todayLoader)
            await inputs.afterLocalCompletion?()
            await rebuildExecutionVMForNextWorkout(
                workoutCache: inputs.workoutCache,
                lastPerformedStore: inputs.lastPerformedStore,
                todayLoader: inputs.todayLoader,
                executionHolder: inputs.executionHolder,
                rebuild: inputs.rebuild
            )
        }
    }

    /// Grouped args for `makeCompletionWriter`. Keeps the builder under
    /// SwiftLint's `function_parameter_count` cap.
    struct CompletionWriterInputs: Sendable {
        let workoutCache: WorkoutCache
        let lastPerformedStore: LastPerformedStore?
        let todayViewModel: TodayViewModel
        let todayLoader: TodayLoader
        let afterLocalCompletion: (@Sendable () async -> Void)?
        let executionHolder: ExecutionVMHolder
        let rebuild: @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
    }

    /// Load the next planned workout's context and install a fresh
    /// `ExecutionViewModel` on the holder. Nil context → nil vm (Today's
    /// empty state handles the "no more planned workouts" terminal case).
    ///
    /// Fire-and-forget from the caller: cache read failures leave the
    /// previous VM in place so the user at least sees the post-save
    /// Today screen rather than a blank UI. The next app launch's
    /// `AppBootstrap.bootstrap` recovers into a clean state either way.
    private static func rebuildExecutionVMForNextWorkout(
        workoutCache: WorkoutCache,
        lastPerformedStore: LastPerformedStore?,
        todayLoader: TodayLoader,
        executionHolder: ExecutionVMHolder,
        rebuild: @escaping @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel
    ) async {
        let nextContext: TodayContext?
        do {
            nextContext = try await todayLoader.load()
        } catch {
            // Cache read failure — leave the (now-emptied) previous VM
            // in place rather than nil-ing `holder.vm`. The user's
            // Today tab will still render; relaunch recovers cleanly.
            return
        }
        guard let ctx = nextContext else {
            await MainActor.run { executionHolder.vm = nil }
            return
        }
        let workoutContext: WorkoutContext
        do {
            workoutContext = try await AppBootstrap.buildWorkoutContext(
                for: ctx.workout,
                cache: workoutCache,
                lastPerformedStore: lastPerformedStore
            )
        } catch {
            return
        }
        await MainActor.run {
            executionHolder.vm = rebuild(workoutContext)
        }
    }
}
