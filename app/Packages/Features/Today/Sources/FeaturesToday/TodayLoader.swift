// TodayLoader.swift
//
// Assembles Today read models by querying `Persistence.WorkoutCache`.
// `load()` preserves the execution contract: select one planned workout
// for the active `ExecutionViewModel`. `loadPlan()` adds the read-side
// plan queue around that selected workout so Today can expose missed,
// today, and upcoming plans without making the app a plan editor.
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
        let primitiveWorkouts = try await cache.loadPrimitiveWorkouts()
        let primitiveWorkout = primitiveWorkouts.first { $0.id == workout.id }
        let userParameters = try await numericUserParameters()
        let primitivePlan = try primitiveWorkout.map {
            try ExecutionPlan.validated(workout: $0, userParameters: userParameters)
        }

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
            primitiveWorkout: primitiveWorkout,
            primitiveExecutionPlan: primitivePlan,
            blocks: blocks,
            items: items,
            exercises: exercises,
            lastPerformed: resolvedLastPerformed,
            lastSessionSummary: lastSessionSummary,
            programTags: programTags,
            userParameters: userParameters,
            sessionStateBinding: sessionStateBinding
        )
    }

    /// Produce the read-side plan queue plus the one selected workout
    /// that remains wired for execution. This is intentionally a superset
    /// of `load()`: the app can show missed/upcoming workouts without
    /// mutating prescriptions or switching the execution VM.
    public func loadPlan(
        lastPerformed: [UUID: String]? = nil,
        lastSessionSummary: String? = nil,
        programTags: [String] = [],
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)? = nil
    ) async throws -> TodayPlanContext? {
        let planned = try await cache.loadWorkouts(status: .planned, since: nil)
        let now = clock()
        guard let selectedWorkout = Self.pickClosest(to: now, from: planned) else {
            return nil
        }

        let orderedWorkouts = Self.sortPlanQueue(to: now, workouts: planned)
        let primitiveWorkouts = try await cache.loadPrimitiveWorkouts()
        let userParameters = try await numericUserParameters()
        let contexts = try await contextsForWorkouts(
            orderedWorkouts,
            selectedWorkoutID: selectedWorkout.id,
            primitiveWorkouts: primitiveWorkouts,
            userParameters: userParameters,
            lastPerformed: lastPerformed,
            lastSessionSummary: lastSessionSummary,
            programTags: programTags,
            sessionStateBinding: sessionStateBinding
        )
        guard let selected = contexts.first(where: { $0.workout.id == selectedWorkout.id }) else {
            return nil
        }
        return TodayPlanContext(selected: selected, workouts: contexts)
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

    /// Sort for the plan queue: missed/today first, nearest to now first,
    /// then upcoming in chronological order. Workouts without a
    /// `scheduledDate` fall to the end.
    static func sortPlanQueue(to now: Date, workouts: [Workout]) -> [Workout] {
        workouts.sorted { lhs, rhs in
            switch (lhs.scheduledDate, rhs.scheduledDate) {
            case (.some(let lDate), .some(let rDate)):
                let lPast = lDate.timeIntervalSince(now) <= 0
                let rPast = rDate.timeIntervalSince(now) <= 0
                if lPast != rPast { return lPast }
                if lPast {
                    return abs(lDate.timeIntervalSince(now)) < abs(rDate.timeIntervalSince(now))
                }
                return lDate < rDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private func contextsForWorkouts(
        _ workouts: [Workout],
        selectedWorkoutID: WorkoutID,
        primitiveWorkouts: [PrimitiveWorkout],
        userParameters: [String: Double],
        lastPerformed: [UUID: String]?,
        lastSessionSummary: String?,
        programTags: [String],
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)?
    ) async throws -> [TodayContext] {
        var blocksByWorkout: [WorkoutID: [Block]] = [:]
        var itemsByBlock: [BlockID: [WorkoutItem]] = [:]
        var exerciseIDs: Set<ExerciseID> = []

        for workout in workouts {
            let blocks = try await cache.loadBlocks(workoutID: workout.id)
            blocksByWorkout[workout.id] = blocks
            for block in blocks {
                let blockItems = try await cache.loadItems(blockID: block.id)
                itemsByBlock[block.id] = blockItems
                exerciseIDs.formUnion(blockItems.map(\.exerciseID))
            }
        }

        let catalog = try await cache.loadExercises()
        let exercises = Dictionary(
            uniqueKeysWithValues: catalog
                .filter { exerciseIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let resolvedLastPerformed = await resolveLastPerformed(lastPerformed)

        return try workouts.map { workout in
            let blocks = blocksByWorkout[workout.id] ?? []
            let items = blocks
                .sorted { $0.position < $1.position }
                .flatMap { itemsByBlock[$0.id] ?? [] }
            let primitiveWorkout = primitiveWorkouts.first { $0.id == workout.id }
            let primitivePlan = try primitiveWorkout.map {
                try ExecutionPlan.validated(workout: $0, userParameters: userParameters)
            }
            return TodayContext(
                workout: workout,
                primitiveWorkout: primitiveWorkout,
                primitiveExecutionPlan: primitivePlan,
                blocks: blocks,
                items: items,
                exercises: exercises,
                lastPerformed: resolvedLastPerformed,
                lastSessionSummary: workout.id == selectedWorkoutID ? lastSessionSummary : nil,
                programTags: programTags,
                userParameters: userParameters,
                sessionStateBinding: sessionStateBinding
            )
        }
    }

    private func resolveLastPerformed(_ override: [UUID: String]?) async -> [UUID: String] {
        if let override {
            return override
        } else if let store = lastPerformedStore {
            return await store.load()
        } else {
            return [:]
        }
    }

    private func numericUserParameters() async throws -> [String: Double] {
        let rawParams = try await cache.loadUserParametersLatest()
        var numeric: [String: Double] = [:]
        for (key, param) in rawParams {
            if let value = Double(param.value) {
                numeric[key] = value
            }
        }
        return numeric
    }
}
