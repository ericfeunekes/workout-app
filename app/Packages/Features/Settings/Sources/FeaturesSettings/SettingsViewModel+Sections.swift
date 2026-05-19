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

    func buildHealthArchiveSection() -> SettingsSection {
        var rows: [SettingsRow] = [
            .picker(
                id: "health-archive.scope-mode",
                label: "scope",
                options: ["all supported", "custom"],
                selected: healthArchiveScopeMode(),
                onPick: { [weak self] picked in
                    // swiftlint:disable:next no_direct_task_unstructured
                    Task { @MainActor in await self?.pickHealthArchiveScopeMode(picked) }
                }
            ),
        ]
        if case .explicitDescriptorIDs(let ids) = cachedHealthArchiveExport.scope {
            let selected = Set(ids)
            rows.append(contentsOf: healthArchiveDescriptorOptions.map { option in
                .toggle(
                    id: "health-archive.descriptor.\(option.id)",
                    label: option.label,
                    isOn: selected.contains(option.id),
                    onToggle: { [weak self] enabled in
                        // swiftlint:disable:next no_direct_task_unstructured
                        Task { @MainActor in
                            await self?.toggleHealthArchiveDescriptor(
                                id: option.id,
                                enabled: enabled
                            )
                        }
                    }
                )
            })
        }
        rows.append(contentsOf: [
            .toggle(
                id: "health-archive.automatic",
                label: "automatic",
                isOn: cachedHealthArchiveExport.automaticEnabled,
                onToggle: { [weak self] enabled in
                    // swiftlint:disable:next no_direct_task_unstructured
                    Task { @MainActor in await self?.setHealthArchiveAutomatic(enabled) }
                }
            ),
            .info(
                id: "health-archive.next-attempt",
                label: "next attempt",
                value: healthArchiveNextAttemptValue()
            ),
            .info(
                id: "health-archive.status",
                label: "status",
                value: healthArchiveStatusValue()
            ),
            .action(
                id: "health-archive.export-now",
                label: "export now",
                destructive: false,
                onTap: { [weak self] in
                    // swiftlint:disable:next no_direct_task_unstructured
                    Task { @MainActor in self?.exportHealthArchiveNow() }
                }
            ),
        ])
        return SettingsSection(
            id: "health-archive",
            title: "HEALTH ARCHIVE",
            rows: rows
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

    func currentServerNamespace() -> String? {
        do {
            guard let connection = try tokenStore.loadConnection() else {
                return nil
            }
            let url = connection.url
            guard let scheme = url.scheme, let host = url.host else {
                return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            var namespace = "\(scheme)://\(host)"
            if let port = url.port {
                namespace += ":\(port)"
            }
            if !url.path.isEmpty && url.path != "/" {
                namespace += url.path
            }
            return namespace
        } catch {
            return nil
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

    func healthArchiveScopeValue() -> String {
        switch cachedHealthArchiveExport.scope {
        case .allSupported:
            return "all supported"
        case .explicitDescriptorIDs(let ids):
            return "\(ids.count) selected"
        }
    }

    func healthArchiveScopeMode() -> String {
        switch cachedHealthArchiveExport.scope {
        case .allSupported:
            return "all supported"
        case .explicitDescriptorIDs:
            return "custom"
        }
    }

    func healthArchiveNextAttemptValue() -> String {
        guard cachedHealthArchiveExport.automaticEnabled else {
            return "off"
        }
        guard let nextAttemptAt = cachedHealthArchiveExport.nextAttemptAt else {
            return "when due"
        }
        return formatFutureRelative(until: nextAttemptAt.timeIntervalSince(now()))
    }

    func healthArchiveStatusValue() -> String {
        let snapshot = cachedHealthArchiveExport
        switch snapshot.status {
        case .neverRun:
            return "not exported"
        case .running:
            return "exporting"
        case .failed:
            if let failure = snapshot.lastFailureClass {
                return "failed · \(failure)"
            }
            return "failed"
        case .alreadyRunning:
            return "already running"
        case .succeeded:
            let count = snapshot.lastRecordCount + snapshot.lastTombstoneCount
            if let uploaded = snapshot.lastUploadAt {
                return "\(count) · \(formatRelative(elapsed: now().timeIntervalSince(uploaded)))"
            }
            return "\(count) uploaded"
        }
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

    /// "due" / "in 4 min" / "in 2 h" / "in 3 d".
    func formatFutureRelative(until interval: TimeInterval) -> String {
        if interval <= 0 { return "due" }
        if interval < 60 { return "soon" }
        if interval < 60 * 60 {
            let minutes = Int(interval / 60)
            return "in \(minutes) min"
        }
        if interval < 60 * 60 * 24 {
            let hours = Int(interval / 3600)
            return "in \(hours) h"
        }
        let days = Int(interval / (3600 * 24))
        return "in \(days) d"
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
