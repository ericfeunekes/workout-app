import XCTest
import CoreTelemetry
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

    func testManualSettingsExportEmitsRequestedAndSuccessTelemetry() async {
        let controller = FakeHealthArchiveController()
        let telemetry = RecordingTelemetryEmitter()
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let result = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: tokenStore,
            telemetry: telemetry
        )

        guard case .succeeded = result else {
            XCTFail("expected succeeded, got \(result)")
            return
        }
        XCTAssertEqual(telemetry.events.map(\.name), [
            "health_archive.manual_export_requested",
            "health_archive.export_succeeded",
        ])
        XCTAssertTrue(telemetry.events[0].dataJSON?.contains(#""trigger":"manual""#) == true)
        XCTAssertTrue(telemetry.events[1].dataJSON?.contains(#""serverNamespace""#) == true)
        XCTAssertTrue(telemetry.events[1].dataJSON?.contains("localhost:8000") == true)
        XCTAssertTrue(telemetry.events[1].dataJSON?.contains(#""recordsFetched":0"#) == true)
    }

    func testManualSettingsExportQueuesTelemetryThroughPreparedPersistenceEmitter() async throws {
        let persistence = try PersistenceFactory.makeInMemory()
        let controller = FakeHealthArchiveController()

        let result = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            telemetry: persistence.telemetryEmitter(),
            prepareTelemetry: {
                await persistence.prepareTelemetry()
            }
        )

        guard case .succeeded = result else {
            XCTFail("expected succeeded, got \(result)")
            return
        }
        let events = try await waitForQueuedTelemetryEvents(
            in: persistence.pushQueueStore,
            count: 2
        )
        XCTAssertEqual(events.map(\.name), [
            "health_archive.manual_export_requested",
            "health_archive.export_succeeded",
        ])
    }

    func testManualSettingsExportEmitsSkippedTelemetryWithoutConnection() async {
        let controller = FakeHealthArchiveController()
        let telemetry = RecordingTelemetryEmitter()

        let result = await HealthArchiveAppHooks.manualExportFromSettings(
            controllerProvider: { controller },
            tokenStore: FakeTokenStore(url: nil),
            telemetry: telemetry
        )

        XCTAssertEqual(result, .skipped(.missingConnection))
        XCTAssertEqual(telemetry.events.map(\.name), [
            "health_archive.manual_export_requested",
            "health_archive.export_skipped",
        ])
        XCTAssertTrue(telemetry.events[1].dataJSON?.contains(#""skipReason":"MissingConnection""#)
            == true)
        XCTAssertEqual(controller.exportNowCalls, [])
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

    func testBackgroundExportUsesSavedServerAndScheduledTrigger() async {
        let controller = FakeHealthArchiveController()
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let result = await HealthArchiveBackgroundExport.run(
            makeController: { _, _ in controller },
            tokenStore: tokenStore
        )

        guard case .succeeded(let summary?) = result else {
            XCTFail("expected succeeded summary, got \(result)")
            return
        }
        XCTAssertEqual(summary.trigger, .backgroundScheduled)
        XCTAssertEqual(controller.exportIfDueCalls, [
            FakeHealthArchiveController.ExportIfDueCall(
                serverURL: URL(string: "http://localhost:8000")!,
                trigger: .backgroundScheduled
            )
        ])
        XCTAssertEqual(controller.exportNowCalls, [])
    }

    func testBackgroundExportEmitsFailureTelemetry() async {
        struct SyntheticBackgroundExportError: Error {}
        let controller = FakeHealthArchiveController()
        controller.error = SyntheticBackgroundExportError()
        let telemetry = RecordingTelemetryEmitter()

        let result = await HealthArchiveBackgroundExport.run(
            makeController: { _, _ in controller },
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            telemetry: telemetry
        )

        XCTAssertEqual(result, .failed("SyntheticBackgroundExportError"))
        XCTAssertEqual(telemetry.events.map(\.name), [
            "health_archive.background_export_requested",
            "health_archive.export_failed",
        ])
        XCTAssertTrue(
            telemetry.events[1].dataJSON?.contains(
                #""failureClass":"SyntheticBackgroundExportError""#
            ) == true
        )
    }

    func testBackgroundExportQueuesTelemetryThroughPreparedPersistenceEmitter() async throws {
        let persistence = try PersistenceFactory.makeInMemory()
        let controller = FakeHealthArchiveController()

        let result = await HealthArchiveBackgroundExport.run(
            makeController: { _, _ in controller },
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            telemetry: persistence.telemetryEmitter(),
            prepareTelemetry: {
                await persistence.prepareTelemetry()
            }
        )

        guard case .succeeded = result else {
            XCTFail("expected succeeded, got \(result)")
            return
        }
        let events = try await waitForQueuedTelemetryEvents(
            in: persistence.pushQueueStore,
            count: 2
        )
        XCTAssertEqual(events.map(\.name), [
            "health_archive.background_export_requested",
            "health_archive.export_succeeded",
        ])
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

    func testForegroundCatchUpSurfacesTokenRejected() async {
        let controller = FakeHealthArchiveController()
        controller.error = SyncError.tokenRejected
        let tokenStore = FakeTokenStore(url: URL(string: "http://localhost:8000")!)

        let result = await HealthArchiveAppHooks.foregroundCatchUp(
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

    func testBackgroundSchedulerRegistersAndSubmitsWhenAutomaticEnabled() async {
        let scheduler = FakeBackgroundTaskScheduler()
        let telemetry = RecordingTelemetryEmitter()
        let stateStore = FakeHealthArchiveExportStateStore(snapshot: HealthArchiveExportSnapshot(
            serverNamespace: "http://localhost:8000",
            automaticEnabled: true,
            nextAttemptAt: Date(timeIntervalSince1970: 100)
        ))
        let background = HealthArchiveBackgroundExportScheduler(
            scheduler: scheduler,
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            stateStore: stateStore,
            telemetry: telemetry,
            now: { Date(timeIntervalSince1970: 50) },
            makeController: { _, _ in FakeHealthArchiveController() }
        )

        XCTAssertTrue(background.register())
        await background.scheduleIfAutomaticEnabled()

        XCTAssertEqual(scheduler.registeredIdentifiers, [
            HealthArchiveBackgroundExport.taskIdentifier,
        ])
        XCTAssertEqual(scheduler.submissions, [
            FakeBackgroundTaskScheduler.Submission(
                identifier: HealthArchiveBackgroundExport.taskIdentifier,
                earliestBeginDate: Date(timeIntervalSince1970: 100)
            ),
        ])
        XCTAssertEqual(scheduler.cancelledIdentifiers, [])
        XCTAssertEqual(telemetry.events.map(\.name), [
            "health_archive.bg_schedule_submitted",
        ])
    }

    func testBackgroundSchedulerEmitsScheduleFailureTelemetry() async {
        struct SyntheticScheduleError: Error {}
        let scheduler = FakeBackgroundTaskScheduler()
        scheduler.submitError = SyntheticScheduleError()
        let telemetry = RecordingTelemetryEmitter()
        let stateStore = FakeHealthArchiveExportStateStore(snapshot: HealthArchiveExportSnapshot(
            serverNamespace: "http://localhost:8000",
            automaticEnabled: true
        ))
        let background = HealthArchiveBackgroundExportScheduler(
            scheduler: scheduler,
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            stateStore: stateStore,
            telemetry: telemetry,
            makeController: { _, _ in FakeHealthArchiveController() }
        )

        await background.scheduleIfAutomaticEnabled()

        XCTAssertEqual(telemetry.events.map(\.name), [
            "health_archive.bg_schedule_failed",
        ])
        XCTAssertTrue(telemetry.events[0].dataJSON?.contains(#""failureClass":"SyntheticScheduleError""#)
            == true)
    }

    func testBackgroundSchedulerRegisterIsIdempotent() {
        let scheduler = FakeBackgroundTaskScheduler()
        let background = HealthArchiveBackgroundExportScheduler(
            scheduler: scheduler,
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            stateStore: FakeHealthArchiveExportStateStore(snapshot: HealthArchiveExportSnapshot()),
            makeController: { _, _ in FakeHealthArchiveController() }
        )

        XCTAssertTrue(background.register())
        XCTAssertTrue(background.register())

        XCTAssertEqual(scheduler.registeredIdentifiers, [
            HealthArchiveBackgroundExport.taskIdentifier,
        ])
    }

    func testBackgroundSchedulerCancelsWhenAutomaticDisabled() async {
        let scheduler = FakeBackgroundTaskScheduler()
        let stateStore = FakeHealthArchiveExportStateStore(snapshot: HealthArchiveExportSnapshot(
            serverNamespace: "http://localhost:8000",
            automaticEnabled: false
        ))
        let background = HealthArchiveBackgroundExportScheduler(
            scheduler: scheduler,
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            stateStore: stateStore,
            makeController: { _, _ in FakeHealthArchiveController() }
        )

        await background.scheduleIfAutomaticEnabled()

        XCTAssertEqual(scheduler.submissions, [])
        XCTAssertEqual(scheduler.cancelledIdentifiers, [
            HealthArchiveBackgroundExport.taskIdentifier,
        ])
    }

    func testBackgroundTaskLaunchCompletesAndReschedules() async {
        let scheduler = FakeBackgroundTaskScheduler()
        let controller = FakeHealthArchiveController()
        let stateStore = FakeHealthArchiveExportStateStore(snapshot: HealthArchiveExportSnapshot(
            serverNamespace: "http://localhost:8000",
            automaticEnabled: true
        ))
        let background = HealthArchiveBackgroundExportScheduler(
            scheduler: scheduler,
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            stateStore: stateStore,
            now: { Date(timeIntervalSince1970: 50) },
            makeController: { _, _ in controller }
        )

        XCTAssertTrue(background.register())
        let task = FakeBackgroundTaskHandle()
        scheduler.launch(task)
        await task.waitForCompletion()

        XCTAssertEqual(task.completions, [true])
        XCTAssertEqual(controller.exportIfDueCalls.map(\.trigger), [.backgroundScheduled])
        XCTAssertEqual(scheduler.submissions, [
            FakeBackgroundTaskScheduler.Submission(
                identifier: HealthArchiveBackgroundExport.taskIdentifier,
                earliestBeginDate: Date(timeIntervalSince1970: 50)
            ),
        ])
    }

    func testBackgroundTaskExpirationCompletesOnceRetiresControllerAndDoesNotReschedule() async {
        let scheduler = FakeBackgroundTaskScheduler()
        let controller = BlockingHealthArchiveController()
        let stateStore = FakeHealthArchiveExportStateStore(snapshot: HealthArchiveExportSnapshot(
            serverNamespace: "http://localhost:8000",
            automaticEnabled: true
        ))
        let background = HealthArchiveBackgroundExportScheduler(
            scheduler: scheduler,
            tokenStore: FakeTokenStore(url: URL(string: "http://localhost:8000")!),
            stateStore: stateStore,
            makeController: { _, _ in controller }
        )

        XCTAssertTrue(background.register())
        let task = FakeBackgroundTaskHandle()
        scheduler.launch(task)
        await controller.waitForExportStart()

        task.expirationHandler?()
        await task.waitForCompletion()
        await controller.waitForRetire()

        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(scheduler.submissions, [])
    }
}

private final class FakeHealthArchiveController: HealthArchiveExportControlling, @unchecked Sendable {
    struct ExportNowCall: Equatable {
        var serverURL: URL
        var trigger: HealthArchiveExportTrigger
    }

    struct ExportIfDueCall: Equatable {
        var serverURL: URL
        var trigger: HealthArchiveExportTrigger
    }

    private(set) var exportNowCalls: [ExportNowCall] = []
    private(set) var exportIfDueCalls: [ExportIfDueCall] = []
    var exportIfDueURLs: [URL] {
        exportIfDueCalls.map(\.serverURL)
    }
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

    func exportIfDue(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary? {
        if let error {
            throw error
        }
        exportIfDueCalls.append(ExportIfDueCall(serverURL: serverURL, trigger: trigger))
        return HealthArchiveExportSummary(
            trigger: trigger,
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

private final class FakeHealthArchiveExportStateStore: HealthArchiveExportStateStore,
    @unchecked Sendable {
    private var snapshot: HealthArchiveExportSnapshot

    init(snapshot: HealthArchiveExportSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot(serverNamespace: String?) async -> HealthArchiveExportSnapshot {
        snapshot
    }

    func saveSnapshot(_ snapshot: HealthArchiveExportSnapshot) async {
        self.snapshot = snapshot
    }

    func setScope(_ scope: HealthArchiveExportScope) async {
        snapshot = HealthArchiveExportSnapshot(
            scope: scope,
            serverNamespace: snapshot.serverNamespace,
            automaticEnabled: snapshot.automaticEnabled
        )
    }

    func setAutomaticEnabled(_ enabled: Bool) async {
        snapshot = HealthArchiveExportSnapshot(
            scope: snapshot.scope,
            serverNamespace: snapshot.serverNamespace,
            automaticEnabled: enabled
        )
    }

    func clear() async {
        snapshot = HealthArchiveExportSnapshot()
    }
}

@MainActor
private final class FakeBackgroundTaskScheduler: HealthArchiveBackgroundTaskScheduling {
    struct Submission: Equatable {
        var identifier: String
        var earliestBeginDate: Date?
    }

    private var handler: ((any HealthArchiveBackgroundTaskHandle) -> Void)?
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submissions: [Submission] = []
    private(set) var cancelledIdentifiers: [String] = []
    var submitError: Error?

    func register(
        identifier: String,
        launchHandler: @escaping @MainActor @Sendable (
            any HealthArchiveBackgroundTaskHandle
        ) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        handler = launchHandler
        return true
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        if let submitError {
            throw submitError
        }
        submissions.append(Submission(identifier: identifier, earliestBeginDate: earliestBeginDate))
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    func launch(_ task: any HealthArchiveBackgroundTaskHandle) {
        handler?(task)
    }
}

private final class RecordingTelemetryEmitter: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func emit(_ event: Event) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }
}

private final class BlockingHealthArchiveController: HealthArchiveExportControlling,
    @unchecked Sendable {
    private var exportStartContinuations: [CheckedContinuation<Void, Never>] = []
    private var retireContinuations: [CheckedContinuation<Void, Never>] = []
    private var exportStarted = false
    private var retired = false

    func exportNow(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary {
        try await exportIfDue(serverURL: serverURL, trigger: trigger) ?? HealthArchiveExportSummary(
            trigger: trigger,
            recordsFetched: 0,
            tombstonesFetched: 0,
            acknowledgedCursor: nil
        )
    }

    func exportIfDue(
        serverURL: URL,
        trigger: HealthArchiveExportTrigger
    ) async throws -> HealthArchiveExportSummary? {
        exportStarted = true
        let startContinuations = exportStartContinuations
        exportStartContinuations.removeAll()
        for continuation in startContinuations {
            continuation.resume()
        }
        while !retired {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        throw CancellationError()
    }

    func retire() async {
        retired = true
        let continuations = retireContinuations
        retireContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForExportStart() async {
        if exportStarted { return }
        await withCheckedContinuation { continuation in
            exportStartContinuations.append(continuation)
        }
    }

    func waitForRetire() async {
        if retired { return }
        await withCheckedContinuation { continuation in
            retireContinuations.append(continuation)
        }
    }
}

@MainActor
private final class FakeBackgroundTaskHandle: HealthArchiveBackgroundTaskHandle {
    var expirationHandler: (@MainActor @Sendable () -> Void)?
    private(set) var completions: [Bool] = []
    private var completionContinuations: [CheckedContinuation<Void, Never>] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
        let continuations = completionContinuations
        completionContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForCompletion() async {
        if !completions.isEmpty { return }
        await withCheckedContinuation { continuation in
            completionContinuations.append(continuation)
        }
    }
}

private func waitForQueuedTelemetryEvents(
    in store: any PushQueueStore,
    count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> [Event] {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        let events = try await queuedTelemetryEvents(in: store)
        if events.count >= count {
            return events
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTFail("timed out waiting for \(count) queued telemetry events", file: file, line: line)
    return try await queuedTelemetryEvents(in: store)
}

private func queuedTelemetryEvents(in store: any PushQueueStore) async throws -> [Event] {
    let items = try await store.peek(max: 20)
    return items.flatMap { item -> [Event] in
        guard case .events(let events) = item.payload else { return [] }
        return events
    }
}
