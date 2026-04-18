// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// WatchBridge — iPhone ↔ Watch IPC via WatchConnectivity. See
// docs/architecture/swift-packages.md row "WatchBridge":
//   Dependencies: Core/Domain, Sync.
//   "Watch taps on 'log set' travel through WatchBridge → Sync.PushQueue."
//
// FF-13 makes this the only package allowed to `import WatchConnectivity`
// (SwiftLint `no_watchconnectivity_outside_watchbridge` excludes this path).
// Everything else in the app sees a pure-Swift `WatchBridge` protocol — no
// WCSession leaks past this boundary.
//
// Platforms include macOS so the test target can compile on the command line;
// WatchConnectivity is only available on iOS/watchOS, so the live transport
// is gated behind `#if canImport(WatchConnectivity)`. The macOS build path
// falls through to a stub that returns `.notActivated`.
//
// Test target note:
//   XCTest (not the executable-target harness the Core packages use). The
//   live transport requires a paired phone+watch to meaningfully exercise,
//   so unit tests focus on Codable round-trips and the FakeWatchBridge
//   channel.
let package = Package(
    name: "WatchBridge",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WatchBridge",
            targets: ["WatchBridge"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Domain"),
        .package(path: "../Sync"),
    ],
    targets: [
        .target(
            name: "WatchBridge",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "Sync", package: "Sync"),
            ],
            path: "Sources/WatchBridge"
        ),
        .testTarget(
            name: "WatchBridgeTests",
            dependencies: [
                "WatchBridge",
                .product(name: "CoreDomain", package: "Domain"),
            ],
            path: "Tests/WatchBridgeTests"
        ),
    ]
)
