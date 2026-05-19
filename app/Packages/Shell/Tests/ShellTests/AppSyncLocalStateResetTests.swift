import XCTest
import CoreTelemetry
import Persistence
import Sync
import WorkoutCoreFoundation
@testable import Shell

@MainActor
final class AppSyncLocalStateResetTests: XCTestCase {

    func testClearConnectionAndLocalServerDataClearsTokenWorkoutCacheAndCursorButPreservesArchive() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenStore: FakeTokenStore()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let archiveRecord = HealthArchiveRecord(
            externalID: "sample-1",
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            sampleKindRaw: "quantity",
            value: .quantity(120, unit: "count/min")
        )
        let archiveDeletion = HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            externalID: "deleted-sample",
            observedAt: Date(timeIntervalSince1970: 1_000)
        )
        let archiveCursor = HealthArchiveCursor(
            requestSetKey: "archive-all",
            cursor: "cursor-1"
        )
        try factory.tokenStore.saveConnection(
            url: try XCTUnwrap(URL(string: "https://old.example.test")),
            token: "old-token"
        )
        try await factory.sessionStore.save(Data("active-session".utf8))
        await factory.lastPerformedStore.save([fixture.domainExercises[0].id: "LAST · 100 x 5"])
        try await factory.pushQueueStore.enqueue(PushItem(
            payload: .events([Event(sessionID: UUID(), kind: "test", name: "queued")]),
            enqueuedAt: Date(timeIntervalSince1970: 1_100)
        ))
        factory.authRecoveryStore.markTokenRejected()
        try await factory.workoutCache.save(PulledDataset(
            workouts: [fixture.domainWorkout],
            blocks: fixture.domainBlocks,
            items: fixture.domainItems,
            alternatives: [],
            exercises: fixture.domainExercises,
            userParameters: []
        ))
        try await factory.healthArchiveStore.save(
            records: [archiveRecord],
            deletions: [archiveDeletion],
            cursors: [archiveCursor]
        )
        await factory.syncMetadataStore.setLastSyncAt(fixture.serverTime)

        let didClear = await AppSyncLocalStateReset.clearConnectionAndLocalServerData(
            persistence: factory
        )

        XCTAssertTrue(didClear.succeeded)
        let connection = try factory.tokenStore.loadConnection()
        XCTAssertNil(connection)
        let workouts = try await factory.workoutCache.loadWorkouts(status: nil, since: nil)
        XCTAssertTrue(workouts.isEmpty)
        let session = try await factory.sessionStore.load()
        XCTAssertNil(session)
        let lastPerformed = await factory.lastPerformedStore.load()
        XCTAssertTrue(lastPerformed.isEmpty)
        let queued = try await factory.pushQueueStore.peek(max: 10)
        XCTAssertTrue(queued.isEmpty)
        let archiveRecords = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertEqual(archiveRecords.count, 1)
        XCTAssertEqual(archiveRecords[0].externalID, "sample-1")
        let archiveDeletions = try await factory.healthArchiveStore.loadDeletions(descriptorID: nil)
        XCTAssertEqual(archiveDeletions.count, 1)
        let cursor = try await factory.healthArchiveStore.loadCursor(requestSetKey: "archive-all")
        XCTAssertEqual(cursor?.cursor, "cursor-1")
        let lastSyncAt = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertNil(lastSyncAt)
        let isTokenRejected = factory.authRecoveryStore.isTokenRejected()
        XCTAssertFalse(isTokenRejected)
    }

    func testClearLocalServerDataPreservesTokenAndArchiveButClearsServerOwnedLocalState() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenStore: FakeTokenStore()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        try factory.tokenStore.saveConnection(
            url: try XCTUnwrap(URL(string: "https://server.example.test")),
            token: "server-token"
        )
        try await seedServerOwnedLocalState(factory: factory, fixture: fixture)
        factory.authRecoveryStore.markTokenRejected()
        try await seedArchive(factory: factory)

        let didClear = await AppSyncLocalStateReset.clearLocalServerData(persistence: factory)

        XCTAssertTrue(didClear.succeeded)
        let connection = try factory.tokenStore.loadConnection()
        XCTAssertEqual(connection?.token, "server-token")
        let isTokenRejected = factory.authRecoveryStore.isTokenRejected()
        XCTAssertFalse(isTokenRejected)
        try await assertServerOwnedLocalStateCleared(factory: factory)
        let archiveRecords = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertEqual(archiveRecords.map(\.externalID), ["sample-1"])
    }

    func testPauseForTokenRejectedPreservesConnectionServerOwnedStateAndArchive() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenStore: FakeTokenStore()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        try factory.tokenStore.saveConnection(
            url: try XCTUnwrap(URL(string: "https://server.example.test")),
            token: "rejected-token"
        )
        try await seedServerOwnedLocalState(factory: factory, fixture: fixture)
        try await seedArchive(factory: factory)

        let didPause = await AppSyncLocalStateReset.pauseForTokenRejected(persistence: factory)

        XCTAssertTrue(didPause.succeeded)
        let connection = try factory.tokenStore.loadConnection()
        XCTAssertEqual(connection?.token, "rejected-token")
        let workouts = try await factory.workoutCache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(workouts.map(\.id), [fixture.domainWorkout.id])
        let session = try await factory.sessionStore.load()
        XCTAssertEqual(session, Data("active-session".utf8))
        let lastPerformed = await factory.lastPerformedStore.load()
        XCTAssertEqual(lastPerformed[fixture.domainExercises[0].id], "LAST · 100 x 5")
        let queued = try await factory.pushQueueStore.peek(max: 10)
        XCTAssertEqual(queued.count, 1)
        let archiveRecords = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertEqual(archiveRecords.map(\.externalID), ["sample-1"])
        let lastSyncAt = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertEqual(lastSyncAt, fixture.serverTime)
        let isTokenRejected = factory.authRecoveryStore.isTokenRejected()
        XCTAssertTrue(isTokenRejected)
    }

    func testClearLocalStateClearsServerOwnedStoresBeforeIdentityAndRecoveryMarkers() async {
        var operations: [String] = []

        let didClear = await AppSyncLocalStateReset.clearLocalState(
            clearWorkoutCache: {
                operations.append("cache")
            },
            clearSession: {
                operations.append("session")
            },
            clearLastPerformed: {
                operations.append("last-performed")
            },
            clearPushQueue: {
                operations.append("queue")
            },
            clearSyncCursor: {
                operations.append("cursor")
            },
            clearTokenRejected: {
                operations.append("token-rejected")
            },
            clearToken: {
                operations.append("token")
            }
        )

        XCTAssertTrue(didClear.succeeded)
        XCTAssertEqual(operations, [
            "cursor",
            "cache",
            "session",
            "last-performed",
            "queue",
            "token",
            "token-rejected",
        ])
    }

    func testClearLocalStatePreservesIdentityAndRecoveryMarkersWhenWorkoutCacheClearFails() async {
        var clearedCursor = false
        var clearedTokenRejected = false
        var clearedToken = false

        let didClear = await AppSyncLocalStateReset.clearLocalState(
            clearWorkoutCache: {
                throw FailingResetError()
            },
            clearSession: {},
            clearLastPerformed: {},
            clearPushQueue: {},
            clearSyncCursor: {
                clearedCursor = true
            },
            clearTokenRejected: {
                clearedTokenRejected = true
            },
            clearToken: {
                clearedToken = true
            }
        )

        XCTAssertFalse(didClear.succeeded)
        XCTAssertTrue(clearedCursor)
        XCTAssertFalse(clearedTokenRejected)
        XCTAssertFalse(clearedToken)
    }

    func testClearLocalStatePreservesIdentityAndRecoveryMarkersWhenSessionClearFails() async {
        var clearedCursor = false
        var clearedTokenRejected = false
        var clearedToken = false

        let didClear = await AppSyncLocalStateReset.clearLocalState(
            clearWorkoutCache: {},
            clearSession: {
                throw FailingResetError()
            },
            clearLastPerformed: {},
            clearPushQueue: {},
            clearSyncCursor: {
                clearedCursor = true
            },
            clearTokenRejected: {
                clearedTokenRejected = true
            },
            clearToken: {
                clearedToken = true
            }
        )

        XCTAssertFalse(didClear.succeeded)
        XCTAssertTrue(clearedCursor)
        XCTAssertFalse(clearedTokenRejected)
        XCTAssertFalse(clearedToken)
    }
}

private struct FailingResetError: Error {}

private final class FakeTokenStore: TokenStore, @unchecked Sendable {
    private var connection: (url: URL, token: String)?

    func saveConnection(url: URL, token: String) throws {
        connection = (url, token)
    }

    func loadConnection() throws -> (url: URL, token: String)? {
        connection
    }

    func clear() throws {
        connection = nil
    }
}

private func seedServerOwnedLocalState(
    factory: PersistenceFactory,
    fixture: Fixtures.WorkoutPayload
) async throws {
    try await factory.sessionStore.save(Data("active-session".utf8))
    await factory.lastPerformedStore.save([fixture.domainExercises[0].id: "LAST · 100 x 5"])
    try await factory.pushQueueStore.enqueue(PushItem(
        payload: .events([Event(sessionID: UUID(), kind: "test", name: "queued")]),
        enqueuedAt: Date(timeIntervalSince1970: 1_100)
    ))
    try await factory.workoutCache.save(PulledDataset(
        workouts: [fixture.domainWorkout],
        blocks: fixture.domainBlocks,
        items: fixture.domainItems,
        alternatives: [],
        exercises: fixture.domainExercises,
        userParameters: []
    ))
    await factory.syncMetadataStore.setLastSyncAt(fixture.serverTime)
}

private func seedArchive(factory: PersistenceFactory) async throws {
    try await factory.healthArchiveStore.save(
        records: [HealthArchiveRecord(
            externalID: "sample-1",
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            sampleKindRaw: "quantity",
            value: .quantity(120, unit: "count/min")
        )],
        deletions: [HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            externalID: "deleted-sample",
            observedAt: Date(timeIntervalSince1970: 1_000)
        )],
        cursors: [HealthArchiveCursor(
            requestSetKey: "archive-all",
            cursor: "cursor-1"
        )]
    )
}

private func assertServerOwnedLocalStateCleared(factory: PersistenceFactory) async throws {
    let workouts = try await factory.workoutCache.loadWorkouts(status: nil, since: nil)
    XCTAssertTrue(workouts.isEmpty)
    let session = try await factory.sessionStore.load()
    XCTAssertNil(session)
    let lastPerformed = await factory.lastPerformedStore.load()
    XCTAssertTrue(lastPerformed.isEmpty)
    let queued = try await factory.pushQueueStore.peek(max: 10)
    XCTAssertTrue(queued.isEmpty)
    let lastSyncAt = await factory.syncMetadataStore.getLastSyncAt()
    XCTAssertNil(lastSyncAt)
}
