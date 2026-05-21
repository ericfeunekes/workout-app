import Foundation
import HealthArchiveExport
import HealthKitBridge
import Persistence
import Sync

@discardableResult
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws -> Bool {
    guard condition() else {
        throw TestFailure(message)
    }
    return true
}

private func expect<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TestFailure(message)
    }
    return value
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw TestFailure("expected \(expected), got \(actual)")
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func runAsyncCase(_ name: String, _ body: @escaping () async throws -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            Foundation.exit(1)
        }
        semaphore.signal()
    }
    semaphore.wait()
}

private struct NoopPushQueueStore: PushQueueStore {
    func enqueue(_ item: PushItem) async throws {}
    func peek(max: Int) async throws -> [PushItem] { [] }
    func remove(ids: [PushItemID]) async throws {}
    func update(_ item: PushItem) async throws {}
    func removeMatchingDedupKey(_ key: String) async throws -> Int { 0 }
    func enqueue(_ item: PushItem, replacingDedupKeys keys: Set<String>) async throws {}
    func isEmpty() async throws -> Bool { true }
    func clear() async throws {}
}

private enum FakeOutcome {
    case response(HTTPResponse)
    case error(SyncError)
    case archiveSuccess(cursor: String?)
}

private actor FakeTransportState {
    var outcomes: [FakeOutcome]
    var posts: [(path: String, body: Data, token: String)] = []

    init(outcomes: [FakeOutcome]) {
        self.outcomes = outcomes
    }

    func nextPost(path: String, body: Data, token: String) throws -> HTTPResponse {
        posts.append((path, body, token))
        guard !outcomes.isEmpty else {
            return HTTPResponse(status: 200, body: Data())
        }
        switch outcomes.removeFirst() {
        case .response(let response):
            return response
        case .error(let error):
            throw error
        case .archiveSuccess(let cursor):
            return HTTPResponse(status: 200, body: uploadResponse(body: body, cursor: cursor))
        }
    }
}

private struct FakeTransport: HTTPTransport {
    let state: FakeTransportState

    init(outcomes: [FakeOutcome]) {
        self.state = FakeTransportState(outcomes: outcomes)
    }

    func get(path: String, query: [(String, String)], bearerToken: String) async throws
        -> HTTPResponse {
        HTTPResponse(status: 200, body: Data())
    }

    func post(path: String, body: Data, bearerToken: String) async throws -> HTTPResponse {
        try await state.nextPost(path: path, body: body, token: bearerToken)
    }
}

private final class DelayedUploadTransport: HTTPTransport, @unchecked Sendable {
    private let delayNanoseconds: UInt64
    private let storage = FakeDelayedUploadStorage()

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    var completedPosts: Int { storage.completedPosts }

    func get(path: String, query: [(String, String)], bearerToken: String) async throws
        -> HTTPResponse {
        HTTPResponse(status: 200, body: Data())
    }

    func post(path: String, body: Data, bearerToken: String) async throws -> HTTPResponse {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        storage.completedPosts += 1
        return HTTPResponse(status: 200, body: uploadResponse(body: body, cursor: "cursor-delayed"))
    }
}

private final class FakeDelayedUploadStorage: @unchecked Sendable {
    nonisolated(unsafe) var completedPosts = 0
}

private final class DelayedHealthBatchDataProvider: HealthBatchDataProvider, @unchecked Sendable {
    private let result: HealthBatchResult
    private let delayNanoseconds: UInt64
    private let storage = FakeDelayedHealthBatchStorage()

    init(result: HealthBatchResult, delayNanoseconds: UInt64) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    var queries: [HealthBatchQuery] { storage.queries }

    func fetch(_ query: HealthBatchQuery) async throws -> HealthBatchResult {
        try HealthDataRequestValidator.validateBatchFetchRequests(query.requests)
        storage.queries.append(query)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return result
    }
}

private final class FakeDelayedHealthBatchStorage: @unchecked Sendable {
    nonisolated(unsafe) var queries: [HealthBatchQuery] = []
}

private func uploadResponse(body: Data, cursor: String?) -> Data {
    let requestSetKey = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?[
        "request_set_key"
    ] as? String ?? ""
    let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
    return """
    {
      "request_set_key": "\(requestSetKey)",
      "acknowledged_cursor": \(cursorJSON),
      "records_received": 1,
      "tombstones_received": 1,
      "server_time": "2026-05-18T12:10:00Z"
    }
    """.data(using: .utf8)!
}

private func makeCoordinator(
    permissions: FakeHealthPermissionBroker = FakeHealthPermissionBroker(),
    transport: any HTTPTransport,
    batch: any HealthBatchDataProvider,
    store: PersistenceFactory
) -> HealthArchiveExportCoordinator {
    let syncAPI = SyncAPI(
        transport: transport,
        store: NoopPushQueueStore(),
        tokenProvider: { "tok" }
    )
    return HealthArchiveExportCoordinator(
        permissions: permissions,
        batch: batch,
        archiveStore: store.healthArchiveStore,
        stateStore: store.healthArchiveExportStateStore,
        syncAPI: syncAPI,
        now: {
            ISO8601DateFormatter().date(from: "2026-05-18T12:00:00Z") ?? Date()
        }
    )
}

runAsyncCase("manual export advances cursor only after upload success") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-1")
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [
            HealthDataRecord(
                id: "sample-1",
                type: HealthDataTypeRegistry.heartRate,
                start: Date(),
                end: Date(),
                value: .quantity(122, unit: "count/min")
            )
        ],
        deletedRecords: [
            HealthDeletedRecord(
                externalID: "deleted-1",
                type: HealthDataTypeRegistry.heartRate
            )
        ],
        nextCursor: HealthBatchCursor("cursor-1")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)

    let summary = try await coordinator.exportNow(
        serverURL: URL(string: "http://localhost:8000")!
    )
    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )
    let posts = await transport.state.posts

    try expect(summary.acknowledgedCursor == "cursor-1", "summary cursor")
    try expect(snapshot.acknowledgedCursor == "cursor-1", "snapshot cursor")
    let storedCursor = try await store.healthArchiveStore.loadCursor(
        requestSetKey: snapshot.requestSetKey ?? ""
    )
    try expect(storedCursor?.cursor == "cursor-1", "request-set cursor")
    try expect(snapshot.serverNamespace == "http://localhost:8000", "full server namespace")
    try expect(
        snapshot.requestSetKey?.hasPrefix("http://localhost:8000|all-supported|") == true,
        "request set key includes full server namespace"
    )
    try expect(snapshot.status == .succeeded, "snapshot succeeded")
    try expect(posts.first?.path == "/api/health/archive", "upload path")
}

runAsyncCase("upload failure keeps previous acknowledged cursor") {
    let store = try PersistenceFactory.makeInMemory()
    let successTransport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-old")
    ])
    let successBatch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-old")
    ))
    let successCoordinator = makeCoordinator(
        transport: successTransport,
        batch: successBatch,
        store: store
    )
    _ = try await successCoordinator.exportNow(
        serverURL: URL(string: "http://localhost:8000")!
    )

    let failingTransport = FakeTransport(outcomes: [.error(.network("offline"))])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [
            HealthDataRecord(
                id: "sample-1",
                type: HealthDataTypeRegistry.heartRate,
                value: .quantity(122, unit: "count/min")
            )
        ],
        nextCursor: HealthBatchCursor("cursor-new")
    ))
    let coordinator = makeCoordinator(transport: failingTransport, batch: batch, store: store)

    do {
        _ = try await coordinator.exportNow(
            serverURL: URL(string: "http://localhost:8000")!
        )
        try expect(false, "expected upload failure")
    } catch {}
    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )
    let storedCursor = try await store.healthArchiveStore.loadCursor(
        requestSetKey: snapshot.requestSetKey ?? ""
    )
    try expect(storedCursor?.cursor == "cursor-old", "cursor did not advance")
    try expect(snapshot.status == .failed, "failed status")
}

runAsyncCase("request set acknowledgement mismatch does not advance cursor") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: """
        {
          "request_set_key": "wrong-request-set",
          "acknowledged_cursor": "cursor-new",
          "records_received": 0,
          "tombstones_received": 0,
          "server_time": "2026-05-18T12:10:00Z"
        }
        """.data(using: .utf8)!))
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-new")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)

    do {
        _ = try await coordinator.exportNow(serverURL: URL(string: "http://localhost:8000")!)
        try expect(false, "expected request set mismatch")
    } catch HealthArchiveExportError.requestSetAcknowledgementMismatch(
        let expected,
        let actual
    ) {
        try expect(expected.hasPrefix("http://localhost:8000|all-supported|"), "expected key")
        try expectEqual(actual, "wrong-request-set")
    }

    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )
    let storedCursor = try await store.healthArchiveStore.loadCursor(
        requestSetKey: snapshot.requestSetKey ?? ""
    )
    try expect(storedCursor == nil, "mismatched acknowledgement must not advance cursor")
    try expect(snapshot.status == .failed, "mismatch should mark failed")
}

runAsyncCase("manual export requests and fetches all supported batch descriptors") {
    let store = try PersistenceFactory.makeInMemory()
    let permissions = FakeHealthPermissionBroker()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-1")
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-1")
    ))
    let coordinator = makeCoordinator(
        permissions: permissions,
        transport: transport,
        batch: batch,
        store: store
    )

    _ = try await coordinator.exportNow(
        serverURL: URL(string: "http://localhost:8000")!
    )

    let expectedIDs = Set(LiveHealthDataProvider.supportedBatchTypes().map(\.id))
    let permissionIDs = Set(permissions.requested.map(\.type.id))
    let query = try expect(batch.queries.first, "expected a batch query")
    let fetchIDs = Set(query.requests.map(\.type.id))

    try expectEqual(permissionIDs, expectedIDs)
    try expectEqual(fetchIDs, expectedIDs)
    try expect(
        permissions.requested.allSatisfy { $0.access == .read && $0.delivery == .batch },
        "all permission requests should be batch read requests"
    )
    try expect(
        query.requests.allSatisfy { $0.access == .read && $0.delivery == .batch },
        "all fetch requests should be batch read requests"
    )
}

runAsyncCase("manual export persists and uploads category and workout records") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-1")
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [
            HealthDataRecord(
                id: "sleep-1",
                type: HealthDataTypeRegistry.sleepAnalysis,
                value: .category(1)
            ),
            HealthDataRecord(
                id: "workout-1",
                type: HealthDataTypeRegistry.workout,
                value: .workout(
                    activityType: "37",
                    durationSeconds: 1800,
                    totalEnergyKcal: 220
                )
            ),
        ],
        nextCursor: HealthBatchCursor("cursor-1")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)

    _ = try await coordinator.exportNow(serverURL: URL(string: "http://localhost:8000")!)

    let stored = try await store.healthArchiveStore.loadRecords(descriptorID: nil)
    let posts = await transport.state.posts
    let body = String(data: posts[0].body, encoding: .utf8) ?? ""

    try expectEqual(Set(stored.map(\.sampleKindRaw)), Set(["category", "workout"]))
    try expect(body.contains(#""sample_kind":"category""#), "category sample kind uploaded")
    try expect(body.contains(#""category_value":1"#), "category value uploaded")
    try expect(body.contains(#""sample_kind":"workout""#), "workout sample kind uploaded")
    try expect(body.contains(#""workout_activity_type":"37""#), "workout value uploaded")
}

runAsyncCase("explicit subset drives permission fetch fingerprint and cursor key") {
    let store = try PersistenceFactory.makeInMemory()
    await store.healthArchiveExportStateStore.setScope(.explicitDescriptorIDs([
        HealthDataTypeRegistry.heartRate.id,
        HealthDataTypeRegistry.stepCount.id,
    ]))
    let permissions = FakeHealthPermissionBroker()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-subset")
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-subset")
    ))
    let coordinator = makeCoordinator(
        permissions: permissions,
        transport: transport,
        batch: batch,
        store: store
    )

    _ = try await coordinator.exportNow(serverURL: URL(string: "http://localhost:8000")!)

    let permissionIDs = Set(permissions.requested.map(\.type.id))
    let query = try expect(batch.queries.first, "expected a batch query")
    let fetchIDs = Set(query.requests.map(\.type.id))
    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )

    try expectEqual(permissionIDs, Set([
        HealthDataTypeRegistry.heartRate.id,
        HealthDataTypeRegistry.stepCount.id,
    ]))
    try expectEqual(fetchIDs, permissionIDs)
    try expect(
        snapshot.requestSetKey?.contains("|explicit|") == true,
        "explicit request set key"
    )
}

runAsyncCase("unsupported explicit descriptor fails before permission request") {
    let store = try PersistenceFactory.makeInMemory()
    await store.healthArchiveExportStateStore.setScope(.explicitDescriptorIDs(["missing"]))
    let permissions = FakeHealthPermissionBroker()
    let transport = FakeTransport(outcomes: [])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(records: []))
    let coordinator = makeCoordinator(
        permissions: permissions,
        transport: transport,
        batch: batch,
        store: store
    )

    do {
        _ = try await coordinator.exportNow(serverURL: URL(string: "http://localhost:8000")!)
        try expect(false, "expected unsupported descriptor failure")
    } catch HealthArchiveExportError.unsupportedDescriptorIDs(let ids) {
        try expectEqual(ids, ["missing"])
    }

    try expectEqual(permissions.requested.count, 0)
    try expectEqual(batch.queries.count, 0)
}

runAsyncCase("runtime reports already running for overlapping triggers") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-1")
    ])
    let batch = DelayedHealthBatchDataProvider(
        result: HealthBatchResult(records: [], nextCursor: HealthBatchCursor("cursor-1")),
        delayNanoseconds: 200_000_000
    )
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)
    let runtime = HealthArchiveExportRuntime(coordinator: coordinator)
    let serverURL = URL(string: "http://localhost:8000")!

    let first = Task {
        try await runtime.exportNow(serverURL: serverURL, trigger: .manual)
    }
    try await Task.sleep(nanoseconds: 20_000_000)
    let second = try await runtime.exportNow(serverURL: serverURL, trigger: .foregroundCatchUp)
    let firstSummary = try await first.value

    try expect(second.alreadyRunning, "second trigger reports already running")
    try expectEqual(second.recordsFetched, 0)
    try expectEqual(batch.queries.count, 1)
    try expect(!firstSummary.alreadyRunning, "first trigger still performs export")
}

runAsyncCase("retired runtime suppresses stale export completion writes") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-1")
    ])
    let batch = DelayedHealthBatchDataProvider(
        result: HealthBatchResult(
            records: [
                HealthDataRecord(
                    id: "sample-1",
                    type: HealthDataTypeRegistry.heartRate,
                    value: .quantity(122, unit: "count/min")
                ),
            ],
            nextCursor: HealthBatchCursor("cursor-1")
        ),
        delayNanoseconds: 200_000_000
    )
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)
    let runtime = HealthArchiveExportRuntime(coordinator: coordinator)
    let serverURL = URL(string: "http://localhost:8000")!

    let export = Task {
        try await runtime.exportNow(serverURL: serverURL, trigger: .manual)
    }
    try await Task.sleep(nanoseconds: 20_000_000)
    await runtime.retire()

    do {
        _ = try await export.value
        try expect(false, "expected retired export to cancel")
    } catch is CancellationError {}

    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )
    let posts = await transport.state.posts
    let records = try await store.healthArchiveStore.loadRecords(descriptorID: nil)

    try expectEqual(snapshot.status, .failed)
    try expectEqual(snapshot.lastFailureClass, "InterruptedExport")
    try expectEqual(posts.count, 0)
    try expectEqual(records.count, 0)
}

runAsyncCase("retired runtime cancels suspended upload before old-server post completes") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = DelayedUploadTransport(delayNanoseconds: 500_000_000)
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [
            HealthDataRecord(
                id: "sample-1",
                type: HealthDataTypeRegistry.heartRate,
                value: .quantity(122, unit: "count/min")
            ),
        ],
        nextCursor: HealthBatchCursor("cursor-delayed")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)
    let runtime = HealthArchiveExportRuntime(coordinator: coordinator)
    let serverURL = URL(string: "http://localhost:8000")!

    let export = Task {
        try await runtime.exportNow(serverURL: serverURL, trigger: .manual)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    await runtime.retire()

    do {
        _ = try await export.value
        try expect(false, "expected retired upload to cancel")
    } catch is CancellationError {}

    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )
    let storedCursor = try await store.healthArchiveStore.loadCursor(
        requestSetKey: snapshot.requestSetKey ?? ""
    )
    let storedRecords = try await store.healthArchiveStore.loadRecords(descriptorID: nil)

    try expectEqual(transport.completedPosts, 0)
    try expect(storedCursor == nil, "retired upload must not advance cursor")
    try expectEqual(storedRecords.count, 0)
    try expectEqual(snapshot.status, .failed)
    try expectEqual(snapshot.lastFailureClass, "InterruptedExport")
}

runAsyncCase("token rejected export persists token failure class") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [.error(.tokenRejected)])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-new")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)

    do {
        _ = try await coordinator.exportNow(serverURL: URL(string: "http://localhost:8000")!)
        try expect(false, "expected token rejection")
    } catch SyncError.tokenRejected {}

    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )

    try expectEqual(snapshot.status, .failed)
    try expectEqual(snapshot.lastFailureClass, "TokenRejected")
}

runAsyncCase("exportIfDue respects automatic control and uses foreground trigger") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-1")
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-1")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)
    let runtime = HealthArchiveExportRuntime(coordinator: coordinator)
    let serverURL = URL(string: "http://localhost:8000")!

    let disabled = try await runtime.exportIfDue(serverURL: serverURL)
    try expect(disabled == nil, "disabled automatic export should not run")

    await store.healthArchiveExportStateStore.setAutomaticEnabled(true)
    let due = try await runtime.exportIfDue(serverURL: serverURL)
    let summary = try expect(due, "enabled due automatic export should run")

    try expectEqual(summary.trigger, .foregroundCatchUp)
    try expectEqual(batch.queries.count, 1)
}

runAsyncCase("exportIfDue reruns after stale running snapshot") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-after-stale")
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-after-stale")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)
    let runtime = HealthArchiveExportRuntime(coordinator: coordinator)
    let serverURL = URL(string: "http://localhost:8000")!

    await store.healthArchiveExportStateStore.setAutomaticEnabled(true)
    await store.healthArchiveExportStateStore.saveSnapshot(HealthArchiveExportSnapshot(
        serverNamespace: "http://localhost:8000",
        requestSetKey: "http://localhost:8000|all-supported|stale",
        descriptorFingerprint: "stale",
        acknowledgedCursor: "cursor-before-stale",
        status: .running,
        automaticEnabled: true,
        lastAttemptAt: Date().addingTimeInterval(-31 * 60)
    ))

    let summary = try await expect(
        runtime.exportIfDue(serverURL: serverURL),
        "stale running automatic export should rerun"
    )
    let snapshot = await store.healthArchiveExportStateStore.loadSnapshot(
        serverNamespace: "http://localhost:8000"
    )
    let posts = await transport.state.posts

    try expectEqual(summary.trigger, .foregroundCatchUp)
    try expectEqual(batch.queries.count, 1)
    try expectEqual(posts.count, 1)
    try expectEqual(snapshot.status, .succeeded)
    try expectEqual(snapshot.acknowledgedCursor, "cursor-after-stale")
}

runAsyncCase("next attempt is scoped by server namespace") {
    let store = try PersistenceFactory.makeInMemory()
    let serverATransport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-a")
    ])
    let serverABatch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-a")
    ))
    let serverACoordinator = makeCoordinator(
        transport: serverATransport,
        batch: serverABatch,
        store: store
    )
    let serverARuntime = HealthArchiveExportRuntime(coordinator: serverACoordinator)
    await store.healthArchiveExportStateStore.setAutomaticEnabled(true)

    _ = try await serverARuntime.exportIfDue(serverURL: URL(string: "http://server-a")!)

    let serverBTransport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-b")
    ])
    let serverBBatch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor-b")
    ))
    let serverBCoordinator = makeCoordinator(
        transport: serverBTransport,
        batch: serverBBatch,
        store: store
    )
    let serverBRuntime = HealthArchiveExportRuntime(coordinator: serverBCoordinator)

    let serverBSummary = try await expect(
        serverBRuntime.exportIfDue(serverURL: URL(string: "http://server-b")!),
        "new server should be due even after server-a success"
    )

    try expectEqual(serverBSummary.trigger, .foregroundCatchUp)
    try expectEqual(serverABatch.queries.count, 1)
    try expectEqual(serverBBatch.queries.count, 1)
}

runAsyncCase("next attempt is scoped by request set on the same server") {
    let store = try PersistenceFactory.makeInMemory()
    let transport = FakeTransport(outcomes: [
        .archiveSuccess(cursor: "cursor-all"),
        .archiveSuccess(cursor: "cursor-subset"),
    ])
    let batch = FakeHealthBatchDataProvider(result: HealthBatchResult(
        records: [],
        nextCursor: HealthBatchCursor("cursor")
    ))
    let coordinator = makeCoordinator(transport: transport, batch: batch, store: store)
    let runtime = HealthArchiveExportRuntime(coordinator: coordinator)
    let serverURL = URL(string: "http://localhost:8000")!
    await store.healthArchiveExportStateStore.setAutomaticEnabled(true)

    _ = try await expect(
        runtime.exportIfDue(serverURL: serverURL),
        "first request set should be due"
    )
    let suppressed = try await runtime.exportIfDue(serverURL: serverURL)
    try expect(suppressed == nil, "unchanged request set should wait for next attempt")

    await store.healthArchiveExportStateStore.setScope(.explicitDescriptorIDs([
        HealthDataTypeRegistry.heartRate.id,
    ]))
    let changedScope = try await expect(
        runtime.exportIfDue(serverURL: serverURL),
        "same-server scope change should be due"
    )

    try expectEqual(changedScope.trigger, .foregroundCatchUp)
    try expectEqual(batch.queries.count, 2)
}
