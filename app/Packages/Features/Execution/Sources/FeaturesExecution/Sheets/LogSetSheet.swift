// LogSetSheet.swift
//
// Combined reps + RIR entry sheet — the fix for bug-023.
//
// Prior flow: tap "log set" → NumPadSheet (enter reps, tap "log") →
// RirSheet (tap RIR value or "skip") → rest. Three screens, ~39+ taps
// for a 13-set session.
//
// New flow: tap "log set" → LogSetSheet (reps numpad at top, RIR row at
// bottom, single "log" button) → rest. Two screens, ~26 taps for the
// same session. The user can commit reps without touching the RIR row
// (RIR stays nil, preserving the "skip" semantics).
//
// The NumPadSheet + RirSheet primitives are kept around — the rest-screen
// past-set edit paths use them individually and scope doesn't need both
// fields at once there. Only the logSet flow on Active moves to this
// combined sheet.
//
// State lives in `LogSetSheetModel` — an `@Observable` value-type-ish
// controller that owns the reps buffer, the currently-picked RIR, and
// the `commit()` entry point. Keeping state out of the SwiftUI view
// makes unit-testing the commit contract straightforward (construct a
// model, drive it, inspect what it emitted) without ViewInspector.

import SwiftUI
import DesignSystem

// MARK: - Model

/// State + actions for the combined reps + RIR sheet. Owns the reps
/// buffer (mirroring `NumPadSheet`'s editing model) and the currently-
/// picked RIR (nil = user didn't touch it, commit with rir: nil).
///
/// `@Observable` so SwiftUI tracks `buffer` / `pickedRir` reads from
/// `body` and re-renders on mutation. The `LogSetSheet` view holds
/// this as `@State`; tests instantiate it directly and read state
/// programmatically.
///
/// Not having `@Observable` here was a silent bug in the initial
/// landing: unit tests passed (they read `model.buffer` directly),
/// but the rendered sheet's reps readout stayed frozen at "0" because
/// SwiftUI never re-evaluated the view on numpad taps. Found by
/// MCP-driven validation.
@Observable
@MainActor
public final class LogSetSheetModel {

    // MARK: - Inputs

    /// Reps pre-seeded into the numpad buffer. Mirrors `NumPadSheet`'s
    /// priming behavior.
    public let initialReps: Int

    /// Invoked when the user taps the inline "log" button. Fires with
    /// the current reps buffer (parsed) and the picked RIR (nil if
    /// untouched).
    public let onCommit: (Int, Int?) -> Void

    // MARK: - State

    /// The reps buffer. `"0"` when empty, primed to `String(initialReps)`
    /// on `prime()` (mirrors the `NumPadSheet.primeBuffer` contract).
    public private(set) var buffer: String

    /// The currently-picked RIR. `nil` until the user taps a row button.
    /// A tap on the already-selected value toggles it back to `nil` so
    /// the user has a way to undo an accidental pick without
    /// dismissing the sheet.
    public private(set) var pickedRir: Int?

    /// `true` once `prime()` has run (idempotent — subsequent calls are
    /// no-ops). Matches `NumPadSheet`'s one-shot priming.
    public private(set) var primed: Bool = false

    // MARK: - Init

    public init(
        initialReps: Int,
        onCommit: @escaping (Int, Int?) -> Void
    ) {
        self.initialReps = initialReps
        self.onCommit = onCommit
        // Buffer starts empty — `prime()` populates it on view appear so
        // the user sees the prescribed reps pre-filled and can either
        // commit as-is or edit. Tests can call `prime()` directly.
        self.buffer = ""
    }

    // MARK: - Intents

    /// Seed the buffer with `initialReps`. Idempotent.
    public func prime() {
        guard !primed else { return }
        primed = true
        buffer = String(initialReps)
    }

    /// Append a digit to the buffer. `0` in the first slot overwrites;
    /// subsequent digits append (mirrors `NumPadSheet.pressDigit`).
    public func pressDigit(_ digit: Int) {
        let d = String(digit)
        if buffer == "0" {
            buffer = d
        } else {
            buffer.append(d)
        }
    }

    /// Backspace. Empty buffer reverts to `"0"` (mirrors NumPad).
    public func pressDelete() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        if buffer.isEmpty { buffer = "0" }
    }

    /// Tap a RIR row. Tapping the currently-picked value clears it
    /// (undo). Any other value replaces the selection.
    public func pressRir(_ value: Int) {
        if pickedRir == value {
            pickedRir = nil
        } else {
            pickedRir = value
        }
    }

    /// Commit the entry. Parses the buffer to `Int` (defaulting to
    /// `initialReps` on an unparseable buffer — matches NumPad's
    /// `Double(buffer) ?? initialValue` guard) and fires `onCommit`.
    public func commit() {
        let reps = Int(buffer) ?? initialReps
        onCommit(reps, pickedRir)
    }

    /// Display-ready buffer text. Shows `"0"` when empty so the readout
    /// isn't blank (NumPad parity).
    public var displayBuffer: String {
        buffer.isEmpty ? "0" : buffer
    }
}

// MARK: - View

/// Combined reps numpad + RIR picker sheet. Uses `DSKeypad` with the
/// inline `onDone` row wired up — the "log" button lives under the
/// digit grid so one thumb drives the whole flow.
///
/// The RIR picker lives between the readout and the keypad (instead of
/// under it) so it stays visible while the thumb is on the digits —
/// the user can glance at RIR options mid-typing without scrolling or
/// losing the keypad.
struct LogSetSheet: View {
    @State private var model: LogSetSheetModel

    /// RIR option labels. Mirror `RirSheet.options` so the same
    /// language ("failure", "grinder"…) appears in both sheets.
    private let options: [(value: Int, label: String)] = [
        (0, "failure"),
        (1, "grinder"),
        (2, "hard"),
        (3, "moderate"),
        (4, "easy"),
        (5, "very easy"),
    ]

    init(initialReps: Int, onCommit: @escaping (Int, Int?) -> Void) {
        _model = State(initialValue: LogSetSheetModel(
            initialReps: initialReps,
            onCommit: onCommit
        ))
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                readout
                rirRow
                DSKeypad(
                    onDigit: { model.pressDigit($0) },
                    onDelete: { model.pressDelete() },
                    onDecimal: nil,
                    onDone: { model.commit() },
                    doneLabel: "log"
                )
            }
            .padding(DSSpacing.xl)
        }
        .onAppear { model.prime() }
        .presentationDetents([.large])
        // Single-direction sheet animation avoids the backdrop+slide
        // interaction that caused visible frame drops on first present
        // (bug-025). `.move(edge: .bottom)` runs one transition; the
        // system-owned backdrop fade is unchanged, but because the
        // sheet now has an explicit transition instead of the default
        // composite, SwiftUI no longer re-runs geometry on the first
        // frame.
        .transition(.move(edge: .bottom))
        .animation(.easeInOut(duration: 0.25), value: model.buffer)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("log set")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("reps + optional rir · one tap to commit")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private var readout: some View {
        Text(model.displayBuffer)
            .font(.system(size: 48, weight: .light, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(DSColors.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.md)
            .accessibilityIdentifier("logset.reps_readout")
    }

    private var rirRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("RIR")
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)
            HStack(spacing: DSSpacing.sm) {
                ForEach(options, id: \.value) { opt in
                    Button(action: { model.pressRir(opt.value) }, label: {
                        rirButton(value: opt.value, label: opt.label)
                    })
                    .buttonStyle(.plain)
                    .accessibilityLabel("RIR \(opt.value) \(opt.label)")
                    .accessibilityIdentifier("logset.rir.\(opt.value)")
                }
            }
        }
    }

    private func rirButton(value: Int, label: String) -> some View {
        let selected = model.pickedRir == value
        return VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(selected ? DSColors.accentInk : DSColors.foreground)
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(DSColors.foregroundDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.md)
        .background(selected ? DSColors.accentMuted : DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(
                    selected ? DSColors.accent : DSColors.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
    }
}
