// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Module name note:
//   Apple ships two frameworks/modules that are close to the obvious names here:
//   the Swift overlay `Foundation` (imported for Date, URL, UUID, etc.) and the
//   C-level `CoreFoundation` framework. To avoid shadowing either when consumers
//   write `import ...`, the Swift module name for this package is
//   `WorkoutCoreFoundation`. The product name matches; consumers declare
//   `.product(name: "WorkoutCoreFoundation", package: "Foundation")`.
//
// Test target note:
//   macOS Command Line Tools (no full Xcode) do not ship XCTest. To keep the
//   test suite runnable on a CLT-only machine we use an executable target
//   driven by a tiny in-package assertion helper (see TestSupport.swift). Run
//   with `swift run WorkoutCoreFoundationTests`. When Xcode is present, those
//   assertions still execute — they just happen to not use XCTest.
let package = Package(
    name: "WorkoutCoreFoundation",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WorkoutCoreFoundation",
            targets: ["WorkoutCoreFoundation"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WorkoutCoreFoundation",
            dependencies: [],
            path: "Sources/WorkoutCoreFoundation"
        ),
        .executableTarget(
            name: "WorkoutCoreFoundationTests",
            dependencies: ["WorkoutCoreFoundation"],
            path: "Tests/WorkoutCoreFoundationTests"
        ),
    ]
)
