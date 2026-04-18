// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Persistence — on-device storage. The only package allowed to import
// SwiftData (enforced by FF-13 via SwiftLint). See
// docs/architecture/swift-packages.md row "Persistence":
//   Dependencies: Core/Domain, Core/Prescription, Core/Foundation (and Sync
//   for the PushQueueStore protocol definition; Sync declared it in-package
//   precisely so Persistence could implement it without creating a reverse
//   dependency through the graph).
//
// Exposes three protocols — `WorkoutCache`, `SessionStore`, `TokenStore` —
// plus a concrete `PushQueueStore` implementation. Features and Sync take
// protocols via init; they never import SwiftData.
//
// Test target note:
//   Persistence uses SwiftData + Security framework, both of which require
//   Xcode. We use XCTest (no in-package CLT harness) because the package
//   cannot build without Xcode anyway.
let package = Package(
    name: "Persistence",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Persistence",
            targets: ["Persistence"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
        .package(path: "../Core/Prescription"),
        .package(path: "../Core/Telemetry"),
        .package(path: "../Sync"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Sources/Persistence"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Tests/PersistenceTests"
        ),
    ]
)
