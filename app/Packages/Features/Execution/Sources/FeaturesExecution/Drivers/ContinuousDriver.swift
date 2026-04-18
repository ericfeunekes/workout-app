// ContinuousDriver.swift
//
// TimingDriver for `timing_mode = continuous` — one long effort at a target
// zone / pace (Z2 ride, easy run, 5K tempo). Per `docs/prescription.md` §
// "continuous", the block authors any combination of `target_duration_sec`,
// `target_distance_m`, `target_pace_sec_per_km`, `target_hr_zone` — all
// optional. Items are a single cardio exercise with (typically) an empty
// prescription.
//
// Scope of this driver:
//   - `activeContent` renders the single continuous effort. The cursor's
//     setIndex is always 1 and totalSets is always 1 — there are no
//     discrete sets to count. Because `ActiveContent` is reps/load
//     oriented, we reuse the two display strings for cardio targets:
//       * `repsDisplay` carries the primary target — duration ("30 min")
//         when `target_duration_sec` is authored, else distance ("5 km")
//         when `target_distance_m` is authored, else "—".
//       * `loadDisplay` carries the secondary target — pace
//         ("4:30 / km") when `target_pace_sec_per_km` is authored, else a
//         zone label ("Z2") when `target_hr_zone` is authored, else "—".
//     Raw `reps` / `loadKg` remain 0 / nil — the Active view's numpad is
//     not used; logging a continuous effort is a single "tap done"
//     action, not a per-set entry. See the driver brief for the proposed
//     `ActiveContent` refactor (a dedicated `cardio(primary/secondary)`
//     variant) if this convention ever bites.
//   - `restDuration` returns 0. Continuous has no rest — it is one
//     unbroken piece. The VM routes to `.complete` when the target is
//     hit (target logic lives in the VM, not here).
//   - `onSetLogged` returns an empty outcome. Continuous has no autoreg
//     (per `docs/prescription.md` § "Autoregulation").
//
// Malformed / missing timing config → both display fields fall back to
// "—" and `restDuration` stays 0. The user still sees the exercise name
// and can log a completion — the parser failure has already eaten the
// target values and we cannot recover them from here.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct ContinuousDriver: TimingDriver {

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    /// Resolve the single cardio item and format the primary/secondary
    /// targets into the reps/load display fields. See file header for
    /// the repurposing convention.
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

        let (primary, secondary) = parseForDisplay(state: state, context: context)

        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )

        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: 1,
            totalSets: 1,
            loadDisplay: secondary,
            repsDisplay: primary,
            loadKg: nil,
            reps: 0,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    // MARK: - Rest duration

    /// Continuous has no rest — the whole block is one unbroken effort.
    /// Always 0, regardless of timing config contents or parse outcome.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        0
    }

    // MARK: - Log outcome

    /// No autoreg on continuous (per `docs/prescription.md` §
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

    /// Parse the block's timing config and pre-format the two display
    /// strings. Primary target prefers duration over distance; secondary
    /// prefers pace over HR zone. Both return "—" when nothing is
    /// authored (or parsing fails).
    private func parseForDisplay(
        state: SessionState,
        context: WorkoutContext
    ) -> (primary: String, secondary: String) {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else {
            return ("—", "—")
        }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            guard case let .continuous(
                targetDurationSec,
                targetDistanceM,
                targetPaceSecPerKm,
                targetHrZone
            ) = config else {
                return ("—", "—")
            }
            let primary: String
            if let targetDurationSec {
                primary = formatDurationTarget(targetDurationSec)
            } else if let targetDistanceM {
                primary = formatDistanceTarget(targetDistanceM)
            } else {
                primary = "—"
            }
            let secondary: String
            if let targetPaceSecPerKm {
                secondary = formatPace(secPerKm: targetPaceSecPerKm)
            } else if let targetHrZone {
                secondary = "Z\(targetHrZone)"
            } else {
                secondary = "—"
            }
            return (primary, secondary)
        case .failure:
            return ("—", "—")
        }
    }

    /// Render a duration target: whole minutes use "N min" (reads naturally
    /// for longer efforts — "30 min", "45 min"); sub-minute or fractional
    /// minutes fall back to "mm:ss".
    private func formatDurationTarget(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 && total % 60 == 0 {
            return "\(total / 60) min"
        }
        if total < 60 {
            return "\(total) s"
        }
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Render a distance target: ≥1 km renders as "5 km" / "5.5 km";
    /// below that renders as "N m".
    private func formatDistanceTarget(_ metres: Double) -> String {
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

    /// Render a pace: seconds-per-km → "m:ss / km" (e.g. 360 → "6:00 / km").
    private func formatPace(secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d / km", m, s)
    }
}
