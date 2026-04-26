// AccumulateDriver.swift
//
// TimingDriver for `timing_mode = accumulate` — repeated free-rest bouts
// toward one total target. Examples: accumulate 2:00 dead hang, 100 push-ups,
// or 100 ft loaded carry.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct AccumulateDriver: TimingDriver {
    private let parser = PrescriptionParser()

    public init() {}

    public func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        let exercise = context.exercises[item.exerciseID]
        let target = targetForCurrentBlock(state: state, context: context)
        let progress = progressForCurrentItem(state: state, context: context)
        let display = displayStrings(target: target, progress: progress)
        let seed = SessionSeeder.itemRepsAndLoad(for: item, parser: parser)
        let isCardioLike = target.kind != .reps
        return ActiveContent(
            exerciseName: exercise?.name ?? "Unknown exercise",
            setIndex: c.setIndex,
            totalSets: 0,
            loadDisplay: isCardioLike ? display.secondary : formatLoadForDisplay(seed.loadKg, unit: seed.unit),
            repsDisplay: display.primary,
            loadKg: seed.loadKg,
            reps: max(0, target.repsValue - progress.reps),
            adjustGlyph: nil,
            lastTime: nil,
            kind: isCardioLike ? .cardio : .strength
        )
    }

    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        0
    }

    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    private struct Target {
        enum Kind {
            case duration
            case reps
            case distance
            case unknown
        }

        let kind: Kind
        let durationValue: Double
        let repsValue: Int
        let distanceValue: Double
    }

    private struct Progress {
        let duration: Double
        let reps: Int
        let distance: Double
    }

    private func targetForCurrentBlock(
        state: SessionState,
        context: WorkoutContext
    ) -> Target {
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return Target(kind: .unknown, durationValue: 0, repsValue: 0, distanceValue: 0)
        }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(.accumulate(let duration, let reps, let distance)):
            if let duration {
                return Target(kind: .duration, durationValue: duration, repsValue: 0, distanceValue: 0)
            }
            if let reps {
                return Target(kind: .reps, durationValue: 0, repsValue: reps, distanceValue: 0)
            }
            if let distance {
                return Target(kind: .distance, durationValue: 0, repsValue: 0, distanceValue: distance)
            }
            return Target(kind: .unknown, durationValue: 0, repsValue: 0, distanceValue: 0)
        case .success, .failure:
            return Target(kind: .unknown, durationValue: 0, repsValue: 0, distanceValue: 0)
        }
    }

    private func progressForCurrentItem(
        state: SessionState,
        context: WorkoutContext
    ) -> Progress {
        guard let item = context.item(
            at: state.cursor.blockIndex,
            itemIndex: state.cursor.itemIndex
        ) else {
            return Progress(duration: 0, reps: 0, distance: 0)
        }
        let sets = state.items.first(where: { $0.itemID == item.id })?.sets ?? []
        return Progress(
            duration: sets.filter(\.done).compactMap(\.durationSec).reduce(0, +),
            reps: sets.filter(\.done).compactMap(\.reps).reduce(0, +),
            distance: sets.filter(\.done).compactMap(\.distanceM).reduce(0, +)
        )
    }

    private func displayStrings(target: Target, progress: Progress) -> (primary: String, secondary: String) {
        switch target.kind {
        case .duration:
            return (
                "\(formatDuration(progress.duration)) / \(formatDuration(target.durationValue))",
                "accumulate time"
            )
        case .reps:
            return ("\(progress.reps) / \(target.repsValue)", "total reps")
        case .distance:
            return (
                "\(formatDistance(progress.distance)) / \(formatDistance(target.distanceValue))",
                "accumulate distance"
            )
        case .unknown:
            return ("—", "accumulate")
        }
    }

    private func formatLoadForDisplay(_ loadKg: Double?, unit: WeightUnit) -> String {
        formatLoad(weight: loadKg, unit: LoadUnit(setPlanUnit: unit))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func formatDistance(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000.0)
        }
        return "\(Int(metres.rounded())) m"
    }
}
