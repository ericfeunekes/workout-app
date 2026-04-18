// TodayLoader.swift
//
// Assembles a `TodayContext` by querying `Persistence.WorkoutCache` for
// today's planned workout. Selection rule is "the planned workout with
// the scheduled_date closest to today, preferring today-or-past over
// future" — matches the single-user "there's one workout in flight"
// assumption from the architecture doc.
//
// `lastPerformed` and `lastSessionSummary` are placeholders here — the
// history store to pull them from doesn't exist yet (no set_log query
// API on the cache). The loader takes pre-computed values via init so
// the app shell can drive seeding while history lands in a later slice.

import Foundation
import CoreDomain
import CoreSession
import Persistence
import WorkoutCoreFoundation

public struct TodayLoader: Sendable {

    /// The upstream cache — protocol-typed so tests can hand in a fake.
    private let cache: WorkoutCache

    /// Inject "now" so tests are deterministic without date-freezing.
    private let clock: @Sendable () -> Date

    public init(
        cache: WorkoutCache,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cache = cache
        self.clock = clock
    }

    /// Produce the Today context, or `nil` when no planned workout is
    /// cached. Callers render a "no workout scheduled" state in that
    /// case — out of scope for this slice.
    ///
    /// `lastPerformed` and `lastSessionSummary` are pass-throughs until
    /// the history query API lands.
    public func load(
        lastPerformed: [UUID: String] = [:],
        lastSessionSummary: String? = nil,
        programTags: [String] = [],
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)? = nil
    ) async throws -> TodayContext? {
        let planned = try await cache.loadWorkouts(status: .planned, since: nil)
        guard let workout = Self.pickClosest(to: clock(), from: planned) else {
            return nil
        }

        let blocks = try await cache.loadBlocks(workoutID: workout.id)

        var items: [WorkoutItem] = []
        for block in blocks {
            let blockItems = try await cache.loadItems(blockID: block.id)
            items.append(contentsOf: blockItems)
        }

        let exerciseIDs = Set(items.map(\.exerciseID))
        let catalog = try await cache.loadExercises()
        let exercises = Dictionary(
            uniqueKeysWithValues: catalog
                .filter { exerciseIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        return TodayContext(
            workout: workout,
            blocks: blocks,
            items: items,
            exercises: exercises,
            lastPerformed: lastPerformed,
            lastSessionSummary: lastSessionSummary,
            programTags: programTags,
            sessionStateBinding: sessionStateBinding
        )
    }

    // MARK: - Selection

    /// Prefer the planned workout whose `scheduledDate` is closest to
    /// `now`, with today-or-past ranked ahead of the future. Workouts
    /// without a scheduled_date sort last — they're rarely the "today"
    /// one. Visible for testing.
    static func pickClosest(to now: Date, from workouts: [Workout]) -> Workout? {
        let withDates = workouts.compactMap { w -> (Workout, Date)? in
            guard let d = w.scheduledDate else { return nil }
            return (w, d)
        }
        let sortedByProximity = withDates.sorted { a, b in
            // past-or-today (dt <= 0) ranks ahead of future (dt > 0);
            // within each group, smaller absolute distance wins.
            let da = a.1.timeIntervalSince(now)
            let db = b.1.timeIntervalSince(now)
            let aPast = da <= 0
            let bPast = db <= 0
            if aPast != bPast { return aPast }       // past-or-today first
            return abs(da) < abs(db)
        }
        return sortedByProximity.first?.0 ?? workouts.first
    }
}
