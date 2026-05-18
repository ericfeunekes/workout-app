// UserParameter.swift
//
// See docs/specs/v2-architecture.md § "Data model · user_parameters".

import Foundation
import WorkoutCoreFoundation

/// A row in the append-only `user_parameters` log. Latest-per-key is what the
/// app reads at workout start (`GET /api/user-parameters?latest=true`);
/// history drives longitudinal analysis.
///
/// `value` is stored as a `String` and interpreted in context — e.g. the key
/// `one_rep_max_<exercise_id>_kg` implies "numeric in kg". Unknown keys are kept but
/// ignored by the app until it's taught to use them.
public struct UserParameter: Sendable, Hashable {
    public var id: UserParameterID
    public var userID: UserID
    public var key: String
    public var value: String
    public var updatedAt: Date
    public var source: UserParameterSource

    public init(
        id: UserParameterID,
        userID: UserID,
        key: String,
        value: String,
        updatedAt: Date,
        source: UserParameterSource
    ) {
        self.id = id
        self.userID = userID
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
        self.source = source
    }
}
