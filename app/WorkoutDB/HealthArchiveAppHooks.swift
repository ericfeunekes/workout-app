import Foundation
import HealthArchiveExport
import Persistence
import Sync

enum HealthArchiveAppHooks {
    typealias ControllerProvider = @MainActor () -> (any HealthArchiveExportControlling)?

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
        tokenStore: any TokenStore
    ) async -> Result {
        let connection: (url: URL, token: String)?
        do {
            connection = try tokenStore.loadConnection()
        } catch {
            return .skipped(.connectionUnavailable)
        }
        guard let connection else {
            return .skipped(.missingConnection)
        }
        guard let controller = controllerProvider() else {
            return .skipped(.missingController)
        }
        do {
            let summary = try await controller.exportNow(serverURL: connection.url, trigger: .manual)
            return .succeeded(summary)
        } catch SyncError.tokenRejected {
            return .tokenRejected
        } catch {
            return .failed(String(describing: type(of: error)))
        }
    }

    @MainActor
    static func foregroundCatchUp(
        controllerProvider: ControllerProvider,
        tokenStore: any TokenStore
    ) async -> Result {
        let connection: (url: URL, token: String)?
        do {
            connection = try tokenStore.loadConnection()
        } catch {
            return .skipped(.connectionUnavailable)
        }
        guard let connection else {
            return .skipped(.missingConnection)
        }
        guard let controller = controllerProvider() else {
            return .skipped(.missingController)
        }
        do {
            let summary = try await controller.exportIfDue(serverURL: connection.url)
            return .succeeded(summary)
        } catch SyncError.tokenRejected {
            return .tokenRejected
        } catch {
            return .failed(String(describing: type(of: error)))
        }
    }
}
