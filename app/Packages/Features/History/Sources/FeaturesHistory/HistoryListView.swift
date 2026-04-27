// HistoryListView.swift
//
// Reverse-chrono list of completed workouts, grouped by week header.
// Mirrors docs/design/components/history-full.jsx `HistoryList` +
// `HistoryFilters`:
//   - horizontal chip row at the top: ALL / PUSH / PULL / LEGS and a
//     "BY EXERCISE →" pivot chip
//   - grouped rows underneath, each group preceded by a tiny ALL CAPS
//     header ("APR · WEEK 15")
//   - tapping a row opens a navigation destination to the session detail

import SwiftUI
import CoreDomain
import DesignSystem
import WorkoutCoreFoundation

struct HistoryListView: View {
    let viewModel: HistoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                chipRow
                ForEach(viewModel.groups) { group in
                    weekSection(group)
                }
                if viewModel.groups.isEmpty && !viewModel.isLoading {
                    emptyState
                }
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chip row

    private var chipRow: some View {
        HStack(spacing: DSSpacing.md) {
            ForEach(HistoryViewModel.SplitFilter.allCases, id: \.self) { filter in
                Button(action: { viewModel.setSplit(filter) }, label: {
                    DSChip(
                        label: filter.chipLabel,
                        tone: filter == viewModel.activeSplit ? .accent : .default
                    )
                })
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button(action: { viewModel.setTab(.byExercise) }, label: {
                DSChip(label: "BY EXERCISE →", tone: .muted)
            })
            .buttonStyle(.plain)
        }
    }

    // MARK: - Week section

    private func weekSection(_ group: HistoryViewModel.WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(group.header)
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)
                .padding(.top, DSSpacing.md)

            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(renderables(for: group)) { entry in
                        if entry.showDivider {
                            DSDivider()
                        }
                        NavigationLink(value: entry.row.id) {
                            HistoryRow(row: entry.row)
                                .padding(.horizontal, DSSpacing.xl)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("no completed workouts")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foregroundMuted)
            Text("complete a workout to see it listed here.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
        .padding(.vertical, DSSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pair each session row with whether it should get a leading divider.
    /// Same trick the by-exercise view uses — materializing a flat array
    /// of Identifiable wrappers sidesteps the Swift 6 ForEach / Binding
    /// overload ambiguity when the source collection is a plain `[T]`.
    private func renderables(
        for group: HistoryViewModel.WeekGroup
    ) -> [RowRenderable] {
        group.rows.enumerated().map { index, row in
            RowRenderable(row: row, showDivider: index > 0)
        }
    }

    private struct RowRenderable: Identifiable {
        let row: HistoryViewModel.SessionRow
        let showDivider: Bool
        var id: UUID { row.id }
    }
}
