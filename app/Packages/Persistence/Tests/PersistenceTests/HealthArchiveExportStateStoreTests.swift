import XCTest
@testable import Persistence

final class HealthArchiveExportStateStoreTests: XCTestCase {
    func testServerScopedSnapshotsDoNotBleedAcrossNamespaces() async {
        let defaults = UserDefaults(suiteName: "health.archive.export.\(UUID().uuidString)")!
        let store = UserDefaultsHealthArchiveExportStateStore(defaults: defaults)

        await store.saveSnapshot(HealthArchiveExportSnapshot(
            scope: .allSupported,
            serverNamespace: "server-a",
            requestSetKey: "server-a|all-supported|fp",
            descriptorFingerprint: "fp",
            acknowledgedCursor: "cursor-a",
            status: .succeeded,
            lastRecordCount: 3,
            lastTombstoneCount: 1
        ))

        let serverA = await store.loadSnapshot(serverNamespace: "server-a")
        let serverB = await store.loadSnapshot(serverNamespace: "server-b")

        XCTAssertEqual(serverA.acknowledgedCursor, "cursor-a")
        XCTAssertEqual(serverA.lastRecordCount, 3)
        XCTAssertNil(serverB.acknowledgedCursor)
        XCTAssertEqual(serverB.status, .neverRun)
    }

    func testScopeIsControlStateSharedAcrossServerSnapshots() async {
        let defaults = UserDefaults(suiteName: "health.archive.export.\(UUID().uuidString)")!
        let store = UserDefaultsHealthArchiveExportStateStore(defaults: defaults)

        await store.setScope(.explicitDescriptorIDs(["a", "b"]))

        let snapshot = await store.loadSnapshot(serverNamespace: "server-a")
        XCTAssertEqual(snapshot.scope, .explicitDescriptorIDs(["a", "b"]))
    }

    func testAutomaticPreferenceIsSharedButNextAttemptIsServerScoped() async {
        let defaults = UserDefaults(suiteName: "health.archive.export.\(UUID().uuidString)")!
        let store = UserDefaultsHealthArchiveExportStateStore(defaults: defaults)
        let next = Date(timeIntervalSince1970: 42)

        await store.setAutomaticEnabled(true)
        await store.saveSnapshot(HealthArchiveExportSnapshot(
            serverNamespace: "server-a",
            status: .succeeded,
            automaticEnabled: true,
            nextAttemptAt: next
        ))

        let serverA = await store.loadSnapshot(serverNamespace: "server-a")
        let serverB = await store.loadSnapshot(serverNamespace: "server-b")
        XCTAssertTrue(serverA.automaticEnabled)
        XCTAssertTrue(serverB.automaticEnabled)
        XCTAssertEqual(serverA.nextAttemptAt, next)
        XCTAssertNil(serverB.nextAttemptAt)
    }

    func testStatusSnapshotDoesNotOverwriteAutomaticPreference() async {
        let defaults = UserDefaults(suiteName: "health.archive.export.\(UUID().uuidString)")!
        let store = UserDefaultsHealthArchiveExportStateStore(defaults: defaults)

        await store.setAutomaticEnabled(true)
        await store.saveSnapshot(HealthArchiveExportSnapshot(
            serverNamespace: "server-a",
            status: .running,
            automaticEnabled: false
        ))

        let snapshot = await store.loadSnapshot(serverNamespace: "server-a")

        XCTAssertTrue(snapshot.automaticEnabled)
        XCTAssertEqual(snapshot.status, .running)
    }

    func testStaleRunningSnapshotReconcilesToFailed() async {
        let defaults = UserDefaults(suiteName: "health.archive.export.\(UUID().uuidString)")!
        let store = UserDefaultsHealthArchiveExportStateStore(defaults: defaults)

        await store.saveSnapshot(HealthArchiveExportSnapshot(
            serverNamespace: "server-a",
            requestSetKey: "server-a|all-supported|fp",
            descriptorFingerprint: "fp",
            acknowledgedCursor: "cursor-a",
            status: .running,
            lastAttemptAt: Date().addingTimeInterval(-31 * 60)
        ))

        let snapshot = await store.loadSnapshot(serverNamespace: "server-a")

        XCTAssertEqual(snapshot.status, .failed)
        XCTAssertEqual(snapshot.lastFailureClass, "InterruptedExport")
        XCTAssertEqual(snapshot.acknowledgedCursor, "cursor-a")
    }

    func testHealthArchiveServerNamespaceNormalizesConnectionURLs() {
        XCTAssertEqual(
            HealthArchiveServerNamespace.normalized(
                from: URL(string: "https://server.example.test/")!
            ),
            "https://server.example.test"
        )
        XCTAssertEqual(
            HealthArchiveServerNamespace.normalized(
                from: URL(string: "http://127.0.0.1:8123/api")!
            ),
            "http://127.0.0.1:8123/api"
        )
    }
}
