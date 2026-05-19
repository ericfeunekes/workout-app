import Foundation
import HealthArchiveExport
import Persistence

enum HealthArchiveAppHooks {
    typealias ControllerProvider = @MainActor () -> (any HealthArchiveExportControlling)?

    @MainActor
    static func manualExportFromSettings(
        controllerProvider: ControllerProvider,
        tokenStore: any TokenStore
    ) async -> HealthArchiveExportSummary? {
        guard let controller = controllerProvider(),
              let connection = try? tokenStore.loadConnection()
        else {
            return nil
        }
        return try? await controller.exportNow(serverURL: connection.url, trigger: .manual)
    }

    @MainActor
    static func foregroundCatchUp(
        controllerProvider: ControllerProvider,
        tokenStore: any TokenStore
    ) async -> HealthArchiveExportSummary? {
        guard let controller = controllerProvider(),
              let connection = try? tokenStore.loadConnection()
        else {
            return nil
        }
        return try? await controller.exportIfDue(serverURL: connection.url)
    }
}
