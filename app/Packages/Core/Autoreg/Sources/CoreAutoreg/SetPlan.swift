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

public struct SetPlan: Equatable, Sendable, Hashable {

    public enum Adjust: String, Sendable, Equatable, Hashable {
        case up
        case down
        case manual
    }

    /// 1-based set index within the item (set 1, set 2, ...). Matches the
    /// `set_log.set_index` convention on the server.
    public let setIndex: Int

    /// Current prescribed load for this set. Units: kilograms.
    public let loadKg: Double

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

    public init(
        setIndex: Int,
        loadKg: Double,
        reps: Int,
        done: Bool,
        adjust: Adjust?,
        rir: Int? = nil
    ) {
        self.setIndex = setIndex
        self.loadKg = loadKg
        self.reps = reps
        self.done = done
        self.adjust = adjust
        self.rir = rir
    }

    /// Convenience for the apply path — returns a copy with an updated
    /// load and adjust. Internal because callers outside this package
    /// should either go through `Autoreg.apply(...)` or construct a fresh
    /// SetPlan explicitly.
    internal func with(loadKg newLoadKg: Double, adjust newAdjust: Adjust?) -> SetPlan {
        SetPlan(
            setIndex: setIndex,
            loadKg: newLoadKg,
            reps: reps,
            done: done,
            adjust: newAdjust,
            rir: rir
        )
    }
}
