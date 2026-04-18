// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Core/Telemetry — pure domain shape for structured telemetry events.
//
// Owns:
//   • `Event` — a value type mirroring the wire `TelemetryEvent` DTO but in
//     domain form (UUID, Date). Keep it pure — no Codable, no I/O, no state.
//   • `TelemetrySession` — a one-time UUID captured at launch.
//   • `TelemetryEmitter` — the injection protocol. Features take this as an
//     init dep; production uses the Persistence-backed implementation,
//     tests use `NoopTelemetryEmitter`.
//
// Dependencies: none. Matches Core/Domain — the shape layer has no imports
// beyond the Swift Foundation overlay. Concrete emitters live in
// `Persistence` so this package stays free of storage concerns.
//
// Test target note: same CLT-vs-Xcode story as other Core packages — we ship
// an executable test target backed by the shared assertion helper. Run with
// `swift run CoreTelemetryTests`.
let package = Package(
    name: "CoreTelemetry",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CoreTelemetry",
            targets: ["CoreTelemetry"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CoreTelemetry",
            dependencies: [],
            path: "Sources/CoreTelemetry"
        ),
        .executableTarget(
            name: "CoreTelemetryTests",
            dependencies: ["CoreTelemetry"],
            path: "Tests/CoreTelemetryTests"
        ),
    ]
)
