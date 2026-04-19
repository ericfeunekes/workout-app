// HistoryViewModel+Derivation.swift
//
// Pure-ish derivation helpers for HistoryViewModel — filtering,
// grouping, and picker-row assembly. Split out of the main file to
// keep the VM body under SwiftLint's type_body_length cap.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

extension HistoryViewModel {

    func rederive() {
        groups = filteredGroups()
        pickerRows = derivePickerRows()
    }

    /// Apply the active split filter, group by week, produce list rows.
    /// Groups are emitted newest first; within a group rows stay newest
    /// first (inherited from `rawSessions`' reverse-chrono load order).
    func filteredGroups() -> [WeekGroup] {
        let kept = rawSessions.filter { session in
            switch activeSplit {
            case .all:
                return true
            case .push:
                return session.tags.contains(.push)
            case .pull:
                return session.tags.contains(.pull)
            case .legs:
                return session.tags.contains(.legs)
            }
        }
        return Self.groupSessionsByWeek(
            kept,
            calendar: calendar,
            now: now()
        )
    }

    /// Derive the by-exercise picker rows: per exercise → count of
    /// sessions that included it + top load. Current-program exercises
    /// first, then past exercises.
    func derivePickerRows() -> [ExercisePickerRow] {
        let agg = aggregate(rawSessions)
        var rows = agg.counts.map { id, count in
            let topSummary: String? = agg.topLoad[id].map { entry in
                let unitLabel = entry.unit == .kg ? "KG" : "LB"
                return "TOP \(formatKilograms(entry.weight)) \(unitLabel)"
            }
            return ExercisePickerRow(
                id: id,
                name: exerciseName[id] ?? "(unknown)",
                sessionSummary: "\(count) SESSION\(count == 1 ? "" : "S")",
                topLoadSummary: topSummary,
                isInCurrentProgram: currentProgramExerciseIDs.contains(id)
            )
        }
        rows.sort(by: pickerOrdering)
        return rows
    }

    /// Session count + top load per exercise across the loaded sessions.
    /// Split so `derivePickerRows` stays short.
    ///
    /// Top load is computed within a single unit to avoid the numeric
    /// mix-up where "100 lb > 50 kg" is true by number but false by
    /// weight. For each exercise, whichever unit has more logged rows
    /// wins the comparison — ties fall to kg (v0 is kg-only). Rows in
    /// the non-dominant unit are skipped from the top-load search so
    /// the displayed value is always coherent with its own label.
    private func aggregate(
        _ sessions: [SessionDetail]
    ) -> (counts: [ExerciseID: Int], topLoad: [ExerciseID: TopLoad]) {
        var counts: [ExerciseID: Int] = [:]
        // Per-exercise: kg-unit log count, lb-unit log count, and
        // best-weight-seen per unit.
        var unitCounts: [ExerciseID: [WeightUnit: Int]] = [:]
        var bestByUnit: [ExerciseID: [WeightUnit: Double]] = [:]
        for session in sessions {
            for id in session.performedExerciseIDs {
                counts[id, default: 0] += 1
            }
            for log in session.setLogs {
                let displayID = log.performedExerciseID
                    ?? session.plannedExerciseByItem[log.workoutItemID]
                guard let displayID, let weight = log.weight else { continue }
                let unit = log.weightUnit ?? .kg
                unitCounts[displayID, default: [:]][unit, default: 0] += 1
                let existing = bestByUnit[displayID, default: [:]][unit] ?? 0
                if weight > existing {
                    bestByUnit[displayID, default: [:]][unit] = weight
                }
            }
        }

        var topLoad: [ExerciseID: TopLoad] = [:]
        for (id, perUnit) in bestByUnit {
            let dominant = dominantUnit(perUnitCounts: unitCounts[id] ?? [:])
            if let weight = perUnit[dominant] {
                topLoad[id] = TopLoad(weight: weight, unit: dominant)
            }
        }
        return (counts, topLoad)
    }

    /// Top load for one exercise — the weight is in `unit`'s own scale,
    /// not normalized. Kept as a small struct so downstream consumers
    /// (the picker row builder today, tests, future API) don't have to
    /// re-pair weight with unit.
    struct TopLoad: Equatable {
        let weight: Double
        let unit: WeightUnit
    }

    /// Pick the unit with more logged rows for a given exercise. Ties
    /// fall to kg (v0 is kg-only in practice; the default matches the
    /// spec's stated norm).
    private func dominantUnit(perUnitCounts: [WeightUnit: Int]) -> WeightUnit {
        let kgCount = perUnitCounts[.kg] ?? 0
        let lbCount = perUnitCounts[.lb] ?? 0
        return lbCount > kgCount ? .lb : .kg
    }

    /// Current-program rows first, then alphabetical case-insensitive.
    private func pickerOrdering(
        _ lhs: ExercisePickerRow,
        _ rhs: ExercisePickerRow
    ) -> Bool {
        if lhs.isInCurrentProgram != rhs.isInCurrentProgram {
            return lhs.isInCurrentProgram
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Group a list of SessionDetail values by week.
    ///
    /// Header grammar (matches the design reference):
    ///   • THIS WEEK — workouts in the same weekOfYear as `now`
    ///   • LAST WEEK — one week before `now`
    ///   • APR · WEEK 15 — older weeks, using the bucket's own month + week number
    ///
    /// Sessions missing a sortable date sort last under an "UNDATED"
    /// header — this is defensive; completed rows always carry a date.
    static func groupSessionsByWeek(
        _ sessions: [SessionDetail],
        calendar: Calendar,
        now: Date
    ) -> [WeekGroup] {
        let buckets = bucket(sessions, calendar: calendar)
        let nowKey = NowKey(
            week: calendar.component(.weekOfYear, from: now),
            year: calendar.component(.yearForWeekOfYear, from: now)
        )
        var groups = buckets.dated.map { dated in
            WeekGroup(
                header: weekHeader(
                    for: dated.representativeDate,
                    bucketYear: dated.year,
                    bucketWeek: dated.week,
                    nowKey: nowKey,
                    calendar: calendar
                ),
                rows: dated.sessions.map { $0.listRow(calendar: calendar) }
            )
        }
        if !buckets.undated.isEmpty {
            groups.append(WeekGroup(
                header: "UNDATED",
                rows: buckets.undated.map { $0.listRow(calendar: calendar) }
            ))
        }
        return groups
    }

    private struct NowKey {
        let week: Int
        let year: Int
    }

    private struct DatedBucket {
        let year: Int
        let week: Int
        let representativeDate: Date
        let sessions: [SessionDetail]
    }

    private struct Buckets {
        let dated: [DatedBucket]
        let undated: [SessionDetail]
    }

    /// Partition sessions into (year, weekOfYear) buckets keeping the
    /// first-seen insertion order — this preserves the caller's newest-
    /// first ordering across the result.
    private static func bucket(
        _ sessions: [SessionDetail],
        calendar: Calendar
    ) -> Buckets {
        var order: [String] = []
        var rows: [String: [SessionDetail]] = [:]
        var meta: [String: (Int, Int, Date)] = [:]
        var undated: [SessionDetail] = []

        for session in sessions {
            guard let sortDate = session.workout.completedAt
                ?? session.workout.scheduledDate else {
                undated.append(session)
                continue
            }
            let week = calendar.component(.weekOfYear, from: sortDate)
            let year = calendar.component(.yearForWeekOfYear, from: sortDate)
            let key = "\(year)-\(week)"
            if rows[key] == nil {
                rows[key] = []
                order.append(key)
                meta[key] = (year, week, sortDate)
            }
            rows[key]?.append(session)
        }
        let dated: [DatedBucket] = order.compactMap { key in
            guard let m = meta[key], let sess = rows[key] else { return nil }
            return DatedBucket(
                year: m.0,
                week: m.1,
                representativeDate: m.2,
                sessions: sess
            )
        }
        return Buckets(dated: dated, undated: undated)
    }

    /// Header label for one bucket.
    private static func weekHeader(
        for date: Date,
        bucketYear: Int,
        bucketWeek: Int,
        nowKey: NowKey,
        calendar: Calendar
    ) -> String {
        if bucketYear == nowKey.year && bucketWeek == nowKey.week {
            return "THIS WEEK"
        }
        if bucketYear == nowKey.year && bucketWeek == nowKey.week - 1 {
            return "LAST WEEK"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        let month = formatter.string(from: date).uppercased()
        return "\(month) · WEEK \(bucketWeek)"
    }
}
