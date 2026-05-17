import XCTest
import Persistence
import WorkoutCoreFoundation
@testable import Shell

@MainActor
final class AppSyncLocalStateResetTests: XCTestCase {

    func testClearConnectionAndCachedServerDataClearsTokenCacheAndCursor() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        try factory.tokenStore.saveConnection(
            url: try XCTUnwrap(URL(string: "https://old.example.test")),
            token: "old-token"
        )
        try await factory.workoutCache.save(PulledDataset(
            workouts: [fixture.domainWorkout],
            blocks: fixture.domainBlocks,
            items: fixture.domainItems,
            alternatives: [],
            exercises: fixture.domainExercises,
            userParameters: []
        ))
        await factory.syncMetadataStore.setLastSyncAt(fixture.serverTime)

        await AppSyncLocalStateReset.clearConnectionAndCachedServerData(
            persistence: factory
        )

        let connection = try factory.tokenStore.loadConnection()
        XCTAssertNil(connection)
        let workouts = try await factory.workoutCache.loadWorkouts(status: nil, since: nil)
        XCTAssertTrue(workouts.isEmpty)
        let lastSyncAt = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertNil(lastSyncAt)
    }
}
