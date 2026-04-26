// ExecutionViewModel+Accumulate.swift
//
// Runtime helpers for `timing_mode = accumulate`.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession

extension ExecutionViewModel {
    enum AccumulateTargetKind {
        case duration
        case reps
        case distance
        case unknown
    }

    var accumulateTargetKind: AccumulateTargetKind {
        guard let config = currentAccumulateConfig() else { return .unknown }
        switch config {
        case .accumulate(let duration, let reps, let distance):
            if duration != nil { return .duration }
            if reps != nil { return .reps }
            if distance != nil { return .distance }
            return .unknown
        default:
            return .unknown
        }
    }

    func completeAccumulateIfTargetReached() {
        guard let block = context.block(at: state.cursor.blockIndex),
              block.timingMode == .accumulate,
              accumulateTargetReached() else {
            return
        }
        routeOutOfCurrentBlock()
    }

    private func accumulateTargetReached() -> Bool {
        guard let config = currentAccumulateConfig(),
              let item = context.item(
                at: state.cursor.blockIndex,
                itemIndex: state.cursor.itemIndex
              ),
              let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return false
        }
        let doneSets = itemLog.sets.filter(\.done)
        switch config {
        case .accumulate(let duration, let reps, let distance):
            if let duration {
                let total = doneSets.compactMap(\.durationSec).reduce(0, +)
                return total >= duration
            }
            if let reps {
                let total = doneSets.compactMap(\.reps).reduce(0, +)
                return total >= reps
            }
            if let distance {
                let total = doneSets.compactMap(\.distanceM).reduce(0, +)
                return total >= distance
            }
            return false
        default:
            return false
        }
    }

    private func currentAccumulateConfig() -> TimingConfig? {
        guard let block = context.block(at: state.cursor.blockIndex),
              block.timingMode == .accumulate else {
            return nil
        }
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            return config
        case .failure:
            return nil
        }
    }
}
