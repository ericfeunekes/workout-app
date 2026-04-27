// HistoryByExerciseView.swift
//
// Picker view for the by-exercise pivot. Mirrors
// docs/design/components/history-full.jsx `ExercisePicker`:
//   - "IN YOUR PROGRAM" section first
//   - "PAST PROGRAMS" section below, muted styling
//   - tapping a row navigates to `HistoryExerciseDetailView`
//
// Search + fuzzy-match is out of scope for v1 — the design shows a
// search pill but the surface is a flat list of ~20 exercises at most.

import SwiftUI
import CoreDomain
import DesignSystem
import WorkoutCoreFoundation

struct HistoryByExerciseView: View {
    let viewModel: HistoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                chipRow
                if !currentRows.isEmpty {
                    section(title: "IN YOUR PROGRAM", rows: currentRows, muted: false)
                }
                if !pastRows.isEmpty {
                    section(title: "PAST PROGRAMS", rows: pastRows, muted: true)
                }
                if currentRows.isEmpty && pastRows.isEmpty && !viewModel.isLoading {
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

    private var currentRows: [HistoryViewModel.ExercisePickerRow] {
        viewModel.pickerRows.filter(\.isInCurrentProgram)
    }

    private var pastRows: [HistoryViewModel.ExercisePickerRow] {
        viewModel.pickerRows.filter { !$0.isInCurrentProgram }
    }

    // MARK: - Chip row

    private var chipRow: some View {
        HStack(spacing: DSSpacing.md) {
            Button(action: { viewModel.setTab(.list) }, label: {
                DSChip(label: "← HISTORY", tone: .muted)
            })
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Section

    private func section(
        title: String,
        rows: [HistoryViewModel.ExercisePickerRow],
        muted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title)
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)
            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(sectionRenderables(rows: rows)) { entry in
                        if entry.showDivider {
                            DSDivider()
                        }
                        NavigationLink(
                            value: ByExerciseDestination(exerciseID: entry.row.id)
                        ) {
                            pickerRowView(entry.row, muted: muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Pair each picker row with whether it should get a leading divider.
    /// Materialized up front so the ForEach closure avoids indexing back
    /// into the source array (which was tripping Swift 6's ForEach
    /// Binding overload resolution).
    private func sectionRenderables(
        rows: [HistoryViewModel.ExercisePickerRow]
    ) -> [PickerRenderable] {
        rows.enumerated().map { index, row in
            PickerRenderable(row: row, showDivider: index > 0)
        }
    }

    private struct PickerRenderable: Identifiable {
        let row: HistoryViewModel.ExercisePickerRow
        let showDivider: Bool
        var id: ExerciseID { row.id }
    }

    private func pickerRowView(
        _ row: HistoryViewModel.ExercisePickerRow,
        muted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(row.name)
                .font(DSTypography.body)
                .foregroundStyle(muted ? DSColors.foregroundMuted : DSColors.foreground)
            HStack(spacing: DSSpacing.sm) {
                Text(row.sessionSummary)
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundDim)
                if let top = row.topLoadSummary {
                    Text("·")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundDim)
                    Text(top)
                        .font(DSTypography.caption)
                        .tracking(0.5)
                        .foregroundStyle(DSColors.foregroundDim)
                }
            }
        }
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("no logged exercises")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foregroundMuted)
            Text("complete a workout to see exercises listed here.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
        .padding(.vertical, DSSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Navigation destination for the by-exercise pivot — carried through
/// the root `NavigationStack` so SwiftUI can build the right destination
/// view without the list view owning the navigation state directly.
///
/// Declares Equatable + Hashable explicitly so the compiler doesn't
/// trip on the typealiased `ExerciseID = UUID` when synthesizing
/// conformances alongside the many SwiftUI `==` overloads in scope.
struct ByExerciseDestination: Hashable, Equatable {
    let exerciseID: ExerciseID

    static func == (lhs: ByExerciseDestination, rhs: ByExerciseDestination) -> Bool {
        lhs.exerciseID == rhs.exerciseID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(exerciseID)
    }
}
