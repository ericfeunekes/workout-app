// SessionDetail.swift
//
// Intermediate shape: one completed workout plus its set_logs, with tag
// parsing + row derivation attached. Kept separate from the view model so
// the grouping and filter tests can pass in a deterministic `SessionDetail`
// without standing up a cache.
//
// Tag grammar: `Workout.tagsJSON` is a JSON array of strings attached by
// Claude for analysis grouping. The History list filters on the canonical
// tokens `push_day`, `pull_day`, `leg_day` (a leading "_" prefix is
// tolerated — see `SplitTag.parse`). An untagged workout contributes no
// split tags and is therefore only visible under the ALL chip.

import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

/// Canonical split tag used for filtering.
public enum SplitTag: String, Sendable, CaseIterable, Hashable {
    case push
    case pull
    case legs

    /// Parse a raw Claude-authored tag into one of our canonical splits.
    /// Returns nil for anything else (week numbers, block names, etc.).
    /// Matching is case-insensitive; `push_day`, `PushDay`, `push` all
    /// resolve to `.push`.
    public static func parse(_ raw: String) -> SplitTag? {
        let normalized = raw.lowercased()
        if normalized == "push" || normalized == "push_day" || normalized == "pushday" {
            return .push
        }
        if normalized == "pull" || normalized == "pull_day" || normalized == "pullday" {
            return .pull
        }
        if normalized == "legs" || normalized == "leg_day" || normalized == "legday" {
            return .legs
        }
        return nil
    }
}

/// One completed workout with its set_logs, cached for derivation.
public struct SessionDetail: Sendable, Equatable {
    public let workout: Workout
    public let setLogs: [SetLog]
    public let primitiveSetLogs: [PrimitiveSetLog]
    /// Map from `WorkoutItem.id` to the planned `exerciseID`. Used by the
    /// picker to count an exercise as "performed this session" even when
    /// the user didn't swap mid-workout (so `performedExerciseID` is
    /// nil). Empty when the caller couldn't populate it cheaply.
    public let plannedExerciseByItem: [WorkoutItemID: ExerciseID]
    /// Bodyweight captured with this session, if any. Populated by
    /// `HistoryViewModel+Load.buildSession` from the local
    /// `user_parameters` cache by finding the most recent
    /// `bodyweight_kg` row whose `updatedAt` falls inside the workout's
    /// time window (`scheduledDate` | first-log `startedAt` start →
    /// `completedAt` + 2 min). Bodyweight lives in `user_parameters`
    /// (append-only) — see `docs/observability-map.md` § "Completion".
    public let bodyweightKg: Double?

    public init(
        workout: Workout,
        setLogs: [SetLog],
        primitiveSetLogs: [PrimitiveSetLog] = [],
        plannedExerciseByItem: [WorkoutItemID: ExerciseID] = [:],
        bodyweightKg: Double? = nil
    ) {
        self.workout = workout
        self.setLogs = setLogs
        self.primitiveSetLogs = primitiveSetLogs
        self.plannedExerciseByItem = plannedExerciseByItem
        self.bodyweightKg = bodyweightKg
    }

    /// All non-skipped exercise ids that appear in this session,
    /// counting both swapped (`performedExerciseID`) and planned
    /// (resolved via the item lookup) exercises. Empty when neither
    /// source has data.
    public var performedExerciseIDs: Set<ExerciseID> {
        var out: Set<ExerciseID> = []
        for log in primitiveSetLogs where log.resultSemantics.isByExerciseEligible {
            if let performed = log.performedExerciseID {
                out.insert(performed)
            } else if let planned = log.plannedExerciseID {
                out.insert(planned)
            }
        }
        if !out.isEmpty { return out }
        for log in setLogs where !log.skipped {
            if let swap = log.performedExerciseID {
                out.insert(swap)
            } else if let planned = plannedExerciseByItem[log.workoutItemID] {
                out.insert(planned)
            }
        }
        return out
    }

    /// Split-tag membership derived from `workout.tagsJSON`. Empty set
    /// when tags are missing or unparseable — such workouts are ALL-only
    /// in the filter chip row.
    public var tags: Set<SplitTag> {
        guard let json = workout.tagsJSON,
              let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        var out: Set<SplitTag> = []
        for token in raw {
            if let tag = SplitTag.parse(token) {
                out.insert(tag)
            }
        }
        return out
    }

    /// Average RIR across all set_logs that recorded one. Nil when no
    /// set recorded RIR.
    public var avgRIR: Double? {
        let primitiveRIR = primitiveSetLogs
            .filter { $0.resultSemantics.isByExerciseEligible }
            .compactMap(\.rir)
        let rirValues = primitiveRIR.isEmpty
            ? setLogs.filter { !$0.skipped }.compactMap(\.rir)
            : primitiveRIR
        guard !rirValues.isEmpty else { return nil }
        let sum = rirValues.reduce(0, +)
        return Double(sum) / Double(rirValues.count)
    }

    /// Workout duration in seconds, derived from the set_log timestamps.
    /// Uses the first `startedAt` to the last `completedAt` if we have
    /// them, otherwise falls back to the window between earliest and
    /// latest `completedAt`. Nil when fewer than two data points exist.
    public var durationSeconds: TimeInterval? {
        let primitiveCompletions = primitiveSetLogs.map(\.completedAt)
        let legacyCompletions = setLogs.map(\.completedAt)
        let completions = primitiveCompletions.isEmpty ? legacyCompletions : primitiveCompletions
        if completions.isEmpty { return nil }
        let starts = setLogs.compactMap(\.startedAt)
        let first = starts.min() ?? completions.min()
        let last = completions.max()
        guard let first, let last else { return nil }
        let delta = last.timeIntervalSince(first)
        return delta > 0 ? delta : nil
    }

    /// True when the workout has a note, or any set log has one.
    public var hasNote: Bool {
        if let note = workout.notes, !note.isEmpty { return true }
        if primitiveSetLogs.contains(where: { !($0.notes ?? "").isEmpty }) { return true }
        return setLogs.contains { log in
            guard let n = log.notes else { return false }
            return !n.isEmpty
        }
    }

    /// Render a `HistoryViewModel.SessionRow` from this detail.
    public func listRow(calendar: Calendar) -> HistoryViewModel.SessionRow {
        HistoryViewModel.SessionRow(
            id: workout.id,
            programName: workout.name,
            shortDate: Self.shortDateString(for: sortDate, calendar: calendar),
            duration: durationSeconds.map { "\(Int(($0 / 60).rounded())) MIN" },
            avgRIR: avgRIR.map { String(format: "RIR %.1f", $0) },
            bodyweight: bodyweightKg.map { "\(formatKilograms($0)) KG BW" },
            hasNote: hasNote,
            tags: tags
        )
    }

    /// Preferred sort / display date: `completedAt` if present, else
    /// `scheduledDate`, else `updatedAt`.
    public var sortDate: Date? {
        workout.completedAt ?? workout.scheduledDate
    }

    /// "MON APR 14" / "FRI APR 11". Uppercased; uses a POSIX locale so
    /// the abbreviation is stable across regions (the design reference
    /// is English-only).
    static func shortDateString(for date: Date?, calendar: Calendar) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date).uppercased()
    }
}
