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
            note: viewModel.state.note
        )
    }

    static func blockResultEntries(
        context: WorkoutContext,
        items itemLogs: [SessionState.ItemLog],
        note: String
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
        blockItems: [WorkoutItem],
        itemLogs: [SessionState.ItemLog],
        note: String
    ) -> String {
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
}
