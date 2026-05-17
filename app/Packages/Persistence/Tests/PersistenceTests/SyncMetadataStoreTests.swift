import XCTest
@testable import Persistence

final class SyncMetadataStoreTests: XCTestCase {

    func testClearLastSyncAtRemovesStoredCursor() async {
        let suiteName = "SyncMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SyncMetadataStoreImpl(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_778_000_000)

        await store.setLastSyncAt(date)
        let stored = await store.getLastSyncAt()
        XCTAssertEqual(stored, date)

        await store.clearLastSyncAt()

        let cleared = await store.getLastSyncAt()
        XCTAssertNil(cleared)
    }

}
