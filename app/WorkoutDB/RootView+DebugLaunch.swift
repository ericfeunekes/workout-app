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
import CoreTelemetry
import FeaturesExecution
import FeaturesToday
import Persistence
import Shell
import WatchBridge
import WorkoutKitAdapter

extension RootView {

    /// Build the `.debugSeed` phase's view models backed by a DEBUG
    /// execution fixture + matching Today seed. Wraps the
    /// seeded ExecutionViewModel in an `ExecutionVMHolder` so
    /// RootTabView's observation path matches production.
    func buildDebugSeedViewModels(args: [String] = []) -> (TodayViewModel, ExecutionVMHolder) {
        if args.contains("--debug-today-plan") {
            return buildDebugTodayPlanViewModels()
        }

        let cache = persistence.workoutCache
        let telemetry = persistence.telemetryEmitter()
        let context = debugWorkoutContext(from: args)
        let dataset = PulledDataset(
            workouts: [context.workout],
            blocks: context.blocks,
            items: context.itemsByBlock.flatMap { $0 },
            exercises: Array(context.exercises.values)
        )
        Task { [cache, dataset] in
            try? await cache.clear()
            try? await cache.save(dataset)
        }
        // Capture historyVM so save & done on the debug path also
        // refreshes the History tab, matching the production flow.
        let historyVM = self.historyVM
        // Build todayVM FIRST so the executionVM's localCompletionWriter
        // can capture it + a TodayLoader and call `reload` post-save,
        // matching the production bug-036 wiring. The Today → Execution
        // `.start` binding is wired below via the Shell-package
        // `ExecutionVMHolder` (shared with RootTabView's observation).
        let executionHolder = ExecutionVMHolder()
        let todayContext = TodayContext(
            workout: context.workout,
            blocks: context.blocks,
            items: context.itemsByBlock.flatMap { $0 },
            exercises: context.exercises,
            lastPerformed: context.lastPerformed,
            lastSessionSummary: "last time: 45 lb × 8",
            programTags: debugProgramTags(from: args),
            sessionStateBinding: { [executionHolder] mutation in
                guard case .start = mutation else { return }
                Task { @MainActor in executionHolder.vm?.start() }
            }
        )
        let todayVM = TodayViewModel(context: todayContext, telemetry: telemetry)
        let todayLoader = TodayLoader(cache: cache)
        let executionVM = ExecutionViewModel(
            context: context,
            localCompletionWriter: { [cache, historyVM, todayVM, todayLoader] record in
                await emitDebugCompletionCacheWrite(record, telemetry: telemetry) {
                    try await cache.saveWorkout(record.workout)
                    try await cache.savePrimitiveSetLogs(
                        record.primitiveSetLogs,
                        workoutID: record.workoutID
                    )
                }
                await todayVM.reload(using: todayLoader)
                await historyVM.load()
            },
            telemetry: telemetry
        )
        executionHolder.vm = executionVM
        return (todayVM, executionHolder)
    }

    /// DEBUG-only plan-surface fixture. Unlike `--start-active`, this
    /// bypasses FirstRun without starting execution, so simulator QA can
    /// validate missed / today / upcoming cards, detail sheets, and the
    /// start-any-visible-card handoff.
    private func buildDebugTodayPlanViewModels() -> (TodayViewModel, ExecutionVMHolder) {
        let cache = persistence.workoutCache
        let telemetry = persistence.telemetryEmitter()
        let historyVM = self.historyVM
        let executionHolder = ExecutionVMHolder()
        let now = Date()
        let contexts = debugTodayPlanContexts(now: now)
        let selected = contexts.first ?? ExecutionPreviewSeed.pushA()
        let contextsByWorkoutID = Dictionary(uniqueKeysWithValues: contexts.map {
            ($0.workout.id, $0)
        })

        let binding: @Sendable (SessionMutation) -> Void = { [executionHolder] mutation in
            guard case .start = mutation else { return }
            Task { @MainActor in executionHolder.vm?.start() }
        }
        let todayContexts = contexts.map { todayContext(from: $0, binding: binding) }
        let selectedTodayContext = todayContext(from: selected, binding: binding)
        let planContext = TodayPlanContext(
            selected: selectedTodayContext,
            workouts: todayContexts
        )
        let todayVM = TodayViewModel(planContext: planContext, telemetry: telemetry)
        let todayLoader = TodayLoader(cache: cache)
        let makeCompletionWriter: @MainActor () -> LocalCompletionWriter = {
            { [cache, historyVM, todayVM, todayLoader, telemetry] record in
                await emitDebugCompletionCacheWrite(record, telemetry: telemetry) {
                    try await cache.saveWorkout(record.workout)
                    try await cache.savePrimitiveSetLogs(
                        record.primitiveSetLogs,
                        workoutID: record.workoutID
                    )
                }
                await todayVM.reload(using: todayLoader)
                await historyVM.load()
            }
        }

        todayVM.setStartWorkoutAction { [executionHolder, contextsByWorkoutID, telemetry] workoutID in
            guard let context = contextsByWorkoutID[workoutID] else { return false }
            let vm = ExecutionViewModel(
                context: context,
                localCompletionWriter: makeCompletionWriter(),
                telemetry: telemetry
            )
            executionHolder.vm = vm
            vm.start()
            return true
        }

        let executionVM = ExecutionViewModel(
            context: selected,
            localCompletionWriter: makeCompletionWriter(),
            telemetry: telemetry
        )
        executionHolder.vm = executionVM

        let dataset = PulledDataset(
            workouts: contexts.map(\.workout),
            primitiveWorkouts: contexts.compactMap(\.primitiveWorkout),
            blocks: contexts.flatMap(\.blocks),
            items: contexts.flatMap { $0.itemsByBlock.flatMap { $0 } },
            exercises: Array(contexts.flatMap { $0.exercises.values })
        )
        Task { [cache, dataset] in
            try? await cache.clear()
            try? await cache.save(dataset)
        }

        return (todayVM, executionHolder)
    }

    /// Honor `--start-active` / `--jump-rest` / `--jump-transition` /
    /// `--jump-complete` launch args by driving the Execution view model straight to the target
    /// state.
    func applyDebugLaunchJumps(args: [String], executionVM: ExecutionViewModel) {
        if args.contains("--jump-transition") {
            executionVM.start()
            executionVM.startCurrentSet()
            executionVM.logSet(reps: 5, rir: 2)
            executionVM.advance()
        } else if args.contains("--start-active") {
            executionVM.start()
        } else if args.contains("--jump-rest") {
            executionVM.start()
            executionVM.startCurrentSet()
            executionVM.logSet(reps: 5, rir: 2)
        } else if args.contains("--jump-complete") {
            executionVM.start()
            let totalSets = executionVM.state.items.reduce(0) { $0 + $1.sets.count }
            for _ in 0..<totalSets {
                executionVM.startCurrentSet()
                executionVM.logSet(reps: 5, rir: 2)
                executionVM.advance()
            }
        }
    }

    /// DEBUG-only WatchConnectivity smoke. This is intentionally a fixed,
    /// synthetic payload: it proves the iOS simulator can push content through
    /// `LiveWatchBridge` to the paired Watch simulator without coupling the
    /// custom Watch lane to the production execution reducer.
    func sendDebugWatchPayloadIfRequested(args: [String]) {
        guard args.contains("--debug-watch-push") else { return }
        Task.detached {
            let bridge = LiveWatchBridge()
            let message = WatchMessage.pushActiveBlock(ActiveBlockPayload(
                workoutItemID: UUID(),
                exerciseName: "Bench Press",
                prescription: "5 reps @ 102 lb",
                setNumber: 2,
                setCount: 5,
                targetRir: 2
            ))

            for attempt in 0..<6 {
                do {
                    try await bridge.send(message)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return
                } catch {
                    if attempt == 5 { return }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    /// DEBUG-only WorkoutKit side-effect probe. This is evidence collection
    /// for the real-device gate, not a production export path and not a
    /// user-facing button.
    func runDebugWorkoutKitProbeIfRequested(args: [String]) {
        guard args.contains("--debug-workoutkit-push-probe") else { return }
        Task.detached {
            if #available(iOS 17.0, watchOS 10.0, *) {
                print("WORKOUTKIT_DIAGNOSTIC_PROBE_BEGIN")
                print(await WorkoutKitDiagnosticProbe.runScheduleProbeJSON())
                print("WORKOUTKIT_DIAGNOSTIC_PROBE_END")
            } else {
                print("WORKOUTKIT_DIAGNOSTIC_PROBE_UNAVAILABLE")
            }
        }
    }

    private func debugWorkoutContext(from args: [String]) -> WorkoutContext {
        if let scenario = debugScenario(from: args),
           let context = ExecutionPreviewSeed.qaScenario(scenario) {
            return context
        }
        return ExecutionPreviewSeed.timingMode(debugTimingMode(from: args) ?? .straightSets)
    }

    private func debugTodayPlanContexts(now: Date) -> [WorkoutContext] {
        let calendar = Calendar(identifier: .gregorian)
        let today = ExecutionPreviewSeed.qaScenario("primitive_strength_density")
            ?? ExecutionPreviewSeed.pushA()
        let missed = ExecutionPreviewSeed.qaScenario("primitive_intervals")
            ?? ExecutionPreviewSeed.pushA()
        let upcoming = ExecutionPreviewSeed.qaScenario("primitive_carry_circuit")
            ?? ExecutionPreviewSeed.pushA()

        return [
            retitle(
                today,
                name: "Upper Hypertrophy Calibration",
                scheduledDate: now,
                tagsJSON: #"["upper","hypertrophy","bench_station"]"#,
                notes: "Heavy press work first, then controlled shoulder and arm volume. Stay near one bench station if the gym is busy."
            ),
            retitle(
                missed,
                name: "Missed Engine + Core",
                scheduledDate: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                tagsJSON: #"["endurance","core","reschedule"]"#,
                notes: "A missed conditioning day that can be reviewed, moved, or skipped without losing the rest of the week."
            ),
            retitle(
                upcoming,
                name: "Tomorrow Carries",
                scheduledDate: calendar.date(byAdding: .day, value: 1, to: now) ?? now,
                tagsJSON: #"["carries","conditioning","tomorrow"]"#,
                notes: "Loaded carry conditioning with clear bounded current-block progress."
            ),
        ]
    }

    private func retitle(
        _ context: WorkoutContext,
        name: String,
        scheduledDate: Date,
        tagsJSON: String,
        notes: String
    ) -> WorkoutContext {
        let workout = Workout(
            id: context.workout.id,
            userID: context.workout.userID,
            name: name,
            scheduledDate: scheduledDate,
            status: context.workout.status,
            source: context.workout.source,
            notes: notes,
            createdAt: context.workout.createdAt,
            updatedAt: context.workout.updatedAt,
            completedAt: context.workout.completedAt,
            tagsJSON: tagsJSON
        )
        return WorkoutContext(
            workout: workout,
            primitiveWorkout: context.primitiveWorkout,
            primitiveExecutionPlan: context.primitiveExecutionPlan,
            blocks: context.blocks,
            itemsByBlock: context.itemsByBlock,
            exercises: context.exercises,
            lastPerformed: context.lastPerformed,
            alternativesByItem: context.alternativesByItem,
            userParameters: context.userParameters
        )
    }

    private func todayContext(
        from context: WorkoutContext,
        binding: (@Sendable (SessionMutation) -> Void)?
    ) -> TodayContext {
        TodayContext(
            workout: context.workout,
            primitiveWorkout: context.primitiveWorkout,
            primitiveExecutionPlan: context.primitiveExecutionPlan,
            blocks: context.blocks,
            items: context.itemsByBlock.flatMap { $0 },
            exercises: context.exercises,
            lastPerformed: context.lastPerformed,
            lastSessionSummary: "last time: 45 lb × 8",
            programTags: debugProgramTags(from: context),
            userParameters: context.userParameters,
            sessionStateBinding: binding
        )
    }

    private func debugProgramTags(from context: WorkoutContext) -> [String] {
        guard let tagsJSON = context.workout.tagsJSON,
              let data = tagsJSON.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data)
        else {
            return ["qa"]
        }
        return tags.map { $0.replacingOccurrences(of: "_", with: " ") }
    }

    private func debugProgramTags(from args: [String]) -> [String] {
        if let scenario = debugScenario(from: args) {
            return ["qa", scenario.replacingOccurrences(of: "_", with: " ")]
        }
        if let mode = debugTimingMode(from: args) {
            return ["qa", mode.rawValue.replacingOccurrences(of: "_", with: " ")]
        }
        return ["qa", "straight sets"]
    }

    /// Accept either `--debug-mode emom` or `--debug-mode=emom` so
    /// simulator QA can jump directly into each timer mode.
    private func debugTimingMode(from args: [String]) -> TimingMode? {
        if let modeArg = args.first(where: { $0.hasPrefix("--debug-mode=") }) {
            return TimingMode(rawValue: String(modeArg.dropFirst("--debug-mode=".count)))
        }
        guard let idx = args.firstIndex(of: "--debug-mode"),
              args.indices.contains(args.index(after: idx))
        else {
            return nil
        }
        return TimingMode(rawValue: args[args.index(after: idx)])
    }

    /// Accept either `--debug-scenario timer_gauntlet_strength` or
    /// `--debug-scenario=timer_gauntlet_strength`. Scenario wins over
    /// `--debug-mode` because it seeds a full multi-block workout.
    private func debugScenario(from args: [String]) -> String? {
        if let scenarioArg = args.first(where: { $0.hasPrefix("--debug-scenario=") }) {
            return String(scenarioArg.dropFirst("--debug-scenario=".count))
        }
        guard let idx = args.firstIndex(of: "--debug-scenario"),
              args.indices.contains(args.index(after: idx))
        else {
            return nil
        }
        return args[args.index(after: idx)]
    }
}

private func emitDebugCompletionCacheWrite(
    _ record: WorkoutCompletionRecord,
    telemetry: TelemetryEmitter,
    write: @Sendable () async throws -> Void
) async {
    do {
        try await write()
        emitDebugCompletionCacheWriteEvent(record, telemetry: telemetry, errorDescription: nil)
    } catch {
        emitDebugCompletionCacheWriteEvent(
            record,
            telemetry: telemetry,
            errorDescription: String(describing: error)
        )
    }
}

private func emitDebugCompletionCacheWriteEvent(
    _ record: WorkoutCompletionRecord,
    telemetry: TelemetryEmitter,
    errorDescription: String?
) {
    let payload = DebugCompletionCacheWriteEventPayload(
        workoutID: record.workoutID.wireID,
        setLogCount: 0,
        primitiveSetLogCount: record.primitiveSetLogs.count,
        hasNote: record.notes != nil,
        error: errorDescription.map { String($0.prefix(240)) }
    )
    telemetry.emit(Event(
        sessionID: TelemetrySession.id,
        kind: errorDescription == nil ? "state" : "error",
        name: errorDescription == nil
            ? "execution.completion_local_cache_write_succeeded"
            : "execution.completion_local_cache_write_failed",
        dataJSON: encodeDebugTelemetryPayload(payload),
        workoutID: record.workoutID
    ))
}

private func encodeDebugTelemetryPayload<Payload: Encodable>(_ payload: Payload) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // swiftlint:disable:next force_try
    let data = try! encoder.encode(payload)
    // swiftlint:disable:next force_unwrapping
    return String(data: data, encoding: .utf8)!
}

private struct DebugCompletionCacheWriteEventPayload: Encodable {
    let workoutID: String
    let setLogCount: Int
    let primitiveSetLogCount: Int
    let hasNote: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case workoutID = "workout_id"
        case setLogCount = "set_log_count"
        case primitiveSetLogCount = "primitive_set_log_count"
        case hasNote = "has_note"
        case error
    }
}

#endif
