// AppUser.swift
//
// See docs/specs/v2-architecture.md § "Data model · app_user".

import Foundation
import WorkoutCoreFoundation

/// The single user the app is scoped to. In v1 this is effectively
/// singleton — the bearer token resolves to one `AppUser` row on the server.
public struct AppUser: Sendable, Hashable {
    public var id: UserID
    public var name: String
    public var createdAt: Date

    public init(id: UserID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
