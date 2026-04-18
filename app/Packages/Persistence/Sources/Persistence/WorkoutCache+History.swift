// WorkoutCache+History.swift
//
// History-side queries on `WorkoutCacheImpl`. Lives in an extension file so
// `WorkoutCache.swift` stays under SwiftLint's `type_body_length` cap and
// the reader can see "pull-side upserts vs history-side reads" by jumping
// between the two files.
//
// These queries power the Features/History tab:
//   • `loadCompletedWorkouts` — reverse-chrono list view
//   • `loadSetLogs(workoutID:)` — session detail view
//   • `loadSetLogs(exerciseID:limit:)` — by-exercise trend + recent sessions
//   • `saveSetLogs` — populated by Execution on workout complete
//
// Sort conventions (important for the History UI):
//   • completed workouts come out newest first by `completedAt` desc; rows
//     with `completedAt == nil` sort after the dated rows but still appear
//     (defensive — a completed row should always have the field populated
//     but we'd rather show them than hide them).
//   • per-workout set_logs come out in the same order the user logged them:
//     SetLog row order preserved by `workoutItem.position` then
//     `SetLog.setIndex`.
//   • per-exercise set_logs come out newest first by `completedAt` desc.

import Foundation
import SwiftData
import CoreDomain
import WorkoutCoreFoundation

extension WorkoutCacheImpl {

    public func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [Workout] {
        guard limit > 0 else { return [] }
        let completedRaw = WorkoutStatus.completed.rawValue
        var descriptor = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate<WorkoutModel> { $0.statusRaw == completedRaw }
        )
        // Primary sort: completedAt desc (newest first). Secondary:
        // scheduledDate desc as a tiebreaker for rows missing completedAt.
        descriptor.sortBy = [
            SortDescriptor(\WorkoutModel.completedAt, order: .reverse),
            SortDescriptor(\WorkoutModel.scheduledDate, order: .reverse),
        ]
        let rows = try modelContext.fetch(descriptor)
        let start = max(0, offset)
        guard start < rows.count else { return [] }
        let end = min(rows.count, start + limit)
        return rows[start..<end].map { $0.toDomain() }
    }

    public func loadSetLogs(workoutID: WorkoutID) async throws -> [SetLog] {
        // Fetch the workout's items, then for each item fetch its set_logs.
        // We deliberately avoid a cross-entity #Predicate join (SwiftData's
        // predicate language doesn't express "item.block.workoutID" well)
        // and do the two-step walk in-actor — still one transaction, one
        // actor hop from the caller's perspective.
        let blocks = try fetchBlocks(workoutID: workoutID)
        guard !blocks.isEmpty else { return [] }
        let blockIDs = Set(blocks.map(\.id))

        var itemRows: [WorkoutItemModel] = []
        for blockID in blockIDs {
            let itemsDescriptor = FetchDescriptor<WorkoutItemModel>(
                predicate: #Predicate<WorkoutItemModel> { $0.blockID == blockID }
            )
            itemRows.append(contentsOf: try modelContext.fetch(itemsDescriptor))
        }

        // Preserve block-then-item order for stable UI rendering.
        let blockPosition = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.position) })
        itemRows.sort { a, b in
            let pa = blockPosition[a.blockID] ?? Int.max
            let pb = blockPosition[b.blockID] ?? Int.max
            if pa != pb { return pa < pb }
            return a.position < b.position
        }

        var out: [SetLog] = []
        for item in itemRows {
            let itemID = item.id
            var logDescriptor = FetchDescriptor<SetLogModel>(
                predicate: #Predicate<SetLogModel> { $0.workoutItemID == itemID }
            )
            logDescriptor.sortBy = [SortDescriptor(\SetLogModel.setIndex)]
            let logs = try modelContext.fetch(logDescriptor)
            out.append(contentsOf: logs.map { $0.toDomain() })
        }
        return out
    }

    public func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        guard limit > 0 else { return [] }

        // Two sources: set_logs whose `performedExerciseID == exerciseID`
        // (mid-workout swaps), and set_logs whose underlying WorkoutItem has
        // `exerciseID == exerciseID` and no swap recorded. We union both.
        //
        // SwiftData predicates can't traverse the loose UUID link from
        // SetLog → WorkoutItem cleanly, so we resolve in two passes.
        let swapDescriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.performedExerciseID == exerciseID }
        )
        let swapRows = try modelContext.fetch(swapDescriptor)

        let itemDescriptor = FetchDescriptor<WorkoutItemModel>(
            predicate: #Predicate<WorkoutItemModel> { $0.exerciseID == exerciseID }
        )
        let itemRows = try modelContext.fetch(itemDescriptor)
        let itemIDs = Set(itemRows.map(\.id))

        var plannedRows: [SetLogModel] = []
        for itemID in itemIDs {
            let descriptor = FetchDescriptor<SetLogModel>(
                predicate: #Predicate<SetLogModel> {
                    $0.workoutItemID == itemID && $0.performedExerciseID == nil
                }
            )
            plannedRows.append(contentsOf: try modelContext.fetch(descriptor))
        }

        // Merge, de-dupe on id (a row can't match both passes but belt-and-
        // braces), sort newest first, cap at limit.
        var seen = Set<UUID>()
        var merged: [SetLogModel] = []
        for row in swapRows + plannedRows where !seen.contains(row.id) {
            seen.insert(row.id)
            merged.append(row)
        }
        merged.sort { $0.completedAt > $1.completedAt }
        return merged.prefix(limit).map { $0.toDomain() }
    }

    public func saveSetLogs(_ setLogs: [SetLog]) async throws {
        // Explicit do/catch/rollback per the SwiftData caveat documented in
        // docs/architecture/hotspots.md § "SwiftData `ModelContext.transaction`
        // does not roll back on throw (iOS 17.x)". Using `transaction { }`
        // here would silently leak partial inserts into the context — the
        // same bug that was fixed in `save(_:)`. Both mutators MUST use the
        // explicit pattern; tested by WorkoutCacheTests.
        do {
            for log in setLogs {
                try upsertSetLog(log)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func saveWorkout(_ workout: Workout) async throws {
        // Same explicit-rollback pattern as `saveSetLogs` — see comment there
        // for why we can't use `modelContext.transaction { ... }` on iOS 17.x.
        // Thin wrapper around the shared `upsertWorkout` helper so callers
        // (Execution on `save & done`) can write a single completed workout
        // row without building a full `PulledDataset`.
        do {
            try upsertWorkout(workout)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func saveUserParameter(_ param: UserParameter) async throws {
        // Same explicit-rollback pattern as `saveSetLogs` / `saveWorkout`.
        // Thin wrapper around the shared `upsertUserParameter` helper so
        // Execution can land a just-captured bodyweight in the local cache
        // without a full `PulledDataset`. `loadUserParametersLatest()`
        // reads it immediately; History and any other live reader see the
        // new row on their next load.
        do {
            try upsertUserParameter(param)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Internal helpers

    /// Fetch blocks for a workoutID as models (used by the history walk).
    /// Kept separate from `loadBlocks(workoutID:)` so we can work in the
    /// model space inside one transaction without round-tripping to
    /// `CoreDomain` just to re-wrap.
    private func fetchBlocks(workoutID: UUID) throws -> [BlockModel] {
        var descriptor = FetchDescriptor<BlockModel>(
            predicate: #Predicate<BlockModel> { $0.workoutID == workoutID }
        )
        descriptor.sortBy = [SortDescriptor(\BlockModel.position)]
        return try modelContext.fetch(descriptor)
    }

    private func upsertSetLog(_ s: SetLog) throws {
        let id = s.id
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(s)
            try attachSetLogToItem(existing, itemID: s.workoutItemID)
        } else {
            let model = SetLogModel.from(s)
            modelContext.insert(model)
            try attachSetLogToItem(model, itemID: s.workoutItemID)
        }
    }

    private func attachSetLogToItem(_ log: SetLogModel, itemID: UUID) throws {
        let descriptor = FetchDescriptor<WorkoutItemModel>(
            predicate: #Predicate<WorkoutItemModel> { $0.id == itemID }
        )
        if let parent = try modelContext.fetch(descriptor).first {
            log.workoutItem = parent
        }
    }
}
