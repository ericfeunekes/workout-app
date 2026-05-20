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

        let result = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: tokenStore
        )

        guard case .succeeded(let summary?) = result else {
            XCTFail("expected succeeded summary, got \(result)")
            return
        }
        XCTAssertEqual(summary.trigger, .manual)
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

        let result = await HealthArchiveAppHooks.foregroundCatchUp(
            controllerProvider: { controller },
            tokenStore: tokenStore
        )

        guard case .succeeded(let summary?) = result else {
            XCTFail("expected succeeded summary, got \(result)")
            return
        }
        XCTAssertEqual(summary.trigger, .foregroundCatchUp)
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
        let noConnectionBeforeController = await HealthArchiveAppHooks.foregroundCatchUp(
            controllerProvider: { nil },
            tokenStore: FakeTokenStore(url: nil)
        )

        XCTAssertEqual(noConnection, .skipped(.missingConnection))
        XCTAssertEqual(noController, .skipped(.missingController))
        XCTAssertEqual(noConnectionBeforeController, .skipped(.missingConnection))
        XCTAssertEqual(controller.exportIfDueURLs, [])
        XCTAssertEqual(controller.exportNowCalls, [])
    }

    func testManualSettingsExportDistinguishesSkippedReasons() async {
        let controller = FakeHealthArchiveController()

        let noConnection = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: FakeTokenStore(url: nil)
        )
        let noController = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { nil },
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!)
        )
        let noConnectionBeforeController = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { nil },
            tokenStore: FakeTokenStore(url: nil)
        )
        let unavailableConnection = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!, shouldThrow: true)
        )

        XCTAssertEqual(noConnection, .skipped(.missingConnection))
        XCTAssertEqual(noController, .skipped(.missingController))
        XCTAssertEqual(noConnectionBeforeController, .skipped(.missingConnection))
        XCTAssertEqual(unavailableConnection, .skipped(.connectionUnavailable))
        XCTAssertEqual(controller.exportNowCalls, [])
    }

    func testManualSettingsExportSurfacesTokenRejected() async {
        let controller = FakeHealthArchiveController()
        controller.error = SyncError.tokenRejected
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let result = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: tokenStore
        )

        XCTAssertEqual(result, .tokenRejected)
    }

    func testManualSettingsExportSurfacesThrownFailureClass() async {
        struct SyntheticExportError: Error {}
        let controller = FakeHealthArchiveController()
        controller.error = SyntheticExportError()
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let result = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: tokenStore
        )

        XCTAssertEqual(result, .failed("SyntheticExportError"))
    }
}

private final class FakeHealthArchiveController: HealthArchiveExportControlling, @unchecked Sendable {
    struct ExportNowCall: Equatable {
        var serverURL: URL
        var trigger: HealthArchiveExportTrigger
    }

    private(set) var exportNowCalls: [ExportNowCall] = []
    private(set) var exportIfDueURLs: [URL] = []
    var error: Error?

    func exportNow(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary {
        if let error {
            throw error
        }
        exportNowCalls.append(ExportNowCall(serverURL: serverURL, trigger: trigger))
        return HealthArchiveExportSummary(
            trigger: trigger,
            recordsFetched: 0,
            tombstonesFetched: 0,
            acknowledgedCursor: nil
        )
    }

    func exportIfDue(serverURL: URL) async throws -> HealthArchiveExportSummary? {
        if let error {
            throw error
        }
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
    private var shouldThrow: Bool

    init(url: URL?, shouldThrow: Bool = false) {
        self.url = url
        self.shouldThrow = shouldThrow
    }

    func saveConnection(url: URL, token: String) throws {
        self.url = url
    }

    func loadConnection() throws -> (url: URL, token: String)? {
        if shouldThrow {
            throw PersistenceError.keychain(-1)
        }
        guard let url else { return nil }
        return (url, "token")
    }

    func clear() throws {
        url = nil
    }
}
