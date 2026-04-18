// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Core/Session — the live-session state machine. A pure value-type reducer
// over `SessionState` and `SessionMutation`. See:
//   - docs/architecture/swift-packages.md (row: Core/Session)
//   - app/README.md § "Core loop", "Autoregulation", "Tap-to-edit",
//     "Swap", "Persistence (local session)"
//   - docs/prescription.md § "Autoregulation" (esp. "Hold scope",
//     "Autoreg + manual edit", "Edits don't retrigger")
//
// Design call: this package is deliberately pure — no `Observation`, no
// SwiftUI, no SwiftData, no URLSession, no HealthKit, no WatchConnectivity.
// The architecture doc mentions an `@Observable` store; that belongs in
// `Features/Execution` as a thin wrapper around this reducer. Keeping Core
// pure means the state machine is fully testable on CLT with no runtime
// observability, and the wrapping layer can swap its observability story
// (Observation, Combine, plain Swift) without touching the rules.
//
// Dependencies: CoreDomain (IDs), CorePrescription (Autoreg config type),
// CoreAutoreg (SetPlan, AutoregProposal, Autoreg.apply). No edge imports.
//
// Package.swift dependency-product quirk:
//   `.product(name: "CoreDomain", package: "Domain")` — `package:` is the
//   directory name of the path-based dependency, not the package's `name:`
//   field. See Core/Domain/Package.swift header for the full explanation.
//
// Test target note:
//   macOS Command Line Tools (no full Xcode) do not ship XCTest. We run an
//   executable test target `CoreSessionTests` driven by an in-package
//   assertion harness, matching the other Core packages. Run with
//   `swift run CoreSessionTests`.
let package = Package(
    name: "CoreSession",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CoreSession",
            targets: ["CoreSession"]
        ),
    ],
    dependencies: [
        .package(path: "../Foundation"),
        .package(path: "../Domain"),
        .package(path: "../Prescription"),
        .package(path: "../Autoreg"),
    ],
    targets: [
        .target(
            name: "CoreSession",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreAutoreg", package: "Autoreg"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Sources/CoreSession"
        ),
        .executableTarget(
            name: "CoreSessionTests",
            dependencies: [
                "CoreSession",
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreAutoreg", package: "Autoreg"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Tests/CoreSessionTests"
        ),
    ]
)
