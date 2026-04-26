// HistorySessionDetailView.swift
//
// Session detail screen. Mirrors the `SessionDetail` design variant
// (docs/design/components/history-full.jsx lines 94-133):
//   - big program name in display type
//   - short meta line under it (avg RIR · duration · body weight)
//   - per-exercise cards with mono set rows
//   - optional workout-level note at the bottom
//
// Set rows are tap-to-edit: tapping a row opens `EditSetSheet` which
// commits through `HistoryViewModel.editPastSet(workoutID:setLogID:…)`.
// The edit writes locally AND enqueues a push via the shell-wired
// `onSetLogEdited` hook. Fixes bug-015 — the prior stub flashed a
// highlight and did nothing.

import SwiftUI
import CoreDomain
import DesignSystem

struct HistorySessionDetailView: View {
    let viewModel: SessionDetailViewModel
    let historyViewModel: HistoryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var highlightedSetID: UUID?
    @State private var editingSetLogID: UUID?
    @State private var showsResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header
                ForEach(viewModel.cards) { card in
                    exerciseCard(card)
                }
                if historyViewModel.canResetToday(workoutID: viewModel.workoutID) {
                    resetBlock
                }
                if let note = viewModel.workoutNote {
                    noteBlock(note)
                }
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xxl)
        }
        .background(DSColors.background)
        .sheet(item: editingSetLogBinding) { editing in
            EditSetSheet(
                setIndex: editing.setLog.setIndex,
                initialReps: editing.setLog.reps,
                initialRir: editing.setLog.rir,
                initialLoad: editing.setLog.weight,
                // `weightUnit` defaults to `.kg` for rows that predate the
                // column being populated — today's writers always set it,
                // but the SetLog type allows nil so we collapse defensively
                // here rather than assuming every call site tightened its
                // invariant. Once we're confident, make the field
                // non-optional upstream and delete this fallback.
                weightUnit: editing.setLog.weightUnit ?? .kg,
                onCommit: { reps, rir, load in
                    commitEdit(
                        setLogID: editing.setLog.id,
                        reps: reps, rir: rir, load: load
                    )
                }
            )
        }
        .alert("Reset workout?", isPresented: $showsResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetWorkout()
            }
        } message: {
            Text("Delete today's logged sets and make this workout planned again.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(viewModel.programName)
                .font(DSTypography.display)
                .foregroundStyle(DSColors.foreground)
            Text(viewModel.longDate)
                .font(DSTypography.caption)
                .tracking(1.0)
                .foregroundStyle(DSColors.foregroundMuted)
            HStack(spacing: DSSpacing.md) {
                Text(viewModel.summary)
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundDim)
                if let bw = viewModel.bodyweight {
                    Text("·")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundDim)
                    Text(bw)
                        .font(DSTypography.caption)
                        .tracking(0.5)
                        .foregroundStyle(DSColors.foregroundDim)
                }
            }
        }
    }

    private func exerciseCard(_ card: SessionDetailViewModel.ExerciseCard) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(card.name.uppercased())
                .font(DSTypography.caption)
                .tracking(1.0)
                .foregroundStyle(DSColors.foregroundDim)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(card.setRows) { row in
                    setRowView(row)
                }
            }
            if let note = card.note {
                Text(note)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .padding(.top, DSSpacing.xs)
            }
        }
    }

    private func setRowView(_ row: SessionDetailViewModel.SetRow) -> some View {
        Button(action: { handleSetRowTap(rowID: row.id) }, label: {
            Text(row.display)
                .font(DSTypography.mono)
                .monospacedDigit()
                .foregroundStyle(
                    highlightedSetID == row.id
                        ? DSColors.accentInk
                        : DSColors.foregroundMuted
                )
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.session.setrow.\(row.id.uuidString)")
    }

    private var resetBlock: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("START OVER")
                    .font(DSTypography.caption)
                    .tracking(1.5)
                    .foregroundStyle(DSColors.warn)
                Text("Reset this same-day workout if it was logged by mistake.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    Text("reset workout")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DSSpacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history.session.reset-workout")
            }
        }
    }

    private func resetWorkout() {
        let workoutID = viewModel.workoutID
        let historyVM = historyViewModel
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            let didReset = await historyVM.resetWorkout(workoutID: workoutID)
            if didReset {
                dismiss()
            }
        }
    }

    /// Tap handler: flash the accent highlight (so the user sees the row
    /// respond) and open the edit sheet. The highlight clears when the
    /// sheet dismisses.
    private func handleSetRowTap(rowID: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            highlightedSetID = rowID
        }
        editingSetLogID = rowID
    }

    private func commitEdit(
        setLogID: UUID,
        reps: Int?,
        rir: EditPastSetRirCommit,
        load: EditPastSetLoadCommit?
    ) {
        let workoutID = viewModel.workoutID
        let historyVM = historyViewModel
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await historyVM.editPastSet(
                workoutID: workoutID,
                setLogID: setLogID,
                reps: reps,
                rir: rir,
                load: load
            )
        }
        // Dismiss the sheet + clear highlight immediately so the UI
        // feels responsive. The local-cache write + push + reload happen
        // in the Task above.
        editingSetLogID = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            highlightedSetID = nil
        }
    }

    private func noteBlock(_ note: String) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("NOTE")
                    .font(DSTypography.caption)
                    .tracking(1.5)
                    .foregroundStyle(DSColors.foregroundDim)
                // qa-029: long (~500 char) notes previously clipped on
                // the read side — the `Text` inherited the ScrollView's
                // default sizing, which capped its vertical extent and
                // truncated mid-word. `fixedSize(horizontal: false,
                // vertical: true)` lets the text wrap across as many
                // lines as the content needs while keeping the card's
                // horizontal bounds. `frame(maxWidth: .infinity,
                // alignment: .leading)` stops short notes from centering
                // oddly inside a wide card.
                Text(note)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// `.sheet(item:)` binding: resolves `editingSetLogID` to the full
    /// `SetLog` the sheet needs for its prefills. When the id is unknown
    /// (stale state, concurrent reload) the binding collapses back to
    /// nil so the sheet stays dismissed.
    private var editingSetLogBinding: Binding<EditingTarget?> {
        Binding(
            get: {
                guard let id = editingSetLogID,
                      let log = viewModel.setLogsByID[id] else {
                    return nil
                }
                return EditingTarget(setLog: log)
            },
            set: { newValue in
                if newValue == nil {
                    editingSetLogID = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        highlightedSetID = nil
                    }
                }
            }
        )
    }

    /// Wrapper so `.sheet(item:)` has an `Identifiable` payload. Holding
    /// just the UUID in state means we look up the full row at sheet-
    /// present time, so reloads between tap and present can't desync
    /// the prefill.
    private struct EditingTarget: Identifiable {
        let setLog: SetLog
        var id: UUID { setLog.id }
    }
}
