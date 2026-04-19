// AppBootstrap.swift
//
// One-shot composition the app shell runs after FirstRun confirms a saved
// connection (or on launch when the connection is already present). Does:
//
//   1. Build the Sync stack (URLSessionTransport + SyncAPI) over the saved
//      URL + bearer.
//   2. Call `SyncAPI.pullLatest(since: lastSyncAt)`.
//   3. On success — save pulled DTOs → Domain values → `WorkoutCache`, and
//      record `serverTime` as the new `lastSyncAt`.
//   4. Build the Today context via `TodayLoader` and the matching
//      `WorkoutContext` for Execution by flattening the same chosen
//      workout's blocks + items.
//   5. Construct `TodayViewModel` + `ExecutionViewModel` and return them.
//
// Error posture (matches the ADR and `docs/sync.md` § "Auth posture"):
//   • `.tokenRejected` → throw `AppBootstrapError.tokenRejected` so the
//     shell can clear the saved connection and route back to FirstRun.
//   • `.network`, `.server`, `.decode`, `.encode` → fall through and use
//     whatever is already cached. If the cache is also empty, return a
//     `.empty` result so the shell can render "no workouts yet".
//
// The view models are built on the MainActor — both `TodayViewModel` and
// `ExecutionViewModel` require it — so the whole bootstrap is MainActor
// to keep the call site simple. The heavy work (network + cache writes)
// still awaits off the MainActor through the injected transport + cache
// actors.

import Foundation
import CoreDomain
import CoreSession
import CoreTelemetry
import FeaturesExecution
import FeaturesHistory
import FeaturesToday
import Persistence
import Sync
import WorkoutCoreFoundation

/// Possible outcomes of a launch-time bootstrap.
///
/// `tokenRejected` is signalled via `throws`, not a case here — the shell
/// must act on it (clear the saved connection) before showing any UI, so
/// it's modeled as an error.
public enum BootstrapResult: Sendable {
    /// Pull (or cache) produced a planned workout — the holder carries
    /// the initial `ExecutionViewModel` and the post-save completion
    /// writer reassigns `holder.vm` to a freshly-built VM per-workout.
    /// `RootTabView` observes the holder so the swap takes effect
    /// without a relaunch. The `pushFlusher` owns the periodic push
    /// cadence; the shell should `await pushFlusher.start()` on ready
    /// and `stop()` when the connection is wiped.
    case ready(
        todayVM: TodayViewModel,
        executionHolder: ExecutionVMHolder,
        pushFlusher: PushFlusher
    )
    /// Pull failed AND nothing is cached. The shell renders a "no
    /// workouts yet" empty state.
    case empty
}

/// Errors the shell acts on. Everything else the bootstrap eats and
/// either falls back to cache or returns `.empty`.
public enum AppBootstrapError: Error, Equatable, Sendable {
    /// 401 from the server. Shell must clear the saved connection and
    /// route back to FirstRun.
    case tokenRejected
}

@MainActor
public enum AppBootstrap {

    /// Run the full bootstrap pipeline. See the file header for the
    /// decision tree. `transportBuilder` is injected so tests can swap in
    /// a fake; production callers use the default (`URLSessionTransport`).
    public static func bootstrap(
        connection: (url: URL, token: String),
        persistence: PersistenceFactory,
        now: Date = Date(),
        transportBuilder: @Sendable (URL) -> any HTTPTransport = { url in
            URLSessionTransport(baseURL: url)
        },
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)? = nil,
        telemetryEmitter: TelemetryEmitter = NoopTelemetryEmitter(),
        afterLocalCompletion: (@Sendable () async -> Void)? = nil,
        historyViewModel: HistoryViewModel? = nil,
        executionHolder: ExecutionVMHolder? = nil
    ) async throws -> BootstrapResult {
        // Complete the telemetry emitter → push queue wire-up BEFORE the
        // first emit. `PersistenceFactory.prepareTelemetry()` is idempotent
        // and cheap after the first call; without this call, the very
        // first `bootstrap.start` event landed in the local EventModel row
        // but lost the race against the emitter's fire-and-forget attach
        // Task and never reached the push queue. Callers that somehow
        // bypass `bootstrap(...)` (DEBUG seeds, previews) stay on the old
        // "attach best-effort" behavior — no correctness cost because they
        // never hit a real server anyway.
        await persistence.prepareTelemetry()
        emitBootstrap(telemetryEmitter, name: "bootstrap.start")
        let syncAPI = SyncAPI(
            transport: transportBuilder(connection.url),
            store: persistence.pushQueueStore,
            tokenProvider: { connection.token },
            telemetry: telemetryEmitter
        )

        wireHistoryEditHook(historyViewModel, syncAPI: syncAPI)

        try await runPull(
            syncAPI: syncAPI,
            persistence: persistence,
            telemetry: telemetryEmitter
        )

        let loader = TodayLoader(
            cache: persistence.workoutCache,
            lastPerformedStore: persistence.lastPerformedStore,
            clock: { now }
        )
        guard let todayContext = try await loader.load(
            sessionStateBinding: sessionStateBinding
        ) else {
            return try await resolveNoPlannedWorkout(
                persistence: persistence, syncAPI: syncAPI,
                telemetry: telemetryEmitter,
                sessionStateBinding: sessionStateBinding,
                executionHolder: executionHolder
            )
        }
        return try await assembleReady(AssembleInputs(
            todayContext: todayContext,
            todayLoader: loader,
            persistence: persistence,
            syncAPI: syncAPI,
            telemetry: telemetryEmitter,
            afterLocalCompletion: afterLocalCompletion,
            executionHolder: executionHolder
        ))
    }

    /// Grouped args for `assembleReady`. Keeps the helper under
    /// SwiftLint's `function_parameter_count` cap.
    private struct AssembleInputs {
        let todayContext: TodayContext
        let todayLoader: TodayLoader
        let persistence: PersistenceFactory
        let syncAPI: SyncAPI
        let telemetry: TelemetryEmitter
        let afterLocalCompletion: (@Sendable () async -> Void)?
        let executionHolder: ExecutionVMHolder?
    }

    /// Post-load assembly. Extracted so `bootstrap(...)` stays under
    /// SwiftLint's `function_body_length` cap. Builds the execution
    /// `WorkoutContext`, emits `bootstrap.ready`, and composes the view
    /// models via `buildReady`.
    private static func assembleReady(
        _ inputs: AssembleInputs
    ) async throws -> BootstrapResult {
        let workoutContext = try await buildWorkoutContext(
            for: inputs.todayContext.workout,
            cache: inputs.persistence.workoutCache,
            lastPerformedStore: inputs.persistence.lastPerformedStore
        )
        emitBootstrap(
            inputs.telemetry,
            name: "bootstrap.ready",
            workoutID: inputs.todayContext.workout.id
        )
        return await buildReady(ReadyInputs(
            todayContext: inputs.todayContext,
            workoutContext: workoutContext,
            todayLoader: inputs.todayLoader,
            sessionStore: inputs.persistence.sessionStore,
            workoutCache: inputs.persistence.workoutCache,
            lastPerformedStore: inputs.persistence.lastPerformedStore,
            syncAPI: inputs.syncAPI,
            telemetry: inputs.telemetry,
            afterLocalCompletion: inputs.afterLocalCompletion,
            executionHolder: inputs.executionHolder ?? ExecutionVMHolder()
        ))
    }

    /// Pull-once helper. Any failure falls through to the cache *except*
    /// tokenRejected, which we rethrow so the shell can route back to
    /// FirstRun. Extracted so `bootstrap` stays under
    /// `function_body_length`.
    private static func runPull(
        syncAPI: SyncAPI,
        persistence: PersistenceFactory,
        telemetry: TelemetryEmitter
    ) async throws {
        do {
            let lastSyncAt = await persistence.syncMetadataStore.getLastSyncAt()
            let result = try await syncAPI.pullLatest(since: lastSyncAt)
            try await savePull(result, into: persistence.workoutCache)
            // Persist the per-exercise "LAST · …" chip map alongside the
            // workout rows (qa-001 + qa-020). The server's contract is a
            // full snapshot over all exercises referenced by the user's
            // non-completed workouts (see `api/sync.py::_build_last_performed`),
            // so a non-empty response is authoritative — we rewrite.
            //
            // An EMPTY `result.lastPerformed`, however, can also legitimately
            // mean "no completed history yet for any visible exercise" on a
            // fresh account. To tell the two apart we'd need a richer
            // contract; instead we take the conservative route and keep
            // whatever's already stored when the server sent nothing. That
            // way a transient server regression (or an old server that
            // still scopes by delta) can't wipe the chips. The cost is a
            // stale chip after all completed history is server-deleted,
            // which is acceptable — the next real pull rewrites.
            if !result.lastPerformed.isEmpty {
                let lastPerformedMap = LastPerformedFormatter.buildMap(
                    from: result.lastPerformed
                )
                await persistence.lastPerformedStore.save(lastPerformedMap)
            }
            await persistence.syncMetadataStore.setLastSyncAt(result.serverTime)
        } catch SyncError.tokenRejected {
            telemetry.emit(Event(
                sessionID: TelemetrySession.id,
                kind: "error",
                name: "bootstrap.token_rejected"
            ))
            throw AppBootstrapError.tokenRejected
        } catch {
            // Transport / decode / server errors: fall through silently.
            // Cached data (if any) is still usable — that's the offline
            // contract from `docs/specs/v2-architecture.md` § "Sync model".
        }
    }

    /// Wire the History edit hook onto the shell-owned
    /// `HistoryViewModel`. The VM is constructed at RootView init
    /// (bug-016 — hoisted to `@State` so it survives body rebuilds),
    /// but `SyncAPI` doesn't exist until bootstrap runs. Setting the
    /// hook here is the narrowest plumbing that closes bug-015 without
    /// re-architecting the VM lifetime. Same deterministic-UUID
    /// contract as the Execution log push: the edited SetLog carries
    /// the original log's id, so the server upserts in place.
    private static func wireHistoryEditHook(
        _ historyViewModel: HistoryViewModel?,
        syncAPI: SyncAPI
    ) {
        guard let historyViewModel else { return }
        historyViewModel.setSetLogEditHook({ [syncAPI] log in
            try? await syncAPI.pushLog([log])
        })
    }

    /// One-liner for bootstrap.* state events. Keeps the call sites tight.
    /// Not `private` so `+Hooks.swift` can call it for the qa-027
    /// `.ready_empty_today` event without duplicating the stanza.
    static func emitBootstrap(
        _ emitter: TelemetryEmitter, name: String, workoutID: UUID? = nil
    ) {
        emitter.emit(Event(
            sessionID: TelemetrySession.id, kind: "state",
            name: name, workoutID: workoutID
        ))
    }

    // `ReadyInputs`, `buildReady`, and `CompletionWriterBox` live in
    // `AppBootstrap+Hooks.swift` so this main file stays under SwiftLint's
    // `type_body_length` cap for the enum body.

    // MARK: - Pull → cache

    /// Flatten `PullResult` into `WorkoutCache.save(...)`.
    ///
    /// `MappedWorkout` already bundles the workout + blocks + items +
    /// alternatives for one workout; we concatenate across all pulled
    /// workouts and hand the single batch to the cache so the `save` is
    /// one transaction.
    private static func savePull(
        _ result: PullResult,
        into cache: WorkoutCache
    ) async throws {
        var workouts: [Workout] = []
        var blocks: [Block] = []
        var items: [WorkoutItem] = []
        var alternatives: [ExerciseAlternative] = []
        for mapped in result.workouts {
            workouts.append(mapped.workout)
            blocks.append(contentsOf: mapped.blocks)
            items.append(contentsOf: mapped.items)
            alternatives.append(contentsOf: mapped.alternatives)
        }
        try await cache.save(
            PulledDataset(
                workouts: workouts,
                blocks: blocks,
                items: items,
                alternatives: alternatives,
                exercises: result.exercises,
                userParameters: result.userParameters
            )
        )
    }

    // MARK: - Today context → WorkoutContext

    /// Read blocks + items for the given workout and shape them into a
    /// `WorkoutContext`. Block order matches `blocks.position`; items
    /// within each block match `items.position`. `cache.loadBlocks` and
    /// `loadItems` already return sorted rows.
    ///
    /// `lastPerformedStore` is optional so tests / previews that don't
    /// care about the chip can skip wiring it — the SwapSheet "LAST ·
    /// …" line and ActiveView's last-time chip both render off
    /// `WorkoutContext.lastPerformed`, which simply stays empty when
    /// the store is absent (qa-001 + qa-020).
    ///
    /// Visible to the `+Hooks.swift` extension so the post-save
    /// completion writer can reuse the same assembly logic when
    /// rebuilding the ExecutionViewModel for the next workout.
    static func buildWorkoutContext(
        for workout: Workout,
        cache: WorkoutCache,
        lastPerformedStore: LastPerformedStore? = nil
    ) async throws -> WorkoutContext {
        let blocks = try await cache.loadBlocks(workoutID: workout.id)
        let loaded = try await loadItemsAndAlternatives(blocks: blocks, cache: cache)
        let catalog = try await cache.loadExercises()
        let exercises = Dictionary(
            uniqueKeysWithValues: catalog
                .filter { loaded.allExerciseIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let lastPerformed = await lastPerformedStore?.load() ?? [:]
        // qa-045: load latest-per-key user_parameters so the
        // `percent_1rm` resolver in `SessionSeeder` can convert
        // `{sets:3, reps:5, percent_1rm:0.6}` into a concrete load
        // via `1rm_<slug>_kg * percent`. Keeping the numeric coercion
        // local (rather than handing raw `UserParameter` rows through)
        // lets the seeder stay ignorant of the UserParameter shape
        // and tolerant of unparseable values — a bad row just drops
        // the key from the map and the item falls back to BW.
        let rawParams = (try? await cache.loadUserParametersLatest()) ?? [:]
        var numericParams: [String: Double] = [:]
        for (key, param) in rawParams {
            if let value = Double(param.value) {
                numericParams[key] = value
            }
        }
        return WorkoutContext(
            workout: workout,
            blocks: blocks,
            itemsByBlock: loaded.itemsByBlock,
            exercises: exercises,
            lastPerformed: lastPerformed,
            alternativesByItem: loaded.alternativesByItem,
            userParameters: numericParams
        )
    }

}

// MARK: - Loading helpers
//
// Split into an extension so the `AppBootstrap` enum body itself stays
// under SwiftLint's `type_body_length` cap.

@MainActor
extension AppBootstrap {
    struct LoadedItems {
        let itemsByBlock: [[WorkoutItem]]
        let alternativesByItem: [UUID: [ExerciseAlternative]]
        let allExerciseIDs: Set<UUID>
    }

    static func loadItemsAndAlternatives(
        blocks: [Block],
        cache: WorkoutCache
    ) async throws -> LoadedItems {
        var itemsByBlock: [[WorkoutItem]] = []
        var alternativesByItem: [UUID: [ExerciseAlternative]] = [:]
        var allExerciseIDs: Set<UUID> = []
        for block in blocks {
            let items = try await cache.loadItems(blockID: block.id)
            itemsByBlock.append(items)
            for item in items {
                allExerciseIDs.insert(item.exerciseID)
                let alts = try await cache.loadAlternatives(workoutItemID: item.id)
                if alts.isEmpty { continue }
                alternativesByItem[item.id] = alts
                for alt in alts { allExerciseIDs.insert(alt.exerciseID) }
            }
        }
        return LoadedItems(
            itemsByBlock: itemsByBlock,
            alternativesByItem: alternativesByItem,
            allExerciseIDs: allExerciseIDs
        )
    }
}
