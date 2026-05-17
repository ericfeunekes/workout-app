import XCTest
import CoreDomain
import Persistence
@testable import Shell
import Sync

final class PushFlusherTests: XCTestCase {

    func testPeriodicTickReportsTokenRejectedAndLeavesQueueDurable() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
        let transport = ScriptedTransport(postOutcomes: [.status(401, Data())])
        let api = SyncAPI(
            transport: transport,
            store: factory.pushQueueStore,
            tokenProvider: { "tok" }
        )
        try await api.pushStatus(
            workoutID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            status: .completed,
            completedAt: Date()
        )
        let callback = TokenRejectedCallback()
        let flusher = PushFlusher(api: api, onTokenRejected: {
            await callback.record()
        })

        let keepGoing = await flusher.tick()

        XCTAssertFalse(keepGoing)
        let callbackCount = await callback.count()
        XCTAssertEqual(callbackCount, 1)
        let isEmpty = try await factory.pushQueueStore.isEmpty()
        XCTAssertFalse(isEmpty)
    }
}

private actor TokenRejectedCallback {
    private var value = 0

    func count() -> Int { value }

    func record() {
        value += 1
    }
}
