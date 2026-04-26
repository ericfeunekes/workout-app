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
    @State private var noteText: String

    /// Body weight in kg as the user types it. Parsed to Double on save;
    /// an unparseable / empty value means "no capture, skip the
    /// user_parameters push."
    @State private var bodyweightText: String

    /// qa-030: the initial bodyweight text is explicitly empty. Prior
    /// layouts used `@State private var bodyweightText: String = ""` with
    /// `prompt: Text("82.5")` as placeholder — users read "82.5" as a
    /// prefilled value. The fix removed the numeric prompt; this
    /// constant locks the empty-start contract so a future edit can't
    /// silently reintroduce a prefill (e.g. by reading the latest
    /// `user_parameters.bodyweight_kg` at init time). Exposed `static`
    /// for unit tests to pin the contract.
    static let initialBodyweightText: String = ""

    /// Mirror of `initialBodyweightText` for the note field. Currently
    /// the same empty string, exposed separately so a future "seed last
    /// session's note" feature (not planned) would land with a visible
    /// contract change rather than flipping the default silently.
    static let initialNoteText: String = ""

    init(viewModel: ExecutionViewModel) {
        self.viewModel = viewModel
        self._noteText = State(initialValue: Self.initialNoteText)
        self._bodyweightText = State(initialValue: Self.initialBodyweightText)
    }

    #if DEBUG
    /// qa-029 preview initializer — seeds the note / bodyweight fields
    /// so SwiftUI previews can exercise the "500-char note" worst case
    /// without a stateful host. Gated on `#if DEBUG` so it never ships.
    init(
        viewModel: ExecutionViewModel,
        previewNote: String,
        previewBodyweight: String = ""
    ) {
        self.viewModel = viewModel
        self._noteText = State(initialValue: previewNote)
        self._bodyweightText = State(initialValue: previewBodyweight)
    }
    #endif

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.xl) {
                        header
                        blockResults
                        ledger
                        captureCard
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.xxl)
                    .padding(.bottom, DSSpacing.xxl)
                }

                DSButton(
                    title: "save & done",
                    style: .primary,
                    action: onSaveAndDoneTap
                )
                // Belt-and-suspenders for the re-entrancy guard in
                // `ExecutionViewModel.saveAndDone`. The guard is the
                // correctness-critical check (drops the second call
                // silently); disabling the button stops the user from
                // watching a no-op second tap flash the press state
                // during the few ms before the reducer's `.save` flips
                // the route to `.today` and unmounts this view.
                .disabled(viewModel.saveAndDoneInFlight)
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xxl)
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
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("capture")
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundDim)

                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    Text("body weight (kg)")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundMuted)
                    // qa-030: the prior prompt read `Text("82.5")`, which
                    // SwiftUI renders as a grayed-out placeholder but
                    // visually reads as a prefilled numeric value. Users
                    // saw "82.5" in the empty field, assumed it was
                    // captured, and walked away without typing — so
                    // `parsedBodyweightKg` returned nil and the
                    // `enqueueBodyweight` path never fired. Swap to a
                    // non-numeric "optional" hint so the empty state is
                    // unambiguous: no number on screen → no bodyweight
                    // logged yet.
                    TextField(
                        "",
                        text: $bodyweightText,
                        prompt: Text("optional")
                    )
                        .font(DSTypography.mono)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.foreground)
                        .textFieldStyle(.plain)
                        .padding(.top, DSSpacing.md)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("complete.bodyweight_kg")
                }

                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    Text("note")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundMuted)
                    // qa-029: prior `.lineLimit(2...4)` capped the field
                    // at four lines, so a ~500-char note (about 10 lines
                    // at body type) spilled past the visible edit area
                    // and broke the card's vertical rhythm while typing.
                    // Widen the range to 1...8 so short notes keep the
                    // tight single-line shape, long notes grow in-place
                    // up to a bounded cap, and anything beyond the cap
                    // scrolls within the field rather than pushing the
                    // save button off-screen. Fixed-size vertical
                    // prevents horizontal clipping of long words.
                    TextField(
                        "",
                        text: $noteText,
                        prompt: Text("add a note"),
                        axis: .vertical
                    )
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foreground)
                    .lineLimit(1...8)
                    .textFieldStyle(.plain)
                    .padding(.top, DSSpacing.md)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var blockResults: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("block results")
                .font(DSTypography.caption)
                .tracking(0.5)
                .foregroundStyle(DSColors.foregroundDim)
            ForEach(Array(allBlockResultEntries().enumerated()), id: \.offset) { _, entry in
                blockResultSummaryView(entry: entry)
            }
        }
    }
}

#if DEBUG
// qa-029: visual regression preview. A ~500-character note is the QA
// report's worst-case input; this preview seeds exactly that so visual
// QA can confirm the field grows cleanly up to its bounded cap, the
// save button stays reachable, and the card padding doesn't collapse.
// Shares `ExecutionPreviewSeed.pushA` with the other execution previews
// so the ledger underneath renders realistic entries.
#Preview("Complete — 500-char note (qa-029)") {
    let context = ExecutionPreviewSeed.pushA()
    let vm = ExecutionViewModel(context: context)
    // Flip the VM to `.complete` so the Complete screen renders — the
    // default seeded state is `.today`. No log calls needed; the ledger
    // just shows "no sets logged" per-item.
    vm.apply([.start, .complete])
    // 512 characters — matches the QA report's 500-char worst case.
    let longNote = String(
        repeating: "felt strong today, bench speed was clean and lockout solid. ",
        count: 8
    )
    return CompleteView(viewModel: vm, previewNote: longNote)
        .preferredColorScheme(.dark)
}
#endif
