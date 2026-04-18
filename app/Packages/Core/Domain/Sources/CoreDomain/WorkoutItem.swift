// WorkoutItem.swift
//
// See docs/specs/v2-architecture.md § "Data model · workout_item".

import Foundation
import WorkoutCoreFoundation

/// An exercise placed inside a block.
///
/// `prescriptionJSON` is the mode-dependent "what to do" payload. It stays
/// opaque at this layer; parsers live in `Core/Prescription`. See
/// `docs/prescription.md` for the authoring vocabulary.
public struct WorkoutItem: Sendable, Hashable {
    public var id: WorkoutItemID
    public var blockID: BlockID
    public var position: Int
    public var exerciseID: ExerciseID
    /// Resolved prescription — server has already merged library defaults in.
    /// Runtime consumers read only this field.
    public var prescriptionJSON: String
    /// The original sparse payload the client sent to the server (nil when
    /// the resolved form equals what the client sent). Round-tripped for
    /// completeness; not used at runtime. See `ADR-2026-04-18-smart-defaults`.
    public var prescriptionJSONRaw: String?

    public init(
        id: WorkoutItemID,
        blockID: BlockID,
        position: Int,
        exerciseID: ExerciseID,
        prescriptionJSON: String,
        prescriptionJSONRaw: String? = nil
    ) {
        self.id = id
        self.blockID = blockID
        self.position = position
        self.exerciseID = exerciseID
        self.prescriptionJSON = prescriptionJSON
        self.prescriptionJSONRaw = prescriptionJSONRaw
    }
}
