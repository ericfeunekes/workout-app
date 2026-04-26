// ExecutionTimerPresentation.swift
//
// View-model read model for the one timer the athlete should pay
// attention to right now. SessionState stores absolute anchors; this
// value gives views a label + live remaining/elapsed value.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct ExecutionTimerPresentation: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case countdown
        case elapsed
    }

    public let label: String
    public let direction: Direction
    public let seconds: TimeInterval

    public var formattedValue: String {
        formatDuration(seconds: seconds)
    }

    public var inlineText: String {
        "\(label) \(formattedValue)"
    }

    public init(label: String, direction: Direction, seconds: TimeInterval) {
        self.label = label
        self.direction = direction
        self.seconds = seconds
    }
}

extension ExecutionViewModel {
    public func timerPresentation(now: Date) -> ExecutionTimerPresentation? {
        switch state.route {
        case .rest:
            guard let restEndsAt = state.restEndsAt else { return nil }
            if now > restEndsAt {
                return ExecutionTimerPresentation(
                    label: "OVER REST",
                    direction: .elapsed,
                    seconds: now.timeIntervalSince(restEndsAt)
                )
            }
            return countdown(label: "REST", until: restEndsAt, now: now)

        case .active:
            if let compositeRest = compositeIntraRestPresentation(now: now) {
                return compositeRest
            }

            if let workEndsAt = state.workEndsAt {
                return countdown(label: workWindowLabelForCurrentBlock(), until: workEndsAt, now: now)
            }

            if let interval = emomIntervalPresentation(now: now) {
                return interval
            }

            if let blockEndsAt = state.blockEndsAt {
                return countdown(label: blockCapLabelForCurrentBlock(), until: blockEndsAt, now: now)
            }

            if let workStartedAt = state.workStartedAt {
                return ExecutionTimerPresentation(
                    label: elapsedLabelForCurrentBlock(),
                    direction: .elapsed,
                    seconds: max(0, now.timeIntervalSince(workStartedAt))
                )
            }

            if let workReadyAt = state.workReadyAt {
                return ExecutionTimerPresentation(
                    label: "WAITING TO START",
                    direction: .elapsed,
                    seconds: max(0, now.timeIntervalSince(workReadyAt))
                )
            }

            return nil

        case .today, .complete:
            return nil
        }
    }

    private func countdown(
        label: String,
        until deadline: Date,
        now: Date
    ) -> ExecutionTimerPresentation {
        ExecutionTimerPresentation(
            label: label,
            direction: .countdown,
            seconds: max(0, deadline.timeIntervalSince(now))
        )
    }

    private func compositeIntraRestPresentation(now: Date) -> ExecutionTimerPresentation? {
        guard let progress = activeCompositeSet,
              case .intraRest(_, let endsAt) = progress.phase else {
            return nil
        }
        let remaining = endsAt.timeIntervalSince(now)
        if remaining >= 0 {
            return ExecutionTimerPresentation(
                label: "CLUSTER REST",
                direction: .countdown,
                seconds: remaining
            )
        }
        return ExecutionTimerPresentation(
            label: "OVER REST",
            direction: .elapsed,
            seconds: abs(remaining)
        )
    }

    private func emomIntervalPresentation(now: Date) -> ExecutionTimerPresentation? {
        let blockIndex = state.cursor.blockIndex
        guard let block = context.block(at: blockIndex),
              block.timingMode == .emom,
              let anchor = state.intervalAnchorAt,
              blockIndex >= 0,
              blockIndex < context.itemsByBlock.count else {
            return nil
        }

        let items = context.itemsByBlock[blockIndex]
        guard !items.isEmpty else { return nil }
        let intervalSec = emomIntervalSeconds(for: block)
        guard intervalSec > 0 else { return nil }

        let cursor = state.cursor
        let ordinal = (cursor.setIndex - 1) * items.count + cursor.itemIndex + 1
        let boundary = anchor.addingTimeInterval(Double(ordinal) * intervalSec)
        return countdown(label: "INTERVAL", until: boundary, now: now)
    }

    private func emomIntervalSeconds(for block: Block) -> TimeInterval {
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(.emom(let intervalSec, _)):
            return intervalSec
        case .success, .failure:
            return 0
        }
    }

    private func elapsedLabelForCurrentBlock() -> String {
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return "SET ELAPSED"
        }
        switch block.timingMode {
        case .continuous:
            return "ELAPSED"
        case .amrap, .forTime:
            return "CAP ELAPSED"
        case .custom:
            return activeContent?.kind == .cardio ? "SEGMENT ELAPSED" : "SET ELAPSED"
        case .accumulate:
            return "BOUT ELAPSED"
        case .straightSets, .superset, .circuit, .emom, .intervals, .tabata, .rest:
            return "SET ELAPSED"
        }
    }

    private func blockCapLabelForCurrentBlock() -> String {
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return "CAP"
        }
        switch block.timingMode {
        case .amrap:
            return "AMRAP CAP"
        case .forTime:
            return "TIME CAP"
        case .emom:
            return "EMOM CAP"
        case .tabata:
            return "TABATA CAP"
        case .continuous:
            return "TARGET"
        case .straightSets, .superset, .circuit, .intervals, .accumulate, .custom, .rest:
            return "CAP"
        }
    }

    private func workWindowLabelForCurrentBlock() -> String {
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return "WORK"
        }
        switch block.timingMode {
        case .continuous:
            return "TARGET"
        case .straightSets, .superset, .circuit, .emom, .amrap, .forTime,
             .intervals, .tabata, .accumulate, .custom, .rest:
            return "WORK"
        }
    }
}
