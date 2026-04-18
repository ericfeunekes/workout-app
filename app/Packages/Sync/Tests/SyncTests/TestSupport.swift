// TestSupport.swift
//
// Same CLT-friendly assertion harness pattern as Core/Foundation,
// Core/Domain, and Core/Prescription. Kept in-package so the test helpers do
// not ship as a public library.

import Foundation

enum TestHarness {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var runCount: Int = 0
}

func runCase(_ name: String, _ body: () throws -> Void) {
    TestHarness.runCount += 1
    do {
        try body()
        print("PASS  \(name)")
    } catch {
        let msg = "FAIL  \(name): \(error)"
        TestHarness.failures.append(msg)
        print(msg)
    }
}

func runAsyncCase(_ name: String, _ body: @Sendable @escaping () async throws -> Void) {
    TestHarness.runCount += 1
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var caught: Error?
    Task {
        do {
            try await body()
        } catch {
            caught = error
        }
        sem.signal()
    }
    sem.wait()
    if let err = caught {
        let msg = "FAIL  \(name): \(err)"
        TestHarness.failures.append(msg)
        print(msg)
    } else {
        print("PASS  \(name)")
    }
}

struct ExpectationFailure: Error, CustomStringConvertible {
    let message: String
    let file: StaticString
    let line: UInt
    var description: String { "\(message) (\(file):\(line))" }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "expectation failed",
    file: StaticString = #file,
    line: UInt = #line
) throws {
    if !condition() {
        throw ExpectationFailure(message: message(), file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) throws {
    if lhs != rhs {
        let prefix = message().isEmpty ? "not equal" : message()
        throw ExpectationFailure(
            message: "\(prefix): \(lhs) != \(rhs)",
            file: file,
            line: line
        )
    }
}

func expectNotEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) throws {
    if lhs == rhs {
        let prefix = message().isEmpty ? "unexpectedly equal" : message()
        throw ExpectationFailure(
            message: "\(prefix): \(lhs) == \(rhs)",
            file: file,
            line: line
        )
    }
}

func reportAndExit() -> Never {
    let failed = TestHarness.failures.count
    let run = TestHarness.runCount
    if failed == 0 {
        print("\nAll \(run) cases passed.")
        exit(0)
    } else {
        print("\n\(failed) of \(run) cases failed:")
        for f in TestHarness.failures { print("  \(f)") }
        exit(1)
    }
}

// MARK: - Fixture loading
//
// Resolve `schema/fixtures/` from this file's compile-time path so the
// lookup is independent of the current working directory when `swift run`
// is invoked.

enum FixtureLoader {

    /// Path is:
    ///   <repo>/app/Packages/Sync/Tests/SyncTests/TestSupport.swift
    /// → <repo>/schema/fixtures/
    /// Components to drop: TestSupport.swift, SyncTests, Tests, Sync,
    /// Packages, app = 6.
    static let fixturesDir: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        url.appendPathComponent("schema")
        url.appendPathComponent("fixtures")
        return url
    }()

    static func loadData(_ filename: String) throws -> Data {
        let url = fixturesDir.appendingPathComponent(filename)
        return try Data(contentsOf: url)
    }
}
