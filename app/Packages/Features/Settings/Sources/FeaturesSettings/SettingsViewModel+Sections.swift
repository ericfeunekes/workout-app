// SettingsViewModel+Sections.swift
//
// Section-builder helpers and the display formatters, split out of
// `SettingsViewModel.swift` so the main class body stays under SwiftLint's
// `type_body_length` cap. These methods are internal to the module and the
// viewModel invokes them from `rebuild()`.

import Foundation

extension SettingsViewModel {

    // MARK: - Section builders

    func buildServerSection() -> SettingsSection {
        let url = currentServerURL()
        let syncedValue = currentSyncedValue()
        return SettingsSection(
            id: "server",
            title: "SERVER",
            rows: [
                .info(id: "server.url", label: "url", value: url),
                .info(id: "server.synced", label: "last synced", value: syncedValue),
                .action(
                    id: "server.sync-now",
                    label: "sync now",
                    destructive: false,
                    onTap: { [onSyncNow] in
                        // SwiftUI button onTap is a sync `@Sendable` callback
                        // at a leaf — there is no async parent to push the
                        // boundary into. The unstructured Task is the
                        // idiomatic bridge.
                        // swiftlint:disable:next no_direct_task_unstructured
                        Task { await onSyncNow() }
                    }
                ),
                .action(
                    id: "server.change",
                    label: "change server",
                    destructive: true,
                    onTap: { [weak self] in
                        // swiftlint:disable:next no_direct_task_unstructured
                        Task { @MainActor in self?.requestChangeServer() }
                    }
                ),
            ]
        )
    }

    func buildDeviceSection() -> SettingsSection {
        let units = cachedUnits
        let pairedWatch = pairedWatchProvider() ?? "no watch paired"
        return SettingsSection(
            id: "device",
            title: "DEVICE",
            rows: [
                .picker(
                    id: "device.units",
                    label: "units",
                    options: UnitsPreference.allCases.map { $0.label },
                    selected: units.label,
                    onPick: { [weak self] picked in
                        // swiftlint:disable:next no_direct_task_unstructured
                        Task { @MainActor in self?.pickUnits(label: picked) }
                    }
                ),
                .info(
                    id: "device.watch",
                    label: "paired watch",
                    value: pairedWatch
                ),
            ]
        )
    }

    func buildAutoregSection() -> SettingsSection {
        let d = cachedAutoregDefaults
        return SettingsSection(
            id: "autoreg-defaults",
            title: "AUTOREG DEFAULTS",
            rows: [
                .info(
                    id: "autoreg.target-rir",
                    label: "target rir",
                    value: formatRIR(d.targetRIR)
                ),
                .info(
                    id: "autoreg.overshoot",
                    label: "overshoot step",
                    value: formatKg(d.overshootStepKg)
                ),
                .info(
                    id: "autoreg.undershoot",
                    label: "undershoot step",
                    value: formatKg(d.undershootStepKg)
                ),
                .action(
                    id: "autoreg.reset",
                    label: "reset to defaults",
                    destructive: false,
                    onTap: { [weak self] in
                        // swiftlint:disable:next no_direct_task_unstructured
                        Task { @MainActor in self?.resetAutoregDefaults() }
                    }
                ),
            ]
        )
    }

    func buildDataSection() -> SettingsSection {
        SettingsSection(
            id: "data",
            title: "DATA",
            rows: [
                .action(
                    id: "data.reset-local",
                    label: "reset local data",
                    destructive: true,
                    onTap: { [weak self] in
                        // swiftlint:disable:next no_direct_task_unstructured
                        Task { @MainActor in self?.requestResetLocalData() }
                    }
                ),
                .info(
                    id: "data.build",
                    label: "build",
                    value: buildInfo.displayLine
                ),
            ]
        )
    }

    // MARK: - Display helpers

    func currentServerURL() -> String {
        do {
            if let connection = try tokenStore.loadConnection() {
                // Show host, not full URL — matches the design reference
                // ("wdb.local:8080").
                if let host = connection.url.host {
                    if let port = connection.url.port {
                        return "\(host):\(port)"
                    }
                    return host
                }
                return connection.url.absoluteString
            }
            return "no server configured"
        } catch {
            // Keychain read failure — surface it rather than lying.
            return "unavailable"
        }
    }

    func currentSyncedValue() -> String {
        // `cachedLastSyncAt` is populated by `refreshAsync()` from the
        // injected `SyncMetadataStore`. Until the first async refresh
        // completes (or when no pull has ever succeeded) we render the
        // placeholder per the design reference ("—").
        guard let lastSync = cachedLastSyncAt else {
            return "—"
        }
        let elapsed = now().timeIntervalSince(lastSync)
        return formatRelative(elapsed: elapsed)
    }

    // MARK: - Formatters

    /// "just now" / "4 min ago" / "2 h ago" / "3 d ago". The brief's
    /// example copy is "synced 4 min ago" — the label carries the verb,
    /// so the value cell is just the elapsed-time phrase.
    func formatRelative(elapsed: TimeInterval) -> String {
        if elapsed < 60 { return "just now" }
        if elapsed < 60 * 60 {
            let minutes = Int(elapsed / 60)
            return "\(minutes) min ago"
        }
        if elapsed < 60 * 60 * 24 {
            let hours = Int(elapsed / 3600)
            return "\(hours) h ago"
        }
        let days = Int(elapsed / (3600 * 24))
        return "\(days) d ago"
    }

    /// "rir 2" / "rir 1.5". Keep the display unit-suffixed so the row
    /// reads naturally.
    func formatRIR(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "rir \(Int(value))"
        }
        return "rir \(String(format: "%g", value))"
    }

    /// "2.5 kg" / "5 kg". `%g` trims trailing zeros.
    func formatKg(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) kg"
        }
        return "\(String(format: "%g", value)) kg"
    }
}
