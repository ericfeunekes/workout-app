import XCTest
import HealthArchiveExport
import Persistence
import Sync
@testable import WorkoutDB

@MainActor
final class HealthArchiveAppHooksTests: XCTestCase {
    func testManualSettingsExportUsesSavedServerAndManualTrigger() async {
        let controller = FakeHealthArchiveController()
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let summary = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: tokenStore
        )

        XCTAssertEqual(summary?.trigger, .manual)
        XCTAssertEqual(controller.exportNowCalls, [
            FakeHealthArchiveController.ExportNowCall(
                serverURL: URL(string: "http://localhost:8000")!,
                trigger: .manual
            )
        ])
        XCTAssertEqual(controller.exportIfDueURLs, [])
    }

    func testForegroundCatchUpUsesSavedServerAndDuePath() async {
        let controller = FakeHealthArchiveController()
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let summary = await HealthArchiveAppHooks.foregroundCatchUp(
            controllerProvider: { controller },
            tokenStore: tokenStore
        )

        XCTAssertEqual(summary?.trigger, .foregroundCatchUp)
        XCTAssertEqual(controller.exportIfDueURLs, [URL(string: "http://localhost:8000")!])
        XCTAssertEqual(controller.exportNowCalls, [])
    }

    func testForegroundCatchUpDoesNotRunWithoutControllerOrConnection() async {
        let controller = FakeHealthArchiveController()
        let emptyTokenStore = FakeTokenStore(url: nil)

        let noConnection = await HealthArchiveAppHooks.foregroundCatchUp(
            controllerProvider: { controller },
            tokenStore: emptyTokenStore
        )
        let noController = await HealthArchiveAppHooks.foregroundCatchUp(
            controllerProvider: { nil },
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!)
        )

        XCTAssertNil(noConnection)
        XCTAssertNil(noController)
        XCTAssertEqual(controller.exportIfDueURLs, [])
        XCTAssertEqual(controller.exportNowCalls, [])
    }
}

private final class FakeHealthArchiveController: HealthArchiveExportControlling, @unchecked Sendable {
    struct ExportNowCall: Equatable {
        var serverURL: URL
        var trigger: HealthArchiveExportTrigger
    }

    private(set) var exportNowCalls: [ExportNowCall] = []
    private(set) var exportIfDueURLs: [URL] = []

    func exportNow(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary {
        exportNowCalls.append(ExportNowCall(serverURL: serverURL, trigger: trigger))
        return HealthArchiveExportSummary(
            trigger: trigger,
            recordsFetched: 0,
            tombstonesFetched: 0,
            acknowledgedCursor: nil
        )
    }

    func exportIfDue(serverURL: URL) async throws -> HealthArchiveExportSummary? {
        exportIfDueURLs.append(serverURL)
        return HealthArchiveExportSummary(
            trigger: .foregroundCatchUp,
            recordsFetched: 0,
            tombstonesFetched: 0,
            acknowledgedCursor: nil
        )
    }
}

private final class FakeTokenStore: TokenStore, @unchecked Sendable {
    private var url: URL?

    init(url: URL?) {
        self.url = url
    }

    func saveConnection(url: URL, token: String) throws {
        self.url = url
    }

    func loadConnection() throws -> (url: URL, token: String)? {
        guard let url else { return nil }
        return (url, "token")
    }

    func clear() throws {
        url = nil
    }
}
