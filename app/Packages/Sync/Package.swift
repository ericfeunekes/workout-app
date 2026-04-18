// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Sync — the only package that dials the home server. Owns:
//   • `HTTPTransport` (the URLSession boundary — no other file in the app should
//     import URLSession, per FF-13)
//   • `PullService` — GET /api/sync/pull
//   • `PushQueue` — POST /api/sync/results, persistent and idempotent
//   • `ConnectionManager` — offline / syncing / online / tokenRejected signal
//   • `DTOMapping` — schema DTOs ↔ CoreDomain types. The one place WorkoutDBSchema
//     is imported; Features only see Domain types (FF-11 boundary).
//
// Split from day one — see `docs/architecture/hotspots.md` HS-1 for the
// SyncManager-as-god-object intervention.
//
// Dependencies, per `docs/architecture/swift-packages.md` row "Sync":
//   - Core/Domain
//   - Core/Foundation
//   - schema (via ../../../schema)
//   - Persistence — declared in the arch doc, but Persistence does not exist
//     yet. Sync owns the `PushQueueStore` protocol definition; Persistence
//     will implement it once it lands. No dependency edge is declared here.
//
// Test target note:
//   Same CLT-vs-Xcode XCTest story as the Core packages — we ship an
//   executable test target (`swift run SyncTests`) backed by the shared
//   assertion helper copied in-package.
let package = Package(
    name: "Sync",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Sync",
            targets: ["Sync"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
        .package(path: "../Core/Telemetry"),
        .package(path: "../../../schema"),
    ],
    targets: [
        .target(
            name: "Sync",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "WorkoutDBSchema", package: "schema"),
            ],
            path: "Sources/Sync"
        ),
        .executableTarget(
            name: "SyncTests",
            dependencies: [
                "Sync",
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "WorkoutDBSchema", package: "schema"),
            ],
            path: "Tests/SyncTests"
        ),
    ]
)
