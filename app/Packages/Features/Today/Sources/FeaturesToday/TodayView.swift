// TodayView.swift
//
// The Today screen — glance view at the start of a session. Mirrors
// `docs/design/src/hifi.jsx` function `Today` (lines 248-299):
//   - program name large title + subtitle of session tags
//   - a "LAST SESSION" chip pinned below the header
//   - a scrolling exercise list, each row a card with name + prescription
//     line and a "LAST TIME" chip underneath
//   - a pinned "start workout" primary button at the bottom
//
// Dark-only; all color, type, and spacing from DesignSystem tokens.

import SwiftUI
import CoreDomain
import CoreSession
import DesignSystem
import WorkoutCoreFoundation

public struct TodayView: View {
    @State private var viewModel: TodayViewModel

    public init(viewModel: TodayViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            DSColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.xl) {
                        if viewModel.isEmpty {
                            emptyGlance
                        } else {
                            header
                            lastSessionChip
                            exerciseList
                        }
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.xxl)
                    .padding(.bottom, DSSpacing.xxl)
                }

                // qa-008: gate the pinned CTA on `showsStartButton`
                // (false when `isEmpty == true`). An empty Today has no
                // workout to dispatch, so rendering the button produces
                // a disconnected CTA over a black screen.
                if viewModel.showsStartButton {
                    startButton
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.top, DSSpacing.lg)
                        .padding(.bottom, DSSpacing.xl)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Program name is a proper noun — preserve its casing.
            Text(viewModel.programName)
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)

            if !viewModel.programTags.isEmpty {
                Text(viewModel.programTags.joined(separator: " · "))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lastSessionChip: some View {
        if let summary = viewModel.lastSessionSummary {
            DSChip(label: "last session", value: summary, tone: .default)
        }
    }

    private var exerciseList: some View {
        VStack(spacing: DSSpacing.lg) {
            ForEach(viewModel.exercises) { row in
                exerciseRow(row)
            }
        }
    }

    private func exerciseRow(_ row: TodayViewModel.ExerciseSummary) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                    // Exercise name — proper noun, preserve casing.
                    Text(row.name)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Numeric summary uses mono. `monospacedDigit()`
                    // forces tabular figures so "102.5 kg" and
                    // "100 kg" align across rows.
                    Text(row.prescriptionLine)
                        .font(DSTypography.mono)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.foregroundMuted)
                }

                if let lastTime = row.lastTime {
                    HStack(spacing: DSSpacing.md) {
                        Text("LAST TIME")
                            .font(DSTypography.caption)
                            .tracking(0.5)
                            .foregroundStyle(DSColors.foregroundDim)
                        Text(lastTime)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.foregroundMuted)
                    }
                }
            }
        }
    }

    private var startButton: some View {
        DSButton(
            title: "start workout",
            style: .primary,
            action: { viewModel.start() }
        )
    }

    // qa-008: when `viewModel.isEmpty == true` the VM has no workout to
    // render — previously the view still displayed the pinned "start
    // workout" button, producing a black screen with an orphaned CTA.
    // Per `docs/features/today.md` S11, the empty path should render a
    // quiet message and no CTA until Claude pushes a new session.
    private var emptyGlance: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("no planned workouts")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foregroundMuted)
            Text("check back after Claude sends a new session.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
        .padding(.vertical, DSSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Today — Push A") {
    TodayView(viewModel: TodayViewModel(
        context: TodayPreviewSeed.pushA(withLastSession: true)
    ))
    .preferredColorScheme(.dark)
}

#Preview("Today — no prior session") {
    TodayView(viewModel: TodayViewModel(
        context: TodayPreviewSeed.pushA(withLastSession: false)
    ))
    .preferredColorScheme(.dark)
}

#Preview("Today — empty (nothing planned)") {
    let vm = TodayViewModel(
        context: TodayPreviewSeed.pushA(withLastSession: false)
    )
    vm.apply(nil)
    return TodayView(viewModel: vm)
        .preferredColorScheme(.dark)
}
#endif
