// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Core/Prescription — per-shape parsers for `prescription_json` and
// `timing_config_json`. Returns typed `Result` values (no throws). Parsers
// only; no computation. See:
//   - docs/architecture/swift-packages.md (row: Core/Prescription)
//   - docs/prescription.md (the authoring vocabulary this package parses)
//
// Package.swift dependency-product quirk:
//   `.product(name: "CoreDomain", package: "Domain")` — `package:` is the
//   directory name of the path-based dependency, not the package's `name:`
//   field. Same story as Core/Domain → Foundation. See the header comment
//   in ../Domain/Package.swift for the full explanation.
//
// Test target note:
//   macOS Command Line Tools (no full Xcode) do not ship XCTest. We run an
//   executable test target `CorePrescriptionTests` driven by an in-package
//   assertion harness, matching Core/Foundation and Core/Domain. Run with
//   `swift run CorePrescriptionTests`.
let package = Package(
    name: "CorePrescription",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CorePrescription",
            targets: ["CorePrescription"]
        ),
    ],
    dependencies: [
        .package(path: "../Foundation"),
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "CorePrescription",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Sources/CorePrescription"
        ),
        .executableTarget(
            name: "CorePrescriptionTests",
            dependencies: [
                "CorePrescription",
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Tests/CorePrescriptionTests"
        ),
    ]
)
