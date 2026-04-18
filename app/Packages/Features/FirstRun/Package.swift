// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// FeaturesFirstRun — the connection screen the app shows the very first time
// it launches (before a server URL + bearer token are saved). Once the pair
// is persisted to `TokenStore`, the shell routes past this package for the
// rest of the app's lifetime — "change server" in Settings wipes the pair
// to bring this screen back.
//
// Scope:
//   - welcome card: URL + token inputs, connect + ghost "scan QR" button
//   - connecting state: GET /api/version to validate the pair before save
//   - first-pull state: GET /api/sync/pull (no since) so the user lands on
//     a primed local cache
//   - failure state: inline banner, user edits + retries without leaving
//
// Dependencies per docs/architecture/swift-packages.md row "Features/*":
//   - WorkoutCoreFoundation : small helpers (none used today; kept for
//                             consistency with sibling Feature packages)
//   - DesignSystem          : DSButton, DSCard, DSColors, DSTypography
//   - Persistence           : TokenStore protocol (saveConnection)
//   - Sync                  : HTTPTransport + SyncError (401 detection)
//
// FirstRun intentionally does not depend on Core/Domain, CoreSession, or
// CoreAutoreg — it has no workout model, no reducer, no autoreg. Its only
// surface is "is the connection good?", and the answer comes from HTTP +
// TokenStore directly.
//
// Package.swift dependency-product quirk (same as siblings): `package:` in
// `.product(...)` is the directory name of the path-based dependency, not
// the package's `name:` field.
//
// Test target note:
//   Tests use XCTest against fake TokenStore + HTTPTransport. No SwiftData
//   or URLSession round-trips in the test body. Runs under `swift test`.
let package = Package(
    name: "FeaturesFirstRun",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FeaturesFirstRun",
            targets: ["FeaturesFirstRun"]
        ),
    ],
    dependencies: [
        .package(path: "../../Core/Foundation"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Persistence"),
        .package(path: "../../Sync"),
    ],
    targets: [
        .target(
            name: "FeaturesFirstRun",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Sources/FeaturesFirstRun"
        ),
        .testTarget(
            name: "FeaturesFirstRunTests",
            dependencies: [
                "FeaturesFirstRun",
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Tests/FeaturesFirstRunTests"
        ),
    ]
)
