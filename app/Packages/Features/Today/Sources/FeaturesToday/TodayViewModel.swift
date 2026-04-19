// TodayViewModel.swift
//
// `@Observable` view model for the Today screen. Derives the displayable
// shape from a `TodayContext` at construction time and exposes a `start()`
// action that dispatches `.start` into the session state binding.
//
// The view model is deliberately stateless beyond the initial derivation —
// Today is a glance view, not an interactive screen. When the user taps
// an exercise (plan sheet) we'll layer that in as its own sheet in a
// follow-up Feature; this package renders the read-side.
//
// Reload (bug-036): on save & done the shell writes the completed workout
// to the local cache and the session route flips back to `.today`. The
// Today tab must then pick up the NEXT planned workout instead of re-
// rendering the just-completed one. `reload(using:)` re-runs the
// `TodayLoader`, derives a fresh `TodayContext`, and mutates the
// observable fields in place so SwiftUI picks up the new values. When
// the loader returns `nil` (no more planned workouts), the VM flips to
// an empty-shaped state (`isEmpty == true`, `exercises == []`, blank
// program name) — the shell renders the existing S8 "zero-exercise"
// empty glance until the next pull fills the queue.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import CoreTelemetry
import WorkoutCoreFoundation

@Observable
@MainActor
public final class TodayViewModel {

    /// A single row in the exercise list. Pre-formatted for direct
    /// rendering — the view never parses JSON or formats numbers.
    public struct ExerciseSummary: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        /// "4 × 5 @ 102.5 kg" — see `PrescriptionLineFormatter`.
        public let prescriptionLine: String
        /// "5×5 @ 100 kg · RIR 2" when the exercise has prior history,
        /// `nil` when it doesn't.
        public let lastTime: String?

        public init(
            id: UUID,
            name: String,
            prescriptionLine: String,
            lastTime: String?
        ) {
            self.id = id
            self.name = name
            self.prescriptionLine = prescriptionLine
            self.lastTime = lastTime
        }
    }

    // MARK: - Published (mutated by `reload`)
    //
    // All five of these need `internal(set) var` rather than `let` so a
    // reload can replace them in place. Observers see the change because
    // `@Observable` tracks property access automatically.

    public internal(set) var programName: String
    public internal(set) var programTags: [String]
    public internal(set) var lastSessionSummary: String?
    public internal(set) var exercises: [ExerciseSummary]
    /// `true` when the most recent load found no planned workout. The view
    /// can render a degenerate "nothing scheduled" state; today it falls
    /// through to S8 (header + empty list). Callers that need to flip a
    /// different phase should observe this and act.
    public internal(set) var isEmpty: Bool
    /// The id of the currently-displayed workout. `nil` when `isEmpty`.
    /// Exposed so tests can assert that reload advanced to a different
    /// workout; also convenient for telemetry correlation.
    public internal(set) var workoutID: UUID?

    /// Should the view render the pinned "start workout" button? The
    /// button only makes sense when there's a workout to start — when
    /// `isEmpty == true` (reload found nothing planned, per S11) it
    /// would be a disconnected CTA with nothing to dispatch. Exposed
    /// as a computed property so tests can assert the gate directly
    /// without view-tree inspection. See qa-008.
    public var showsStartButton: Bool { !isEmpty }

    // MARK: - Dependencies for reload
    //
    // `sessionStateBinding` survives reload unchanged — the holder it
    // points at is stable across bootstrap (see Shell's
    // `ExecutionVMHolder`). `lastPerformed` / `lastSessionSummary`
    // / `programTags` are pass-through defaults from the original init;
    // they stay `nil` / `[:]` on reload until the history query API lands.

    private let telemetry: TelemetryEmitter
    private let sessionStateBinding: (@Sendable (SessionMutation) -> Void)?

    public init(
        context: TodayContext,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        self.programName = context.workout.name
        self.programTags = context.programTags
        self.lastSessionSummary = context.lastSessionSummary
        self.exercises = Self.deriveExercises(from: context)
        self.isEmpty = false
        self.workoutID = context.workout.id
        self.sessionStateBinding = context.sessionStateBinding
        self.telemetry = telemetry
    }

    /// Flip session route to `.active`. No-op when the binding is absent
    /// (previews, tests).
    public func start() {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "interaction",
            name: "today.start_tap",
            workoutID: workoutID
        ))
        sessionStateBinding?(.start)
    }

    // MARK: - Reload (bug-036)

    /// Re-run the `TodayLoader` against the current cache and replace the
    /// observable fields. Called by the shell after `saveAndDone` writes
    /// the completed workout locally — the just-completed workout is no
    /// longer `.planned`, so the loader picks the next one. When the
    /// loader returns `nil` (nothing planned left) the VM flips to an
    /// empty-shaped state; `isEmpty` becomes `true`, `exercises` becomes
    /// `[]`, and `workoutID` becomes `nil`.
    ///
    /// Errors thrown by the cache are swallowed — reload is fire-and-
    /// forget from the shell's perspective (matches the rest of the save-
    /// and-done side-effect chain). A failure leaves the previous state
    /// intact so the user at least sees something.
    public func reload(using loader: TodayLoader) async {
        let context: TodayContext?
        do {
            context = try await loader.load(
                sessionStateBinding: sessionStateBinding
            )
        } catch {
            // Cache read failed — keep the current rendered state rather
            // than blanking the screen. See `docs/sync.md` § offline.
            return
        }
        apply(context)
    }

    /// Apply a fresh context (or `nil` for empty) to the observable
    /// surface. Split out so tests that want to drive the reload from a
    /// hand-rolled context (without standing up a `TodayLoader`) can
    /// call into it directly.
    func apply(_ context: TodayContext?) {
        guard let context else {
            programName = ""
            programTags = []
            lastSessionSummary = nil
            exercises = []
            isEmpty = true
            workoutID = nil
            return
        }
        programName = context.workout.name
        programTags = context.programTags
        lastSessionSummary = context.lastSessionSummary
        exercises = Self.deriveExercises(from: context)
        isEmpty = false
        workoutID = context.workout.id
    }

    // MARK: - Derivation

    /// Walk the blocks in position order, then items in position order,
    /// assembling one `ExerciseSummary` per item. Items whose block is
    /// missing (data bug) are dropped silently — consistent with the
    /// reducer's no-op-on-invalid posture.
    static func deriveExercises(from context: TodayContext) -> [ExerciseSummary] {
        let parser = PrescriptionParser()
        let sortedBlocks = context.blocks.sorted { $0.position < $1.position }
        var itemsByBlock: [UUID: [WorkoutItem]] = [:]
        for item in context.items {
            itemsByBlock[item.blockID, default: []].append(item)
        }

        var out: [ExerciseSummary] = []
        for block in sortedBlocks {
            let items = (itemsByBlock[block.id] ?? [])
                .sorted { $0.position < $1.position }
            for item in items {
                let exercise = context.exercises[item.exerciseID]
                let name = exercise?.name ?? "(unknown exercise)"
                let prescriptionLine: String
                switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
                case .success(let prescription):
                    prescriptionLine = formatPrescriptionLine(prescription)
                case .failure:
                    // Parse failures are rare on today's pulled data —
                    // render a neutral fallback rather than crashing.
                    prescriptionLine = ""
                }
                out.append(ExerciseSummary(
                    id: item.id,
                    name: name,
                    prescriptionLine: prescriptionLine,
                    lastTime: context.lastPerformed[item.exerciseID]
                ))
            }
        }
        return out
    }
}
