// ExecutionVMHolder.swift
//
// Observable box that routes reads of "the current ExecutionViewModel"
// through a single stable reference the shell can swap. The shell rebuilds
// `vm` per-workout after save-and-done (see `AppBootstrap+Hooks.swift`'s
// `makeCompletionWriter`), and `RootTabView` observes the holder so the
// swap flips the rendered tab back onto the next workout's fresh VM
// without the old VM's stale post-save state leaking into the next
// session (qa-002 / qa-003 root cause).
//
// Why observable rather than a plain mutable box: `RootTabView` reads
// `holder.vm?.state.route` to decide whether to render `TodayView` or
// `ExecutionView`. When `saveAndDone` flips the reducer's route back to
// `.today` and the shell replaces `vm` with a fresh VM, SwiftUI needs to
// re-evaluate RootTabView's body so Today's start button binds to the
// new VM's `start()`. `@Observable` on the holder plus a direct
// `holder.vm` read inside the view body accomplishes that without
// threading an `@Bindable` through the call site.

import Foundation
import FeaturesExecution
import WatchBridge

/// Observable wrapper around the currently-active `ExecutionViewModel`.
/// The shell constructs one holder at bootstrap, passes it to the
/// post-save completion writer so it can install a fresh VM after each
/// workout, and threads the same holder into `RootTabView` so the view
/// hierarchy reads the latest VM.
///
/// `vm` is nullable to handle the "no next planned workout" case — after
/// the user completes their last queued workout, `TodayLoader.load`
/// returns `nil` and the shell has no context to construct a new VM
/// from. `TodayView`'s empty-state (`isEmpty == true`, bug-qa-008) gates
/// the start button in that case so a nil VM can't be dispatched to.
@MainActor
@Observable
public final class ExecutionVMHolder {
    /// The currently-active execution view model, or `nil` when the
    /// user has no planned workouts remaining.
    public var vm: ExecutionViewModel?
    private var watchBridgeTask: Task<Void, Never>?

    public init(vm: ExecutionViewModel? = nil) {
        self.vm = vm
    }

    public func connectWatchBridge(_ bridge: any WatchBridge) {
        watchBridgeTask?.cancel()
        watchBridgeTask = Task { @MainActor [weak self, bridge] in
            for await message in bridge.messages() {
                guard let self else { return }
                routeWatchMessage(message)
            }
        }
    }

    private func routeWatchMessage(_ message: WatchMessage) {
        switch message {
        case .setStarted(let workoutItemID, let setIndex, _):
            vm?.applyWatchSetStarted(workoutItemID: workoutItemID, setIndex: setIndex)
        case .setEnded(let workoutItemID, let setIndex, _, let bpmAvg, let bpmMax):
            vm?.applyWatchSetEnded(
                workoutItemID: workoutItemID,
                setIndex: setIndex,
                bpmAvg: bpmAvg,
                bpmMax: bpmMax
            )
        case .quickLog(let workoutItemID, let setIndex, let reps, let rir):
            vm?.applyWatchQuickLog(
                workoutItemID: workoutItemID,
                setIndex: setIndex,
                reps: reps,
                rir: rir
            )
        case .pushActiveBlock, .pushRestTimer, .pushWorkoutComplete:
            return
        }
    }
}
