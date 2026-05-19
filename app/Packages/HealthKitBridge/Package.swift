// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// HealthKitBridge — the only package allowed to import HealthKit for data
// access/readback (FF-13). WorkoutKitAdapter has a narrow exception for
// HealthKit enum types required by WorkoutKit plan construction.
// Owns the typed data-access boundary for batch archive, post-workout
// readback, and live metric consumers:
//   • descriptors, request shapes, normalized records, cursors, and unit
//     carrying value payloads exposed for consumers without HealthKit imports.
//   • permission broker, batch provider, and live provider protocols.
//   • legacy narrow wrappers (`HealthAuthorization`, `HeartRateObserver`,
//     `BodyWeightReader`) while callers migrate onto the general contract.
//   • Live implementations (`Live…`) that wrap `HKHealthStore`,
//     `HKLiveWorkoutBuilder`, and `HKSampleQuery`. Guarded with
//     `#if canImport(HealthKit)` so the package compiles on macOS for tests.
//   • In-memory fakes (`Fake…`) for Features to use in their tests.
//
// Dependencies, per `docs/architecture/swift-packages.md` row "HealthKitBridge":
//   - Core/Domain
//   - Core/Foundation
//
// Test target note:
//   Same CLT-friendly assertion harness pattern as the Core packages / Sync —
//   an executable test target runnable via `swift run HealthKitBridgeTests`.
//   The `LiveHeartRateObserver` / `LiveBodyWeightReader` / `LiveHealthKitAuthorization`
//   types require a device with HealthKit permissions and are not covered by
//   unit tests — only the fakes are. See `Tests/HealthKitBridgeTests/main.swift`.
let package = Package(
    name: "HealthKitBridge",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HealthKitBridge",
            targets: ["HealthKitBridge"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
    ],
    targets: [
        .target(
            name: "HealthKitBridge",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Sources/HealthKitBridge"
        ),
        .executableTarget(
            name: "HealthKitBridgeTests",
            dependencies: [
                "HealthKitBridge",
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Tests/HealthKitBridgeTests"
        ),
    ]
)
