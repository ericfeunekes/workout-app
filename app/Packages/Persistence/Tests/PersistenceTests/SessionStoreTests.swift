// SessionStoreTests.swift
//
// Verify save/load/clear semantics. Persistence stores the SessionState as
// opaque `Data` (see the SessionStore.swift header for the boundary reason),
// so these tests simulate a Features-layer payload with arbitrary JSON.

import XCTest
@testable import Persistence

final class SessionStoreTests: XCTestCase {

    private func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    func testLoadReturnsNilWhenEmpty() async throws {
        let factory = try makeFactory()
        let loaded = try await factory.sessionStore.load()
        XCTAssertNil(loaded)
    }

    func testSaveThenLoad() async throws {
        let factory = try makeFactory()
        let payload = Data("{\"route\":\"active\"}".utf8)
        try await factory.sessionStore.save(payload)

        let loaded = try await factory.sessionStore.load()
        XCTAssertEqual(loaded, payload)
    }

    func testSaveReplacesExistingRow() async throws {
        let factory = try makeFactory()
        try await factory.sessionStore.save(Data("{\"v\":1}".utf8))
        try await factory.sessionStore.save(Data("{\"v\":2}".utf8))

        let loaded = try await factory.sessionStore.load()
        XCTAssertEqual(loaded, Data("{\"v\":2}".utf8))
    }

    func testClear() async throws {
        let factory = try makeFactory()
        try await factory.sessionStore.save(Data("{\"v\":1}".utf8))
        try await factory.sessionStore.clear()
        let loaded = try await factory.sessionStore.load()
        XCTAssertNil(loaded)
    }
}
