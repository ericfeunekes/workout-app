// TestSupport.swift
//
// Minimal assertion harness — same shape as Core/Foundation and Core/Domain.
// Non-zero exit on failure so `swift run CorePrescriptionTests` propagates
// a real failure signal in CI or pre-push.

import Foundation
import CorePrescription

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

// MARK: - Fixture loading
//
// We resolve the fixtures directory relative to this source file's path at
// compile time. That keeps the lookup independent of the current working
// directory when `swift run` is invoked.

enum FixtureLoader {

    /// Absolute path to `schema/fixtures/` derived from this file's compile-
    /// time path. The path is:
    ///   <repo>/app/Packages/Core/Prescription/Tests/CorePrescriptionTests/TestSupport.swift
    /// → <repo>/schema/fixtures/
    /// Components to drop: TestSupport.swift, CorePrescriptionTests, Tests,
    /// Prescription, Core, Packages, app = 7.
    static let fixturesDir: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { url.deleteLastPathComponent() }  // drop to repo root
        url.appendPathComponent("schema")
        url.appendPathComponent("fixtures")
        return url
    }()

    static func loadRaw(_ name: String) throws -> [String: Any] {
        let url = fixturesDir.appendingPathComponent("prescription_\(name).json")
        let data = try Data(contentsOf: url)
        let any = try JSONSerialization.jsonObject(with: data)
        guard let obj = any as? [String: Any] else {
            throw ExpectationFailure(
                message: "fixture \(name) is not a top-level object",
                file: #file,
                line: #line
            )
        }
        return obj
    }

    /// Returns `(prescriptionJSONString, timingMode, timingConfigJSONString)`
    /// for a "wrapped" fixture that carries both halves (e.g. straight_sets,
    /// superset, circuit, emom, amrap, for_time, intervals, tabata,
    /// continuous, custom, rest_block).
    static func wrapped(_ name: String) throws -> (prescription: String, timingMode: String, config: String) {
        let obj = try loadRaw(name)
        guard let mode = obj["timing_mode"] as? String else {
            throw ExpectationFailure(
                message: "fixture \(name) missing timing_mode",
                file: #file,
                line: #line
            )
        }
        let cfgObj = obj["timing_config_json"] as? [String: Any] ?? [:]
        let preObj = obj["prescription_json"] as? [String: Any] ?? [:]
        let cfgData = try JSONSerialization.data(withJSONObject: cfgObj)
        let preData = try JSONSerialization.data(withJSONObject: preObj)
        return (
            prescription: String(data: preData, encoding: .utf8) ?? "",
            timingMode: mode,
            config: String(data: cfgData, encoding: .utf8) ?? ""
        )
    }

    /// Returns the full fixture re-encoded as a JSON string, for bare
    /// parametric fixtures (bodyweight, cluster, drop_set, per_side,
    /// percent_1rm, rep_range, sets_detail, tempo, warmup, weighted_bodyweight,
    /// amrap_token).
    static func bare(_ name: String) throws -> String {
        let obj = try loadRaw(name)
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Unwraps a .success result for use-sites that need the value. On failure
/// throws an ExpectationFailure with the underlying error.
func unwrap<T>(
    _ r: Result<T, ParseError>,
    file: StaticString = #file,
    line: UInt = #line
) throws -> T {
    switch r {
    case .success(let v): return v
    case .failure(let e):
        throw ExpectationFailure(
            message: "parse failed: \(e)",
            file: file,
            line: line
        )
    }
}
