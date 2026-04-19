// SetPlan.swift
//
// The autoreg "apply" surface operates on a flat list of set-plan rows —
// the remaining prescribed sets that live in a session. This is a local
// value type owned by Core/Autoreg rather than Core/Domain because the
// concept of a *pending* set is a session-runtime concern, not a stored
// entity (set_log is the stored shape). Core/Session uses the same type
// as its in-session log row, materializing it from the prescription on
// start and flipping `done=true` (plus the observed reps/rir) on logSet.
//
// The `adjust` field encodes per-set autoreg state and is the load-bearing
// bit for the manual-wins rule:
//
//   - `nil`     — authored prescription, never touched by autoreg.
//   - `.up`     — autoreg bumped this set up. Can be overwritten by a later
//                 autoreg proposal (up or down) or by a manual edit (→ .manual).
//   - `.down`   — autoreg dropped this set. Same overwrite rules as .up.
//   - `.manual` — the user edited this set's load. Autoreg never overwrites
//                 a manual adjust. See docs/prescription.md § "Autoreg +
//                 manual edit".
//
// The `rir` field is session-local observed RIR. `nil` on a pending set
// (not yet logged) and on a done set where the user skipped the RIR
// picker (docs/prescription.md § "RIR nullable in set_log"). Autoreg
// does not read the field directly — the Features layer passes observed
// rir into `Autoreg.propose` at log time. Storing rir on SetPlan keeps
// the log table a single row-type in Core/Session (see `app/README.md`
// § "Persistence · Log: load, reps, rir, done, adjust").

import Foundation
import CoreDomain

public struct SetPlan: Equatable, Sendable, Hashable {

    public enum Adjust: String, Sendable, Equatable, Hashable {
        case up
        case down
        case manual
    }

    /// 1-based set index within the item (set 1, set 2, ...). Matches the
    /// `set_log.set_index` convention on the server.
    public let setIndex: Int

    /// Current prescribed load for this set. The value is in `unit`'s
    /// scale — `unit == .lb` means `loadKg` is actually a pound value.
    ///
    /// `nil` means "no external load" (bodyweight, loadless AMRAP token,
    /// `.empty` placeholder). The distinction matters end-to-end: a nil
    /// row flows through the push path as `SetLog.weight = nil`, which
    /// History renders as "BW". A numeric 0 would render as "0 lb" and
    /// lie about the lift. Drivers render nil via the unit-aware
    /// `formatLoad(weight: nil, ...)` which returns "BW" by contract.
    /// Autoreg skips nil rows (no numeric load to adjust).
    ///
    /// The field retains the legacy `loadKg` spelling as a sidecar to the
    /// R2.10 cutover; renaming would ripple across ~200 callsites across
    /// Core/Session reducer handlers, mutations, drivers, codable shims,
    /// and tests — all of which read the same Double either way. The
    /// `unit` companion is the source of truth for what scale the number
    /// is in; the `loadKg` name is a semantic compromise flagged in
    /// scratch/codex-reviews session context as a known lie.
    public let loadKg: Double?

    /// Unit the `loadKg` scalar is in. Determines display suffix, autoreg
    /// step size (1.25 for kg, 5.0 for lb), and the `SetLog.weightUnit`
    /// written at log time. Defaults to `.lb` when a prescription omits
    /// `weight_unit` (see docs/prescription.md § "Units").
    public let unit: WeightUnit

    /// Current prescribed rep count for this set. After `logSet`, this
    /// holds the observed reps.
    public let reps: Int

    /// Whether the set has been logged yet. `apply(...)` never touches
    /// done sets — once a set is logged it is immutable history from
    /// autoreg's point of view. (Manual edits to past sets happen through
    /// a different path and do not re-trigger autoreg.)
    public let done: Bool

    /// Per-set autoreg state. See the file header for semantics.
    public let adjust: Adjust?

    /// Observed RIR for this set. `nil` until logged; also `nil` if the
    /// user skipped the RIR picker on log. Autoreg does not read this
    /// field — callers pass rir directly to `Autoreg.propose`. See file
    /// header.
    public let rir: Int?

    /// Wall-clock timestamp the user tapped "log" on this set. `nil`
    /// until logged. Stamped by the reducer's `.logSet` handler with the
    /// `now` the Features layer hands in (the VM pulls it from `clock.now`
    /// at tap time). Used by the push path to preserve the original
    /// timestamp on corrective edits, and by `writeCompletionToLocalCache`
    /// to stamp per-set `completed_at` values (so rest-time analysis has
    /// real timestamps rather than all sets collapsed onto the final
    /// `saveAndDone` instant). Never mutated by autoreg or by manual edits —
    /// once logged, the timestamp is immutable history. See file header.
    public let completedAt: Date?

    /// Cardio-only: how long the interval / effort ran (seconds). `nil`
    /// for strength sets. Stamped by the reducer's `.logCardioSet`
    /// handler when a cardio driver logs a set; plumbed through to the
    /// server's `set_log.duration_sec` column via the push path.
    public let durationSec: Double?

    /// Cardio-only: distance covered during the interval / effort
    /// (metres). `nil` for strength sets.
    public let distanceM: Double?

    /// Cardio-only: average heart rate in bpm during the interval /
    /// effort. `nil` for strength sets and when no HR source was
    /// connected. v1 leaves this nil at log time — the Health-backed
    /// capture is deferred until a later milestone.
    public let hrAvgBpm: Int?

    /// Cardio-only: average cadence (steps or strokes per minute) during
    /// the interval / effort. Same nullability story as `hrAvgBpm`.
    public let cadenceAvgSpm: Int?

    /// Cardio-only: wall-clock stamp for when the interval / effort
    /// started. The strength path derives `startedAt` at completion time
    /// (previous set's `completedAt`) via `buildCompletionSetLogs`;
    /// cardio modes know the start instant at log time and can stamp it
    /// directly.
    public let startedAt: Date?

    public init(
        setIndex: Int,
        loadKg: Double?,
        unit: WeightUnit = .lb,
        reps: Int,
        done: Bool,
        adjust: Adjust?,
        rir: Int? = nil,
        completedAt: Date? = nil,
        durationSec: Double? = nil,
        distanceM: Double? = nil,
        hrAvgBpm: Int? = nil,
        cadenceAvgSpm: Int? = nil,
        startedAt: Date? = nil
    ) {
        self.setIndex = setIndex
        self.loadKg = loadKg
        self.unit = unit
        self.reps = reps
        self.done = done
        self.adjust = adjust
        self.rir = rir
        self.completedAt = completedAt
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.hrAvgBpm = hrAvgBpm
        self.cadenceAvgSpm = cadenceAvgSpm
        self.startedAt = startedAt
    }

    /// Convenience for the apply path — returns a copy with an updated
    /// load and adjust. Internal because callers outside this package
    /// should either go through `Autoreg.apply(...)` or construct a fresh
    /// SetPlan explicitly.
    internal func with(loadKg newLoadKg: Double?, adjust newAdjust: Adjust?) -> SetPlan {
        SetPlan(
            setIndex: setIndex,
            loadKg: newLoadKg,
            unit: unit,
            reps: reps,
            done: done,
            adjust: newAdjust,
            rir: rir,
            completedAt: completedAt,
            durationSec: durationSec,
            distanceM: distanceM,
            hrAvgBpm: hrAvgBpm,
            cadenceAvgSpm: cadenceAvgSpm,
            startedAt: startedAt
        )
    }
}
