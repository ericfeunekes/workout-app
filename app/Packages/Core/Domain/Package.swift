// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Core/Domain — plain Swift structs for the domain entities. No Codable, no
// persistence, no SwiftUI. See docs/architecture/swift-packages.md for the
// package graph and docs/specs/v2-architecture.md § "Data model" for the
// canonical entity shape.
//
// Depends only on Core/Foundation for ID aliases and the Clock protocol.
//
// Test target note:
//   Same CLT-vs-Xcode XCTest story as Core/Foundation — we ship an executable
//   test target (`swift run CoreDomainTests`) backed by the shared assertion
//   helper copied in-package.
let package = Package(
    name: "CoreDomain",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CoreDomain",
            targets: ["CoreDomain"]
        ),
    ],
    dependencies: [
        .package(path: "../Foundation"),
    ],
    targets: [
        .target(
            name: "CoreDomain",
            dependencies: [
                // `package: "Foundation"` refers to the directory name of the
                // dependency (last component of `.package(path: "../Foundation")`),
                // not the package's `name:` field. The package itself is named
                // `WorkoutCoreFoundation`, but SwiftPM resolves path-based
                // dependencies by directory.
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Sources/CoreDomain"
        ),
        .executableTarget(
            name: "CoreDomainTests",
            dependencies: [
                "CoreDomain",
                .product(name: "WorkoutCoreFoundation", package: "Foundation"),
            ],
            path: "Tests/CoreDomainTests"
        ),
    ]
)
