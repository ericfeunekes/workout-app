// TrendComputation.swift
//
// Pure helpers for the per-exercise trend indicator in the by-exercise
// view ("↑ 12.5 KG / 12 WK"). Takes a list of set_logs for one exercise
// across many sessions and returns a display string plus the underlying
// numbers so a future chart can reuse them.
//
// Approach:
//   • Group set_logs by session (`workoutItemID`) AND by weight unit.
//     Cross-unit comparisons are meaningless ("100 lb > 50 kg" —
//     numerically yes, but 100 lb ≈ 45 kg so the lb row is the lighter
//     one). The dominant unit wins: whichever unit accounts for more
//     data points drives the trend. Ties fall to kg — v0 is kg-only for
//     Eric's real data, so the tie-break prefers it. All other unit
//     rows are dropped from the trend series (they'd still show up in
//     the recent-sessions list via
//     `ExerciseDetailViewModel.buildRecentRows`, which is a separate
//     surface).
//   • For each session in the dominant unit, "top set" is the heaviest
//     logged weight. Ties on weight break by reps (higher reps wins).
//     Grouping on `workoutItemID` (rather than calendar day) is load-
//     bearing: two separate workouts on the same day that both include
//     the same exercise (e.g. a circuit + AMRAP on a modal day) must
//     register as two sessions, not one. Same rule as
//     `ExerciseDetailViewModel.buildRecentRows`. bug qa-006.
//   • Produce a simple total delta: (last top weight) - (first top weight).
//     Not a regression — the design reference shows a one-number
//     indicator, not a slope. If the two endpoints are the same, the
//     arrow flattens (→) and delta is 0. Same-day sessions produce a
//     0-week span → "→ 0 KG / 0 WK", which matches the flat-delta
//     rendering the spec already defines (history.md S7).
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
        /// Weight value in the session's native unit (not normalized).
        public let weight: Double
        public let unit: WeightUnit
        public let reps: Int

        public init(date: Date, weight: Double, unit: WeightUnit, reps: Int) {
            self.date = date
            self.weight = weight
            self.unit = unit
            self.reps = reps
        }
    }

    /// Output summary.
    public struct Trend: Sendable, Equatable {
        /// Top set per session in the dominant unit, newest last
        /// (oldest first). Sessions logged in the non-dominant unit are
        /// excluded.
        public let topSets: [TopSet]
        /// The unit that won the dominance tally. Nil when there's no
        /// data at all. Callers render the `displayString` — this field
        /// is surfaced so a future chart can label its axis.
        public let unit: WeightUnit?
        /// Span in completed-weeks between the first and last top set.
        /// 0 when only one session (or the entire span fits in one
        /// week).
        public let weeks: Int
        /// Delta from first to last top set, in `unit`'s scale. Positive
        /// = up, negative = down, zero = flat.
        public let delta: Double

        /// Human-readable arrow + delta + weeks: "↑ 12.5 KG / 12 WK".
        /// Nil when there's nothing to show (zero or one session in the
        /// dominant unit).
        public let displayString: String?

        public init(
            topSets: [TopSet],
            unit: WeightUnit?,
            weeks: Int,
            delta: Double,
            displayString: String?
        ) {
            self.topSets = topSets
            self.unit = unit
            self.weeks = weeks
            self.delta = delta
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
        let dominant = dominantUnit(setLogs: setLogs) ?? .kg
        let filteredLogs = setLogs.filter { effectiveUnit($0) == dominant }
        let topBySession = topSetsBySession(
            setLogs: filteredLogs,
            unit: dominant,
            calendar: calendar
        )
        guard topBySession.count >= 2,
              let first = topBySession.first,
              let last = topBySession.last else {
            // Still include the single data point if we have one — the
            // view renders the recent-sessions list either way; the
            // trend line just doesn't show.
            return Trend(
                topSets: topBySession,
                unit: topBySession.isEmpty ? nil : dominant,
                weeks: 0,
                delta: 0,
                displayString: nil
            )
        }
        let delta = last.weight - first.weight
        let weeks = weeksBetween(first.date, last.date, calendar: calendar)
        let display = formatTrend(delta: delta, unit: dominant, weeks: weeks)
        return Trend(
            topSets: topBySession,
            unit: dominant,
            weeks: weeks,
            delta: delta,
            displayString: display
        )
    }

    /// Pick the unit with the most set_logs. Kg wins ties — v0 is
    /// kg-only in practice, so on the edge case of equal counts the
    /// bias is toward the default. Returns nil when there are no logs
    /// (so the caller can collapse to empty trend without special-
    /// casing).
    static func dominantUnit(setLogs: [SetLog]) -> WeightUnit? {
        guard !setLogs.isEmpty else { return nil }
        var kg = 0
        var lb = 0
        for log in setLogs where log.weight != nil {
            switch effectiveUnit(log) {
            case .kg: kg += 1
            case .lb: lb += 1
            }
        }
        if kg == 0 && lb == 0 { return nil }
        return lb > kg ? .lb : .kg
    }

    /// Bucket the set_logs by session (`workoutItemID`), pick the top
    /// set per session, return chronologically (oldest first). All logs
    /// passed in are assumed to share the supplied `unit` —
    /// `compute(setLogs:)` filters before calling.
    ///
    /// Session key is `workoutItemID` — two workouts completed on the
    /// same calendar day have separate WorkoutItems for the same
    /// exercise (e.g. Burpee in a circuit block and Burpee in a later
    /// AMRAP block are two different items). Grouping by day would
    /// collapse them into one data point and drop the trend line per
    /// bug qa-006. This matches how `buildRecentRows` keys the
    /// recent-sessions list.
    ///
    /// `calendar` is kept in the signature for API stability / future
    /// per-day fallbacks, but is unused by the current implementation.
    static func topSetsBySession(
        setLogs: [SetLog],
        unit: WeightUnit,
        calendar: Calendar
    ) -> [TopSet] {
        _ = calendar
        var best: [UUID: (weight: Double, reps: Int, at: Date)] = [:]
        for log in setLogs {
            guard let weight = log.weight, let reps = log.reps else { continue }
            let key = log.workoutItemID
            if let current = best[key] {
                if weight > current.weight
                    || (weight == current.weight && reps > current.reps) {
                    best[key] = (weight, reps, log.completedAt)
                }
            } else {
                best[key] = (weight, reps, log.completedAt)
            }
        }
        return best
            .map { _, value in
                TopSet(date: value.at, weight: value.weight, unit: unit, reps: value.reps)
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

    /// "↑ 12.5 KG / 12 WK" / "↓ 2.5 LB / 4 WK" / "→ 0 KG / 3 WK".
    static func formatTrend(delta: Double, unit: WeightUnit, weeks: Int) -> String {
        let arrow: String
        let magnitude: Double
        if delta > 0 {
            arrow = "↑"
            magnitude = delta
        } else if delta < 0 {
            arrow = "↓"
            magnitude = -delta
        } else {
            arrow = "→"
            magnitude = 0
        }
        let weekPart = weeks == 1 ? "1 WK" : "\(weeks) WK"
        let unitLabel = unit == .kg ? "KG" : "LB"
        return "\(arrow) \(formatKilograms(magnitude)) \(unitLabel) / \(weekPart)"
    }

    /// Collapse `SetLog.weightUnit` (`nil` allowed for legacy rows) into
    /// a concrete unit. `nil` is treated as `.kg` — v0 is kg-only, so
    /// older rows without an explicit unit are kg by construction.
    private static func effectiveUnit(_ log: SetLog) -> WeightUnit {
        log.weightUnit ?? .kg
    }
}
