// TrendComputation.swift
//
// Pure helpers for the per-exercise trend indicator in the by-exercise
// view ("↑ 12.5 KG / 12 WK"). Takes a list of set_logs for one exercise
// across many sessions and returns a display string plus the underlying
// numbers so a future chart can reuse them.
//
// Approach:
//   • Group set_logs by calendar day (one session → one top set). This
//     avoids treating a warmup + work + backoff progression as three
//     separate data points.
//   • For each session, "top set" is the heaviest logged weight. Ties on
//     weight break by reps (higher reps wins).
//   • Produce a simple total delta: (last top weight) - (first top weight).
//     Not a regression — the design reference shows a one-number
//     indicator, not a slope. If the two endpoints are the same, the
//     arrow flattens (→) and delta is 0.
//
// Rationale for "total delta" over regression: the v1 surface is a
// single-line summary. A regression would hide weeks where the user was
// stuck and then broke through — the headline delta is easier to read.
// We expose the raw top-set series so a future per-session trend chart
// (v1.1+) can compute whatever smoothing it likes.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public enum TrendComputation {

    /// One session's top set for a given exercise.
    public struct TopSet: Sendable, Equatable {
        public let date: Date
        public let weightKg: Double
        public let reps: Int

        public init(date: Date, weightKg: Double, reps: Int) {
            self.date = date
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    /// Output summary.
    public struct Trend: Sendable, Equatable {
        /// Top set per session, newest last (oldest first).
        public let topSets: [TopSet]
        /// Span in completed-weeks between the first and last top set.
        /// 0 when only one session (or the entire span fits in one
        /// week).
        public let weeks: Int
        /// Delta in kg from first to last top set. Positive = up,
        /// negative = down, zero = flat.
        public let deltaKg: Double

        /// Human-readable arrow + delta + weeks: "↑ 12.5 KG / 12 WK".
        /// Nil when there's nothing to show (zero or one session).
        public let displayString: String?

        public init(
            topSets: [TopSet],
            weeks: Int,
            deltaKg: Double,
            displayString: String?
        ) {
            self.topSets = topSets
            self.weeks = weeks
            self.deltaKg = deltaKg
            self.displayString = displayString
        }
    }

    /// Compute the trend summary from a set of set_logs.
    ///
    /// - Parameters:
    ///   - setLogs: All set_logs for the exercise (order unimportant).
    ///   - calendar: Injected for testability — tests pin UTC so the
    ///     "same session?" grouping is deterministic.
    public static func compute(
        setLogs: [SetLog],
        calendar: Calendar = .current
    ) -> Trend {
        let topByDay = topSetsByDay(setLogs: setLogs, calendar: calendar)
        guard topByDay.count >= 2,
              let first = topByDay.first,
              let last = topByDay.last else {
            // Still include the single data point if we have one — the
            // view renders the recent-sessions list either way; the
            // trend line just doesn't show.
            return Trend(
                topSets: topByDay,
                weeks: 0,
                deltaKg: 0,
                displayString: nil
            )
        }
        let delta = last.weightKg - first.weightKg
        let weeks = weeksBetween(first.date, last.date, calendar: calendar)
        let display = formatTrend(deltaKg: delta, weeks: weeks)
        return Trend(topSets: topByDay, weeks: weeks, deltaKg: delta, displayString: display)
    }

    /// Bucket the set_logs by calendar day, pick the top set per day,
    /// return chronologically (oldest first).
    static func topSetsByDay(
        setLogs: [SetLog],
        calendar: Calendar
    ) -> [TopSet] {
        var best: [Date: (weight: Double, reps: Int, at: Date)] = [:]
        for log in setLogs {
            guard let weight = log.weight, let reps = log.reps else { continue }
            let day = calendar.startOfDay(for: log.completedAt)
            if let current = best[day] {
                if weight > current.weight
                    || (weight == current.weight && reps > current.reps) {
                    best[day] = (weight, reps, log.completedAt)
                }
            } else {
                best[day] = (weight, reps, log.completedAt)
            }
        }
        return best
            .map { _, value in
                TopSet(date: value.at, weightKg: value.weight, reps: value.reps)
            }
            .sorted { $0.date < $1.date }
    }

    /// Completed weeks between two dates, rounded down. Minimum 0.
    static func weeksBetween(
        _ first: Date,
        _ last: Date,
        calendar: Calendar
    ) -> Int {
        let comps = calendar.dateComponents([.weekOfYear], from: first, to: last)
        return max(0, comps.weekOfYear ?? 0)
    }

    /// "↑ 12.5 KG / 12 WK" / "↓ 2.5 KG / 4 WK" / "→ 0 KG / 3 WK".
    static func formatTrend(deltaKg: Double, weeks: Int) -> String {
        let arrow: String
        let magnitude: Double
        if deltaKg > 0 {
            arrow = "↑"
            magnitude = deltaKg
        } else if deltaKg < 0 {
            arrow = "↓"
            magnitude = -deltaKg
        } else {
            arrow = "→"
            magnitude = 0
        }
        let weekPart = weeks == 1 ? "1 WK" : "\(weeks) WK"
        return "\(arrow) \(formatKilograms(magnitude)) KG / \(weekPart)"
    }
}
