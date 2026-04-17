// swift-tools-version: 6.0
//
// WorkoutDBSchema — pure Codable DTOs mirroring the server's Pydantic schemas.
// Consumed by the iOS app (app/) and validated against server/ via tests/contract/.

import PackageDescription

let package = Package(
    name: "WorkoutDBSchema",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "WorkoutDBSchema", targets: ["WorkoutDBSchema"]),
    ],
    targets: [
        .target(name: "WorkoutDBSchema"),
        .testTarget(name: "WorkoutDBSchemaTests", dependencies: ["WorkoutDBSchema"]),
    ]
)
