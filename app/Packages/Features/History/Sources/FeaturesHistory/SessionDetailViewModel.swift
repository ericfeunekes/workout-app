// SessionDetailViewModel.swift
//
// View model for `HistorySessionDetailView`. Takes one completed workout
// + its set_logs and groups them by exercise for rendering. Pure — no
// async, no persistence. The History VM constructs it lazily when the
// user taps a row in the list.

import Foundation
import CoreDomain
import CoreSession
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
            primitiveSetLogs: session.primitiveSetLogs,
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
        primitiveSetLogs: [PrimitiveSetLog] = [],
        plannedExerciseByItem: [WorkoutItemID: ExerciseID],
        exerciseName: [ExerciseID: String]
    ) -> [ExerciseCard] {
        if !primitiveSetLogs.isEmpty {
            return buildPrimitiveCards(
                primitiveSetLogs: primitiveSetLogs,
                exerciseName: exerciseName
            )
        }
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

    static func buildPrimitiveCards(
        primitiveSetLogs: [PrimitiveSetLog],
        exerciseName: [ExerciseID: String]
    ) -> [ExerciseCard] {
        var order: [UUID] = []
        var bucket: [UUID: [PrimitiveSetLog]] = [:]
        var names: [UUID: String] = [:]
        for log in primitiveSetLogs where !log.resultSemantics.isSentinel {
            let id: UUID
            let name: String
            switch log.resultSemantics.scope {
            case .exercise:
                id = log.performedExerciseID ?? log.plannedExerciseID ?? log.slotID ?? log.id
                name = exerciseName[id] ?? "(unknown exercise)"
            case .setAggregate:
                id = log.setID ?? log.id
                name = "set result"
            case .blockAggregate:
                id = log.blockID ?? log.id
                name = "block result"
            }
            if bucket[id] == nil {
                bucket[id] = []
                order.append(id)
                names[id] = name
            }
            bucket[id]?.append(log)
        }

        return order.map { id in
            let logs = (bucket[id] ?? []).sorted { lhs, rhs in
                if lhs.blockRepeatIndex != rhs.blockRepeatIndex {
                    return lhs.blockRepeatIndex < rhs.blockRepeatIndex
                }
                if lhs.setRepeatIndex != rhs.setRepeatIndex {
                    return lhs.setRepeatIndex < rhs.setRepeatIndex
                }
                if lhs.setIndex != rhs.setIndex {
                    return lhs.setIndex < rhs.setIndex
                }
                return lhs.completedAt < rhs.completedAt
            }
            let rows = logs.enumerated().map { index, log -> SetRow in
                SetRow(id: log.id, display: formatPrimitiveRow(log, displayIndex: index))
            }
            let note = primitiveNotes(logs)
            return ExerciseCard(
                id: id,
                name: names[id] ?? "(unknown result)",
                setRows: rows,
                note: note
            )
        }
    }

    /// "1 · 100 kg × 5 · RIR 2" — or "1 · 225 lb × 5 · RIR 2" when the
    /// set was logged in lb. Skipped and cardio-shaped rows get their own
    /// compact summaries so History does not render them as loadless strength.
    /// - setIndex is 1-based both in storage and in display — the rest
    ///   of the session pipeline (SessionSeeder, cursor math, reducer)
    ///   emits 1-based indexes, so no off-by-one shift is needed here.
    /// - Weight is omitted when nil ("bodyweight" collapses to "BW").
    /// - Unit suffix follows `log.weightUnit`; nil defaults to `.kg` to
    ///   match the app's historical v0-kg-only logs (pre-unit-field rows).
    /// - RIR is omitted when not logged.
    static func formatSetRow(_ log: SetLog) -> String {
        var parts: [String] = [String(log.setIndex)]
        if log.skipped {
            parts.append("SKIPPED")
            appendSide(log.side, to: &parts)
            return parts.joined(separator: " · ")
        }
        if log.durationSec != nil || log.distanceM != nil,
           log.weight == nil,
           log.reps == nil {
            parts.append(formatCardioSummary(
                durationSec: log.durationSec,
                distanceM: log.distanceM
            ).uppercased())
            appendSide(log.side, to: &parts)
            if let rir = log.rir {
                parts.append("RIR \(rir)")
            }
            return parts.joined(separator: " · ")
        }
        let unit: LoadUnit = log.weightUnit.flatMap { LoadUnit(rawValue: $0.rawValue) } ?? .kg
        let load = formatLoad(weight: log.weight, unit: unit)
        let reps = log.reps.map(String.init) ?? "—"
        parts.append("\(load) × \(reps)")
        if let duration = log.durationSec, duration > 0 {
            parts.append(formatDuration(seconds: duration))
        }
        if let distance = log.distanceM, distance > 0 {
            parts.append(formatCardioDistance(distance))
        }
        appendSide(log.side, to: &parts)
        if let rir = log.rir {
            parts.append("RIR \(rir)")
        }
        return parts.joined(separator: " · ")
    }

    static func formatPrimitiveRow(_ log: PrimitiveSetLog, displayIndex: Int = 0) -> String {
        var parts: [String] = [primitiveRowPrefix(log, displayIndex: displayIndex)]
        if log.skipped {
            parts.append("SKIPPED")
            appendSide(log.side, to: &parts)
            return parts.joined(separator: " · ")
        }

        var metrics: [String] = []
        if let rounds = log.rounds {
            metrics.append("\(rounds) round\(rounds == 1 ? "" : "s")")
        }
        if let weight = log.weight {
            let unit = log.weightUnit ?? .kg
            metrics.append("\(formatKilograms(weight)) \(unit.rawValue)")
        } else if log.role == .slot, log.reps != nil, log.durationSec == nil, log.distanceM == nil {
            metrics.append("BW")
        }
        if let reps = log.reps {
            metrics.append("\(reps) rep\(reps == 1 ? "" : "s")")
        }
        if let duration = log.durationSec {
            metrics.append(formatDuration(seconds: duration))
        }
        if let distance = log.distanceM {
            metrics.append(formatCardioDistance(distance))
        }
        if metrics.isEmpty {
            metrics.append("completed")
        }
        parts.append(metrics.joined(separator: " + "))
        appendSide(log.side, to: &parts)
        if let rir = log.rir {
            parts.append("RIR \(rir)")
        }
        if let hrAvg = log.hrAvgBpm {
            parts.append("HR \(hrAvg)")
        }
        return parts.joined(separator: " · ")
    }

    private static func primitiveRowPrefix(_ log: PrimitiveSetLog, displayIndex: Int) -> String {
        switch log.resultSemantics.scope {
        case .exercise:
            return "SET \(displayIndex + 1)"
        case .setAggregate:
            return "SET"
        case .blockAggregate:
            return "BLOCK"
        }
    }

    private static func appendSide(_ side: SetLogSide, to parts: inout [String]) {
        switch side {
        case .bilateral:
            return
        case .left:
            parts.append("LEFT")
        case .right:
            parts.append("RIGHT")
        }
    }

    /// Concatenate non-empty `notes` fields from the logs. Separator is
    /// " · " to keep it compact and match the design's mid-dot divider.
    static func concatenateNotes(_ logs: [SetLog]) -> String? {
        let notes = logs.compactMap { $0.notes?.nilIfEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: " · ")
    }

    static func primitiveNotes(_ logs: [PrimitiveSetLog]) -> String? {
        let notes = logs.compactMap { $0.notes?.nilIfEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: " · ")
    }

    private static func formatCardioDistance(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000.0)
        }
        return "\(Int(metres.rounded())) m"
    }
}

private extension String {
    /// Return nil when the string is empty or whitespace-only; else self.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
