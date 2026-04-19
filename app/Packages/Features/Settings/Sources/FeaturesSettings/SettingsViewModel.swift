// SettingsViewModel.swift
//
// Drives the Settings screen. Owns all dependencies (TokenStore, autoreg
// defaults, units preference, build info) and turns them into a pure
// `[SettingsSection]` that the view renders with no branching of its own.
//
// Why a single `sections` array: HS-4 ("settings mega-view") — adding a row
// is appending a value, not editing a large SwiftUI body. The view is dumb.
// The viewModel re-derives the array whenever underlying state changes
// (`rebuild()` is called on every mutation).
//
// Destructive confirmations funnel through `showDestructiveConfirm`. The
// view displays an alert / confirm dialog when non-nil and invokes
// `onConfirm` on yes. The viewModel never runs a destructive action
// without a matching confirm being presented first.
//
// Parallel sync-integration slice note: the brief is explicit that the
// real "sync now" / "reset cache" / "change server" plumbing is still in
// flight. This viewModel accepts closures for those so the shell can wire
// them to the real services once the slice lands, and tests can verify the
// closure was called without any network I/O.

import Foundation
import Persistence

/// View model for the Settings screen. `@Observable` so SwiftUI's
/// observation tracking picks up `sections` and `showDestructiveConfirm`
/// mutations without a manual `objectWillChange.send()`.
///
/// `Sendable` because the shell holds it as `@State` on a `View` that
/// lives on `MainActor`; the `@MainActor` annotation pins every method to
/// the main actor, so concurrent access across threads is impossible at
/// the Swift language level.
@Observable
@MainActor
public final class SettingsViewModel {

    // MARK: - Public state

    /// The current list of sections to render. Rebuilt on every mutation
    /// — picker change, autoreg reset, etc. The view iterates this.
    public private(set) var sections: [SettingsSection] = []

    /// Non-nil while a destructive action is waiting for confirmation.
    /// The view observes this and presents the matching confirm dialog;
    /// tapping "confirm" fires `onConfirm` and clears the field.
    public var showDestructiveConfirm: DestructiveConfirm?

    /// A destructive-action handle.
    public struct DestructiveConfirm: Identifiable, Sendable {
        /// Stable id for SwiftUI's `.alert(item:)` binding.
        public let id: String
        /// Short imperative title (e.g. "change server").
        public let title: String
        /// ALL CAPS warning body — matches `CHANGING SERVERS WIPES LOCAL DATA`
        /// in the design reference.
        public let message: String
        /// Fired when the user taps the primary (destructive) button. The
        /// viewModel clears `showDestructiveConfirm` before invoking it.
        public let onConfirm: @Sendable () -> Void

        public init(
            id: String,
            title: String,
            message: String,
            onConfirm: @escaping @Sendable () -> Void
        ) {
            self.id = id
            self.title = title
            self.message = message
            self.onConfirm = onConfirm
        }
    }

    // MARK: - Dependencies
    //
    // Declared `internal` (the Swift default) rather than `private` so the
    // section-builder extension in `SettingsViewModel+Sections.swift` can
    // read them. They remain module-private from the host package's point
    // of view — consumers only see the `public` surface.

    let tokenStore: any TokenStore
    let autoregStore: any AutoregDefaultsStore
    let unitsStore: any UnitsPreferenceStore
    let syncMetadata: any SyncMetadataStore
    let buildInfo: BuildInfo
    let pairedWatchProvider: @MainActor () -> String?
    let onSyncNow: @Sendable () async -> Void
    let onResetCache: @Sendable () async -> Void
    let onChangeServer: @Sendable () async -> Void
    let now: @MainActor () -> Date

    // MARK: - Cached derived state (rebuilt on mutation)

    var cachedAutoregDefaults: AutoregDefaults
    var cachedUnits: UnitsPreference
    /// Latest `lastSyncAt` snapshot — populated by `refreshAsync()` from
    /// the injected `SyncMetadataStore`. Synchronous `refresh()` does not
    /// touch it (SwiftData/UserDefaults reads through the store protocol
    /// are async), so first paint before `.task` fires shows the
    /// placeholder.
    var cachedLastSyncAt: Date?

    // MARK: - Init

    /// Primary initializer.
    ///
    /// `syncMetadata` is the single source for the "last synced" row —
    /// the shell passes in `PersistenceFactory.syncMetadataStore`, tests
    /// and previews inject an in-memory fake. `pairedWatchProvider` is
    /// still a closure because WatchBridge runtime isn't wired yet.
    ///
    /// The three `on*` closures let the viewModel stay ignorant of the
    /// concrete `PullService` / `WorkoutCache` — the shell passes the
    /// real wiring in, tests pass no-op capturing doubles.
    public init(
        tokenStore: any TokenStore,
        autoregStore: any AutoregDefaultsStore = UserDefaultsAutoregStore(),
        unitsStore: any UnitsPreferenceStore = UserDefaultsUnitsStore(),
        syncMetadata: any SyncMetadataStore,
        buildInfo: BuildInfo = .fromMainBundle(),
        pairedWatchProvider: @escaping @MainActor () -> String? = { nil },
        onSyncNow: @escaping @Sendable () async -> Void = {},
        onResetCache: @escaping @Sendable () async -> Void = {},
        onChangeServer: @escaping @Sendable () async -> Void = {},
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.tokenStore = tokenStore
        self.autoregStore = autoregStore
        self.unitsStore = unitsStore
        self.syncMetadata = syncMetadata
        self.buildInfo = buildInfo
        self.pairedWatchProvider = pairedWatchProvider
        self.onSyncNow = onSyncNow
        self.onResetCache = onResetCache
        self.onChangeServer = onChangeServer
        self.now = now
        self.cachedAutoregDefaults = autoregStore.load()
        self.cachedUnits = unitsStore.load()
        self.cachedLastSyncAt = nil
        rebuild()
    }

    // MARK: - Intent

    /// Force a rebuild — the shell can call this on `.task` if external
    /// state (last-synced time, pairing status) changed while the view
    /// was off-screen. Synchronous; does not await the SyncMetadataStore.
    /// Callers who want the fresh `lastSyncAt` should use `refreshAsync()`.
    public func refresh() {
        cachedAutoregDefaults = autoregStore.load()
        cachedUnits = unitsStore.load()
        rebuild()
    }

    /// Read the async `SyncMetadataStore` and rebuild. Views should call
    /// this from a `.task` on appear so the "last synced" row reflects the
    /// latest pull.
    public func refreshAsync() async {
        cachedLastSyncAt = await syncMetadata.getLastSyncAt()
        cachedAutoregDefaults = autoregStore.load()
        cachedUnits = unitsStore.load()
        rebuild()
    }

    // MARK: - Section builders

    /// Re-derive `sections` from current state. Called from `init`, from
    /// `refresh()`, and from every row callback that mutates state.
    private func rebuild() {
        sections = [
            buildServerSection(),
            buildDeviceSection(),
            buildAutoregSection(),
            buildDataSection(),
        ]
    }

    // Section builders live in `SettingsViewModel+Sections.swift`.

    // MARK: - Row callbacks

    func requestChangeServer() {
        showDestructiveConfirm = DestructiveConfirm(
            id: "change-server",
            title: "change server",
            // ALL CAPS copy straight out of `docs/design/components/meta.jsx`
            // SettingsChangeServer — "CHANGING SERVERS WIPES LOCAL DATA".
            message: "CHANGING SERVERS WIPES LOCAL DATA",
            onConfirm: { [onChangeServer] in
                // swiftlint:disable:next no_direct_task_unstructured
                Task { await onChangeServer() }
            }
        )
    }

    func requestResetLocalData() {
        showDestructiveConfirm = DestructiveConfirm(
            id: "reset-local-data",
            title: "reset local data",
            message: "THIS WIPES CACHED WORKOUTS · SERVER CONNECTION STAYS",
            onConfirm: { [onResetCache] in
                // swiftlint:disable:next no_direct_task_unstructured
                Task { await onResetCache() }
            }
        )
    }

    /// Called from the view when the user taps "confirm" on the active
    /// destructive dialog. Clears the dialog first, then fires the stored
    /// closure. View binds this to the primary action of the alert.
    public func confirmDestructive() {
        guard let confirm = showDestructiveConfirm else { return }
        showDestructiveConfirm = nil
        confirm.onConfirm()
    }

    /// Called from the view when the user taps "cancel" on the active
    /// destructive dialog. Simply clears the field.
    public func cancelDestructive() {
        showDestructiveConfirm = nil
    }

    func pickUnits(label: String) {
        guard let picked = UnitsPreference.allCases.first(where: { $0.label == label }) else {
            return
        }
        unitsStore.save(picked)
        cachedUnits = picked
        rebuild()
    }

    func resetAutoregDefaults() {
        autoregStore.resetToDefaults()
        cachedAutoregDefaults = autoregStore.load()
        rebuild()
    }

    // Display helpers and formatters live in `SettingsViewModel+Sections.swift`.
}
