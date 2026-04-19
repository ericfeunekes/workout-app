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

extension AppBootstrap {

    /// Grouped args for `buildReady`. Keeps the function under SwiftLint's
    /// `function_parameter_count` cap.
    struct ReadyInputs {
        let todayContext: TodayContext
        let workoutContext: WorkoutContext
        /// Kept past build time so `makeCompletionWriter` can call
        /// `todayVM.reload(using:)` after save-and-done — the completed
        /// workout is no longer `.planned` and Today must advance to the
        /// next one (bug-036).
        let todayLoader: TodayLoader
        let sessionStore: SessionStore
        let workoutCache: WorkoutCache
        let syncAPI: SyncAPI
        let telemetry: TelemetryEmitter
        let afterLocalCompletion: (@Sendable () async -> Void)?
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
    static func buildReady(_ inputs: ReadyInputs) -> BootstrapResult {
        let todayVM = TodayViewModel(
            context: inputs.todayContext,
            telemetry: inputs.telemetry
        )
        let pushFlusher = PushFlusher(api: inputs.syncAPI)
        let hooks = makePushHooks(
            syncAPI: inputs.syncAPI,
            workoutCache: inputs.workoutCache,
            pushFlusher: pushFlusher
        )
        let executionHolder = inputs.executionHolder
        // The completion writer must install a FRESH VM onto the holder
        // after each save-and-done, AND that fresh VM must carry the same
        // completion writer so it rebuilds again after its own save.
        // Resolve the self-reference by binding the writer to a shared
        // box that gets populated immediately below — the closure reads
        // `writerBox.value` lazily, so the late assign is safe.
        let writerBox = CompletionWriterBox()
        let sessionStore = inputs.sessionStore
        let telemetry = inputs.telemetry
        let rebuildVM: @Sendable @MainActor (WorkoutContext) -> ExecutionViewModel = { [hooks, sessionStore, telemetry, writerBox] ctx in
            ExecutionViewModel(
                context: ctx,
                sessionStore: sessionStore,
                push: hooks,
                localCompletionWriter: writerBox.value,
                telemetry: telemetry
            )
        }
        writerBox.value = makeCompletionWriter(
            inputs: CompletionWriterInputs(
                workoutCache: inputs.workoutCache,
                todayViewModel: todayVM,
                todayLoader: inputs.todayLoader,
                afterLocalCompletion: inputs.afterLocalCompletion,
                executionHolder: executionHolder,
                rebuild: rebuildVM
            )
        )
        let executionVM = rebuildVM(inputs.workoutContext)
        executionHolder.vm = executionVM
        return .ready(
            todayVM: todayVM,
            executionHolder: executionHolder,
            pushFlusher: pushFlusher
        )
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
                cache: workoutCache
            )
        } catch {
            return
        }
        await MainActor.run {
            executionHolder.vm = rebuild(workoutContext)
        }
    }
}
