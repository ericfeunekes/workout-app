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
//   • AppBootstrap throws `tokenRejected` → clear the TokenStore and drop
//     back to FirstRun. User re-enters creds.
//   • AppBootstrap returns `.empty` (pull failed + empty cache) → show a
//     minimal "no workouts yet" state. User can reopen the app after Claude
//     pushes a session.
//   • AppBootstrap returns `.ready` → render routed view.
//
// DEBUG launch args (`--start-active`, `--jump-rest`, `--jump-complete`)
// bypass bootstrap and use `ExecutionPreviewSeed.pushA()` directly — keeps
// screenshots fast and offline.
//
// TODO(settings): `FeaturesSettings.SettingsView` exists but has no entry
// point yet. Add a gear icon to the Today header (or a nav-bar button on
// the shell) that presents SettingsView in a `.sheet`. Wire `onSyncNow`
// to `AppBootstrap.pull`, `onResetCache` to `WorkoutCache.clear`, and
// `onChangeServer` to `TokenStore.clear` + cache clear + flip hasConnection
// back to false so FirstRun re-renders. Pass
// `PersistenceFactory.syncMetadataStore` in as `syncMetadata:` — the view
// model reads it on `.task` via `refreshAsync()`. Deferred until
// sync-integration lands so this slice doesn't collide with its RootView
// rewrite.

import SwiftUI
import CoreDomain
import CoreSession
import CoreTelemetry
import DesignSystem
import FeaturesExecution
import FeaturesFirstRun
import FeaturesHistory
import FeaturesToday
import Persistence
import Shell
import Sync

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
    /// Bootstrap produced view models. `pushFlusher` is the periodic
    /// foreground push cadence — the shell retains it so it survives
    /// view re-renders and can be stopped on server-change.
    ///
    /// `executionHolder` is an observable wrapper whose `vm` swaps
    /// per-workout after save-and-done (qa-002 / qa-003 fix). The shell
    /// retains the holder — not the raw VM — so post-save VM rebuilds
    /// performed by `AppBootstrap+Hooks.makeCompletionWriter` are
    /// visible to `RootTabView`'s body re-evaluation.
    case ready(
        todayVM: TodayViewModel,
        executionHolder: ExecutionVMHolder,
        pushFlusher: PushFlusher
    )
    /// Bootstrap completed but nothing is cached and the server was
    /// unreachable — "no workouts yet" empty state.
    case empty
    #if DEBUG
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

    /// Shared persistence — the shell consults it on launch, passes it to
    /// AppBootstrap, and hands the TokenStore slice down to FirstRun.
    /// `internal` (default access) so DEBUG extensions in sibling files
    /// can read the shared factory without duplicating it.
    let persistence: PersistenceFactory

    init() {
        let persistence = Self.makePersistence()
        self.persistence = persistence
        self._historyVM = State(
            wrappedValue: HistoryViewModel(
                cache: persistence.workoutCache,
                telemetry: persistence.telemetryEmitter()
            )
        )
    }

    private static func makePersistence() -> PersistenceFactory {
        do {
            return try PersistenceFactory.makeDefault()
        } catch {
            // SwiftData should not fail at module load. If it does, fall
            // back to in-memory so the app at least launches — the user
            // sees the empty state rather than a crash.
            do {
                return try PersistenceFactory.makeInMemory()
            } catch {
                // In-memory SwiftData failing means the SwiftData runtime
                // itself is broken — there is no meaningful fallback and
                // the app cannot function. Crash loudly so the failure is
                // obvious rather than producing silent misbehaviour.
                fatalError("PersistenceFactory.makeInMemory() failed: \(error)")
            }
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

            case .empty:
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
    }

    // MARK: - Routed execution vs today

    /// Once bootstrap is done (or a DEBUG launch arg short-circuited
    /// it) we enter the three-tab root. The History tab is the fifth
    /// and final v1 Feature; Settings remains TODO-wired per the shell
    /// header note. `RootTabView` lives in `Shell` — the one package
    /// allowed to see multiple `Features/*` at once.
    @ViewBuilder
    private func tabbedView(
        todayVM: TodayViewModel,
        executionHolder: ExecutionVMHolder
    ) -> some View {
        RootTabView(
            todayVM: todayVM,
            executionHolder: executionHolder,
            historyVM: historyVM
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
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let forceBypass = args.contains("--start-active")
            || args.contains("--jump-rest")
            || args.contains("--jump-complete")
        if forceBypass {
            applyDebugLaunchArguments(args: args)
            return
        }
        #endif
        do {
            if try persistence.tokenStore.loadConnection() != nil {
                phase = .bootstrapping
                Task { @MainActor in await runBootstrap() }
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
                historyViewModel: historyVM,
                executionHolder: executionHolder
            )
            switch result {
            case .ready(let todayVM, let holder, let pushFlusher):
                // The holder returned from bootstrap IS the one we passed
                // in — AppBootstrap populated `holder.vm` and wired the
                // post-save rebuild path. Kick off the periodic foreground
                // flusher — per `docs/sync.md` § "Cadence", every ~60s
                // while foregrounded.
                await pushFlusher.start()
                phase = .ready(
                    todayVM: todayVM,
                    executionHolder: holder,
                    pushFlusher: pushFlusher
                )
            case .empty:
                phase = .empty
            }
        } catch AppBootstrapError.tokenRejected {
            // Server rejected our saved credentials. Wipe the connection
            // and drop back to FirstRun. Clear the bootstrap guard so the
            // FirstRun success callback can re-enter.
            try? persistence.tokenStore.clear()
            didStartBootstrap = false
            phase = .firstRun(prefill: nil)
        } catch {
            // Any other error here is unexpected — bootstrap is supposed
            // to absorb transport failures and return `.empty`. Treat as
            // empty so the user at least sees *something* and can try
            // relaunching. Leave `didStartBootstrap` set; the retry
            // button on EmptyStateView clears it before re-entering.
            phase = .empty
        }
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
        let (todayVM, executionHolder) = buildDebugSeedViewModels()
        if let vm = executionHolder.vm {
            applyDebugLaunchJumps(args: args, executionVM: vm)
        }
        phase = .debugSeed(todayVM: todayVM, executionHolder: executionHolder)
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
    /// Order of operations is deliberate:
    ///   1. Read the current connection for pre-fill BEFORE clearing it.
    ///   2. Clear `TokenStore` so a subsequent launch (or a failed new
    ///      connect) cannot accidentally re-enter bootstrap with the
    ///      stale pair.
    ///   3. Wipe the local `WorkoutCache`. Per `docs/sync.md` §
    ///      "Changing servers" pointing at a different server is
    ///      equivalent to switching users, so the cached workouts /
    ///      blocks / items / set_logs must go.
    ///   4. Reset `didStartBootstrap` so the new FirstRun's onComplete
    ///      can re-enter `runBootstrap()`.
    ///   5. Flip phase. The new FirstRun VM sees `prefill` and pre-fills
    ///      both fields.
    ///
    /// Known gap: `lastSyncAt` on the shared `UserDefaults`-backed
    /// `SyncMetadataStore` is not reset here (that API has no `clear()`).
    /// If the user picks a *different* server, the stale `lastSyncAt`
    /// causes the next pull to fetch only deltas after that timestamp.
    /// Acceptable for the `.empty → change server` recovery path where
    /// the empty state typically means `lastSyncAt` is nil anyway (no
    /// successful pull ever produced a serverTime). Full "change server"
    /// handling (settings surface + dated warning) is the open-question
    /// item already in `docs/open-questions.md` § "Empty-cache state
    /// dead end".
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
        try? persistence.tokenStore.clear()
        try? await persistence.workoutCache.clear()
        didStartBootstrap = false
        phase = .firstRun(prefill: prefill)
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
/// state dead end" partially — Settings remains TODO).
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
