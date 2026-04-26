// ExecutionViewModel+LogCardioSet.swift
//
// Cardio log entry point, split out of `ExecutionViewModel.swift` so
// the class body stays under SwiftLint's `type_body_length` cap.
//
// The cardio path mirrors the shape of `logSet(reps:rir:)` with two
// differences:
//   1. Inputs are bundled in `CardioLogInput` so the public call site
//      doesn't exceed `function_parameter_count`. All cardio metrics
//      are optional — time-only intervals carry only `durationSec`;
//      distance-only pieces carry only `distanceM`.
//   2. No autoreg proposal is ever surfaced — cardio drivers return an
//      empty `DriverLogOutcome` by contract (per
//      `docs/prescription.md` § "Autoregulation").
//
// The rest/advance flow is shared with the strength path via
// `buildLogMutations`, so the `IntervalsDriver`'s final-interval
// short-circuit (rest=0 on the last interval → advance → `.complete`)
// works the same way strength's final-set advance does.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

extension ExecutionViewModel {

    /// Bundle of cardio metrics captured at log time. Every field is
    /// optional so the call site can author whichever sensors produced
    /// data — a treadmill interval with no HR strap logs with only
    /// `durationSec` / `distanceM` populated.
    public struct CardioLogInput: Sendable, Equatable {
        public let durationSec: Double?
        public let distanceM: Double?
        public let hrAvgBpm: Int?
        public let cadenceAvgSpm: Int?
        public let startedAt: Date?

        public init(
            durationSec: Double? = nil,
            distanceM: Double? = nil,
            hrAvgBpm: Int? = nil,
            cadenceAvgSpm: Int? = nil,
            startedAt: Date? = nil
        ) {
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.hrAvgBpm = hrAvgBpm
            self.cadenceAvgSpm = cadenceAvgSpm
            self.startedAt = startedAt
        }
    }

    /// Log a cardio set from a `CardioLogInput` bundle. See file header
    /// for the semantics — this is the bundle form of `logCardioSet(...)`
    /// that stays under SwiftLint's parameter-count cap.
    public func logCardioSet(_ input: CardioLogInput) {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        let logMutation: SessionMutation = .logCardioSet(
            itemID: item.id,
            setIndex: c.setIndex,
            durationSec: input.durationSec,
            distanceM: input.distanceM,
            hrAvgBpm: input.hrAvgBpm,
            cadenceAvgSpm: input.cadenceAvgSpm,
            startedAt: input.startedAt,
            now: clock.now
        )
        applyCardioLog(item: item, setIndex: c.setIndex, logMutation: logMutation)
        completeAccumulateIfTargetReached()
        emitSessionMutation("logCardioSet")
        enqueueLoggedCardioSet(item: item, setIndex: c.setIndex, input: input)
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
        prepareExplicitSetStartIfNeeded()
    }

    /// Convenience overload that accepts individual cardio fields.
    /// Mirrors the shape of `logSet(reps:rir:)` for call-site symmetry.
    public func logCardioSet(
        durationSec: Double?,
        distanceM: Double?,
        hrAvgBpm: Int? = nil,
        cadenceAvgSpm: Int? = nil,
        startedAt: Date? = nil
    ) {
        logCardioSet(CardioLogInput(
            durationSec: durationSec,
            distanceM: distanceM,
            hrAvgBpm: hrAvgBpm,
            cadenceAvgSpm: cadenceAvgSpm,
            startedAt: startedAt
        ))
    }

    /// `true` when the cursor's current block is cardio-shaped. The
    /// Active view reads this to
    /// pick its log affordance — cardio blocks fire `logCurrentSet()`
    /// directly (no reps/RIR sheet), strength blocks open `LogSetSheet`.
    ///
    /// Tabata and custom only route here when the driver renders the
    /// current content as `.cardio`; strength-shaped Tabata rounds still
    /// open the normal load/reps/RIR sheet.
    public var isCurrentBlockCardio: Bool {
        let bi = state.cursor.blockIndex
        guard let block = context.block(at: bi) else { return false }
        switch block.timingMode {
        case .intervals, .continuous:
            return true
        case .accumulate:
            return accumulateTargetKind != .reps
        case .straightSets, .superset, .circuit, .emom, .tabata, .custom:
            return activeContent?.kind == .cardio
        case .amrap, .forTime, .rest:
            return false
        }
    }

    public var continuousTargetReached: Bool {
        guard state.route == .active,
              let block = context.block(at: state.cursor.blockIndex),
              block.timingMode == .continuous,
              let workEndsAt = state.workEndsAt else {
            return false
        }
        return clock.now >= workEndsAt
    }

    public func continueContinuousPastTarget() {
        guard continuousTargetReached else { return }
        state.workEndsAt = nil
        persist()
    }

    /// Log the current set, routing to either `logSet(reps:rir:)` or
    /// `logCardioSet(...)` based on the current block's timing mode.
    ///
    /// Strength modes consume `reps` / `rir` and fire the strength path.
    /// Cardio modes (`.intervals`, `.continuous`) derive a
    /// `CardioLogInput` from the current `SessionState` + timing config
    /// and fire `logCardioSet`. Callers in the Active view can invoke
    /// this without knowing the mode — the "dumb app" principle: the
    /// view dispatches a single intent; the view model picks the shape.
    ///
    /// Timing data sources:
    ///   * `intervals`: `durationSec` = elapsed `clock.now - workStartedAt`
    ///     when `workStartedAt` is populated (the live gym case); else
    ///     `work_sec` from `timing_config_json` when authored. Elapsed wins
    ///     because a log must describe what actually happened — authored
    ///     targets are prescription, not performance.
    ///   * `continuous`: `durationSec` = elapsed `clock.now - workStartedAt`.
    ///   * `startedAt` = `state.workStartedAt` when set (stamped by
    ///     `.start` / `.advanceFromRest`); else nil (the reducer falls
    ///     back to its own `workStartedAt`).
    ///   * `distanceM` / `hrAvgBpm` / `cadenceAvgSpm` are nil — v1 has
    ///     no sensor integration. Authored distance (e.g. intervals
    ///     `work_distance_m`) is passed through so the cardio row
    ///     carries the prescribed distance even without GPS.
    public func logCurrentSet(reps: Int? = nil, rir: Int? = nil) {
        if isCurrentBlockCardio {
            logCardioSet(buildCardioLogInputFromState())
        } else {
            logSet(reps: reps ?? 0, rir: rir)
        }
    }

    /// Build a `CardioLogInput` from the current `SessionState` + the
    /// current block's parsed timing config. Called by `logCurrentSet`
    /// when the active block is cardio. See `logCurrentSet` for the
    /// duration-derivation rules.
    private func buildCardioLogInputFromState() -> CardioLogInput {
        let startedAt = state.workStartedAt
        let elapsed: TimeInterval? = startedAt.map { clock.now.timeIntervalSince($0) }
        if let set = activeSetPlan,
           activeKind(for: set) == .cardio {
            return CardioLogInput(
                durationSec: canonicalDurationForLog(set: set, elapsed: elapsed),
                distanceM: canonicalDistanceForLog(set: set),
                startedAt: startedAt
            )
        }
        let bi = state.cursor.blockIndex
        guard let block = context.block(at: bi) else {
            return CardioLogInput(durationSec: elapsed, startedAt: startedAt)
        }
        let parser = PrescriptionParser()
        guard case .success(let config) = parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) else {
            return CardioLogInput(durationSec: elapsed, startedAt: startedAt)
        }
        return buildCardioLogInput(
            from: config,
            elapsed: elapsed,
            startedAt: startedAt
        )
    }

    /// Map a parsed `TimingConfig` to a `CardioLogInput`. Intervals
    /// prefers elapsed real time when `workStartedAt` is populated —
    /// that's the actual performance. Authored `work_sec` / target pace
    /// are prescription targets; falling back to them when we already
    /// have elapsed would echo the plan instead of logging reality.
    /// Prescription-derived values only fire when elapsed is nil — a
    /// restored session with no start anchor, for instance.
    /// `distanceM` still comes from the authored prescription (no
    /// sensor integration in v1), so an interval run logs the prescribed
    /// distance alongside the actual duration. Continuous uses
    /// elapsed-since-start. Anything else (defensive — the caller has
    /// already narrowed via `isCurrentBlockCardio`) falls through to
    /// elapsed-only.
    private func buildCardioLogInput(
        from config: TimingConfig,
        elapsed: TimeInterval?,
        startedAt: Date?
    ) -> CardioLogInput {
        switch config {
        case let .intervals(workSec, _, workDistanceM, _, _, _):
            let duration: Double?
            if let elapsed {
                duration = elapsed
            } else if let workSec {
                duration = workSec
            } else {
                duration = nil
            }
            return CardioLogInput(
                durationSec: duration,
                distanceM: workDistanceM,
                startedAt: startedAt
            )
        case .tabata:
            return CardioLogInput(
                durationSec: elapsed ?? TabataDriver.workSec,
                startedAt: startedAt
            )
        case .custom(let segments):
            let index = state.cursor.setIndex - 1
            let segmentDuration = segments.indices.contains(index)
                ? segments[index].durationSec
                : nil
            return CardioLogInput(
                durationSec: elapsed ?? segmentDuration,
                startedAt: startedAt
            )
        case .accumulate:
            return CardioLogInput(durationSec: elapsed, startedAt: startedAt)
        default:
            // Continuous + any other cardio-adjacent mode that lands here:
            // duration is the elapsed real time since `workStartedAt`.
            // An authored `target_duration_sec` is a TARGET, not what
            // actually happened.
            return CardioLogInput(durationSec: elapsed, startedAt: startedAt)
        }
    }

    /// Apply the cardio log mutation plus the driver's post-log
    /// outcome (rest / advance), matching `logSet`'s ordering. Cardio
    /// drivers never propose autoreg, so the `currentProposal` slots
    /// are cleared unconditionally.
    private func applyCardioLog(
        item: WorkoutItem,
        setIndex: Int,
        logMutation: SessionMutation
    ) {
        let previousBlockIndex = state.cursor.blockIndex
        let outcome = driver.onSetLogged(
            state: state,
            context: context,
            event: SetLogEvent(
                itemID: item.id,
                setIndex: setIndex,
                loggedReps: 0,
                loggedRir: nil
            )
        )
        let postLogState = SessionReducer.reduce(state, logMutation)
        apply(buildLogMutations(
            logMutation: logMutation,
            outcome: outcome,
            item: item,
            postLogState: postLogState
        ))
        _ = enterBlockTransitionIfNeeded(from: previousBlockIndex)
        currentProposal = nil
        currentProposalItemID = nil
    }
}
