// RootView+DebugLaunch.swift
//
// DEBUG-only launch-args honoring for `RootView`. Kept in a separate file
// so `WorkoutDBApp.swift`'s struct body stays under SwiftLint's
// `type_body_length` cap. See the DEBUG block in `WorkoutDBApp.swift` for
// the router that calls into these helpers.

#if DEBUG
import SwiftUI
import CoreDomain
import CoreSession
import FeaturesExecution
import FeaturesToday
import Persistence
import Shell

extension RootView {

    /// Build the `.debugSeed` phase's view models backed by
    /// `ExecutionPreviewSeed.pushA()` + matching Today seed. Wraps the
    /// seeded ExecutionViewModel in an `ExecutionVMHolder` so
    /// RootTabView's observation path matches production.
    func buildDebugSeedViewModels() -> (TodayViewModel, ExecutionVMHolder) {
        let cache = persistence.workoutCache
        let telemetry = persistence.telemetryEmitter()
        let context = ExecutionPreviewSeed.pushA()
        let dataset = PulledDataset(
            workouts: [context.workout],
            blocks: context.blocks,
            items: context.itemsByBlock.flatMap { $0 },
            exercises: Array(context.exercises.values)
        )
        Task { [cache, dataset] in try? await cache.save(dataset) }
        // Capture historyVM so save & done on the debug path also
        // refreshes the History tab, matching the production flow.
        let historyVM = self.historyVM
        let todaySeed = TodayPreviewSeed.pushA(withLastSession: true)
        // Build todayVM FIRST so the executionVM's localCompletionWriter
        // can capture it + a TodayLoader and call `reload` post-save,
        // matching the production bug-036 wiring. The Today → Execution
        // `.start` binding is wired below via the Shell-package
        // `ExecutionVMHolder` (shared with RootTabView's observation).
        let executionHolder = ExecutionVMHolder()
        let todayContext = TodayContext(
            workout: todaySeed.workout,
            blocks: todaySeed.blocks,
            items: todaySeed.items,
            exercises: todaySeed.exercises,
            lastPerformed: todaySeed.lastPerformed,
            lastSessionSummary: todaySeed.lastSessionSummary,
            programTags: todaySeed.programTags,
            sessionStateBinding: { [executionHolder] mutation in
                guard case .start = mutation else { return }
                Task { @MainActor in executionHolder.vm?.start() }
            }
        )
        let todayVM = TodayViewModel(context: todayContext, telemetry: telemetry)
        let todayLoader = TodayLoader(cache: cache)
        let executionVM = ExecutionViewModel(
            context: context,
            localCompletionWriter: { [cache, historyVM, todayVM, todayLoader] workout, setLogs in
                try? await cache.saveWorkout(workout)
                try? await cache.saveSetLogs(setLogs, workoutID: workout.id)
                await todayVM.reload(using: todayLoader)
                await historyVM.load()
            },
            telemetry: telemetry
        )
        executionHolder.vm = executionVM
        return (todayVM, executionHolder)
    }

    /// Honor `--start-active` / `--jump-rest` / `--jump-complete` launch
    /// args by driving the Execution view model straight to the target
    /// state.
    func applyDebugLaunchJumps(args: [String], executionVM: ExecutionViewModel) {
        if args.contains("--start-active") {
            executionVM.start()
        } else if args.contains("--jump-rest") {
            executionVM.start()
            executionVM.logSet(reps: 5, rir: 2)
        } else if args.contains("--jump-complete") {
            executionVM.start()
            let totalSets = executionVM.state.items.reduce(0) { $0 + $1.sets.count }
            for _ in 0..<totalSets {
                executionVM.logSet(reps: 5, rir: 2)
                executionVM.advance()
            }
        }
    }
}

#endif
