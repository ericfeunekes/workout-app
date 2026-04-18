// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// DesignSystem — visual tokens (colors, type ramp, spacing, motion) and
// primitives (button, chip, pill, ring, keypad). No routing, no business rules.
// See docs/architecture/swift-packages.md for the package graph and
// docs/design/RULES.md § "Copywriting rules" for the copy rules these tokens
// support.
//
// Depends only on Core/Foundation for formatting helpers (e.g. formatLoad).
//
// Test target note:
//   Same CLT-vs-Xcode XCTest story as Core/Foundation — we ship an executable
//   test target (`swift run DesignSystemTests`) backed by the shared assertion
//   helper copied in-package. SwiftUI is available on macOS 11+, so primitive
//   construction smoke tests compile on CLT-only machines too.
let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DesignSystem",
            targets: ["DesignSystem"]
        ),
    ],
    dependencies: [
        .package(path: "../Core/Foundation"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                // `package: "Foundation"` is the directory name of the local
                // SwiftPM dependency (last component of `../Core/Foundation`),
                // not the package's `name:` field. The package is named
                // `WorkoutCoreFoundation`; SwiftPM resolves path-based deps by
                // directory.
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Sources/DesignSystem"
        ),
        .executableTarget(
            name: "DesignSystemTests",
            dependencies: [
                "DesignSystem",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Tests/DesignSystemTests"
        ),
    ]
)
