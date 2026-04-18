// SessionDetailViewModel.swift
//
// View model for `HistorySessionDetailView`. Takes one completed workout
// + its set_logs and groups them by exercise for rendering. Pure — no
// async, no persistence. The History VM constructs it lazily when the
// user taps a row in the list.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

@Observable
@MainActor
public final class SessionDetailViewModel {

    /// One exercise's set rows as they appear in the detail view.
    public struct ExerciseCard: Identifiable, Equatable, Sendable {
        /// Exercise UUID (performed, if swapped; else planned).
        public let id: ExerciseID
        public let name: String
        /// Mono-formatted set rows: "1 · 100 kg × 5 · RIR 2".
        public let setRows: [SetRow]
        /// Per-exercise note, if any (concatenated from set_log.notes).
        public let note: String?
    }

    /// A single set row inside an ExerciseCard.
    public struct SetRow: Identifiable, Equatable, Sendable {
        public let id: SetLogID
        public let display: String
        /// Underlying SetLog id so tap handlers can find the row again.
        public var setLogID: SetLogID { id }
    }

    // MARK: - Public state

    /// Underlying workout id — used by `HistoryViewModel.editPastSet`
    /// to re-lookup the target session by `(workoutID, setLogID)`.
    public let workoutID: WorkoutID
    /// Workout program name as-authored.
    public let programName: String
    /// Long-form date: "Friday, Apr 11".
    public let longDate: String
    /// "RIR 1.5 AVG · 54 MIN" — the chip row under the title. Nil parts
    /// render when data isn't available.
    public let summary: String
    /// Body weight summary, if any — "82.1 KG BW". Separate field so
    /// the view can render it conditionally without parsing strings.
    public let bodyweight: String?
    /// Workout-level note at the bottom of the screen.
    public let workoutNote: String?
    /// Cards in block-then-position order.
    public let cards: [ExerciseCard]
    /// Raw set_logs keyed by `SetLog.id`, so the edit sheet can read the
    /// current `reps` / `rir` / `weight` to prefill the controls when
    /// the user taps a row. Kept as a dictionary rather than an array so
    /// the tap handler doesn't linear-scan on every open.
    public let setLogsByID: [SetLogID: SetLog]

    public init(
        session: SessionDetail,
        exerciseName: [ExerciseID: String],
        calendar: Calendar
    ) {
        self.workoutID = session.workout.id
        self.programName = session.workout.name
        self.longDate = Self.longDateString(
            for: session.sortDate,
            calendar: calendar
        )
        self.summary = Self.buildSummary(session: session)
        self.bodyweight = session.bodyweightKg.map {
            "\(formatKilograms($0)) KG BW"
        }
        self.workoutNote = session.workout.notes?.nilIfEmpty
        self.cards = Self.buildCards(
            setLogs: session.setLogs,
            plannedExerciseByItem: session.plannedExerciseByItem,
            exerciseName: exerciseName
        )
        self.setLogsByID = Dictionary(
            uniqueKeysWithValues: session.setLogs.map { ($0.id, $0) }
        )
    }

    // MARK: - Static builders (pure)

    static func buildSummary(session: SessionDetail) -> String {
        var parts: [String] = []
        if let rir = session.avgRIR {
            parts.append(String(format: "RIR %.1f AVG", rir))
        }
        if let dur = session.durationSeconds {
            parts.append("\(Int((dur / 60).rounded())) MIN")
        }
        return parts.joined(separator: " · ")
    }

    /// Long date: "Friday, Apr 11". Uses a POSIX locale for stable
    /// formatting — the design reference is English-only.
    static func longDateString(for date: Date?, calendar: Calendar) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    /// Group set_logs into cards. Order is "order first set_log appears"
    /// — the cache returns logs in (item position, setIndex) order so
    /// this is stable for a given pull.
    ///
    /// Display id per log:
    ///   • `performedExerciseID` when set (swap)
    ///   • else the planned exerciseID resolved from
    ///     `plannedExerciseByItem`
    ///   • else the WorkoutItemID as a last-resort surrogate so cards
    ///     still render even when the items lookup is empty.
    static func buildCards(
        setLogs: [SetLog],
        plannedExerciseByItem: [WorkoutItemID: ExerciseID],
        exerciseName: [ExerciseID: String]
    ) -> [ExerciseCard] {
        var order: [UUID] = []
        var bucket: [UUID: [SetLog]] = [:]
        for log in setLogs {
            let id: UUID = log.performedExerciseID
                ?? plannedExerciseByItem[log.workoutItemID]
                ?? log.workoutItemID
            if bucket[id] == nil {
                bucket[id] = []
                order.append(id)
            }
            bucket[id]?.append(log)
        }

        return order.map { id in
            let logs = bucket[id] ?? []
            let sortedLogs = logs.sorted { $0.setIndex < $1.setIndex }
            let rows = sortedLogs.map { log -> SetRow in
                SetRow(id: log.id, display: formatSetRow(log))
            }
            let note = concatenateNotes(sortedLogs)
            return ExerciseCard(
                id: id,
                name: exerciseName[id] ?? "(unknown exercise)",
                setRows: rows,
                note: note
            )
        }
    }

    /// "1 · 100 kg × 5 · RIR 2".
    /// - setIndex is 1-based both in storage and in display — the rest
    ///   of the session pipeline (SessionSeeder, cursor math, reducer)
    ///   emits 1-based indexes, so no off-by-one shift is needed here.
    /// - Weight is omitted when nil ("bodyweight" collapses to "BW").
    /// - RIR is omitted when not logged.
    static func formatSetRow(_ log: SetLog) -> String {
        var parts: [String] = [String(log.setIndex)]
        let load = formatLoad(kg: log.weight)
        let reps = log.reps.map(String.init) ?? "—"
        parts.append("\(load) × \(reps)")
        if let rir = log.rir {
            parts.append("RIR \(rir)")
        }
        return parts.joined(separator: " · ")
    }

    /// Concatenate non-empty `notes` fields from the logs. Separator is
    /// " · " to keep it compact and match the design's mid-dot divider.
    static func concatenateNotes(_ logs: [SetLog]) -> String? {
        let notes = logs.compactMap { $0.notes?.nilIfEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: " · ")
    }
}

private extension String {
    /// Return nil when the string is empty or whitespace-only; else self.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
