// WorkoutCache.swift
//
// On-device cache for pulled workouts / exercises / alternatives /
// user_parameters. The protocol is `Sendable`; the concrete actor holds a
// `ModelContext` bound to its own `ModelContainer` and performs UUID-keyed
// upserts inside the actor's serial executor.
//
// Upsert semantics — per `docs/sync.md` § "Pull protocol":
//   Pulling a row re-keys on UUID. A new row is inserted, an existing row is
//   updated in place (no delete + insert — we keep the @Model identity to
//   preserve any SwiftUI observers bound to it).
//
// What this cache does NOT do: merge set_logs. Set logs are the app's
// authoritative data; they come in via `SessionStore` / local writes and
// flow out via `PushQueue`. The cache is pull-only.

import Foundation
import SwiftData
import CoreDomain
import WorkoutCoreFoundation

/// Flat dataset of one complete `PullResult` ready to hand to the cache.
///
/// Motivation: `WorkoutCache.save` previously took six parallel arrays as
/// individual parameters, which tripped SwiftLint's `function_parameter_count`
/// rule and made call sites noisy. Grouping them into one value keeps the
/// save signature small and documents the "these arrays describe one pull"
/// invariant at the type level. The struct is naturally `Sendable` because
/// every field is a `Sendable` array of `Sendable` domain values.
public struct PulledDataset: Sendable {
    public var workouts: [Workout]
    public var blocks: [Block]
    public var items: [WorkoutItem]
    public var alternatives: [ExerciseAlternative]
    public var exercises: [Exercise]
    public var userParameters: [UserParameter]

    public init(
        workouts: [Workout] = [],
        blocks: [Block] = [],
        items: [WorkoutItem] = [],
        alternatives: [ExerciseAlternative] = [],
        exercises: [Exercise] = [],
        userParameters: [UserParameter] = []
    ) {
        self.workouts = workouts
        self.blocks = blocks
        self.items = items
        self.alternatives = alternatives
        self.exercises = exercises
        self.userParameters = userParameters
    }
}

public protocol WorkoutCache: Sendable {
    /// Upsert the full pulled shape. Idempotent on UUID. Callers (PullService
    /// consumers) pass everything they got; the cache overwrites in place.
    func save(_ dataset: PulledDataset) async throws

    /// Return workouts, optionally filtered by status and/or updated-since.
    func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout]

    /// All blocks for a given workout, in position order.
    func loadBlocks(workoutID: WorkoutID) async throws -> [Block]

    /// All items for a given block, in position order.
    func loadItems(blockID: BlockID) async throws -> [WorkoutItem]

    /// All alternatives for a given item.
    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative]

    /// Full exercise catalog.
    func loadExercises() async throws -> [Exercise]

    /// Latest user_parameter per key. Matches the server's
    /// `GET /api/user-parameters?latest=true` shape.
    func loadUserParametersLatest() async throws -> [String: UserParameter]

    /// Completed workouts in reverse-chronological order (newest first).
    /// Used by the History feature.
    ///
    /// Sort key is `completedAt` descending, falling back to `scheduledDate`
    /// when `completedAt` is nil (defensive — a completed row should always
    /// have `completedAt` populated, but we don't want a nil to drop the row
    /// out of the list entirely).
    ///
    /// `limit <= 0` returns an empty slice; a negative `offset` is clamped
    /// to 0. The cache does not paginate the server's full history — only
    /// what's already been pulled is visible here.
    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [Workout]

    /// All set_logs for a given workout, in (workoutItem position, set index)
    /// order. Returns `[]` when none are logged yet — a completed workout
    /// may have zero set_logs if every set was skipped.
    func loadSetLogs(workoutID: WorkoutID) async throws -> [SetLog]

    /// Recent set_logs that reference `exerciseID` — either as the planned
    /// `exerciseID` on the underlying `WorkoutItem`, or as a mid-workout
    /// swap captured in `performedExerciseID`. Sorted newest first by
    /// `completedAt`.
    ///
    /// `limit <= 0` returns empty. Callers trim further as needed (the
    /// by-exercise view currently shows ~10 recent rows).
    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog]

    /// Insert or upsert a batch of set_logs. Used by Execution on workout
    /// completion so the History feature can read them back without a
    /// round-trip to the server.
    ///
    /// Idempotent on `SetLog.id` — re-persisting the same set replaces in
    /// place (matches the cache's upsert-on-UUID contract).
    func saveSetLogs(_ setLogs: [SetLog]) async throws

    /// Upsert a single workout row. Used by Execution on `save & done`
    /// so the just-completed workout (with `status == .completed` and
    /// `completedAt` populated) lands in the local cache immediately —
    /// the History tab reads it without waiting for a subsequent server
    /// pull. Idempotent on `Workout.id`.
    func saveWorkout(_ workout: Workout) async throws

    /// Upsert a single `user_parameter` row. Used by Execution on
    /// `save & done` so a just-captured bodyweight (or other user-
    /// parameter) lands in the local cache immediately — readers that
    /// resolve latest-per-key see it without waiting for a subsequent
    /// server pull. Idempotent on `UserParameter.id`.
    func saveUserParameter(_ param: UserParameter) async throws

    /// Wipe everything — used by Settings → "clear local data".
    func clear() async throws
}

@ModelActor
public actor WorkoutCacheImpl: WorkoutCache {

    /// Upsert the full pulled dataset atomically. On any mid-loop throw
    /// we call `modelContext.rollback()` to drop every pending insert /
    /// edit made during this call, then rethrow — leaving both disk and
    /// the in-memory context clean.
    ///
    /// Why not `ModelContext.transaction { ... }`: that API's doc comment
    /// implies rollback-on-throw, but in iOS 17.x the contract is "save
    /// when the block exits normally; on throw, the pending changes stay
    /// attached to the context and the next successful save() flushes
    /// them." An explicit `rollback()` is the only way to get the
    /// all-or-nothing semantics we want for a pull.
    ///
    /// NOTE: rollback also discards any uncommitted changes made outside
    /// this function between the last save and this call. We accept that
    /// — pulls don't interleave with other writers on this actor (the
    /// `@ModelActor` bounds everything to one context per actor).
    public func save(_ dataset: PulledDataset) async throws {
        do {
            for w in dataset.workouts {
                try upsertWorkout(w)
            }
            for b in dataset.blocks {
                try upsertBlock(b)
            }
            for i in dataset.items {
                try upsertItem(i)
            }
            for a in dataset.alternatives {
                try upsertAlternative(a)
            }
            for e in dataset.exercises {
                try upsertExercise(e)
            }
            for p in dataset.userParameters {
                try upsertUserParameter(p)
            }
            try modelContext.save()
        } catch {
            // Discard everything staged in this call so a later save()
            // doesn't flush partial state.
            modelContext.rollback()
            throw error
        }
    }

    public func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout] {
        let statusRaw = status?.rawValue
        var descriptor = FetchDescriptor<WorkoutModel>()
        descriptor.sortBy = [SortDescriptor(\WorkoutModel.scheduledDate, order: .reverse)]
        if let statusRaw, let since {
            descriptor.predicate = #Predicate<WorkoutModel> { w in
                w.statusRaw == statusRaw && w.updatedAt >= since
            }
        } else if let statusRaw {
            descriptor.predicate = #Predicate<WorkoutModel> { w in
                w.statusRaw == statusRaw
            }
        } else if let since {
            descriptor.predicate = #Predicate<WorkoutModel> { w in
                w.updatedAt >= since
            }
        }
        let rows = try modelContext.fetch(descriptor)
        return rows.map { $0.toDomain() }
    }

    public func loadBlocks(workoutID: WorkoutID) async throws -> [Block] {
        var descriptor = FetchDescriptor<BlockModel>(
            predicate: #Predicate<BlockModel> { $0.workoutID == workoutID }
        )
        descriptor.sortBy = [SortDescriptor(\BlockModel.position)]
        let rows = try modelContext.fetch(descriptor)
        return rows.map { $0.toDomain() }
    }

    public func loadItems(blockID: BlockID) async throws -> [WorkoutItem] {
        var descriptor = FetchDescriptor<WorkoutItemModel>(
            predicate: #Predicate<WorkoutItemModel> { $0.blockID == blockID }
        )
        descriptor.sortBy = [SortDescriptor(\WorkoutItemModel.position)]
        let rows = try modelContext.fetch(descriptor)
        return rows.map { $0.toDomain() }
    }

    public func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        let descriptor = FetchDescriptor<ExerciseAlternativeModel>(
            predicate: #Predicate<ExerciseAlternativeModel> { $0.workoutItemID == workoutItemID }
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.map { $0.toDomain() }
    }

    public func loadExercises() async throws -> [Exercise] {
        var descriptor = FetchDescriptor<ExerciseModel>()
        descriptor.sortBy = [SortDescriptor(\ExerciseModel.name)]
        let rows = try modelContext.fetch(descriptor)
        return rows.map { $0.toDomain() }
    }

    public func loadUserParametersLatest() async throws -> [String: UserParameter] {
        // user_parameters is append-only on the server; locally we store
        // every row we pull. "Latest" means per-key max(updatedAt).
        let descriptor = FetchDescriptor<UserParameterModel>()
        let rows = try modelContext.fetch(descriptor)
        var latest: [String: UserParameterModel] = [:]
        for row in rows {
            if let existing = latest[row.key] {
                if row.updatedAt > existing.updatedAt {
                    latest[row.key] = row
                }
            } else {
                latest[row.key] = row
            }
        }
        return latest.mapValues { $0.toDomain() }
    }

    public func clear() async throws {
        try modelContext.delete(model: WorkoutModel.self)
        try modelContext.delete(model: BlockModel.self)
        try modelContext.delete(model: WorkoutItemModel.self)
        try modelContext.delete(model: ExerciseModel.self)
        try modelContext.delete(model: ExerciseAlternativeModel.self)
        try modelContext.delete(model: SetLogModel.self)
        try modelContext.delete(model: UserParameterModel.self)
        try modelContext.delete(model: AppUserModel.self)
        try modelContext.save()
    }

    // Per-entity upsert helpers live in `WorkoutCache+Upserts.swift` so
    // the actor body here stays under SwiftLint's `type_body_length` cap.

    // MARK: - Test hooks

    #if DEBUG
    /// Test-only: perform the same first-half of `save(_:)` (workout +
    /// exercise upserts), then throw to simulate a mid-loop failure, and
    /// run the same `rollback()` cleanup that `save(_:)` uses. Proves
    /// rollback is clean — nothing the failed batch touched ends up on
    /// disk OR stays staged for the next save().
    internal func saveThenThrowForTests(
        _ dataset: PulledDataset
    ) throws {
        struct TestAbort: Error {}
        do {
            for w in dataset.workouts {
                try upsertWorkout(w)
            }
            for e in dataset.exercises {
                try upsertExercise(e)
            }
            throw TestAbort()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
    #endif
}
