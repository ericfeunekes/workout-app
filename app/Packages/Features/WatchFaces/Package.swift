// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// FeaturesWatchFaces — the watch companion's screens. v1 scope is three
// faces: Idle (no active workout), ActiveSet (tap-to-start-set), and Rest
// (ring countdown + tap-to-end-set). The full design-grammar faces (EMOM,
// AMRAP, intervals, etc.) are deferred to v1.1+; see `app/README.md`
// § "Watch (v1 scope)" / "Watch (deferred to v1.1+)".
//
// Per `docs/architecture/swift-packages.md`, watch UI lives in a Features
// package — the watch target itself stays a thin shell that wires a view
// model + view. Dependencies mirror iOS Features packages but are scoped
// to what a watch face actually needs:
//
//   - CoreSession   : `SessionState.Route` + structural types used for
//                     face-state semantics. The watch does NOT run the
//                     reducer — the phone is authoritative; the watch
//                     receives rendered payloads via WatchBridge.
//   - DesignSystem  : tokens + primitives (DSRing, typography, colors).
//   - HealthKitBridge : typed metric-source seam used by watch metric
//                     consumers. Tests inject deterministic fixture streams;
//                     HealthKit API access remains inside HealthKitBridge.
//   - WatchBridge   : inbound `messages()` stream + outbound `send(_:)`.
//                     This is the only IPC surface the package sees.
//
// Test target note:
//   XCTest. Tests exercise the view model against `FakeWatchBridge` —
//   deliver a message, assert `face` transitions and/or the outbound
//   `sentMessages()` log. No SwiftUI is rendered in unit tests; previews
//   are the visual check and `xcodebuild` is the compile check.
//
// Package.swift dependency-product quirk (same as siblings): `package:` in
// `.product(...)` is the directory name of the path-based dependency, not
// the package's `name:` field.
let package = Package(
    name: "FeaturesWatchFaces",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FeaturesWatchFaces",
            targets: ["FeaturesWatchFaces"]
        ),
    ],
    dependencies: [
        .package(path: "../../Core/Session"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../HealthKitBridge"),
        .package(path: "../../WatchBridge"),
    ],
    targets: [
        .target(
            name: "FeaturesWatchFaces",
            dependencies: [
                .product(name: "CoreSession", package: "Session"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "HealthKitBridge", package: "HealthKitBridge"),
                .product(name: "WatchBridge", package: "WatchBridge"),
            ],
            path: "Sources/FeaturesWatchFaces"
        ),
        .testTarget(
            name: "FeaturesWatchFacesTests",
            dependencies: [
                "FeaturesWatchFaces",
                .product(name: "HealthKitBridge", package: "HealthKitBridge"),
                .product(name: "WatchBridge", package: "WatchBridge"),
            ],
            path: "Tests/FeaturesWatchFacesTests"
        ),
    ]
)
