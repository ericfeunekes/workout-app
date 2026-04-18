// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// HealthKitBridge — the only package allowed to import HealthKit (FF-13).
// Owns:
//   • `HealthAuthorization`, `HeartRateObserver`, `BodyWeightReader` protocols
//     exposed for Features to consume without ever importing HealthKit.
//   • Live implementations (`Live…`) that wrap `HKHealthStore`,
//     `HKLiveWorkoutBuilder`, and `HKSampleQuery`. Guarded with
//     `#if canImport(HealthKit)` so the package compiles on macOS for tests.
//   • In-memory fakes (`Fake…`) for Features to use in their tests.
//
// Per ADR-2026-04-17-ux-scope §4, v1 only records HR avg + max into `set_log`
// via `HKLiveWorkoutBuilder` — no sample timeseries are persisted. The stream
// API exists so Features can read live HR during a set; aggregation into
// `hr_avg_bpm` / `hr_max_bpm` lives in the consuming layer.
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
