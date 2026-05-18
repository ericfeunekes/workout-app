// CompleteView+BlockResults.swift
//
// Per-block completion summaries. The existing completion ledger is
// item-detail; this layer gives the athlete the block-level result first.

import SwiftUI
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import DesignSystem
import WorkoutCoreFoundation

extension CompleteView {
    struct BlockResultEntry {
        let title: String
        let subtitle: String
        let summary: String
    }

    func allBlockResultEntries() -> [BlockResultEntry] {
        CompleteView.blockResultEntries(
            context: viewModel.context,
            items: viewModel.state.items,
            note: viewModel.state.note,
            primitiveSetLogs: viewModel.primitiveSetLogs
        )
    }

    static func blockResultEntries(
        context: WorkoutContext,
        items itemLogs: [SessionState.ItemLog],
        note: String,
        primitiveSetLogs: [PrimitiveSetLog] = []
    ) -> [BlockResultEntry] {
        context.blocks.enumerated().map { blockIndex, block in
            let blockItems = blockIndex < context.itemsByBlock.count
                ? context.itemsByBlock[blockIndex]
                : []
            return BlockResultEntry(
                title: block.name ?? "Block \(blockIndex + 1)",
                subtitle: block.timingMode.rawValue,
                summary: blockResultSummary(
                    block: block,
                    blockIndex: blockIndex,
                    primitivePlan: context.primitiveExecutionPlan,
                    primitiveSetLogs: primitiveSetLogs,
                    blockItems: blockItems,
                    itemLogs: itemLogs,
                    note: note
                )
            )
        }
    }

    @ViewBuilder
    func blockResultSummaryView(entry: BlockResultEntry) -> some View {
        DSCard(padding: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.foreground)
                    Spacer()
                    Text(entry.subtitle)
                        .font(DSTypography.caption)
                        .tracking(0.5)
                        .foregroundStyle(DSColors.foregroundDim)
                }
                Text(entry.summary)
                    .font(DSTypography.mono)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.foregroundMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.xl)
            .padding(.vertical, DSSpacing.lg)
        }
    }

    private static func blockResultSummary(
        block: Block,
        blockIndex: Int,
        primitivePlan: ExecutionPlan?,
        primitiveSetLogs: [PrimitiveSetLog],
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog],
        note: String
    ) -> String {
        if let primitive = primitiveResultSummary(
            blockIndex: blockIndex,
            primitivePlan: primitivePlan,
            primitiveSetLogs: primitiveSetLogs
        ) {
            return primitive
        }
        switch block.timingMode {
        case .amrap:
            return amrapResult(note: note) ?? loggedCountSummary(
                blockItems: blockItems,
                itemLogs: itemLogs,
                noun: "stations"
            )
        case .forTime, .continuous, .intervals, .tabata, .custom:
            return cardioOrCountSummary(blockItems: blockItems, itemLogs: itemLogs)
        case .accumulate:
            return accumulateSummary(block: block, blockItems: blockItems, itemLogs: itemLogs)
        case .rest:
            return "completed rest"
        case .straightSets, .superset, .circuit, .emom:
            return loggedCountSummary(blockItems: blockItems, itemLogs: itemLogs, noun: "sets")
        }
    }

    private static func cardioOrCountSummary(
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog]
    ) -> String {
        let done = doneRows(blockItems: blockItems, itemLogs: itemLogs)
        guard done.contains(where: CompleteView.isCardioLike) else {
            return "\(done.count) rows logged"
        }
        return cardioLedgerSummary(done: done)
    }

    private static func loggedCountSummary(
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog],
        noun: String
    ) -> String {
        let rows = rowsForBlock(blockItems: blockItems, itemLogs: itemLogs)
        let total = rows.count
        let done = rows.filter(\.done).count
        guard total > 0 else { return "completed" }
        return "\(done) / \(total) \(noun) completed"
    }

    private static func accumulateSummary(
        block: Block,
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog]
    ) -> String {
        let done = doneRows(blockItems: blockItems, itemLogs: itemLogs)
        let parser = PrescriptionParser()
        guard case .success(.accumulate(let duration, let reps, let distance)) =
            parser.parseTimingConfig(
                timingMode: block.timingMode.rawValue,
                configJSON: block.timingConfigJSON
            ) else {
            return "\(done.count) chunks"
        }
        if let duration {
            let total = done.compactMap(\.durationSec).reduce(0, +)
            return "\(formatDuration(seconds: total)) / \(formatDuration(seconds: duration))"
        }
        if let reps {
            let total = done.compactMap(\.reps).reduce(0, +)
            return "\(total) / \(reps) reps"
        }
        if let distance {
            let total = done.compactMap(\.distanceM).reduce(0, +)
            return "\(formatDistance(total)) / \(formatDistance(distance))"
        }
        return "\(done.count) chunks"
    }

    private static func amrapResult(note: String) -> String? {
        note.split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("AMRAP result:") })
    }

    private static func primitiveResultSummary(
        blockIndex: Int,
        primitivePlan: ExecutionPlan?,
        primitiveSetLogs: [PrimitiveSetLog]
    ) -> String? {
        guard let block = primitivePlan?.blocks[safe: blockIndex] else {
            return nil
        }
        let logs = primitiveSetLogs.filter { $0.blockID == block.blockID }
        guard !logs.isEmpty else { return nil }
        let summary = logs
            .filter { $0.role == .blockResult || $0.role == .setResult }
            .map(primitiveResultText(for:))
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
        if let summary {
            return summary
        }
        return logs
            .filter { $0.role == .slot }
            .map(primitiveResultText(for:))
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private static func primitiveResultText(for log: PrimitiveSetLog) -> String {
        var parts: [String] = []
        if let rounds = log.rounds {
            parts.append("\(rounds) rounds")
        }
        if let reps = log.reps {
            parts.append("\(reps) reps")
        }
        if let duration = log.durationSec {
            parts.append(formatDuration(seconds: duration))
        }
        if let distance = log.distanceM {
            parts.append(formatDistance(distance))
        }
        if let weight = log.weight {
            let unit = log.weightUnit?.rawValue ?? "load"
            parts.append("\(formatNumber(weight)) \(unit)")
        }
        return parts.joined(separator: " + ")
    }

    private static func doneRows(
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog]
    ) -> [SetPlan] {
        rowsForBlock(blockItems: blockItems, itemLogs: itemLogs).filter(\.done)
    }

    private static func rowsForBlock(
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog]
    ) -> [SetPlan] {
        let ids = Set(blockItems.map(\.id))
        return itemLogs
            .filter { ids.contains($0.itemID) }
            .flatMap(\.sets)
    }

    private static func formatDistance(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000.0)
        }
        return "\(Int(metres.rounded())) m"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var formatted = String(format: "%.2f", value)
        while formatted.hasSuffix("0") {
            formatted.removeLast()
        }
        if formatted.hasSuffix(".") {
            formatted.removeLast()
        }
        return formatted
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
