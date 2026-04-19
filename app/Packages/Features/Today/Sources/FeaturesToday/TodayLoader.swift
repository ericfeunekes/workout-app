// TodayLoader.swift
//
// Assembles a `TodayContext` by querying `Persistence.WorkoutCache` for
// today's planned workout. Selection rule is "the planned workout with
// the scheduled_date closest to today, preferring today-or-past over
// future" — matches the single-user "there's one workout in flight"
// assumption from the architecture doc.
//
// `lastPerformed` is sourced from `LastPerformedStore` (populated by
// Shell after each pull per ADR-2026-04-17-ux-scope § 3 — the server
// piggybacks the per-exercise snapshot on `GET /api/sync/pull`). The
// store is optional-injected so callers that don't have it (tests,
// previews) get an empty map and the chip simply hides. The
// `lastSessionSummary` remains a pass-through until a dedicated
// summariser lands.

import Foundation
import CoreDomain
import CoreSession
import Persistence
import WorkoutCoreFoundation

public struct TodayLoader: Sendable {

    /// The upstream cache — protocol-typed so tests can hand in a fake.
    private let cache: WorkoutCache

    /// Injected "LAST · …" chip store. Optional so tests / previews that
    /// don't care about the chip can skip wiring it — `load` then treats
    /// the map as empty and the UI hides the chip.
    private let lastPerformedStore: LastPerformedStore?

    /// Inject "now" so tests are deterministic without date-freezing.
    private let clock: @Sendable () -> Date

    public init(
        cache: WorkoutCache,
        lastPerformedStore: LastPerformedStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cache = cache
        self.lastPerformedStore = lastPerformedStore
        self.clock = clock
    }

    /// Produce the Today context, or `nil` when no planned workout is
    /// cached. Callers render a "no workout scheduled" state in that
    /// case — out of scope for this slice.
    ///
    /// `lastPerformed` is read from the injected `LastPerformedStore`
    /// when present; callers may still pass an explicit override to
    /// force a specific map (tests, previews). `lastSessionSummary` is
    /// a pass-through until a dedicated summariser lands.
    public func load(
        lastPerformed: [UUID: String]? = nil,
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

        // Resolve `lastPerformed`: caller override wins (tests, previews
        // that want determinism); otherwise read the pulled snapshot
        // from the store. No store + no override ⇒ empty map, chip hides.
        let resolvedLastPerformed: [UUID: String]
        if let override = lastPerformed {
            resolvedLastPerformed = override
        } else if let store = lastPerformedStore {
            resolvedLastPerformed = await store.load()
        } else {
            resolvedLastPerformed = [:]
        }

        return TodayContext(
            workout: workout,
            blocks: blocks,
            items: items,
            exercises: exercises,
            lastPerformed: resolvedLastPerformed,
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
