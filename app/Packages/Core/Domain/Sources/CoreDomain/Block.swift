// Block.swift
//
// See docs/specs/v2-architecture.md § "Data model · block".

import Foundation
import WorkoutCoreFoundation

/// A group of exercises with a timing contract. Blocks nest via
/// `parentBlockID`.
///
/// `timingConfigJSON` holds mode-specific configuration (e.g.
/// `rest_between_sets_sec` for `straightSets`, `interval_sec` for `emom`).
/// `roundsRepSchemeJSON` holds block-level descending/ascending rep schemes
/// such as `[21, 15, 9]` for a "21-15-9 Fran" block. Both stay as opaque
/// `String`s — per-shape parsing lives in `Core/Prescription`.
public struct Block: Sendable, Hashable {
    public var id: BlockID
    public var workoutID: WorkoutID
    public var parentBlockID: BlockID?
    public var position: Int
    public var name: String?
    public var timingMode: TimingMode
    public var timingConfigJSON: String
    public var rounds: Int?
    public var roundsRepSchemeJSON: String?
    public var notes: String?

    public init(
        id: BlockID,
        workoutID: WorkoutID,
        parentBlockID: BlockID? = nil,
        position: Int,
        name: String? = nil,
        timingMode: TimingMode,
        timingConfigJSON: String,
        rounds: Int? = nil,
        roundsRepSchemeJSON: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutID = workoutID
        self.parentBlockID = parentBlockID
        self.position = position
        self.name = name
        self.timingMode = timingMode
        self.timingConfigJSON = timingConfigJSON
        self.rounds = rounds
        self.roundsRepSchemeJSON = roundsRepSchemeJSON
        self.notes = notes
    }
}
