// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// FeaturesToday — the "Today" screen. First Feature package and the
// integration proof that Domain + DesignSystem + Persistence + Session
// compose cleanly behind a SwiftUI view.
//
// Scope is read-side: show the planned workout, last-session summary,
// exercise list, and a "start workout" action. Sync and HealthKit come
// later — this package stays off them intentionally.
//
// Dependencies per docs/architecture/swift-packages.md:
//   - CoreDomain        : Workout, Block, WorkoutItem, Exercise types
//   - CorePrescription  : PrescriptionParser for per-item summary lines
//   - CoreSession       : SessionMutation for the start handoff
//   - DesignSystem      : tokens + primitives (chips, card, button)
//   - Persistence       : WorkoutCache protocol for the loader
//   - WorkoutCoreFoundation : IDs, formatLoad / formatKilograms helpers
//
// Package.swift dependency-product quirk (same as siblings): `package:` in
// `.product(...)` is the directory name of the path-based dependency, not
// the package's `name:` field.
//
// Test target note:
//   FeaturesToday's tests exercise Swift code only (view model + formatter
//   + a mock WorkoutCache). No SwiftData required in the tests themselves,
//   so XCTest works on any host with Xcode. We keep `testTarget` here.
let package = Package(
    name: "FeaturesToday",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FeaturesToday",
            targets: ["FeaturesToday"]
        ),
    ],
    dependencies: [
        .package(path: "../../Core/Foundation"),
        .package(path: "../../Core/Domain"),
        .package(path: "../../Core/Prescription"),
        .package(path: "../../Core/Session"),
        .package(path: "../../Core/Telemetry"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Persistence"),
    ],
    targets: [
        .target(
            name: "FeaturesToday",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/FeaturesToday"
        ),
        .testTarget(
            name: "FeaturesTodayTests",
            dependencies: [
                "FeaturesToday",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Tests/FeaturesTodayTests"
        ),
    ]
)
