// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "HealthArchiveExport",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HealthArchiveExport", targets: ["HealthArchiveExport"]),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Telemetry"),
        .package(path: "../Persistence"),
        .package(path: "../Sync"),
        .package(path: "../HealthKitBridge"),
    ],
    targets: [
        .target(
            name: "HealthArchiveExport",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
                .product(name: "HealthKitBridge", package: "HealthKitBridge"),
            ],
            path: "Sources/HealthArchiveExport"
        ),
        .executableTarget(
            name: "HealthArchiveExportTests",
            dependencies: [
                "HealthArchiveExport",
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
                .product(name: "HealthKitBridge", package: "HealthKitBridge"),
            ],
            path: "Tests/HealthArchiveExportTests"
        ),
    ]
)
