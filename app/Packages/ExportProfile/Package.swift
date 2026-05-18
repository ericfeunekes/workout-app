// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// ExportProfile - pure export classification for Setmark primitive workouts.
//
// The package is split into two compile-time targets so the neutral primitive
// projection cannot import WorkoutKit-specific target policy. It deliberately
// does not import WorkoutKit, HealthKit, WatchConnectivity, SwiftUI, SwiftData,
// Sync, Persistence, or any Feature package. Target-specific side effects live
// in later adapter packages.
let package = Package(
    name: "ExportProfile",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PrimitiveExportProfile",
            targets: ["PrimitiveExportProfile"]
        ),
        .library(
            name: "WorkoutKitExportProfile",
            targets: ["WorkoutKitExportProfile"]
        ),
        .library(
            name: "ExportProfile",
            targets: ["PrimitiveExportProfile", "WorkoutKitExportProfile"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
        .package(path: "../Core/Session"),
    ],
    targets: [
        .target(
            name: "PrimitiveExportProfile",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreSession", package: "Session"),
            ],
            path: "Sources/PrimitiveExportProfile"
        ),
        .target(
            name: "WorkoutKitExportProfile",
            dependencies: [
                "PrimitiveExportProfile",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
            ],
            path: "Sources/WorkoutKitExportProfile"
        ),
        .testTarget(
            name: "ExportProfileTests",
            dependencies: [
                "PrimitiveExportProfile",
                "WorkoutKitExportProfile",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
            ],
            path: "Tests/ExportProfileTests"
        ),
    ]
)
