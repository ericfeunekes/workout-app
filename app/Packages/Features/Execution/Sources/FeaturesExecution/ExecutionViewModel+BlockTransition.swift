// ExecutionViewModel+BlockTransition.swift
//
// Between-block setup gating. This is deliberately view-model level: the
// reducer owns cursor math, while the VM knows whether the newly landed block
// has enough user-facing setup information to deserve a transition screen.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

struct BlockTransitionPresentation: Equatable, Sendable {
    let finishedTitle: String
    let nextTitle: String
    let timingMode: String
    let firstTask: String
    let setup: String?
}

extension ExecutionViewModel {
    var blockTransitionPresentation: BlockTransitionPresentation? {
        guard state.route == .transition,
              let block = context.block(at: state.cursor.blockIndex) else {
            return nil
        }
        let previousBlockIndex = state.cursor.blockIndex - 1
        let finished = previousBlockIndex >= 0
            ? blockTitle(at: previousBlockIndex)
            : "Previous block"
        return BlockTransitionPresentation(
            finishedTitle: finished,
            nextTitle: blockTitle(at: state.cursor.blockIndex),
            timingMode: block.timingMode.rawValue.replacingOccurrences(of: "_", with: " "),
            firstTask: transitionFirstTask(for: block),
            setup: transitionSetupDetail(for: block)
        )
    }

    @discardableResult
    func enterBlockTransitionIfNeeded(from previousBlockIndex: Int) -> Bool {
        guard shouldEnterBlockTransition(from: previousBlockIndex) else {
            return false
        }
        apply([.enterTransition])
        return true
    }

    func beginBlockTransition() {
        guard state.route == .transition else { return }
        emitSessionMutation("begin_block_transition")
        apply([.beginTransition])
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
        markExplicitWorkReadyIfNeeded()
        prepareExplicitSetStartIfNeeded()
    }

    func shouldEnterBlockTransition(from previousBlockIndex: Int) -> Bool {
        guard state.route == .active,
              state.cursor.blockIndex != previousBlockIndex,
              state.cursor.blockIndex > previousBlockIndex,
              state.cursor.blockIndex < state.structure.itemsPerBlock.count,
              previousBlockIndex >= 0,
              state.structure.itemsPerBlock.indices.contains(previousBlockIndex),
              state.structure.itemsPerBlock[previousBlockIndex] > 0,
              state.structure.itemsPerBlock[state.cursor.blockIndex] > 0 else {
            return false
        }
        return context.block(at: state.cursor.blockIndex) != nil
    }

    private func blockTitle(at index: Int) -> String {
        guard let block = context.block(at: index) else { return "Block \(index + 1)" }
        if let name = block.name, !name.isEmpty {
            return name
        }
        return "Block \(index + 1)"
    }

    private func transitionFirstTask(for block: Block) -> String {
        let previewState = state
        guard let content = driverRegistry
            .driver(for: block.timingMode)
            .activeContent(state: previewState, context: context) else {
            return "Start block"
        }
        if content.kind == .strength {
            return "\(content.exerciseName) · \(content.loadDisplay) · \(content.repsDisplay) reps"
        }
        return "\(content.exerciseName) · \(content.repsDisplay) · \(content.loadDisplay)"
    }

    private func transitionSetupDetail(for block: Block) -> String? {
        let items = context.itemsByBlock.indices.contains(state.cursor.blockIndex)
            ? context.itemsByBlock[state.cursor.blockIndex]
            : []
        guard !items.isEmpty else { return nil }

        let parser = PrescriptionParser()
        var details: [String] = []
        if let timing = transitionTimingSetup(for: block, itemCount: items.count, parser: parser) {
            details.append(timing)
        }
        details.append(contentsOf: items.compactMap { item -> String? in
            let plan = SessionSeeder.itemPlan(for: item, parser: parser)
            var pieces: [String] = [context.exerciseName(for: item)]
            let amount = transitionAmountDisplay(for: plan)
            if !amount.isEmpty {
                pieces.append(amount)
            }
            let load = loadDisplayForTarget(set: SetPlan(
                setIndex: 1,
                loadKg: plan.loadKg,
                unit: plan.unit,
                reps: plan.reps,
                workTarget: plan.workTarget,
                done: false,
                adjust: nil
            ))
            if load != "BW" {
                pieces.append(load)
            }
            return pieces.joined(separator: " · ")
        })
        guard !details.isEmpty else { return nil }
        return details.joined(separator: "\n")
    }

    private func markExplicitWorkReadyIfNeeded() {
        guard state.route == .active,
              requiresExplicitSetStartForCurrentWork,
              state.workStartedAt == nil,
              state.workReadyAt == nil else {
            return
        }
        state.workReadyAt = clock.now
        persist()
    }

    private func transitionAmountDisplay(for plan: SessionSeeder.ItemPlan) -> String {
        guard let target = plan.workTarget else {
            return plan.reps > 0 ? "\(plan.reps) reps" : ""
        }
        if target.kind == .reps {
            return "\(Int(target.value.rounded())) reps"
        }
        return displayText(for: target)
    }

    private func transitionTimingSetup(
        for block: Block,
        itemCount: Int,
        parser: PrescriptionParser
    ) -> String? {
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            return transitionTimingSetup(config: config, block: block, itemCount: itemCount)
        case .failure:
            return nil
        }
    }

    private func transitionTimingSetup(
        config: TimingConfig,
        block: Block,
        itemCount: Int
    ) -> String? {
        switch config {
        case .straightSets:
            return nil
        case .superset(_, let loggingMode):
            let rounds = block.rounds.map { "\($0) rounds" } ?? "rounds"
            return "\(itemCount) stations · \(rounds) · \(loggingModeDisplay(loggingMode))"
        case .circuit(_, _, let loggingMode):
            let rounds = block.rounds.map { "\($0) rounds" } ?? "rounds"
            return "\(itemCount) stations · \(rounds) · \(loggingModeDisplay(loggingMode))"
        case .emom(let intervalSec, let totalMinutes):
            return "\(formatDuration(seconds: intervalSec)) intervals · \(totalMinutes) min total"
        case .amrap(let timeCapSec):
            return "Time cap \(formatDuration(seconds: timeCapSec))"
        case .forTime(let timeCapSec):
            guard let timeCapSec else { return "For time · no cap" }
            return "For time · cap \(formatDuration(seconds: timeCapSec))"
        case .intervals(let workSec, let restSec, let workDistanceM, let restDistanceM, let intervalCount, _):
            let work = workSec.map { formatDuration(seconds: $0) }
                ?? workDistanceM.map(formatCardioDistance)
                ?? "work"
            let rest = restSec.map { formatDuration(seconds: $0) }
                ?? restDistanceM.map(formatCardioDistance)
                ?? "rest"
            return "\(intervalCount) intervals · \(work) work / \(rest) rest"
        case .tabata:
            return "8 rounds · 0:20 work / 0:10 rest"
        case .continuous(let durationSec, let distanceM, _, let hrZone):
            let targets = [
                durationSec.map { formatDuration(seconds: $0) },
                distanceM.map(formatCardioDistance),
                hrZone.map { "zone \($0)" },
            ].compactMap { $0 }
            return targets.isEmpty ? nil : targets.joined(separator: " · ")
        case .accumulate(let durationSec, let targetReps, let distanceM):
            let targets = [
                durationSec.map { formatDuration(seconds: $0) },
                targetReps.map { "\($0) reps" },
                distanceM.map(formatCardioDistance),
            ].compactMap { $0 }
            return targets.isEmpty ? nil : "Accumulate " + targets.joined(separator: " · ")
        case .custom(let segments):
            let total = segments.reduce(0) { $0 + $1.durationSec }
            return "\(segments.count) segments · \(formatDuration(seconds: total)) total"
        case .rest:
            return nil
        }
    }

    private func loggingModeDisplay(_ mode: RoundRobinLoggingMode) -> String {
        switch mode {
        case .stationByStation:
            return "log each station"
        case .batchAtRoundRest:
            return "round log at rest"
        }
    }
}
