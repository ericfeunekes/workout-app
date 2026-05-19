// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Shell — the app-level composition package. Thin, untested business logic:
// just "take a connection, run a pull, hand the view models back to the
// SwiftUI shell."
//
// Deliberately placed at `app/Packages/Shell/` (not under `Features/*`)
// because the SwiftLint rule `no_feature_cross_import` forbids Features
// importing sibling Features — and Shell's job is exactly that: wire
// Today + Execution together after a pull. Shell is the one place that's
// allowed to see multiple Features and compose them.
//
// Dependencies:
//   - Persistence : WorkoutCache, TokenStore, SyncMetadataStore
//   - Sync        : SyncAPI, HTTPTransport, URLSessionTransport, DTOMapping
//   - WatchBridge : phone-side watch message inbox
//   - FeaturesToday     : TodayLoader, TodayContext, TodayViewModel
//   - FeaturesExecution : WorkoutContext, ExecutionViewModel
//   - FeaturesHistory   : HistoryView, HistoryViewModel (for RootTabView)
//   - FeaturesSettings  : SettingsView, SettingsViewModel (for RootTabView)
//   - DesignSystem      : tokens for RootTabView's tab bar tint
//   - CoreDomain        : Domain value types
//   - CoreSession       : SessionMutation (for the Today → Execution binding)
//   - WorkoutCoreFoundation : Clock, IDs

let package = Package(
    name: "Shell",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Shell",
            targets: ["Shell"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
        .package(path: "../Core/Domain"),
        .package(path: "../Core/Session"),
        .package(path: "../Core/Telemetry"),
        .package(path: "../DesignSystem"),
        .package(path: "../Persistence"),
        .package(path: "../Sync"),
        .package(path: "../WatchBridge"),
        .package(path: "../Features/Today"),
        .package(path: "../Features/Execution"),
        .package(path: "../Features/History"),
        .package(path: "../Features/Settings"),
    ],
    targets: [
        .target(
            name: "Shell",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
                .product(name: "WatchBridge", package: "WatchBridge"),
                .product(name: "FeaturesToday", package: "Today"),
                .product(name: "FeaturesExecution", package: "Execution"),
                .product(name: "FeaturesHistory", package: "History"),
                .product(name: "FeaturesSettings", package: "Settings"),
            ],
            path: "Sources/Shell"
        ),
        .testTarget(
            name: "ShellTests",
            dependencies: [
                "Shell",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Sync", package: "Sync"),
                .product(name: "WatchBridge", package: "WatchBridge"),
                .product(name: "FeaturesToday", package: "Today"),
                .product(name: "FeaturesExecution", package: "Execution"),
                .product(name: "FeaturesHistory", package: "History"),
                .product(name: "FeaturesSettings", package: "Settings"),
            ],
            path: "Tests/ShellTests"
        ),
    ]
)
