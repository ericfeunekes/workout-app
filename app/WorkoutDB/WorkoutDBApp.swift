// WorkoutDBApp.swift
//
// The iOS app shell. Per docs/architecture/swift-packages.md, shell targets
// stay thin — they compose packages and host the root view. All features,
// sync, persistence, and design system live in their own SwiftPM packages
// under app/Packages/.
//
// Forces dark color scheme — the design bundle is explicit about dark-only
// (gym lighting, per docs/design/BACKLOG.md § "Out of scope for v1").
//
// Routing (v0):
//   - No saved connection (`TokenStore.loadConnection == nil`) → FirstRunView
//   - Saved connection → run AppBootstrap → TodayView / ExecutionView
//
// Launch flow:
//   On launch the shell asks `TokenStore` whether a URL + bearer pair is
//   saved. If not, the whole UI is `FirstRunView` until its `onComplete`
//   fires; that callback flips `hasConnection` to true. Once `hasConnection`
//   is true, the shell enters the `.task` that runs `AppBootstrap.bootstrap`
//   — pull, write to cache, build Today + Execution view models, render.
//
// Error posture:
//   • AppBootstrap throws `tokenRejected` → mark auth recovery and drop
//     back to FirstRun with the existing connection prefilled.
//   • AppBootstrap returns `.empty` (pull failed + empty cache) → show a
//     minimal "no workouts yet" state. User can reopen the app after Claude
//     pushes a session.
//   • AppBootstrap returns `.ready` → render routed view.
//
// DEBUG launch args (`--start-active`, `--jump-rest`, `--jump-complete`)
// bypass bootstrap and use `ExecutionPreviewSeed.pushA()` directly — keeps
// screenshots fast and offline.
//
// Settings is mounted through `Shell.RootTabView`. The app shell owns the
// concrete persistence/bootstrap closures because Settings only depends on
// protocols and does not know about app-level phase transitions.

import SwiftUI
import CoreDomain
import CoreSession
import CoreTelemetry
import DesignSystem
import FeaturesExecution
import FeaturesFirstRun
import FeaturesHistory
import FeaturesSettings
import FeaturesToday
import HealthArchiveExport
import HealthKitBridge
import Persistence
import Shell
import Sync
import WatchBridge

@main
struct WorkoutDBApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Which high-level state the shell is in. Drives `RootView.body`.
private enum ShellPhase {
    /// No saved connection. Show FirstRun. The optional `prefill` carries
    /// the previously-entered URL + token when the user arrives here via
    /// the "change server" recovery button on `.empty`, so they don't
    /// retype values they likely just want to edit.
    case firstRun(prefill: FirstRunPrefill?)
    /// Saved connection, bootstrap not yet run (or running).
    case bootstrapping
    /// Bootstrap produced view models. `appSync` owns foreground pull
    /// policy and the periodic push cadence.
    ///
    /// `executionHolder` is an observable wrapper whose `vm` swaps
    /// per-workout after save-and-done (qa-002 / qa-003 fix). The shell
    /// retains the holder — not the raw VM — so post-save VM rebuilds
    /// performed by `AppBootstrap+Hooks.makeCompletionWriter` are
    /// visible to `RootTabView`'s body re-evaluation.
    case ready(
        todayVM: TodayViewModel,
        executionHolder: ExecutionVMHolder,
        appSync: AppSyncCoordinator
    )
    /// Bootstrap completed but nothing is cached and the server was
    /// unreachable — "no workouts yet" empty state.
    case empty(appSync: AppSyncCoordinator?)
    #if DEBUG
    /// DEBUG launch-arg path for the HealthKit simulator capability spike.
    case healthKitProbe
    /// DEBUG launch-arg fast-path. Uses the preview seed directly.
    ///
    /// Wraps the seeded VM in an `ExecutionVMHolder` so RootTabView's
    /// observation path is the same as production. The debug path
    /// doesn't exercise VM rebuild (there's no next workout queued in
    /// the seed), so `holder.vm` stays as the seeded instance forever.
    case debugSeed(todayVM: TodayViewModel, executionHolder: ExecutionVMHolder)
    #endif
}

/// Pre-fill the FirstRun inputs when returning there via the "change
/// server" recovery route on `.empty`. Both fields are strings (not a
/// typed URL) so the existing `validatedURL()` path runs unchanged when
/// the user taps connect.
struct FirstRunPrefill: Equatable {
    let url: String
    let token: String
}

/// The shell's composite view — owns the shell phase and routes between
/// FirstRun, bootstrap, and the live view models.
///
/// Double-bootstrap race (fixed 2026-04-18): flipping `phase` to
/// `.bootstrapping` re-renders the body into `BootstrapLoadingView`. When
/// that view had a `.task { await runBootstrap() }` modifier, both the
/// `onComplete` caller and the `.task` ran concurrently — two pulls, two
/// cache writes, a coin-flip on which `.ready(...)` assignment won. The
/// fix is two-fold:
///   1. `BootstrapLoadingView` is inert — it no longer kicks off work.
///      The sole initiators of `runBootstrap()` are `performLaunchCheck`
///      (on first appear with a saved connection) and `onComplete`
///      (fires when FirstRun succeeds).
///   2. `didStartBootstrap` is a belt-and-braces guard that early-returns
///      if a bootstrap is already running. It's cleared only by
///      `performLaunchCheck` resetting after a failed bootstrap wipes the
///      connection and routes back to FirstRun.
///
/// Note: this shell has no XCTest target of its own. The guard is verified
/// indirectly by the FirstRun re-entrancy test + the AppBootstrap tests in
/// the Shell package; if those go green, a second concurrent bootstrap
/// from this shell would show up as duplicate cache writes there. If this
/// becomes too indirect, extract the bootstrap orchestration into the
/// Shell package so it can be unit-tested with the `didStartBootstrap`
/// guard in hand.
struct RootView: View {

    @State private var phase: ShellPhase = .firstRun(prefill: nil)
    @State private var didPerformLaunchCheck: Bool = false
    @State private var didStartBootstrap: Bool = false
    @State private var lifecycleGeneration: Int = 0
    @State private var scenePhaseTask: Task<Void, Never>?
    @State private var healthArchiveRuntime: HealthArchiveExportRuntime?
    @Environment(\.scenePhase) private var scenePhase

    /// HistoryViewModel is hoisted to RootView so it survives body
    /// rebuilds. Previously it was constructed inline in `tabbedView`,
    /// which meant SwiftUI discarded its state (loaded sessions, filter
    /// selection) on every re-render AND made save-and-done → History
    /// auto-refresh impossible to wire (no stable reference).
    ///
    /// Internal (not `private`) so the DEBUG extension in
    /// `RootView+DebugLaunch.swift` can wire it into the debug-seed
    /// `localCompletionWriter`. Extensions in sibling files can only
    /// reach `internal` members.
    @State var historyVM: HistoryViewModel
    let watchBridge: LiveWatchBridge

    /// Shared persistence — the shell consults it on launch, passes it to
    /// AppBootstrap, and hands the TokenStore slice down to FirstRun.
    /// `internal` (default access) so DEBUG extensions in sibling files
    /// can read the shared factory without duplicating it.
    let persistence: PersistenceFactory

    init() {
        let persistence = Self.makePersistence()
        self.persistence = persistence
        self.watchBridge = LiveWatchBridge()
        self._historyVM = State(
            wrappedValue: HistoryViewModel(
                cache: persistence.workoutCache,
                telemetry: persistence.telemetryEmitter()
            )
        )
    }

    private static func makePersistence() -> PersistenceFactory {
        let environment = ProcessInfo.processInfo.environment
        let forceDefaultHealthKitProbeStore = environment[
            "WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE"
        ] == "1"
        if environment["XCTestConfigurationFilePath"] != nil && !forceDefaultHealthKitProbeStore {
            do {
                return try PersistenceFactory.makeInMemory()
            } catch {
                fatalError("PersistenceFactory.makeInMemory() failed under XCTest: \(error)")
            }
        }

        do {
            return try PersistenceFactory.makeDefault()
        } catch {
            fatalError("PersistenceFactory.makeDefault() failed: \(error)")
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .firstRun(let prefill):
                FirstRunView(viewModel: FirstRunViewModel(
                    tokenStore: persistence.tokenStore,
                    onComplete: {
                        Task { @MainActor in
                            let result = await AppSyncLocalStateReset.clearLocalServerData(
                                persistence: persistence
                            )
                            guard result.succeeded else {
                                await recoverAfterFailedLocalStateReset()
                                return
                            }
                            didStartBootstrap = false
                            phase = .bootstrapping
                            await runBootstrap()
                        }
                    },
                    initialURL: prefill?.url ?? "",
                    initialToken: prefill?.token ?? ""
                ))

            case .bootstrapping:
                // BootstrapLoadingView is intentionally inert — it does
                // NOT kick off `runBootstrap()` itself. See the double-
                // bootstrap race note on `RootView`.
                BootstrapLoadingView()

            #if DEBUG
            case .healthKitProbe:
                HealthKitProbeView(archiveStore: persistence.healthArchiveStore)
            #endif

            case .empty(let appSync):
                EmptyStateView(
                    onRetry: {
                        // User-initiated retry must be able to re-enter
                        // the bootstrap path, so clear the guard first.
                        // The async form lets EmptyStateView reset its
                        // local `isRetrying` after `runBootstrap` returns,
                        // which matters if the phase transitions
                        // `.empty → .empty` (failed retry) without a
                        // teardown — SwiftUI `@State` persists across
                        // identical view-identity renders, so the old
                        // behaviour relied on teardown that doesn't
                        // always happen.
                        didStartBootstrap = false
                        phase = .bootstrapping
                        lifecycleGeneration += 1
                        scenePhaseTask?.cancel()
                        await appSync?.retire(trigger: .emptyRetry)
                        await runBootstrap()
                    },
                    onChangeServer: {
                        await changeServer()
                    }
                )

            case .ready(let todayVM, let executionHolder, _):
                tabbedView(todayVM: todayVM, executionHolder: executionHolder)

            #if DEBUG
            case .debugSeed(let todayVM, let executionHolder):
                tabbedView(todayVM: todayVM, executionHolder: executionHolder)
            #endif
            }
        }
        .onAppear {
            guard !didPerformLaunchCheck else { return }
            didPerformLaunchCheck = true
            performLaunchCheck()
        }
        .onChange(of: scenePhase) { _, newPhase in
            scenePhaseTask?.cancel()
            let generation = lifecycleGeneration
            scenePhaseTask = Task { @MainActor in
                await handleScenePhase(newPhase, generation: generation)
            }
        }
    }

    // MARK: - Routed execution vs today

    /// Once bootstrap is done (or a DEBUG launch arg short-circuited
    /// it) we enter the three-tab root. `RootTabView` lives in `Shell`
    /// — the one package allowed to see multiple `Features/*` at once.
    @ViewBuilder
    private func tabbedView(
        todayVM: TodayViewModel,
        executionHolder: ExecutionVMHolder
    ) -> some View {
        RootTabView(
            todayVM: todayVM,
            executionHolder: executionHolder,
            historyVM: historyVM,
            settingsVM: makeSettingsViewModel()
        )
    }

    private func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            tokenStore: persistence.tokenStore,
            syncMetadata: persistence.syncMetadataStore,
            healthArchiveExportState: persistence.healthArchiveExportStateStore,
            healthArchiveDescriptorOptions: healthArchiveDescriptorOptions(),
            onSyncNow: { @MainActor in
                await rerunBootstrapFromReady()
            },
            onResetCache: { @MainActor in
                await resetLocalDataFromSettings()
            },
            onChangeServer: { @MainActor in
                await changeServer()
            },
            onHealthArchiveExportNow: { @MainActor in
                await exportHealthArchiveFromSettings()
            }
        )
    }

    // MARK: - Launch

    /// Consults TokenStore on the very first `onAppear`. In DEBUG the
    /// launch args can force-bypass the first-run gate; in release the
    /// gate is purely data-driven. When a saved connection exists we
    /// kick off `runBootstrap()` here — `BootstrapLoadingView` no longer
    /// initiates the work itself (see the double-bootstrap race note on
    /// `RootView`).
    private func performLaunchCheck() {
        var shouldRecreateLocalServerData = false
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let debugRoute = DebugLaunchRoute.classify(args: args)
        if debugRoute.bypassesFirstRun {
            if debugRoute.showsHealthKitProbe {
                phase = .healthKitProbe
            } else if debugRoute.usesDebugSeed {
                applyDebugLaunchArguments(args: args)
            } else {
                runStandaloneDebugProbes(args: args)
                phase = .empty(appSync: nil)
            }
            return
        }
        if let serverIdx = args.firstIndex(of: "--server"),
           serverIdx + 2 < args.count {
            let urlStr = args[serverIdx + 1]
            let token = args[serverIdx + 2]
            if let url = URL(string: urlStr) {
                try? persistence.tokenStore.saveConnection(url: url, token: token)
                shouldRecreateLocalServerData = true
            }
        }
        #endif
        do {
            if try persistence.tokenStore.loadConnection() != nil {
                if persistence.authRecoveryStore.isTokenRejected() {
                    phase = .firstRun(prefill: prefillForCurrentConnection())
                    return
                }
                phase = .bootstrapping
                Task { @MainActor in
                    if shouldRecreateLocalServerData {
                        let result = await AppSyncLocalStateReset.clearLocalServerData(
                            persistence: persistence
                        )
                        guard result.succeeded else {
                            await recoverAfterFailedLocalStateReset()
                            return
                        }
                    }
                    await runBootstrap()
                }
            } else {
                phase = .firstRun(prefill: nil)
            }
        } catch {
            // Keychain read failure — treat as no connection.
            phase = .firstRun(prefill: nil)
        }
    }

    // MARK: - Bootstrap

    /// Run the Sync pull → cache → build-view-models pipeline and update
    /// the phase accordingly. The `didStartBootstrap` guard early-returns
    /// if a run is already in flight — second concurrent invocations
    /// from any source (view re-render, stray Task, double-tap) no-op
    /// rather than racing.
    private func runBootstrap() async {
        guard !didStartBootstrap else { return }
        didStartBootstrap = true
        guard let connection = try? persistence.tokenStore.loadConnection() else {
            didStartBootstrap = false
            phase = .firstRun(prefill: nil)
            return
        }

        // Build the Today → Execution start binding up front. It needs a
        // stable reference to the CURRENT Execution view model — which
        // changes per-workout after save-and-done (qa-002 / qa-003 fix).
        // `ExecutionVMHolder` (from the Shell package) is the single
        // observable box both this binding and `RootTabView` read from,
        // so the post-save VM swap is visible to both.
        //
        // `executionHolder` is captured *strongly* below: the binding
        // outlives this function (it lives inside `TodayContext` inside the
        // `.ready` phase), and a weak capture would drop to nil the moment
        // `runBootstrap()` returns — silent no-op on every "start workout"
        // tap. The holder has no back-reference to the binding, so there
        // is no retain cycle; the holder is freed when `phase` drops the
        // `.ready` case.
        let executionHolder = ExecutionVMHolder()
        let binding: @Sendable (SessionMutation) -> Void = { mutation in
            guard case .start = mutation else { return }
            Task { @MainActor in
                executionHolder.vm?.start()
            }
        }

        await runBootstrapPipeline(
            connection: connection,
            binding: binding,
            executionHolder: executionHolder
        )
    }

    /// The do/catch half of `runBootstrap`. Extracted so the parent stays
    /// under SwiftLint's `function_body_length` cap.
    private func runBootstrapPipeline(
        connection: (url: URL, token: String),
        binding: @escaping @Sendable (SessionMutation) -> Void,
        executionHolder: ExecutionVMHolder
    ) async {
        // HistoryViewModel is a @MainActor class; closure-captures by
        // reference so a save-and-done write refreshes the SAME instance
        // the History tab is looking at (hoisted to RootView `@State`).
        let historyVM = self.historyVM
        do {
            let result = try await AppBootstrap.bootstrap(
                connection: connection,
                persistence: persistence,
                now: Date(),
                sessionStateBinding: binding,
                telemetryEmitter: persistence.telemetryEmitter(),
                afterLocalCompletion: { [historyVM] in
                    await historyVM.load()
                },
                onManualRefreshTokenRejected: {
                    await routeBackToFirstRunForTokenRejected()
                },
                onEmptyTodayRefresh: {
                    await rerunBootstrapFromReady()
                    return true
                },
                historyViewModel: historyVM,
                executionHolder: executionHolder,
                watchBridge: watchBridge
            )
            switch result {
            case .ready(let todayVM, let holder, let appSync):
                // The holder returned from bootstrap IS the one we passed
                // in — AppBootstrap populated `holder.vm` and wired the
                // post-save rebuild path. Kick off foreground flushing
                // without re-pulling; later scene-phase foreground entries
                // go through the full app-sync lifecycle.
                await appSync.startForegroundFlushing(trigger: .bootstrap)
                phase = .ready(
                    todayVM: todayVM,
                    executionHolder: holder,
                    appSync: appSync
                )
            case .empty(let appSync):
                await appSync.startForegroundFlushing(trigger: .bootstrap)
                phase = .empty(appSync: appSync)
            }
        } catch AppBootstrapError.tokenRejected {
            await AppSyncLocalStateReset.pauseForTokenRejected(persistence: persistence)
            didStartBootstrap = false
            phase = .firstRun(prefill: prefillForCurrentConnection())
        } catch {
            // Any other error here is unexpected — bootstrap is supposed
            // to absorb transport failures and return `.empty`. Treat as
            // empty so the user at least sees *something* and can try
            // relaunching. Leave `didStartBootstrap` set; the retry
            // button on EmptyStateView clears it before re-entering.
            phase = .empty(appSync: nil)
        }
    }

    private func routeBackToFirstRunForTokenRejected() async {
        lifecycleGeneration += 1
        scenePhaseTask?.cancel()
        healthArchiveRuntime = nil
        await currentAppSync()?.retire(trigger: .manualTodayRefresh)
        await AppSyncLocalStateReset.pauseForTokenRejected(persistence: persistence)
        didStartBootstrap = false
        phase = .firstRun(prefill: prefillForCurrentConnection())
    }

    private func rerunBootstrapFromReady() async {
        lifecycleGeneration += 1
        scenePhaseTask?.cancel()
        healthArchiveRuntime = nil
        await currentAppSync()?.retire()
        didStartBootstrap = false
        phase = .bootstrapping
        await runBootstrap()
    }

    private func resetLocalDataFromSettings() async {
        lifecycleGeneration += 1
        scenePhaseTask?.cancel()
        healthArchiveRuntime = nil
        await currentAppSync()?.retire()
        let result = await AppSyncLocalStateReset.clearLocalServerData(persistence: persistence)
        guard result.succeeded else {
            await recoverAfterFailedLocalStateReset()
            return
        }
        await historyVM.load()
        didStartBootstrap = false
        phase = .bootstrapping
        await runBootstrap()
    }

    private func currentAppSync() -> AppSyncCoordinator? {
        switch phase {
        case .ready(_, _, let appSync):
            return appSync
        case .empty(let appSync):
            return appSync
        case .firstRun, .bootstrapping:
            return nil
        #if DEBUG
        case .debugSeed, .healthKitProbe:
            return nil
        #endif
        }
    }

    private func currentHealthArchiveExport() -> (any HealthArchiveExportControlling)? {
        guard let appSync = currentAppSync() else {
            return nil
        }
        if let healthArchiveRuntime {
            return healthArchiveRuntime
        }
        let runtime = HealthArchiveExportFactory.live(
            archiveStore: persistence.healthArchiveStore,
            stateStore: persistence.healthArchiveExportStateStore,
            syncAPI: appSync.syncAPI,
            telemetry: persistence.telemetryEmitter()
        )
        healthArchiveRuntime = runtime
        return runtime
    }

    private func exportHealthArchiveFromSettings() async {
        _ = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: currentHealthArchiveExport,
            tokenStore: persistence.tokenStore
        )
    }

    private func healthArchiveDescriptorOptions() -> [HealthArchiveDescriptorOption] {
        HealthArchiveDescriptorCatalog.supportedBatchDescriptors.map {
            HealthArchiveDescriptorOption(id: $0.type.id, label: $0.label)
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase, generation: Int) async {
        guard let appSync = currentAppSync() else { return }
        guard generation == lifecycleGeneration else { return }
        let startedFromEmpty: Bool
        if case .empty = phase {
            startedFromEmpty = true
        } else {
            startedFromEmpty = false
        }
        switch newPhase {
        case .active:
            let result = await appSync.enterForeground()
            guard generation == lifecycleGeneration else { return }
            if case .foreground(refresh: .tokenRejected) = result {
                await routeBackToFirstRunForTokenRejected()
                return
            }
            await runHealthArchiveForegroundCatchUp()
            if startedFromEmpty,
               case .foreground(refresh: .pulled) = result {
                await promoteEmptyAfterForegroundPull(generation: generation)
            }
        case .background:
            _ = await appSync.enterBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func promoteEmptyAfterForegroundPull(generation: Int) async {
        guard generation == lifecycleGeneration else { return }
        lifecycleGeneration += 1
        await currentAppSync()?.retire(trigger: .foreground)
        didStartBootstrap = false
        phase = .bootstrapping
        await runBootstrap()
    }

    private func runHealthArchiveForegroundCatchUp() async {
        _ = await HealthArchiveAppHooks.foregroundCatchUp(
            controllerProvider: currentHealthArchiveExport,
            tokenStore: persistence.tokenStore
        )
    }

    #if DEBUG
    /// Debug-only: honor launch args like `--start-active` so screenshots
    /// can jump to a specific route without tap automation.
    ///
    /// Wires a `localCompletionWriter` that persists the completed workout
    /// to an in-memory `PersistenceFactory`'s `WorkoutCache`, so the debug
    /// path exercises the same save-and-done → History round-trip as real
    /// runtime. Without this, `--jump-complete` → `save & done` → History
    /// would show the empty state even though the save path works — making
    /// E2E screenshot verification impossible to distinguish from a bug.
    private func applyDebugLaunchArguments(args: [String]) {
        let (todayVM, executionHolder) = buildDebugSeedViewModels(args: args)
        if let vm = executionHolder.vm {
            applyDebugLaunchJumps(args: args, executionVM: vm)
        }
        sendDebugWatchPayloadIfRequested(args: args)
        runDebugWorkoutKitProbeIfRequested(args: args)
        phase = .debugSeed(todayVM: todayVM, executionHolder: executionHolder)
    }

    private func runStandaloneDebugProbes(args: [String]) {
        sendDebugWatchPayloadIfRequested(args: args)
        runDebugWorkoutKitProbeIfRequested(args: args)
    }
    #endif
}

// MARK: - Change server recovery
//
// Extracted to an extension so RootView's struct body stays under
// SwiftLint's `type_body_length` cap. Only `changeServer()` is needed
// externally — it uses `@MainActor`-isolated `@State` writes on the
// owning view.

extension RootView {

    /// Bail out of `.empty` back to FirstRun so the user can point at a
    /// different server (or fix a typo) without force-quitting. Captures
    /// the current saved URL + token so FirstRun pre-fills its fields
    /// rather than forcing the user to retype.
    ///
    /// Order of operations is deliberate: capture prefill first, clear all
    /// server-owned local state, clear the token last, then route to FirstRun.
    /// HealthKit archive data is preserved because HealthKit, not the server,
    /// is authoritative for those samples.
    func changeServer() async {
        let prefill: FirstRunPrefill
        if let existing = try? persistence.tokenStore.loadConnection() {
            prefill = FirstRunPrefill(
                url: existing.url.absoluteString,
                token: existing.token
            )
        } else {
            prefill = FirstRunPrefill(url: "", token: "")
        }
        lifecycleGeneration += 1
        scenePhaseTask?.cancel()
        healthArchiveRuntime = nil
        await currentAppSync()?.retire()
        let result = await AppSyncLocalStateReset.clearConnectionAndLocalServerData(
            persistence: persistence
        )
        guard result.succeeded else {
            await recoverAfterFailedLocalStateReset()
            return
        }
        await historyVM.load()
        didStartBootstrap = false
        phase = .firstRun(prefill: prefill)
    }

    private func prefillForCurrentConnection() -> FirstRunPrefill? {
        guard let existing = try? persistence.tokenStore.loadConnection() else {
            return nil
        }
        return FirstRunPrefill(
            url: existing.url.absoluteString,
            token: existing.token
        )
    }

    private func recoverAfterFailedLocalStateReset() async {
        await historyVM.load()
        didStartBootstrap = false
        phase = .firstRun(prefill: prefillForCurrentConnection())
    }
}

// MARK: - Tiny transient views

/// Minimal loading card while AppBootstrap runs. Kept as a stub rather
/// than a full DesignSystem screen because it's visible for <1s on a good
/// network.
private struct BootstrapLoadingView: View {
    var body: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
            Text("Syncing…")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColors.background)
    }
}

/// Shown when bootstrap returned `.empty` — nothing cached and the server
/// was unreachable. The primary "try again" button re-enters
/// `runBootstrap()` (clearing the `didStartBootstrap` guard first, see
/// `RootView.body`); the ghost "change server" button routes back to
/// FirstRun so the user can point at a different server or fix a typo
/// without force-quitting (closes `open-questions.md` § "Empty-cache
/// state dead end" partially; broader Settings recovery remains tracked in
/// `SETTINGS-GAP-002`).
///
/// `isRetrying` locally disables both buttons while either async closure
/// is running so rapid taps cannot enqueue parallel bootstraps / change-
/// server calls from this surface. The async-closure shape ensures
/// `isRetrying` resets deterministically when the caller returns, rather
/// than relying on SwiftUI tearing down `@State` on a phase transition.
private struct EmptyStateView: View {
    let onRetry: @MainActor () async -> Void
    let onChangeServer: @MainActor () async -> Void
    @State private var isBusy = false

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            VStack(spacing: DSSpacing.md) {
                Text("No workouts yet")
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                Text("Ask Claude to push a session, then retry.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DSSpacing.lg)
            }
            VStack(spacing: DSSpacing.md) {
                DSButton(
                    title: "try again",
                    style: .primary,
                    disabled: isBusy,
                    action: {
                        guard !isBusy else { return }
                        isBusy = true
                        Task { @MainActor in
                            await onRetry()
                            isBusy = false
                        }
                    }
                )
                DSButton(
                    title: "change server",
                    style: .ghost,
                    disabled: isBusy,
                    action: {
                        guard !isBusy else { return }
                        isBusy = true
                        Task { @MainActor in
                            await onChangeServer()
                            isBusy = false
                        }
                    }
                )
            }
            .padding(.horizontal, DSSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColors.background)
    }
}
