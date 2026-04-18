// EMOMDriver.swift
//
// TimingDriver for `timing_mode = emom` — Every Minute On the Minute.
// The block's `timing_config_json` supplies `interval_sec` (usually 60)
// and `total_minutes`; the interval count = total_minutes * 60 /
// interval_sec. Each item holds the per-interval work prescription
// (e.g. `{reps: 10, load_kg: 95}` for 10 KB swings every minute).
//
// Execution model:
//   - The VM drives a wall-clock timer ticking every `interval_sec`.
//     Each tick advances the cursor to the next interval.
//   - At interval N, the active item is `items[N % items.count]` —
//     round-robin per interval when multiple items are authored
//     (docs/prescription.md § "emom": "If multiple, they rotate per
//     minute in the listed order").
//   - The user logs their work inside the interval; the remaining
//     time in the interval IS the rest. When the user logs early,
//     the rest ring counts down `interval_sec − elapsed-since-tick`;
//     the VM is responsible for that subtraction. This driver just
//     returns `interval_sec` and the VM does the wall-clock math.
//   - At `total_minutes` elapsed the VM routes to `.complete`.
//
// Scope (this driver, today):
//   - activeContent: exercise name + reps + load for the item the
//     cursor points at, with setIndex = interval number and totalSets
//     = interval count (the "N of M" display becomes "interval N of M").
//   - restDuration: returns `interval_sec`. The remaining-time math
//     is VM work.
//   - onSetLogged: empty outcome. EMOM has no autoreg per spec
//     (docs/prescription.md § "Autoregulation" — "emom: No").
//
// Driving the interval ticks, the `total_minutes` cap, and the
// round-robin item resolution all live outside this driver —
// see the driver brief's "reducer / VM wiring" section.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct EMOMDriver: TimingDriver {

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    /// Resolve the current item via the cursor and pre-format the
    /// active-screen content. `setIndex` carries the 1-based interval
    /// number (from the cursor's `setIndex`, which the VM ticks each
    /// interval). `totalSets` is the total interval count —
    /// `total_minutes * 60 / interval_sec`.
    public func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }

        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

        let (reps, loadKg) = prescribed(for: item)
        let intervalCount = resolveIntervalCount(state: state, context: context)

        let loadDisplay = formatLoad(kg: loadKg)
        let repsDisplay = reps.map { String($0) } ?? "—"

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: c.setIndex,
            totalSets: intervalCount,
            loadDisplay: loadDisplay,
            repsDisplay: repsDisplay,
            loadKg: loadKg,
            reps: reps ?? 0,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// Return the interval length. The VM subtracts elapsed-since-
    /// start-of-interval when rendering the rest ring — this driver
    /// does not read the wall clock. Malformed/missing config → 0
    /// (matches `RestBlockDriver` and `StraightSetsDriver`'s parse-
    /// failure fallback).
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else { return 0 }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            if case .emom(let intervalSec, _) = config {
                return intervalSec
            }
            return 0
        case .failure:
            return 0
        }
    }

    // MARK: - Log outcome

    /// EMOM has no autoreg (docs/prescription.md § "Autoregulation").
    /// The VM advances the cursor on interval tick — logging a set
    /// does not trigger any driver-side mutation here.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Pull `reps` and `load_kg` off the item's prescription. EMOM
    /// items are `{reps, load_kg}` with no `sets`; the parser routes
    /// them to `.straightSets(sets: nil, reps: .count(n), loadKg: kg, ...)`.
    /// Defensive fallbacks on other shapes keep the driver from
    /// crashing on unexpected authoring.
    private func prescribed(for item: WorkoutItem) -> (reps: Int?, loadKg: Double?) {
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            switch p {
            case .straightSets(_, let reps, let loadKg, _, _, _, _):
                let repCount: Int? = {
                    guard let rc = reps, case .count(let n) = rc else { return nil }
                    return n
                }()
                return (repCount, loadKg)
            case .bodyweight(_, let reps, _):
                return (reps, nil)
            case .amrapToken(let loadKg, _):
                return (nil, loadKg)
            default:
                return (nil, nil)
            }
        case .failure:
            return (nil, nil)
        }
    }

    /// Compute the total interval count from the block's config.
    /// Returns 0 when the config is malformed or the mode is wrong,
    /// so `activeContent` still renders without lying about totals.
    private func resolveIntervalCount(
        state: SessionState,
        context: WorkoutContext
    ) -> Int {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else { return 0 }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            if case .emom(let intervalSec, let totalMinutes) = config {
                guard intervalSec > 0 else { return 0 }
                return Int((Double(totalMinutes) * 60.0) / intervalSec)
            }
            return 0
        case .failure:
            return 0
        }
    }
}
