// CompleteView.swift
//
// Simplified v0 completion screen. Mirrors the summary card from
// `docs/design/src/hifi.jsx` § "Completion ledger" (lines 1113+).
//
// Scope:
//   - big "workout complete" headline
//   - per-item ledger line: exercise name + aggregate summary
//     ("4 × 5 @ 102.5 kg · rir 2")
//   - body-weight (kg) input — optional; enqueues a `user_parameters` row
//     with key "bodyweight_kg" when the user taps save & done
//     (bug-011 fix; see `app/README.md` § "Body weight")
//   - workout-note TextField — optional; written to the completed
//     workout's `notes` column on local cache write (bug-012 fix;
//     see `app/README.md` § "Complete")
//   - primary "save & done" button → clears session state and routes
//     back to Today via the shell's route-flip logic
//
// Ledger rendering + summary math live in `CompleteView+Ledger.swift`
// so the struct stays under SwiftLint's type_body_length cap.
//
// History ledger expansion, dictation-mic on the note, share sheet, and
// the avg-RIR header are out of scope for v0 — they'll layer in future
// slices. Dictation is tracked in `docs/open-questions.md` as a polish
// item.

import SwiftUI
import CoreAutoreg
import CoreDomain
import CoreSession
import DesignSystem
import WorkoutCoreFoundation

struct CompleteView: View {
    @Bindable var viewModel: ExecutionViewModel

    /// Workout-level note text. Bound to a multi-line TextField so the
    /// user can jot a sentence ("felt strong"). Empty is the default and
    /// collapses to `nil` on save.
    @State private var noteText: String = ""

    /// Body weight in kg as the user types it. Parsed to Double on save;
    /// an unparseable / empty value means "no capture, skip the
    /// user_parameters push."
    @State private var bodyweightText: String = ""

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.xl) {
                        header
                        ledger
                        captureCard
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.xxl)
                    .padding(.bottom, DSSpacing.xl)
                }

                DSButton(
                    title: "save & done",
                    style: .primary,
                    action: onSaveAndDoneTap
                )
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xl)
            }
        }
    }

    // MARK: - Save

    /// Parse the capture inputs and hand them to the view model. Keeping
    /// the parse here (rather than in the VM) lets tests exercise the
    /// VM with already-typed values while the view-level tests lock the
    /// parse.
    private func onSaveAndDoneTap() {
        let bodyweight = parsedBodyweightKg(from: bodyweightText)
        viewModel.saveAndDone(note: noteText, bodyweightKg: bodyweight)
    }

    /// Parse the body-weight string. Trims whitespace, treats empty as
    /// "no capture", normalizes commas to dots so a de-DE locale input
    /// ("82,5") still parses. Unparseable strings also fall through to
    /// nil — the save still goes, the user just doesn't get a param
    /// row.
    private func parsedBodyweightKg(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    // MARK: - Capture inputs

    private var captureCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("capture")
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundDim)

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("body weight (kg)")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundMuted)
                    TextField("", text: $bodyweightText, prompt: Text("82.5"))
                        .font(DSTypography.mono)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.foreground)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("complete.bodyweight_kg")
                }

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("note")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundMuted)
                    TextField(
                        "",
                        text: $noteText,
                        prompt: Text("add a note"),
                        axis: .vertical
                    )
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foreground)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("complete.note")
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("workout complete")
                .font(DSTypography.display)
                .foregroundStyle(DSColors.foreground)
            Text(viewModel.context.workout.name)
                .font(DSTypography.caption)
                .tracking(0.5)
                .foregroundStyle(DSColors.foregroundDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            ForEach(Array(allLedgerEntries().enumerated()), id: \.offset) { _, entry in
                // DSCard's default padding (16pt uniform) pushed the
                // exercise text right against the card edge in a way
                // visual QA flagged as cramped (bug-028). Switch to
                // `padding: 0` and own the inner padding so we can use
                // the 16×12 rhythm (DSSpacing.xl horizontal,
                // DSSpacing.lg vertical) — same horizontal breath as
                // the card's outer margin, tighter vertical so the
                // list reads as a rhythm rather than a grid.
                DSCard(padding: 0) {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Text(entry.name)
                            .font(DSTypography.body)
                            .foregroundStyle(DSColors.foreground)
                        ledgerSummaryView(entry: entry)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.vertical, DSSpacing.lg)
                }
            }
        }
    }
}
