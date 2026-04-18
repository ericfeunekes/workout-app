// Workout.swift
//
// See docs/specs/v2-architecture.md § "Data model · workout".

import Foundation
import WorkoutCoreFoundation

/// A complete session ready to execute.
///
/// `tagsJSON` is an opaque JSON array attached by Claude for analysis
/// grouping (e.g. `["hypertrophy_block_2", "week_3"]`). The app does not
/// interpret it; keep it as a `String?` and round-trip it unchanged.
public struct Workout: Sendable, Hashable {
    public var id: WorkoutID
    public var userID: UserID
    public var name: String
    public var scheduledDate: Date?
    public var status: WorkoutStatus
    public var source: WorkoutSource
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var tagsJSON: String?

    public init(
        id: WorkoutID,
        userID: UserID,
        name: String,
        scheduledDate: Date? = nil,
        status: WorkoutStatus,
        source: WorkoutSource,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        tagsJSON: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.scheduledDate = scheduledDate
        self.status = status
        self.source = source
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.tagsJSON = tagsJSON
    }
}
