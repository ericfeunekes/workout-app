// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// FeaturesSettings — the Settings screen. Data-driven sections + rows per
// HS-4 ("settings mega-view"): adding a row is appending a struct value to
// an array, not editing a giant `VStack`.
//
// Scope (per `docs/design/components/meta.jsx` SettingsMain + SettingsChangeServer,
// scaled down to what's wire-able today):
//   • SERVER — current URL, last-synced chip, "sync now", "change server"
//     (destructive: wipes local cache + flips connection state back to
//     FirstRun).
//   • DEVICE — units (kg/lb), paired watch (stub until WatchBridge runtime
//     wires up).
//   • AUTOREG DEFAULTS — target RIR, overshoot step, undershoot step, reset
//     to defaults (backed by UserDefaults for now; no Claude-side
//     integration yet — see `docs/open-questions.md` § "Autoreg defaults").
//   • DATA — reset local data (destructive), build + commit footer.
//
// Dependencies per docs/architecture/swift-packages.md row "Features/*":
//   - DesignSystem          : DSButton, DSCard, DSColors, DSTypography
//   - Persistence           : TokenStore + SyncMetadataStore protocols.
//                             SyncMetadataStore is what drives the
//                             "synced X min ago" row — the parallel
//                             sync-integration slice writes it on every
//                             successful pull.
//
// Notably absent: `Sync`. The brief allowed it "for ConnectionManager
// status display only", but every surface we ship is satisfied by
// Persistence's protocols. Not depending on Sync means Settings can't
// accidentally import URLSession even as it grows, per FF-13.
//
// Package.swift dependency-product quirk (same as siblings): `package:` in
// `.product(...)` is the directory name of the path-based dependency, not
// the package's `name:` field.
//
// Test target note:
//   Tests use XCTest against the viewModel with in-memory fakes. No
//   SwiftData, no URLSession. Runs under `swift test`.
let package = Package(
    name: "FeaturesSettings",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FeaturesSettings",
            targets: ["FeaturesSettings"]
        ),
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Persistence"),
    ],
    targets: [
        .target(
            name: "FeaturesSettings",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/FeaturesSettings"
        ),
        .testTarget(
            name: "FeaturesSettingsTests",
            dependencies: [
                "FeaturesSettings",
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Tests/FeaturesSettingsTests"
        ),
    ]
)
