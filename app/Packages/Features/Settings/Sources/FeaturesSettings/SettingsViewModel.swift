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

public enum HealthArchiveManualExportOutcome: Sendable, Equatable {
    case completed
    case unavailable(String)
    case failed(String)
    case tokenRejected
}

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
    let healthArchiveExportState: any HealthArchiveExportStateStore
    let healthArchiveDescriptorOptions: [HealthArchiveDescriptorOption]
    let buildInfo: BuildInfo
    let pairedWatchProvider: @Sendable @MainActor () async -> String?
    let onSyncNow: @Sendable () async -> Void
    let onResetCache: @Sendable () async -> Void
    let onChangeServer: @Sendable () async -> Void
    let onHealthArchiveExportNow: @Sendable () async -> HealthArchiveManualExportOutcome
    let onHealthArchiveAutomaticChanged: @Sendable (Bool) async -> Void
    let healthArchiveExportTimeoutNanoseconds: UInt64?
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
    var cachedHealthArchiveExport: HealthArchiveExportSnapshot
    var cachedPairedWatch: String?
    var transientHealthArchiveStatus: String?
    private var healthArchiveControlMutationTail: Task<Void, Never>?

    // MARK: - Init

    /// Primary initializer.
    ///
    /// `syncMetadata` is the single source for the "last synced" row —
    /// the shell passes in `PersistenceFactory.syncMetadataStore`, tests
    /// and previews inject an in-memory fake. `pairedWatchProvider` stays as
    /// a closure so the shell can keep WatchConnectivity inside WatchBridge.
    ///
    /// The three `on*` closures let the viewModel stay ignorant of the
    /// concrete `PullService` / `WorkoutCache` — the shell passes the
    /// real wiring in, tests pass no-op capturing doubles.
    public init(
        tokenStore: any TokenStore,
        autoregStore: any AutoregDefaultsStore = UserDefaultsAutoregStore(),
        unitsStore: any UnitsPreferenceStore = UserDefaultsUnitsStore(),
        syncMetadata: any SyncMetadataStore,
        healthArchiveExportState: any HealthArchiveExportStateStore =
            UserDefaultsHealthArchiveExportStateStore(),
        healthArchiveDescriptorOptions: [HealthArchiveDescriptorOption] = [],
        buildInfo: BuildInfo = .fromMainBundle(),
        pairedWatchProvider: @escaping @Sendable @MainActor () async -> String? = { nil },
        onSyncNow: @escaping @Sendable () async -> Void = {},
        onResetCache: @escaping @Sendable () async -> Void = {},
        onChangeServer: @escaping @Sendable () async -> Void = {},
        onHealthArchiveExportNow: @escaping @Sendable () async -> HealthArchiveManualExportOutcome = {
            .completed
        },
        onHealthArchiveAutomaticChanged: @escaping @Sendable (Bool) async -> Void = { _ in },
        healthArchiveExportTimeoutNanoseconds: UInt64? = 120_000_000_000,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.tokenStore = tokenStore
        self.autoregStore = autoregStore
        self.unitsStore = unitsStore
        self.syncMetadata = syncMetadata
        self.healthArchiveExportState = healthArchiveExportState
        self.healthArchiveDescriptorOptions = healthArchiveDescriptorOptions
        self.buildInfo = buildInfo
        self.pairedWatchProvider = pairedWatchProvider
        self.onSyncNow = onSyncNow
        self.onResetCache = onResetCache
        self.onChangeServer = onChangeServer
        self.onHealthArchiveExportNow = onHealthArchiveExportNow
        self.onHealthArchiveAutomaticChanged = onHealthArchiveAutomaticChanged
        self.healthArchiveExportTimeoutNanoseconds = healthArchiveExportTimeoutNanoseconds
        self.now = now
        self.cachedAutoregDefaults = autoregStore.load()
        self.cachedUnits = unitsStore.load()
        self.cachedLastSyncAt = nil
        self.cachedHealthArchiveExport = HealthArchiveExportSnapshot()
        self.cachedPairedWatch = nil
        self.transientHealthArchiveStatus = nil
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
    public func refreshAsync(preserveTransientHealthArchiveStatus: Bool = false) async {
        cachedLastSyncAt = await syncMetadata.getLastSyncAt()
        let serverNamespace = currentServerNamespace()
        cachedHealthArchiveExport = await healthArchiveExportState.loadSnapshot(
            serverNamespace: serverNamespace
        )
        cachedPairedWatch = await pairedWatchProvider() ?? "no watch paired"
        if !preserveTransientHealthArchiveStatus {
            transientHealthArchiveStatus = nil
        }
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
            buildHealthArchiveSection(),
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
            message: "THIS WIPES LOCAL WORKOUTS, SESSION, AND QUEUED PUSHES · SERVER CONNECTION STAYS",
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

    @discardableResult
    func exportHealthArchiveNow() -> Task<Void, Never> {
        let pendingMutation = healthArchiveControlMutationTail
        return Task { @MainActor in
            await pendingMutation?.value
            applyHealthArchiveTransientExporting()
            let outcome = await runHealthArchiveExportWithTimeout()
            await self.handleHealthArchiveManualExportOutcome(outcome)
        }
    }

    private func runHealthArchiveExportWithTimeout() async -> HealthArchiveManualExportOutcome {
        guard let timeout = healthArchiveExportTimeoutNanoseconds else {
            return await onHealthArchiveExportNow()
        }
        let gate = HealthArchiveExportTimeoutGate()
        return await withCheckedContinuation { continuation in
            let exportTask = Task {
                let outcome = await onHealthArchiveExportNow()
                if await gate.tryComplete() {
                    continuation.resume(returning: outcome)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: timeout)
                if await gate.tryComplete() {
                    exportTask.cancel()
                    continuation.resume(returning: .failed("TimedOut"))
                }
            }
        }
    }

    private func handleHealthArchiveManualExportOutcome(
        _ outcome: HealthArchiveManualExportOutcome
    ) async {
        switch outcome {
        case .completed:
            await refreshAsync()
        case .unavailable(let reason):
            applyHealthArchiveTransientUnavailable(reason)
        case .failed(let reason):
            applyHealthArchiveTransientUnavailable(reason)
        case .tokenRejected:
            await refreshAsync()
        }
    }

    private func applyHealthArchiveTransientUnavailable(_ failureClass: String) {
        transientHealthArchiveStatus = "failed · \(failureClass)"
        rebuild()
    }

    private func applyHealthArchiveTransientExporting() {
        transientHealthArchiveStatus = "exporting"
        rebuild()
    }

    @discardableResult
    func pickHealthArchiveScopeMode(_ mode: String) -> Task<Void, Never> {
        enqueueHealthArchiveIntent { [self] in
            await applyHealthArchiveScopeMode(mode)
        }
    }

    private func applyHealthArchiveScopeMode(_ mode: String) async {
        await reloadHealthArchiveExportSnapshot()
        if mode == "all supported" {
            await healthArchiveExportState.setScope(.allSupported)
        } else {
            let ids = explicitDescriptorIDsForEditing()
            await healthArchiveExportState.setScope(.explicitDescriptorIDs(
                healthArchiveDescriptorOptions.map(\.id).filter { ids.contains($0) }
            ))
        }
        await refreshAsync(preserveTransientHealthArchiveStatus: true)
    }

    @discardableResult
    func setHealthArchiveAutomatic(_ enabled: Bool) -> Task<Void, Never> {
        enqueueHealthArchiveIntent { [self] in
            await applyHealthArchiveAutomatic(enabled)
        }
    }

    private func applyHealthArchiveAutomatic(_ enabled: Bool) async {
        await reloadHealthArchiveExportSnapshot()
        await healthArchiveExportState.setAutomaticEnabled(enabled)
        await onHealthArchiveAutomaticChanged(enabled)
        await refreshAsync(preserveTransientHealthArchiveStatus: true)
    }

    @discardableResult
    func toggleHealthArchiveDescriptor(id: String, enabled: Bool) -> Task<Void, Never> {
        enqueueHealthArchiveIntent { [self] in
            await applyHealthArchiveDescriptorToggle(id: id, enabled: enabled)
        }
    }

    private func applyHealthArchiveDescriptorToggle(id: String, enabled: Bool) async {
        await reloadHealthArchiveExportSnapshot()
        var ids = explicitDescriptorIDsForEditing()
        if enabled {
            ids.insert(id)
        } else if ids.count > 1 {
            ids.remove(id)
        }
        await healthArchiveExportState.setScope(.explicitDescriptorIDs(
            healthArchiveDescriptorOptions.map(\.id).filter { ids.contains($0) }
        ))
        await refreshAsync(preserveTransientHealthArchiveStatus: true)
    }

    @discardableResult
    private func enqueueHealthArchiveIntent(
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = healthArchiveControlMutationTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        healthArchiveControlMutationTail = task
        return task
    }

    private func reloadHealthArchiveExportSnapshot() async {
        let serverNamespace = currentServerNamespace()
        cachedHealthArchiveExport = await healthArchiveExportState.loadSnapshot(
            serverNamespace: serverNamespace
        )
    }

    private func explicitDescriptorIDsForEditing() -> Set<String> {
        let optionIDs = healthArchiveDescriptorOptions.map(\.id)
        switch cachedHealthArchiveExport.scope {
        case .allSupported:
            return Set(optionIDs)
        case .explicitDescriptorIDs(let ids):
            let filtered = ids.filter { optionIDs.contains($0) }
            return Set(filtered.isEmpty ? optionIDs : filtered)
        }
    }
}

private actor HealthArchiveExportTimeoutGate {
    private var completed = false

    func tryComplete() -> Bool {
        guard !completed else { return false }
        completed = true
        return true
    }
}
