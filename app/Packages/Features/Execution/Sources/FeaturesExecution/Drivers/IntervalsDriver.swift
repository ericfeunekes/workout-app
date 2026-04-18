// IntervalsDriver.swift
//
// TimingDriver for `timing_mode = intervals` — alternating work/rest phases
// over a fixed number of intervals, usually cardio (run / bike / row). Per
// `docs/prescription.md` § "intervals", the block authors either a
// time-based shape (`work_sec` / `rest_sec`) or a distance-based shape
// (`work_distance_m` / `rest_distance_m`), plus `interval_count` and an
// optional `target_pace_sec_per_km`. Items are usually a single cardio
// exercise with an empty prescription (`{}`).
//
// Scope of this driver:
//   - `activeContent` renders the current interval for the cardio item.
//     Because the `ActiveContent` struct is reps/load oriented and cardio
//     intervals carry no reps/load, we reuse the two display fields:
//       * `repsDisplay` carries the work "amount" ("400 m" for distance-
//         based; "30 s" for time-based).
//       * `loadDisplay` carries the target pace ("4:30 / km") or "—" when
//         no pace is authored.
//     Raw `reps` / `loadKg` remain 0 / nil — there is nothing numeric for
//     the numpad to edit; v1 logs the interval as a "tap next lap" event,
//     not a typed reps/load entry. The Active view treats these two
//     display strings as free-form hero labels for cardio modes.
//     `setIndex` carries the 1-based interval number, `totalSets` carries
//     the authored `interval_count`.
//   - `restDuration` returns the rest between intervals. Time-based configs
//     use `rest_sec` directly. Distance-based configs have no native rest
//     time, so we approximate from the authored pace:
//       rest_time_sec = rest_distance_m / 1000 * target_pace_sec_per_km.
//     When the distance-based config omits pace we fall back to 0 — the
//     VM's auto-advance path collapses the zero rest and drops straight
//     back to `.active` for the next interval. GPS-driven distance
//     advancement is a v1.1+ concern.
//   - `onSetLogged` returns an empty outcome. Intervals has no autoreg
//     (per `docs/prescription.md` § "Autoregulation").
//
// Malformed / missing timing config → restDuration = 0 and totalSets = 0.
// The parser returns `.failure` in that case; we degrade gracefully
// rather than trapping the session.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct IntervalsDriver: TimingDriver {

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    /// Resolve the current cardio item and render distance/pace into the
    /// reps/load display fields. See file header for the repurposing
    /// convention — cardio drivers overload the existing struct rather
    /// than introduce a parallel "cardio active content" type (proposed as
    /// a future structural change in the driver brief).
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

        let (workDisplay, paceDisplay, intervalCount) = parseForDisplay(
            state: state,
            context: context
        )

        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: c.setIndex,
            totalSets: intervalCount,
            loadDisplay: paceDisplay,
            repsDisplay: workDisplay,
            loadKg: nil,
            reps: 0,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// Rest between intervals. Time-based configs expose `rest_sec`
    /// directly. Distance-based configs derive a time estimate from the
    /// authored pace; without a pace we return 0 (user taps "next lap"
    /// to advance — GPS-driven advance is not v1). Malformed / wrong-mode
    /// configs also return 0.
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
            guard case let .intervals(_, restSec, _, restDistanceM, _, paceSecPerKm) = config else {
                return 0
            }
            if let restSec {
                return restSec
            }
            if let restDistanceM, let paceSecPerKm {
                return restDistanceM / 1000.0 * paceSecPerKm
            }
            return 0
        case .failure:
            return 0
        }
    }

    // MARK: - Log outcome

    /// No autoreg on intervals (per `docs/prescription.md` §
    /// "Autoregulation"). The driver never proposes a change regardless
    /// of the logged reps/RIR.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Parse the block's timing config once and pre-format the display
    /// strings for the Active hero. Returns ("—", "—", 0) on any failure
    /// so the UI renders a placeholder rather than a crash.
    private func parseForDisplay(
        state: SessionState,
        context: WorkoutContext
    ) -> (work: String, pace: String, intervalCount: Int) {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else {
            return ("—", "—", 0)
        }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            guard case let .intervals(
                workSec,
                _,
                workDistanceM,
                _,
                intervalCount,
                paceSecPerKm
            ) = config else {
                return ("—", "—", 0)
            }
            let work: String
            if let workDistanceM {
                work = formatMetres(workDistanceM)
            } else if let workSec {
                work = formatSeconds(workSec)
            } else {
                work = "—"
            }
            let pace = paceSecPerKm.map(formatPace(secPerKm:)) ?? "—"
            return (work, pace, intervalCount)
        case .failure:
            return ("—", "—", 0)
        }
    }

    /// Render a distance in metres: "400 m" for integer metres,
    /// "1.2 km" when the value reaches a full kilometre (compact for
    /// longer intervals).
    private func formatMetres(_ metres: Double) -> String {
        if metres >= 1000 {
            let km = metres / 1000.0
            if km.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(km)) km"
            }
            return String(format: "%.1f km", km)
        }
        if metres.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(metres)) m"
        }
        return String(format: "%.0f m", metres)
    }

    /// Render a duration in seconds: "30 s" under a minute; otherwise
    /// "mm:ss" (e.g. "1:30", "10:00") to match how runners read splits.
    private func formatSeconds(_ seconds: Double) -> String {
        if seconds < 60 {
            if seconds.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(seconds)) s"
            }
            return String(format: "%.0f s", seconds)
        }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Render a pace: seconds-per-km → "m:ss / km" (e.g. 270 → "4:30 / km").
    private func formatPace(secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d / km", m, s)
    }
}
