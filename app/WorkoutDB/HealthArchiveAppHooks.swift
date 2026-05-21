import Foundation
import CoreTelemetry
import HealthArchiveExport
import Persistence
import Sync

enum HealthArchiveAppHooks {
    typealias ControllerProvider = @MainActor () -> (any HealthArchiveExportControlling)?
    typealias PrepareTelemetry = @MainActor () async -> Void

    enum Result: Equatable {
        case skipped(SkipReason)
        case succeeded(HealthArchiveExportSummary?)
        case tokenRejected
        case failed(String)
    }

    enum SkipReason: Equatable {
        case missingController
        case missingConnection
        case connectionUnavailable
    }

    @MainActor
    static func manualExportFromSettings(
        controllerProvider: ControllerProvider,
        tokenStore: any TokenStore,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        prepareTelemetry: PrepareTelemetry = {}
    ) async -> Result {
        await prepareTelemetry()
        emitExportEvent(
            telemetry,
            name: "health_archive.manual_export_requested",
            trigger: .manual
        )
        let connection: (url: URL, token: String)?
        do {
            connection = try tokenStore.loadConnection()
        } catch {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .manual,
                skipReason: "ConnectionUnavailable"
            )
            return .skipped(.connectionUnavailable)
        }
        guard let connection else {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .manual,
                skipReason: "MissingConnection"
            )
            return .skipped(.missingConnection)
        }
        guard let controller = controllerProvider() else {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .manual,
                serverURL: connection.url,
                skipReason: "MissingController"
            )
            return .skipped(.missingController)
        }
        do {
            let summary = try await controller.exportNow(serverURL: connection.url, trigger: .manual)
            emitExportEvent(
                telemetry,
                name: "health_archive.export_succeeded",
                trigger: .manual,
                serverURL: connection.url,
                summary: summary
            )
            return .succeeded(summary)
        } catch SyncError.tokenRejected {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_token_rejected",
                trigger: .manual,
                serverURL: connection.url
            )
            return .tokenRejected
        } catch {
            let failureClass = String(describing: type(of: error))
            emitExportEvent(
                telemetry,
                name: "health_archive.export_failed",
                trigger: .manual,
                serverURL: connection.url,
                failureClass: failureClass
            )
            return .failed(failureClass)
        }
    }

    @MainActor
    static func foregroundCatchUp(
        controllerProvider: ControllerProvider,
        tokenStore: any TokenStore,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        prepareTelemetry: PrepareTelemetry = {}
    ) async -> Result {
        await prepareTelemetry()
        emitExportEvent(
            telemetry,
            name: "health_archive.foreground_catchup_requested",
            trigger: .foregroundCatchUp
        )
        let connection: (url: URL, token: String)?
        do {
            connection = try tokenStore.loadConnection()
        } catch {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .foregroundCatchUp,
                skipReason: "ConnectionUnavailable"
            )
            return .skipped(.connectionUnavailable)
        }
        guard let connection else {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .foregroundCatchUp,
                skipReason: "MissingConnection"
            )
            return .skipped(.missingConnection)
        }
        guard let controller = controllerProvider() else {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .foregroundCatchUp,
                serverURL: connection.url,
                skipReason: "MissingController"
            )
            return .skipped(.missingController)
        }
        do {
            let summary = try await controller.exportIfDue(serverURL: connection.url)
            if let summary {
                emitExportEvent(
                    telemetry,
                    name: "health_archive.export_succeeded",
                    trigger: .foregroundCatchUp,
                    serverURL: connection.url,
                    summary: summary
                )
            } else {
                emitExportEvent(
                    telemetry,
                    name: "health_archive.export_skipped",
                    trigger: .foregroundCatchUp,
                    serverURL: connection.url,
                    skipReason: "NotDue"
                )
            }
            return .succeeded(summary)
        } catch SyncError.tokenRejected {
            emitExportEvent(
                telemetry,
                name: "health_archive.export_token_rejected",
                trigger: .foregroundCatchUp,
                serverURL: connection.url
            )
            return .tokenRejected
        } catch {
            let failureClass = String(describing: type(of: error))
            emitExportEvent(
                telemetry,
                name: "health_archive.export_failed",
                trigger: .foregroundCatchUp,
                serverURL: connection.url,
                failureClass: failureClass
            )
            return .failed(failureClass)
        }
    }

    static func emitExportEvent(
        _ telemetry: TelemetryEmitter,
        name: String,
        trigger: HealthArchiveExportTrigger,
        serverURL: URL? = nil,
        summary: HealthArchiveExportSummary? = nil,
        failureClass: String? = nil,
        skipReason: String? = nil
    ) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "health_archive",
            name: name,
            dataJSON: exportEventPayload(
                trigger: trigger,
                serverURL: serverURL,
                summary: summary,
                failureClass: failureClass,
                skipReason: skipReason
            )
        ))
    }

    private static func exportEventPayload(
        trigger: HealthArchiveExportTrigger,
        serverURL: URL?,
        summary: HealthArchiveExportSummary?,
        failureClass: String?,
        skipReason: String?
    ) -> String? {
        let payload = HealthArchiveExportTelemetryPayload(
            trigger: trigger.rawValue,
            serverNamespace: serverURL.map(HealthArchiveServerNamespace.normalized(from:)),
            recordsFetched: summary?.recordsFetched,
            tombstonesFetched: summary?.tombstonesFetched,
            acknowledgedCursorPresent: summary.map { $0.acknowledgedCursor != nil },
            alreadyRunning: summary?.alreadyRunning,
            failureClass: failureClass,
            skipReason: skipReason
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct HealthArchiveExportTelemetryPayload: Encodable {
    let trigger: String
    let serverNamespace: String?
    let recordsFetched: Int?
    let tombstonesFetched: Int?
    let acknowledgedCursorPresent: Bool?
    let alreadyRunning: Bool?
    let failureClass: String?
    let skipReason: String?
}
