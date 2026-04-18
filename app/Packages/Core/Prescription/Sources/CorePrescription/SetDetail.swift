// SetDetail.swift
//
// One element inside a `sets_detail` array — see docs/prescription.md
// § "Per-set variation" and § "Drop sets" and § "Warm-ups".
//
// Each element is one set with its own reps + (optional) load. Flags:
//   `drop`   : collapse under the previous set's rest (drop set mechanic)
//   `warmup` : exclude this set from autoreg triggers and history aggregates
//
// Loads are optional because bodyweight-only details omit `load_kg`.

import Foundation

public struct SetDetail: Equatable, Sendable, Hashable {
    public let reps: RepCount
    public let loadKg: Double?
    public let drop: Bool
    public let warmup: Bool

    public init(
        reps: RepCount,
        loadKg: Double? = nil,
        drop: Bool = false,
        warmup: Bool = false
    ) {
        self.reps = reps
        self.loadKg = loadKg
        self.drop = drop
        self.warmup = warmup
    }
}
