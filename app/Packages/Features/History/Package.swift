// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// FeaturesHistory — the History tab. Surfaces three screens:
//   • reverse-chronological list of completed workouts, filterable by split
//   • session detail with per-exercise set rows
//   • by-exercise pivot: picker + minimal trend indicator + recent sessions
//
// Dependencies per docs/architecture/swift-packages.md row "Features/History":
//   CoreDomain, DesignSystem, Persistence, Sync.
//
// Notably absent: CoreSession, CorePrescription, HealthKitBridge, WatchBridge.
// History is a read-only surface over logged data; it does not drive the
// session state machine, parse prescriptions, or touch sensors.
//
// Package.swift dependency-product quirk (same as siblings): `package:` in
// `.product(...)` is the directory name of the path-based dependency, not
// the package's `name:` field.
//
// Test target note:
//   Tests run against a FakeHistoryCache (no SwiftData) so they execute
//   under `swift test` on any host. The trend computation and view model
//   are pure logic — no async, no I/O inside the tests beyond the fake
//   actor hops.
let package = Package(
    name: "FeaturesHistory",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FeaturesHistory",
            targets: ["FeaturesHistory"]
        ),
    ],
    dependencies: [
        .package(path: "../../Core/Foundation"),
        .package(path: "../../Core/Domain"),
        .package(path: "../../Core/Telemetry"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Persistence"),
        .package(path: "../../Sync"),
    ],
    targets: [
        .target(
            name: "FeaturesHistory",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Sources/FeaturesHistory"
        ),
        .testTarget(
            name: "FeaturesHistoryTests",
            dependencies: [
                "FeaturesHistory",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Tests/FeaturesHistoryTests"
        ),
    ]
)
