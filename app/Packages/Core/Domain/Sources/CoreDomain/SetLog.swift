// SetLog.swift
//
// See docs/specs/v2-architecture.md § "Data model · set_log".

import Foundation
import WorkoutCoreFoundation

/// What actually happened during one set.
///
/// `performedExerciseID` is `nil` when the planned exercise was performed as
/// prescribed; non-`nil` when the user swapped to an alternative mid-workout.
/// Swaps are lossless on the log — the workout template is not mutated.
///
/// `rir` is on the 0–5 "reps in reserve" scale (0 = failure, 5 = very easy).
/// The value is not enforced at the type level; callers validate before
/// persisting. See `docs/prescription.md` § "RIR" for the full scale.
public struct SetLog: Sendable, Hashable {
    public var id: SetLogID
    public var workoutItemID: WorkoutItemID
    public var performedExerciseID: ExerciseID?
    public var setIndex: Int
    public var reps: Int?
    public var weight: Double?
    public var weightUnit: WeightUnit?
    public var durationSec: Double?
    public var distanceM: Double?
    /// Reps in Reserve, 0–5. See type doc.
    public var rir: Int?
    public var isWarmup: Bool
    public var skipped: Bool
    public var side: SetLogSide
    public var startedAt: Date?
    public var completedAt: Date
    public var hrAvgBpm: Int?
    public var hrMaxBpm: Int?
    public var cadenceAvgSpm: Int?
    /// Reserved for future bar-speed / power analysis. v1 does not capture.
    public var motionSamplesRef: String?
    public var notes: String?

    public init(
        id: SetLogID,
        workoutItemID: WorkoutItemID,
        performedExerciseID: ExerciseID? = nil,
        setIndex: Int,
        reps: Int? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit? = nil,
        durationSec: Double? = nil,
        distanceM: Double? = nil,
        rir: Int? = nil,
        isWarmup: Bool = false,
        skipped: Bool = false,
        side: SetLogSide = .bilateral,
        startedAt: Date? = nil,
        completedAt: Date,
        hrAvgBpm: Int? = nil,
        hrMaxBpm: Int? = nil,
        cadenceAvgSpm: Int? = nil,
        motionSamplesRef: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutItemID = workoutItemID
        self.performedExerciseID = performedExerciseID
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rir = rir
        self.isWarmup = isWarmup
        self.skipped = skipped
        self.side = side
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
        self.cadenceAvgSpm = cadenceAvgSpm
        self.motionSamplesRef = motionSamplesRef
        self.notes = notes
    }
}
