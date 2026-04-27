// HistoryExerciseDetailView.swift
//
// Per-exercise detail reached from the picker. Mirrors
// docs/design/components/history-full.jsx `ExerciseHistory`:
//   - top-set trend indicator ("↑ 25 KG / 12 WK")
//   - recent sessions list in mono
//
// v1 deliberately does NOT render the polyline chart shown in the
// design mock. One-number indicator + list of sessions is enough; the
// chart is punted per the notes in the design reference and
// app/README.md § "History" ("What the app deliberately does not show:
// charts beyond the per-exercise top-set trend indicator").

import SwiftUI
import DesignSystem

struct HistoryExerciseDetailView: View {
    let viewModel: ExerciseDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header
                trendRow
                recentSessions
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColors.background)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(viewModel.exerciseName)
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
        }
    }

    private var trendRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("TOP SET")
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)
            if let trend = viewModel.trendDisplay {
                Text(trend)
                    .font(DSTypography.monoLarge)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.accentInk)
            } else {
                Text("— not enough history yet")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundDim)
            }
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("RECENT SESSIONS")
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)
            if viewModel.recentSessions.isEmpty {
                Text("no sessions logged yet")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundDim)
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(viewModel.recentSessions) { row in
                        if let workoutID = row.workoutID {
                            NavigationLink(value: workoutID) {
                                recentSessionRow(row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            recentSessionRow(row)
                        }
                    }
                }
            }
        }
    }

    private func recentSessionRow(_ row: ExerciseDetailViewModel.SessionRow) -> some View {
        Text(row.display)
            .font(DSTypography.mono)
            .monospacedDigit()
            .foregroundStyle(DSColors.foregroundMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
