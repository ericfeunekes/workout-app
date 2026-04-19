// AppBootstrap+Hooks.swift
//
// Push-hook + completion-writer factories for `AppBootstrap.buildReady`.
// Split out of `AppBootstrap.swift` so the parent enum's body stays under
// SwiftLint's `type_body_length` cap. Every closure here is fire-and-
// forget: a network hiccup never blocks the UI mutation path. See
// `docs/sync.md` § "Cadence".

import Foundation
import CoreDomain
import FeaturesExecution
import FeaturesToday
import Persistence
import Sync

extension AppBootstrap {

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
    /// cache (so History sees them without a server round-trip), then
    /// re-runs the `TodayLoader` against the cache so the Today tab
    /// advances to the NEXT planned workout (bug-036 — previously the
    /// VM held the completed workout's context forever until relaunch),
    /// and finally runs the optional shell-supplied `afterLocalCompletion`
    /// hook (History `load()`) so live readers re-derive without tangling
    /// Execution with History / Today.
    ///
    /// Ordering is load-bearing: cache write happens BEFORE the reload
    /// so the loader sees the just-completed workout as `.completed` and
    /// skips it; the History refresh runs AFTER so it reflects the new
    /// row. All steps are local + fire-and-forget — no network I/O
    /// blocks the UI's route flip back to `.today`.
    static func makeCompletionWriter(
        workoutCache: WorkoutCache,
        todayViewModel: TodayViewModel,
        todayLoader: TodayLoader,
        afterLocalCompletion: (@Sendable () async -> Void)?
    ) -> LocalCompletionWriter {
        { [workoutCache, todayViewModel, todayLoader, afterLocalCompletion] workout, setLogs in
            try? await workoutCache.saveWorkout(workout)
            // `workoutID` stamps each log's denormalized column so
            // History's `loadSetLogs(workoutID:)` resolves via a direct
            // predicate even after a future reconcile removes the
            // parent WorkoutItem (R1.4 SetLog denormalization). The
            // completed workout we just wrote carries the id.
            try? await workoutCache.saveSetLogs(setLogs, workoutID: workout.id)
            await todayViewModel.reload(using: todayLoader)
            await afterLocalCompletion?()
        }
    }
}
