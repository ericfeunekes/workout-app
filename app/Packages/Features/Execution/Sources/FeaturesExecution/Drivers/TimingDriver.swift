// TimingDriver.swift
//
// Strategy protocol for per-timing-mode behavior. Per
// `docs/architecture/hotspots.md` § HS-2, adding a new timing mode must
// be "add a file, not edit a switch": each mode conforms once and the
// view model routes to it by `block.timingMode`.
//
// The driver is kept narrow on purpose — it answers three questions the
// Execution view needs:
//
//   1. What should the Active screen show for this (item, setIndex)?
//   2. How long is the rest after logging a set here?
//   3. What per-item autoreg + set-log mutations does this log imply?
//
// All three are pure functions over inputs. State lives in
// `SessionState`; the driver is reconstructed fresh per call.
//
// Drivers never dispatch mutations themselves — they return a list of
// `SessionMutation`s that the view model applies via the reducer. Keeping
// the write path flowing through one place (the reducer) keeps testing
// and persistence coherent.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

/// Pure description of what the Active screen should display for the
/// current set. Produced by a driver; consumed by `ActiveView`.
public struct ActiveContent: Equatable, Sendable {
    public let exerciseName: String
    /// 1-based set counter — "2" of `totalSets`.
    public let setIndex: Int
    /// Total sets prescribed for the current item (post-autoreg-adjust).
    public let totalSets: Int
    /// Pre-formatted load (honors bodyweight, BW+kg, fractional plates).
    public let loadDisplay: String
    /// Pre-formatted rep count (matches `formatReps` convention in the
    /// hi-fi — integer for numeric, "AMRAP" token passthrough).
    public let repsDisplay: String
    /// Raw load in kg for the numpad initial value. `nil` for bodyweight.
    public let loadKg: Double?
    /// Raw reps count for the numpad initial value.
    public let reps: Int
    /// Per-set autoreg glyph for the hero — `.up`, `.down`, `.manual`,
    /// or nil if untouched.
    public let adjustGlyph: SetPlan.Adjust?
    /// Optional "last time" summary (e.g. "5×5 @ 100 kg · RIR 2").
    public let lastTime: String?

    public init(
        exerciseName: String,
        setIndex: Int,
        totalSets: Int,
        loadDisplay: String,
        repsDisplay: String,
        loadKg: Double?,
        reps: Int,
        adjustGlyph: SetPlan.Adjust?,
        lastTime: String?
    ) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.totalSets = totalSets
        self.loadDisplay = loadDisplay
        self.repsDisplay = repsDisplay
        self.loadKg = loadKg
        self.reps = reps
        self.adjustGlyph = adjustGlyph
        self.lastTime = lastTime
    }
}

/// Strategy for a timing mode. Conforming types live in
/// `Drivers/<Mode>Driver.swift`, one per mode.
///
/// Drivers are stateless value types — any state they need comes in as
/// a parameter. This keeps them cheap to construct and trivial to test.
public protocol TimingDriver: Sendable {

    /// Build the Active screen content for the current cursor position.
    /// Returns nil when the cursor is outside the item this driver runs
    /// (defensive — the router should never call a driver with a cursor
    /// pointing to a different block).
    func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent?

    /// Duration of the rest after a set log. Parsed from the block's
    /// `timing_config_json`. Returns 0 when the block has no rest (e.g.
    /// last-set-overall handling lives in the view model, not here).
    func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval

    /// Given a just-logged (reps, rir), return any additional mutations
    /// the driver wants applied after the `.logSet` that surfaced the
    /// log. For straight_sets this is the autoreg proposal path; other
    /// modes may enqueue per-mode bookkeeping here.
    ///
    /// The caller (`ExecutionViewModel`) is responsible for dispatching
    /// the returned mutations through the reducer in order.
    func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome
}

/// The (item, set-index, reps, rir) tuple that identifies a single set-log
/// event. Bundled into one value so `TimingDriver.onSetLogged` stays under
/// SwiftLint's `function_parameter_count` cap and so future fields (e.g.
/// logged load, wall-clock) can be added without churn at every call site.
public struct SetLogEvent: Equatable, Sendable {
    public let itemID: UUID
    public let setIndex: Int
    public let loggedReps: Int
    public let loggedRir: Int?

    public init(itemID: UUID, setIndex: Int, loggedReps: Int, loggedRir: Int?) {
        self.itemID = itemID
        self.setIndex = setIndex
        self.loggedReps = loggedReps
        self.loggedRir = loggedRir
    }
}

/// The result of a driver's `onSetLogged`. The view model uses the
/// proposal (if any) to surface the autoreg banner; it dispatches the
/// mutations to the reducer in order.
public struct DriverLogOutcome: Equatable, Sendable {
    public let proposal: AutoregProposal?
    public let mutations: [SessionMutation]

    public init(
        proposal: AutoregProposal? = nil,
        mutations: [SessionMutation] = []
    ) {
        self.proposal = proposal
        self.mutations = mutations
    }
}
