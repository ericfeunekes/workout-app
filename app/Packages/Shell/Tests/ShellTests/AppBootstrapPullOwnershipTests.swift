// AppBootstrapPullOwnershipTests.swift
//
// Pins the "one owner for initial pull" invariant: FirstRun no longer
// fires `/api/sync/pull` as part of its welcome flow. The very first
// pull — the one that populates the cache — is exclusively AppBootstrap's
// job.
//
// This test asserts that a bootstrap run fires exactly one GET to
// `/api/sync/pull`, so a future regression (e.g. re-adding a pull to
// FirstRun or double-calling bootstrap) would be flagged here. Pair
// with `testFirstRunHandsOffToBootstrapWithoutSecondPull` in the
// FeaturesFirstRun test target: together they assert "FirstRun makes
// zero pull calls AND AppBootstrap makes exactly one."
//
// Split into its own file so `AppBootstrapTests`'s class body stays
// under SwiftLint's `type_body_length` cap.

import XCTest
import Persistence
import Sync
import WorkoutCoreFoundation
@testable import Shell

@MainActor
final class AppBootstrapPullOwnershipTests: XCTestCase {

    func testBootstrapFiresExactlyOnePullPerRun() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )
        let baseURL = try XCTUnwrap(URL(string: "https://example.test"))

        _ = try await AppBootstrap.bootstrap(
            connection: (url: baseURL, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )

        let paths = await transport.store.snapshotGetPaths()
        // One and only one pull. AppBootstrap is the sole owner of the
        // initial hydration path; FirstRun only validates credentials
        // via `/api/version`.
        XCTAssertEqual(paths, ["/api/sync/pull"])
    }

    /// Simulates the `.empty → Change Server → FirstRun → bootstrap`
    /// recovery loop at the bootstrap-only layer. Two back-to-back
    /// bootstrap runs (with a cache clear in between, mirroring the
    /// shell's `changeServer()` behaviour) must each fire exactly one
    /// pull. Guards against re-introducing a duplicate pull during
    /// the recovery path.
    func testRepeatedBootstrapAfterCacheClearRehydrates() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let baseURL = try XCTUnwrap(URL(string: "https://example.test"))

        // First bootstrap — empty server, cache stays empty.
        let emptyTransport = ScriptedTransport(getOutcomes: [
            .ok(Data(#"{"server_time":"2026-04-17T08:00:00Z","workouts":[],"exercises":[],"user_parameters":[],"last_performed":[]}"#.utf8))
        ])
        let firstResult = try await AppBootstrap.bootstrap(
            connection: (url: baseURL, token: "old"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in emptyTransport }
        )
        guard case .empty = firstResult else {
            return XCTFail("expected .empty, got \(firstResult)")
        }
        let firstPaths = await emptyTransport.store.snapshotGetPaths()
        XCTAssertEqual(firstPaths, ["/api/sync/pull"])

        // Shell's `changeServer()` wipes the cache. Re-enter bootstrap
        // with a fresh transport carrying a populated payload — the
        // "new server with data" case.
        try await factory.workoutCache.clear()
        let populatedTransport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let secondResult = try await AppBootstrap.bootstrap(
            connection: (url: baseURL, token: "new"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in populatedTransport }
        )
        guard case .ready = secondResult else {
            return XCTFail("expected .ready after recovery, got \(secondResult)")
        }
        let secondPaths = await populatedTransport.store.snapshotGetPaths()
        // Second bootstrap also fires exactly one pull — no residual
        // calls carried over from the first bootstrap's transport.
        XCTAssertEqual(secondPaths, ["/api/sync/pull"])
    }

    func testBootstrapAfterLocalStateResetPullsWithoutSinceCursor() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        await factory.syncMetadataStore.setLastSyncAt(fixture.serverTime)
        try await factory.workoutCache.save(PulledDataset(
            workouts: [fixture.domainWorkout],
            blocks: fixture.domainBlocks,
            items: fixture.domainItems,
            alternatives: [],
            exercises: fixture.domainExercises,
            userParameters: []
        ))
        await AppSyncLocalStateReset.clearCachedServerData(persistence: factory)
        let transport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let baseURL = try XCTUnwrap(URL(string: "https://example.test"))

        _ = try await AppBootstrap.bootstrap(
            connection: (url: baseURL, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )

        let queries = await transport.store.snapshotGetQueries()
        XCTAssertEqual(queries.count, 1)
        XCTAssertTrue(queries[0].isEmpty, "cache reset must force a full pull")
    }
}
