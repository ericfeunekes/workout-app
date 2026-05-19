import XCTest
@testable import Persistence

final class AuthRecoveryStoreTests: XCTestCase {
    func testTokenRejectedMarkerRoundTrip() {
        let defaults = UserDefaults(suiteName: "auth-recovery.\(UUID().uuidString)")!
        let store = AuthRecoveryStoreImpl(defaults: defaults)

        XCTAssertFalse(store.isTokenRejected())
        store.markTokenRejected()
        XCTAssertTrue(store.isTokenRejected())
        store.clearTokenRejected()
        XCTAssertFalse(store.isTokenRejected())
    }
}
