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

    /// Bucket set_logs by workout-session and summarize each session
    /// as "N × weight × reps · RIR mean", newest first.
    ///
    /// Session key is `workoutItemID` — two workouts logged on the same
    /// calendar day have different WorkoutItems for the same exercise,
    /// so grouping by item keeps them as distinct rows. Previous
    /// implementation collapsed on `startOfDay`, which merged same-day
    /// sessions into one row and silently dropped a workout from the
    /// list.
    ///
    /// Within a session we pick the top set by weight, comparing only
    /// within the session's own unit (a session is single-unit by
    /// construction — a user doesn't mid-workout swap lb for kg). So
    /// cross-unit numerical comparison never happens inside this
    /// helper even if upstream data somehow mixed units.
    static func buildRecentRows(
        setLogs: [SetLog],
        calendar: Calendar
    ) -> [SessionRow] {
        // Order sessions by their latest set's completedAt. Using the
        // first-seen ordering preserves the input's newest-first layout
        // cleanly.
        var order: [UUID] = []
        var buckets: [UUID: [SetLog]] = [:]
        for log in setLogs {
            let key = log.workoutItemID
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(log)
        }

        // Sort sessions newest-first by their latest completedAt —
        // which matches the cache's reverse-chrono delivery order but
        // is also resilient if the caller reorders.
        let sortedKeys = order.sorted { lhs, rhs in
            let lhsLatest = buckets[lhs]?.map(\.completedAt).max() ?? .distantPast
            let rhsLatest = buckets[rhs]?.map(\.completedAt).max() ?? .distantPast
            return lhsLatest > rhsLatest
        }

        return sortedKeys.compactMap { key in
            let logs = buckets[key] ?? []
            guard !logs.isEmpty, let latest = logs.map(\.completedAt).max() else {
                return nil
            }
            let display = formatRecentRow(latestAt: latest, logs: logs, calendar: calendar)
            // Row id uniquely identifies the session on screen —
            // workoutItemID is stable across reloads.
            return SessionRow(id: key.uuidString, display: display)
        }
    }

    /// "MON APR 14 · 4 × 100 kg × 5 · RIR 1.5".
    /// - Count is number of non-warmup sets in the session.
    /// - Weight + reps are the top set's values (heaviest weight,
    ///   tie-break by reps; same rule as TrendComputation).
    /// - Weight unit comes from the top set's own `weightUnit`,
    ///   defaulting to `.kg` when legacy rows don't carry one.
    /// - RIR is mean across sets that logged one.
    static func formatRecentRow(
        latestAt: Date,
        logs: [SetLog],
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        let dateStr = formatter.string(from: latestAt).uppercased()

        let workingSets = logs.filter { !$0.isWarmup }
        let count = workingSets.count
        // Restrict the top-set search to the session's dominant unit.
        // Single-unit sessions (the 100% common case) reduce to the
        // same max-by-weight as before.
        let sessionUnit: WeightUnit = workingSets
            .compactMap { $0.weightUnit }
            .first ?? .kg
        let topSet = workingSets
            .filter { ($0.weightUnit ?? .kg) == sessionUnit }
            .max { lhs, rhs in
                (lhs.weight ?? 0) < (rhs.weight ?? 0)
            }

        var parts: [String] = [dateStr]
        if let top = topSet, let weight = top.weight, let reps = top.reps {
            let unitLabel = sessionUnit == .kg ? "kg" : "lb"
            parts.append("\(count) × \(formatKilograms(weight)) \(unitLabel) × \(reps)")
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
