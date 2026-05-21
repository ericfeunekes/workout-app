// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "WorkoutKitHandoff",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WorkoutKitHandoff",
            targets: ["WorkoutKitHandoff"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
        .package(path: "../Core/Telemetry"),
        .package(path: "../ExportProfile"),
        .package(path: "../WorkoutKitAdapter"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(
            name: "WorkoutKitHandoff",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "WorkoutKitExportProfile", package: "ExportProfile"),
                .product(name: "WorkoutKitAdapter", package: "WorkoutKitAdapter"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/WorkoutKitHandoff"
        ),
        .testTarget(
            name: "WorkoutKitHandoffTests",
            dependencies: [
                "WorkoutKitHandoff",
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "WorkoutKitExportProfile", package: "ExportProfile"),
                .product(name: "WorkoutKitAdapter", package: "WorkoutKitAdapter"),
            ],
            path: "Tests/WorkoutKitHandoffTests"
        ),
    ]
)
