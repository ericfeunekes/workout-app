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
        // Direct predicate on the denormalized `workoutID` column (R1.4
        // SetLog denormalization — see `SwiftDataModels.swift`). This
        // path survives reconcile: a SetLog whose parent WorkoutItem
        // was deleted by a server-side plan edit still carries its
        // original `workoutID` and stays visible to History, which is
        // the whole reason we added the column. Pre-R1.4 the query
        // walked blocks → items → logs and silently dropped orphans.
        var descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.workoutID == workoutID }
        )
        // Stable UI order: by the parent WorkoutItem's position (when the
        // item still exists) then by `setIndex`. We resolve the positions
        // with a single items fetch scoped to the workout's blocks — the
        // ordering is a best-effort UI concern, so a reconciled-away item
        // falls through to `Int.max` and sorts after extant items, which
        // matches the "show the live plan then the orphaned history"
        // intent.
        descriptor.sortBy = [SortDescriptor(\SetLogModel.setIndex)]
        let rows = try modelContext.fetch(descriptor)
        guard !rows.isEmpty else { return [] }

        let positionByItem = try itemPositions(workoutID: workoutID)
        let ordered = rows.sorted { a, b in
            let pa = positionByItem[a.workoutItemID] ?? Int.max
            let pb = positionByItem[b.workoutItemID] ?? Int.max
            if pa != pb { return pa < pb }
            return a.setIndex < b.setIndex
        }
        return ordered.map { $0.toDomain() }
    }

    public func loadOrphanedSetLogs() async throws -> [SetLog] {
        // Rows the V2→V3 backfill (and every subsequent open-time
        // pass) could not map to a surviving WorkoutItem: their
        // original parent item was reconciled away under the R1.3
        // detach path BEFORE the V3 upgrade shipped, so neither the
        // block→item walk nor the new map scan can resolve the chain.
        // We never invent a workoutID for these — they stay nil on
        // disk and this API is the only way to surface them to the
        // UI. Local set_logs are authoritative client data; silently
        // hiding them would violate the one invariant `CLAUDE.md`
        // names as load-bearing.
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.workoutID == nil }
        )
        let rows = try modelContext.fetch(descriptor)
        let ordered = rows.sorted { $0.completedAt > $1.completedAt }
        return ordered.map { $0.toDomain() }
    }

    public func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        guard limit > 0 else { return [] }

        // Direct predicate against the denormalized `plannedExerciseID`
        // (set to the parent WorkoutItem's `exerciseID` at log time) or
        // `performedExerciseID` (the swap target when the user mid-
        // workout swapped). Both columns live on SetLog itself, so this
        // query no longer needs a WorkoutItem fetch and survives the
        // case where the parent item was reconciled away — the hole
        // the R1.4 fix-it exists to close.
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { log in
                log.plannedExerciseID == exerciseID
                    || log.performedExerciseID == exerciseID
            }
        )
        let rows = try modelContext.fetch(descriptor)
        // Sort newest first, cap at limit. Pre-R1.4 the query also had
        // to de-dupe between two passes; with a single predicate the
        // two sources can't double-count a row, so no de-dupe needed.
        let ordered = rows.sorted { $0.completedAt > $1.completedAt }
        return ordered.prefix(limit).map { $0.toDomain() }
    }

    public func saveSetLogs(_ setLogs: [SetLog], workoutID: WorkoutID) async throws {
        // Explicit do/catch/rollback per the SwiftData caveat documented in
        // docs/architecture/hotspots.md § "SwiftData `ModelContext.transaction`
        // does not roll back on throw (iOS 17.x)". Using `transaction { }`
        // here would silently leak partial inserts into the context — the
        // same bug that was fixed in `save(_:)`. Both mutators MUST use the
        // explicit pattern; tested by WorkoutCacheTests.
        do {
            for log in setLogs {
                try upsertSetLog(log, workoutID: workoutID)
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
        // row without building a full `PulledDataset`. Builds a one-row
        // preload so the upsert helper's dictionary contract is satisfied.
        do {
            let preload = try preloadModels(for: PulledDataset(workouts: [workout]))
            try upsertWorkout(workout, preload: preload)
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
            let preload = try preloadModels(for: PulledDataset(userParameters: [param]))
            try upsertUserParameter(param, preload: preload)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Internal helpers

    /// Build an `itemID -> block.position * 10000 + item.position` map
    /// scoped to one workout, used by `loadSetLogs(workoutID:)` to sort
    /// logs into block-then-item order for stable UI rendering. The
    /// composite key is just a compact way to encode the two-axis sort
    /// in a single `Int` — the exact magnitude doesn't matter, only
    /// that later blocks / items dominate earlier ones.
    private func itemPositions(workoutID: UUID) throws -> [UUID: Int] {
        let blocksDescriptor = FetchDescriptor<BlockModel>(
            predicate: #Predicate<BlockModel> { $0.workoutID == workoutID }
        )
        let blocks = try modelContext.fetch(blocksDescriptor)
        guard !blocks.isEmpty else { return [:] }
        let blockPosition = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.position) })

        var out: [UUID: Int] = [:]
        for block in blocks {
            let blockID = block.id
            let itemsDescriptor = FetchDescriptor<WorkoutItemModel>(
                predicate: #Predicate<WorkoutItemModel> { $0.blockID == blockID }
            )
            let items = try modelContext.fetch(itemsDescriptor)
            for item in items {
                let bp = blockPosition[item.blockID] ?? 0
                out[item.id] = bp * 10_000 + item.position
            }
        }
        return out
    }

    private func upsertSetLog(_ s: SetLog, workoutID: UUID) throws {
        let id = s.id
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.id == id }
        )
        // Resolve `plannedExerciseID` from the parent WorkoutItem so
        // History's exerciseID query can bypass a WorkoutItem fetch
        // even after reconcile removes the item. This runs once per
        // insert (not per edit) — `apply(_:)` intentionally leaves
        // the denormalized columns alone.
        let itemID = s.workoutItemID
        let parentItem = try modelContext.fetch(
            FetchDescriptor<WorkoutItemModel>(
                predicate: #Predicate<WorkoutItemModel> { $0.id == itemID }
            )
        ).first
        let plannedExerciseID = parentItem?.exerciseID

        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(s)
            // Stamp the denormalized columns if they're missing — this
            // is the in-actor equivalent of the V2→V3 backfill, for
            // rows that shipped before R1.4 landed. Preserves any
            // value that was already populated.
            if existing.workoutID == nil {
                existing.workoutID = workoutID
            }
            if existing.plannedExerciseID == nil, let planned = plannedExerciseID {
                existing.plannedExerciseID = planned
            }
            if let parent = parentItem {
                existing.workoutItem = parent
            }
        } else {
            let model = SetLogModel.from(
                s,
                workoutID: workoutID,
                plannedExerciseID: plannedExerciseID
            )
            modelContext.insert(model)
            if let parent = parentItem {
                model.workoutItem = parent
            }
        }
    }
}
