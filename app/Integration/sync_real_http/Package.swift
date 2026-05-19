// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SyncRealHTTPProbe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PrimitiveSyncProbe", targets: ["PrimitiveSyncProbe"])
    ],
    dependencies: [
        .package(path: "../../Packages/Core/Domain"),
        .package(path: "../../Packages/Core/Foundation"),
        .package(path: "../../Packages/Core/Session"),
        .package(path: "../../Packages/ExportProfile"),
        .package(path: "../../Packages/Persistence"),
        .package(path: "../../Packages/Sync"),
    ],
    targets: [
        .executableTarget(
            name: "PrimitiveSyncProbe",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "WorkoutKitExportProfile", package: "ExportProfile"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
            ]
        )
    ]
)
