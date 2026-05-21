import BackgroundTasks
import Foundation
import CoreTelemetry
import HealthArchiveExport
import Persistence
import Sync

enum HealthArchiveBackgroundExport {
    static let taskIdentifier = "com.ericfeunekes.WorkoutDB.health-archive.refresh"

    @MainActor
    static func run(
        makeController: @MainActor @Sendable (
            _ url: URL,
            _ token: String
        ) -> (any HealthArchiveExportControlling),
        tokenStore: any TokenStore,
        authRecoveryStore: (any AuthRecoveryStore)? = nil,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        prepareTelemetry: HealthArchiveAppHooks.PrepareTelemetry = {},
        activeController: @MainActor @Sendable (
            (any HealthArchiveExportControlling)?
        ) -> Void = { _ in }
    ) async -> HealthArchiveAppHooks.Result {
        await prepareTelemetry()
        HealthArchiveAppHooks.emitExportEvent(
            telemetry,
            name: "health_archive.background_export_requested",
            trigger: .backgroundScheduled
        )
        let connection: (url: URL, token: String)?
        do {
            connection = try tokenStore.loadConnection()
        } catch {
            HealthArchiveAppHooks.emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .backgroundScheduled,
                skipReason: "ConnectionUnavailable"
            )
            return .skipped(.connectionUnavailable)
        }
        guard let connection else {
            HealthArchiveAppHooks.emitExportEvent(
                telemetry,
                name: "health_archive.export_skipped",
                trigger: .backgroundScheduled,
                skipReason: "MissingConnection"
            )
            return .skipped(.missingConnection)
        }
        do {
            let controller = makeController(connection.url, connection.token)
            activeController(controller)
            defer { activeController(nil) }
            let summary = try await controller.exportIfDue(
                serverURL: connection.url,
                trigger: .backgroundScheduled
            )
            if let summary {
                HealthArchiveAppHooks.emitExportEvent(
                    telemetry,
                    name: "health_archive.export_succeeded",
                    trigger: .backgroundScheduled,
                    serverURL: connection.url,
                    summary: summary
                )
            } else {
                HealthArchiveAppHooks.emitExportEvent(
                    telemetry,
                    name: "health_archive.export_skipped",
                    trigger: .backgroundScheduled,
                    serverURL: connection.url,
                    skipReason: "NotDue"
                )
            }
            return .succeeded(summary)
        } catch SyncError.tokenRejected {
            authRecoveryStore?.markTokenRejected()
            HealthArchiveAppHooks.emitExportEvent(
                telemetry,
                name: "health_archive.export_token_rejected",
                trigger: .backgroundScheduled,
                serverURL: connection.url
            )
            return .tokenRejected
        } catch {
            let failureClass = String(describing: type(of: error))
            HealthArchiveAppHooks.emitExportEvent(
                telemetry,
                name: "health_archive.export_failed",
                trigger: .backgroundScheduled,
                serverURL: connection.url,
                failureClass: failureClass
            )
            return .failed(failureClass)
        }
    }
}

@MainActor
protocol HealthArchiveBackgroundTaskHandle: AnyObject {
    var expirationHandler: (@MainActor @Sendable () -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol HealthArchiveBackgroundTaskScheduling: AnyObject {
    @discardableResult
    func register(
        identifier: String,
        launchHandler: @escaping @MainActor @Sendable (
            any HealthArchiveBackgroundTaskHandle
        ) -> Void
    ) -> Bool
    func submit(identifier: String, earliestBeginDate: Date?) throws
    func cancel(identifier: String)
}

@MainActor
final class LiveHealthArchiveBackgroundTaskScheduler: HealthArchiveBackgroundTaskScheduling {
    func register(
        identifier: String,
        launchHandler: @escaping @MainActor @Sendable (
            any HealthArchiveBackgroundTaskHandle
        ) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in
                launchHandler(LiveHealthArchiveBackgroundTaskHandle(task: task))
            }
        }
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

@MainActor
private final class LiveHealthArchiveBackgroundTaskHandle: HealthArchiveBackgroundTaskHandle {
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    var expirationHandler: (@MainActor @Sendable () -> Void)? {
        get { nil }
        set {
            task.expirationHandler = {
                guard let newValue else { return }
                Task { @MainActor in
                    newValue()
                }
            }
        }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

@MainActor
final class HealthArchiveBackgroundExportScheduler {
    private let scheduler: any HealthArchiveBackgroundTaskScheduling
    private let tokenStore: any TokenStore
    private let authRecoveryStore: any AuthRecoveryStore
    private let stateStore: any HealthArchiveExportStateStore
    private let telemetry: TelemetryEmitter
    private let prepareTelemetry: HealthArchiveAppHooks.PrepareTelemetry
    private let makeController: @MainActor @Sendable (
        _ url: URL,
        _ token: String
    ) -> (any HealthArchiveExportControlling)
    private let now: @MainActor @Sendable () -> Date
    private var currentTask: Task<HealthArchiveAppHooks.Result, Never>?
    private var currentController: (any HealthArchiveExportControlling)?
    private var currentBackgroundTask: (any HealthArchiveBackgroundTaskHandle)?
    private var completedCurrentBackgroundTask = false
    private var didRegister = false

    init(
        scheduler: any HealthArchiveBackgroundTaskScheduling =
            LiveHealthArchiveBackgroundTaskScheduler(),
        tokenStore: any TokenStore,
        authRecoveryStore: any AuthRecoveryStore = AuthRecoveryStoreImpl(),
        stateStore: any HealthArchiveExportStateStore,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        prepareTelemetry: @escaping HealthArchiveAppHooks.PrepareTelemetry = {},
        now: @escaping @MainActor @Sendable () -> Date = { Date() },
        makeController: @escaping @MainActor @Sendable (
            _ url: URL,
            _ token: String
        ) -> (any HealthArchiveExportControlling)
    ) {
        self.scheduler = scheduler
        self.tokenStore = tokenStore
        self.authRecoveryStore = authRecoveryStore
        self.stateStore = stateStore
        self.telemetry = telemetry
        self.prepareTelemetry = prepareTelemetry
        self.now = now
        self.makeController = makeController
    }

    @discardableResult
    func register() -> Bool {
        guard !didRegister else { return true }
        let registered = scheduler.register(
            identifier: HealthArchiveBackgroundExport.taskIdentifier
        ) { [weak self] task in
            self?.handle(task)
        }
        didRegister = registered
        return registered
    }

    func scheduleIfAutomaticEnabled() async {
        await prepareTelemetry()
        guard !authRecoveryStore.isTokenRejected() else {
            scheduler.cancel(identifier: HealthArchiveBackgroundExport.taskIdentifier)
            return
        }
        let connection: (url: URL, token: String)?
        do {
            connection = try tokenStore.loadConnection()
        } catch {
            scheduler.cancel(identifier: HealthArchiveBackgroundExport.taskIdentifier)
            return
        }
        guard let connection else {
            scheduler.cancel(identifier: HealthArchiveBackgroundExport.taskIdentifier)
            return
        }
        let serverNamespace = HealthArchiveServerNamespace.normalized(from: connection.url)
        let snapshot = await stateStore.loadSnapshot(serverNamespace: serverNamespace)
        guard snapshot.automaticEnabled else {
            scheduler.cancel(identifier: HealthArchiveBackgroundExport.taskIdentifier)
            return
        }
        do {
            try scheduler.submit(
                identifier: HealthArchiveBackgroundExport.taskIdentifier,
                earliestBeginDate: nextEarliestBeginDate(snapshot: snapshot)
            )
            HealthArchiveAppHooks.emitExportEvent(
                telemetry,
                name: "health_archive.bg_schedule_submitted",
                trigger: .backgroundScheduled,
                serverURL: connection.url
            )
        } catch {
            await stateStore.saveSnapshot(HealthArchiveExportSnapshot(
                scope: snapshot.scope,
                serverNamespace: serverNamespace,
                requestSetKey: snapshot.requestSetKey,
                descriptorFingerprint: snapshot.descriptorFingerprint,
                acknowledgedCursor: snapshot.acknowledgedCursor,
                status: .failed,
                lastFetchAt: snapshot.lastFetchAt,
                lastUploadAt: snapshot.lastUploadAt,
                lastRecordCount: snapshot.lastRecordCount,
                lastTombstoneCount: snapshot.lastTombstoneCount,
                lastFailureClass: "BGTaskScheduleFailed",
                automaticEnabled: snapshot.automaticEnabled,
                nextAttemptAt: snapshot.nextAttemptAt,
                lastAttemptAt: snapshot.lastAttemptAt
            ))
            HealthArchiveAppHooks.emitExportEvent(
                telemetry,
                name: "health_archive.bg_schedule_failed",
                trigger: .backgroundScheduled,
                serverURL: connection.url,
                failureClass: String(describing: type(of: error))
            )
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        let controller = currentController
        currentController = nil
        Task { await controller?.retire() }
        scheduler.cancel(identifier: HealthArchiveBackgroundExport.taskIdentifier)
    }

    private func handle(_ task: any HealthArchiveBackgroundTaskHandle) {
        currentBackgroundTask = task
        completedCurrentBackgroundTask = false
        let run = Task { @MainActor in
            await HealthArchiveBackgroundExport.run(
                makeController: makeController,
                tokenStore: tokenStore,
                authRecoveryStore: authRecoveryStore,
                telemetry: telemetry,
                prepareTelemetry: prepareTelemetry,
                activeController: { [weak self] controller in
                    self?.currentController = controller
                }
            )
        }
        currentTask = run
        task.expirationHandler = { [weak self, weak task] in
            guard let self, let task else { return }
            let telemetry = self.telemetry
            let prepareTelemetry = self.prepareTelemetry
            Task { @MainActor in
                await prepareTelemetry()
                HealthArchiveAppHooks.emitExportEvent(
                    telemetry,
                    name: "health_archive.bg_expired",
                    trigger: .backgroundScheduled
                )
            }
            self.currentTask?.cancel()
            self.currentTask = nil
            let controller = self.currentController
            self.currentController = nil
            Task { await controller?.retire() }
            self.complete(task, success: false)
            self.currentBackgroundTask = nil
        }
        Task { @MainActor in
            let result = await run.value
            guard currentBackgroundTask === task else { return }
            currentTask = nil
            currentController = nil
            await scheduleIfAutomaticEnabled()
            complete(task, success: result.wasSuccessfulBackgroundCompletion)
            currentBackgroundTask = nil
        }
    }

    private func complete(_ task: any HealthArchiveBackgroundTaskHandle, success: Bool) {
        guard !completedCurrentBackgroundTask else { return }
        completedCurrentBackgroundTask = true
        task.setTaskCompleted(success: success)
    }

    private func nextEarliestBeginDate(snapshot: HealthArchiveExportSnapshot) -> Date? {
        guard let nextAttemptAt = snapshot.nextAttemptAt else {
            return now()
        }
        return nextAttemptAt
    }
}

private extension HealthArchiveAppHooks.Result {
    var wasSuccessfulBackgroundCompletion: Bool {
        switch self {
        case .succeeded:
            return true
        case .skipped, .tokenRejected, .failed:
            return false
        }
    }
}
