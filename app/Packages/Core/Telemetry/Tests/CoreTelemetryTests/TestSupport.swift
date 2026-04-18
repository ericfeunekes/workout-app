// TestSupport.swift
//
// Minimal assertion harness for CLT-only macOS (no XCTest available without
// Xcode). Copy of the same file in Core/Foundation/Tests/WorkoutCoreFoundationTests.

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
