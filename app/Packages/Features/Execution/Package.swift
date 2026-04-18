// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// FeaturesExecution — the core-loop screens: active set, rest timer, RIR
// picker, autoreg banner, completion ledger.
//
// Scope of the v0 slice (this package as first landed):
//   - straight_sets timing mode, end to end
//   - observable view model wrapping CoreSession's pure reducer
//   - TimingDriver protocol strategy (HS-2) so adding a mode later is a
//     new file, not an edited switch
//   - session persistence via Persistence.SessionStore (opaque bytes)
//   - no Sync imports; Execution is offline-first, sync is the shell's job
//   - no other Features/* imports
//
// Dependencies per docs/architecture/swift-packages.md:
//   - WorkoutCoreFoundation : Clock, formatLoad, formatDuration
//   - CoreDomain            : Workout, Block, WorkoutItem, Exercise
//   - CorePrescription      : PrescriptionParser, Prescription, TimingConfig,
//                             Autoreg (config), RepCount
//   - CoreAutoreg           : Autoreg.propose/apply, AutoregProposal, SetPlan
//   - CoreSession           : SessionState, SessionMutation, SessionReducer
//   - DesignSystem          : tokens + primitives (ring, pill, keypad, button)
//   - Persistence           : SessionStore (opaque bytes bucket)
//
// HealthKitBridge is listed in the task brief as an allowed dependency but
// v0 does not use it. We'll add the dependency when the HR-during-rest
// slice actually lands — carrying an unused import just adds link-time
// noise today.
//
// Package.swift dependency-product quirk (same as siblings): `package:` in
// `.product(...)` is the directory name of the path-based dependency, not
// the package's `name:` field.
//
// Test target note:
//   XCTest target. Tests cover the view model, drivers, persistence
//   round-trip through an in-memory SessionStore, and the clock-driven
//   rest-timer math. No SwiftUI view rendering is exercised — previews
//   are the visual check and `xcodebuild` is the compile check.
let package = Package(
    name: "FeaturesExecution",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FeaturesExecution",
            targets: ["FeaturesExecution"]
        ),
    ],
    dependencies: [
        .package(path: "../../Core/Foundation"),
        .package(path: "../../Core/Domain"),
        .package(path: "../../Core/Prescription"),
        .package(path: "../../Core/Autoreg"),
        .package(path: "../../Core/Session"),
        .package(path: "../../Core/Telemetry"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Persistence"),
    ],
    targets: [
        .target(
            name: "FeaturesExecution",
            dependencies: [
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreAutoreg", package: "Autoreg"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Sources/FeaturesExecution"
        ),
        .testTarget(
            name: "FeaturesExecutionTests",
            dependencies: [
                "FeaturesExecution",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "CoreAutoreg", package: "Autoreg"),
                .product(name: "CoreSession", package: "Session"),
                .product(name: "CoreTelemetry", package: "Telemetry"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            path: "Tests/FeaturesExecutionTests"
        ),
    ]
)
