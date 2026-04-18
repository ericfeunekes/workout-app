// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Core/Autoreg — pure functions that compute autoreg proposals and apply them
// to remaining set plans. No state, no I/O. See:
//   - docs/architecture/swift-packages.md (row: Core/Autoreg)
//   - docs/prescription.md § "Autoregulation" (the authoritative behavior)
//
// Dependencies: CoreDomain, CorePrescription. No edge imports.
//
// Package.swift dependency-product quirk:
//   `.product(name: "CoreDomain", package: "Domain")` — `package:` is the
//   directory name of the path-based dependency, not the package's `name:`
//   field. Same story as Core/Prescription → Domain; see the header comment
//   in ../Domain/Package.swift for the full explanation.
//
// Test target note:
//   macOS Command Line Tools (no full Xcode) do not ship XCTest. We run an
//   executable test target `CoreAutoregTests` driven by an in-package
//   assertion harness, matching Core/Foundation, Core/Domain, and
//   Core/Prescription. Run with `swift run CoreAutoregTests`.
let package = Package(
    name: "CoreAutoreg",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CoreAutoreg",
            targets: ["CoreAutoreg"]
        ),
    ],
    dependencies: [
        .package(path: "../Foundation"),
        .package(path: "../Domain"),
        .package(path: "../Prescription"),
    ],
    targets: [
        .target(
            name: "CoreAutoreg",
            dependencies: [
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Sources/CoreAutoreg"
        ),
        .executableTarget(
            name: "CoreAutoregTests",
            dependencies: [
                "CoreAutoreg",
                .product(name: "CoreDomain", package: "Domain"),
                .product(name: "CorePrescription", package: "Prescription"),
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Tests/CoreAutoregTests"
        ),
    ]
)
