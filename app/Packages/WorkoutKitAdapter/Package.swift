// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// WorkoutKitAdapter — the only package allowed to import WorkoutKit.
// Owns target-side WorkoutKit plan construction, schedule/open side effects,
// proof-gated push coordination, and DEBUG/test diagnostic probes.
//
// Dependencies, per `docs/architecture/swift-packages.md` row "WorkoutKitAdapter":
//   - Core/Domain
//   - Core/Foundation
//   - ExportProfile
//
// Public APIs expose SDK-free request/outcome types. Real WorkoutKit symbols
// stay inside the live client so package tests can run on macOS with fakes.
let package = Package(
    name: "WorkoutKitAdapter",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WorkoutKitAdapter",
            targets: ["WorkoutKitAdapter"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
        .package(path: "../ExportProfile"),
    ],
    targets: [
        .target(
            name: "WorkoutKitAdapter",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "WorkoutKitExportProfile", package: "ExportProfile"),
            ],
            path: "Sources/WorkoutKitAdapter"
        ),
        .testTarget(
            name: "WorkoutKitAdapterTests",
            dependencies: [
                "WorkoutKitAdapter",
                .product(name: "WorkoutKitExportProfile", package: "ExportProfile"),
            ],
            path: "Tests/WorkoutKitAdapterTests"
        ),
    ]
)
