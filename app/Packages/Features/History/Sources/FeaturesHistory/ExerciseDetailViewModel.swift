// ExerciseDetailViewModel.swift
//
// View model for `HistoryExerciseDetailView` — the per-exercise screen
// reached from the by-exercise picker. Pulls set_logs for the exercise
// via `cache.loadSetLogs(exerciseID:)`, computes the top-set trend, and
// exposes a mono-formatted list of recent sessions.
//
// Kept self-loading (takes a `WorkoutCache`) rather than preloaded by
// HistoryViewModel because the data is per-screen: only fetched when the
// user drills in. Tests pass a fake cache.

import Foundation
import CoreDomain
import Persistence
import WorkoutCoreFoundation

@Observable
@MainActor
public final class ExerciseDetailViewModel {

    /// One recent session row in the mono list.
    public struct SessionRow: Identifiable, Equatable, Sendable {
        /// Stable id — day-start date's ISO8601 string.
        public let id: String
        /// "MON APR 14 · 4 × 100 × 5 · RIR 1.5"
        public let display: String
    }

    // MARK: - Public state

    public let exerciseID: ExerciseID
    public let exerciseName: String

    /// Trend summary — arrow + delta + weeks, e.g. "↑ 12.5 KG / 12 WK".
    /// Nil when there's insufficient history (fewer than 2 sessions).
    public private(set) var trendDisplay: String?

    /// Recent sessions, newest first. Capped by the fetch limit.
    public private(set) var recentSessions: [SessionRow] = []

    public private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let cache: WorkoutCache
    private let calendar: Calendar

    /// Most-recent N set_logs to pull. The view shows ~10 rows; we pull
    /// more so the trend has enough data points to be meaningful.
    private let fetchLimit: Int = 120

    public init(
        exerciseID: ExerciseID,
        exerciseName: String,
        cache: WorkoutCache,
        calendar: Calendar = .current
    ) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.cache = cache
        self.calendar = calendar
    }

    /// Load the set_logs and derive trend + recent sessions. Idempotent
    /// — safe to call from a `.task` on appear.
    public func load() async {
        isLoading = true
        defer { isLoading = false }

        let logs: [SetLog]
        do {
            logs = try await cache.loadSetLogs(
                exerciseID: exerciseID,
                limit: fetchLimit
            )
        } catch {
            // Leave the current state — the view just shows the empty
            // recent-sessions case.
            return
        }

        let trend = TrendComputation.compute(setLogs: logs, calendar: calendar)
        trendDisplay = trend.displayString
        recentSessions = Self.buildRecentRows(
            setLogs: logs,
            calendar: calendar
        )
    }

    // MARK: - Pure helpers

    /// Bucket set_logs by day, summarize each day as "N × weight × reps ·
    /// RIR mean", newest first.
    static func buildRecentRows(
        setLogs: [SetLog],
        calendar: Calendar
    ) -> [SessionRow] {
        // Group by calendar day so one session collapses to one row.
        var buckets: [Date: [SetLog]] = [:]
        for log in setLogs {
            let day = calendar.startOfDay(for: log.completedAt)
            buckets[day, default: []].append(log)
        }

        let sortedDays = buckets.keys.sorted(by: >)
        return sortedDays.compactMap { day in
            let logs = buckets[day] ?? []
            guard !logs.isEmpty else { return nil }
            let display = formatRecentRow(day: day, logs: logs, calendar: calendar)
            let id = ISO8601DateFormatter().string(from: day)
            return SessionRow(id: id, display: display)
        }
    }

    /// "MON APR 14 · 4 × 100 kg × 5 · RIR 1.5".
    /// - Count is number of non-warmup sets on that day.
    /// - Weight + reps are the most common across the day's working
    ///   sets; if they vary we show the top set's values (same rule as
    ///   TrendComputation).
    /// - RIR is mean across sets that logged one.
    static func formatRecentRow(
        day: Date,
        logs: [SetLog],
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        let dateStr = formatter.string(from: day).uppercased()

        let workingSets = logs.filter { !$0.isWarmup }
        let count = workingSets.count
        let topSet = workingSets.max { lhs, rhs in
            (lhs.weight ?? 0) < (rhs.weight ?? 0)
        }

        var parts: [String] = [dateStr]
        if let top = topSet, let weight = top.weight, let reps = top.reps {
            parts.append("\(count) × \(formatKilograms(weight)) × \(reps)")
        } else if let reps = topSet?.reps {
            parts.append("\(count) × BW × \(reps)")
        }

        let rirValues = workingSets.compactMap(\.rir)
        if !rirValues.isEmpty {
            let mean = Double(rirValues.reduce(0, +)) / Double(rirValues.count)
            parts.append(String(format: "RIR %.1f", mean))
        }
        return parts.joined(separator: " · ")
    }
}
