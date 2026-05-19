// HistoryPreviewSeed.swift
//
// DEBUG-only seed. Feeds SwiftUI `#Preview`s with four completed
// workouts so the canvas shows realistic grouping without standing up a
// SwiftData store.
//
// The seed is hand-invented data — the values and names are reasonable
// but not pulled from a specific reference. Bench press and row sessions
// alternate across two weeks; one workout carries a note so the form-
// note dot renders.

#if DEBUG

import Foundation
import CoreDomain
import Persistence
import WorkoutCoreFoundation

public enum HistoryPreviewSeed {

    /// Build the preview cache handed to the root `HistoryView`.
    public static func makePreviewCache() -> WorkoutCache {
        SeedCache(seed: makeSeed())
    }

    /// The raw preview data. Exposed so tests can reuse the same
    /// fixture without importing the seed cache implementation.
    public static func makeSeed() -> PreviewSeed {
        let ids = CatalogIDs()
        let now = Date(timeIntervalSince1970: 1_713_100_000) // fixed for previews

        let specs: [SessionSpec] = [
            SessionSpec(name: "Push A", daysAgo: 0,
                        tags: ["push_day", "week_3"],
                        notes: "Bench grip felt narrow. Try standard width next time.",
                        primary: ids.benchID, secondary: ids.ohpID),
            SessionSpec(name: "Pull A", daysAgo: 2,
                        tags: ["pull_day", "week_3"], notes: nil,
                        primary: ids.rowID, secondary: ids.benchID),
            SessionSpec(name: "Legs A", daysAgo: 3,
                        tags: ["leg_day", "week_3"],
                        notes: "Knees cranky, slowed eccentric.",
                        primary: ids.squatID, secondary: ids.ohpID),
            SessionSpec(name: "Push A", daysAgo: 7,
                        tags: ["push_day", "week_2"], notes: nil,
                        primary: ids.benchID, secondary: ids.ohpID),
        ]

        let built = specs.map { spec in
            build(spec: spec, userID: ids.userID, now: now)
        }

        // Bodyweight sample lands inside the most-recent Push A session's
        // wall-clock window (`[firstSetStartedAt, completedAt + 2min]`, see
        // `HistoryViewModel.bodyweight(for:setLogs:history:)`). Without
        // this the Complete-screen BW chip never renders in SwiftUI
        // previews — `loadUserParameters("bodyweight_kg")` used to return
        // `[]`. The id is deterministic so the preview is stable across
        // canvas refreshes; source `.appLog` matches what
        // `ExecutionViewModel.enqueueBodyweight` writes in production.
        let pushASpec = specs[0]
        let pushAScheduled = now.addingTimeInterval(TimeInterval(-pushASpec.daysAgo * 86_400))
        let pushACompletedAt = pushAScheduled.addingTimeInterval(54 * 60)
        let bodyweight = UserParameter(
            id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb") ?? UUID(),
            userID: ids.userID,
            key: "bodyweight_kg",
            value: "80.5",
            updatedAt: pushACompletedAt,
            source: .appLog
        )

        return PreviewSeed(
            exercises: ids.exercises,
            workouts: built.map(\.workout),
            blocks: built.flatMap(\.blocks),
            items: built.flatMap(\.items),
            setLogs: built.flatMap(\.setLogs),
            primitiveSetLogs: Self.primitiveLogs(
                setLogs: built.flatMap(\.setLogs),
                items: built.flatMap(\.items),
                blocks: built.flatMap(\.blocks)
            ),
            userParameters: [bodyweight]
        )
    }

    /// Flat bag the cache adapter consumes.
    public struct PreviewSeed: Sendable {
        public let exercises: [Exercise]
        public let workouts: [Workout]
        public let blocks: [Block]
        public let items: [WorkoutItem]
        public let setLogs: [SetLog]
        public let primitiveSetLogs: [PrimitiveSetLog]
        public let userParameters: [UserParameter]

        public init(
            exercises: [Exercise],
            workouts: [Workout],
            blocks: [Block],
            items: [WorkoutItem],
            setLogs: [SetLog],
            primitiveSetLogs: [PrimitiveSetLog] = [],
            userParameters: [UserParameter] = []
        ) {
            self.exercises = exercises
            self.workouts = workouts
            self.blocks = blocks
            self.items = items
            self.setLogs = setLogs
            self.primitiveSetLogs = primitiveSetLogs
            self.userParameters = userParameters
        }
    }

    private static func primitiveLogs(
        setLogs: [SetLog],
        items: [WorkoutItem],
        blocks: [Block]
    ) -> [PrimitiveSetLog] {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let blockByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        return setLogs.compactMap { log in
            guard let item = itemByID[log.workoutItemID],
                  let block = blockByID[item.blockID] else {
                return nil
            }
            return PrimitiveSetLog(
                id: log.id,
                role: .slot,
                slotID: item.id,
                setID: item.id,
                blockID: block.id,
                workoutID: block.workoutID,
                plannedExerciseID: item.exerciseID,
                performedExerciseID: log.performedExerciseID,
                setIndex: log.setIndex,
                reps: log.reps,
                weight: log.weight,
                weightUnit: log.weightUnit,
                durationSec: log.durationSec,
                distanceM: log.distanceM,
                rir: log.rir,
                hrAvgBpm: log.hrAvgBpm,
                hrMaxBpm: log.hrMaxBpm,
                isWarmup: log.isWarmup,
                skipped: log.skipped,
                side: log.side,
                notes: log.notes,
                completedAt: log.completedAt
            )
        }
    }

    // MARK: - Session specs / IDs

    /// Stable exercise ids so the same exercise resolves across sessions.
    private struct CatalogIDs {
        let userID = UUID()
        let benchID = UUID()
        let rowID = UUID()
        let ohpID = UUID()
        let squatID = UUID()

        var exercises: [Exercise] {
            [
                Exercise(id: benchID, name: "Barbell Bench Press"),
                Exercise(id: rowID, name: "Barbell Row"),
                Exercise(id: ohpID, name: "Overhead Press"),
                Exercise(id: squatID, name: "Back Squat"),
            ]
        }
    }

    /// Declarative shape of a single completed session in the seed.
    private struct SessionSpec {
        let name: String
        let daysAgo: Int
        let tags: [String]
        let notes: String?
        let primary: UUID
        let secondary: UUID
    }

    /// The rows a session contributes. A small struct keeps us under the
    /// `large_tuple` lint cap.
    private struct SessionRows {
        let workout: Workout
        let blocks: [Block]
        let items: [WorkoutItem]
        let setLogs: [SetLog]
    }

    // MARK: - Builders

    private static func build(
        spec: SessionSpec,
        userID: UUID,
        now: Date
    ) -> SessionRows {
        let scheduledDate = now.addingTimeInterval(TimeInterval(-spec.daysAgo * 86_400))
        let completedAt = scheduledDate.addingTimeInterval(54 * 60)
        let ids = RowIDs()
        let workout = makeWorkout(
            id: ids.workoutID, userID: userID, spec: spec,
            scheduled: scheduledDate, completed: completedAt
        )
        let block = Block(
            id: ids.blockID, workoutID: ids.workoutID, parentBlockID: nil,
            position: 0, name: "main", timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        return SessionRows(
            workout: workout,
            blocks: [block],
            items: makeItems(ids: ids, spec: spec),
            setLogs: makeSetLogs(
                primaryItemID: ids.primaryItemID,
                secondaryItemID: ids.secondaryItemID,
                startedAt: scheduledDate
            )
        )
    }

    private struct RowIDs {
        let workoutID = UUID()
        let blockID = UUID()
        let primaryItemID = UUID()
        let secondaryItemID = UUID()
    }

    private static func makeWorkout(
        id: UUID,
        userID: UUID,
        spec: SessionSpec,
        scheduled: Date,
        completed: Date
    ) -> Workout {
        Workout(
            id: id, userID: userID, name: spec.name,
            scheduledDate: scheduled, status: .completed, source: .claude,
            notes: spec.notes,
            createdAt: scheduled,
            updatedAt: completed,
            completedAt: completed,
            tagsJSON: encodeTags(spec.tags)
        )
    }

    private static func makeItems(ids: RowIDs, spec: SessionSpec) -> [WorkoutItem] {
        [
            WorkoutItem(id: ids.primaryItemID, blockID: ids.blockID, position: 0,
                        exerciseID: spec.primary,
                        prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#),
            WorkoutItem(id: ids.secondaryItemID, blockID: ids.blockID, position: 1,
                        exerciseID: spec.secondary,
                        prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":52.5}"#),
        ]
    }

    // `encodeTags` + `makeSetLogs` live on `HistoryPreviewSeed+Builders.swift`
    // so the enum body stays under SwiftLint's `type_body_length` cap.
}

// MARK: - Seed cache

/// In-memory `WorkoutCache` adapter backed by the preview seed. All
/// methods are nominally async to match the protocol; none actually
/// await anything.
final class SeedCache: WorkoutCache, @unchecked Sendable {
    private let seed: HistoryPreviewSeed.PreviewSeed

    init(seed: HistoryPreviewSeed.PreviewSeed) {
        self.seed = seed
    }

    func save(_ dataset: PulledDataset) async throws {}

    func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout] {
        guard let status else { return seed.workouts }
        return seed.workouts.filter { $0.status == status }
    }

    func loadPrimitiveWorkouts() async throws -> [PrimitiveWorkout] { [] }

    func loadBlocks(workoutID: WorkoutID) async throws -> [Block] {
        seed.blocks.filter { $0.workoutID == workoutID }
    }

    func loadItems(blockID: BlockID) async throws -> [WorkoutItem] {
        seed.items.filter { $0.blockID == blockID }
    }

    func loadItems(
        workoutIDs: [WorkoutID]
    ) async throws -> [WorkoutID: [WorkoutItem]] {
        guard !workoutIDs.isEmpty else { return [:] }
        let wanted = Set(workoutIDs)
        let blocksByWorkout = Dictionary(
            grouping: seed.blocks.filter { wanted.contains($0.workoutID) }
        ) { $0.workoutID }
        var out: [WorkoutID: [WorkoutItem]] = [:]
        for (workoutID, blocks) in blocksByWorkout {
            let orderedBlocks = blocks.sorted { $0.position < $1.position }
            var items: [WorkoutItem] = []
            for block in orderedBlocks {
                let blockItems = seed.items
                    .filter { $0.blockID == block.id }
                    .sorted { $0.position < $1.position }
                items.append(contentsOf: blockItems)
            }
            if !items.isEmpty {
                out[workoutID] = items
            }
        }
        return out
    }

    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        []
    }

    func loadExercises() async throws -> [Exercise] {
        seed.exercises
    }

    func loadUserParametersLatest() async throws -> [String: UserParameter] {
        // History's BW chip reads `loadUserParameters(key:)`, not this
        // endpoint, but the protocol has both so the preview seed mirrors
        // what a real cache would return. Group by key, newest wins.
        var latest: [String: UserParameter] = [:]
        for row in seed.userParameters.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            latest[row.key] = row
        }
        return latest
    }

    func loadUserParameters(key: String) async throws -> [UserParameter] {
        // Newest-first ordering matches the real `WorkoutCache` — the
        // `bodyweight(for:setLogs:history:)` picker walks the list
        // front-to-back and stops at the first in-window match.
        seed.userParameters
            .filter { $0.key == key }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [Workout] {
        let completed = seed.workouts
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let start = max(0, offset)
        guard start < completed.count, limit > 0 else { return [] }
        let end = min(completed.count, start + limit)
        return Array(completed[start..<end])
    }

    func loadSetLogs(workoutID: WorkoutID) async throws -> [SetLog] {
        let itemIDs = Set(
            seed.items.filter { item in
                seed.blocks.contains {
                    $0.workoutID == workoutID && $0.id == item.blockID
                }
            }.map(\.id)
        )
        return seed.setLogs
            .filter { itemIDs.contains($0.workoutItemID) }
            .sorted { $0.setIndex < $1.setIndex }
    }

    func loadPrimitiveSetLogs(workoutID: WorkoutID) async throws -> [PrimitiveSetLog] {
        seed.primitiveSetLogs
            .filter { $0.workoutID == workoutID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    func loadPrimitiveSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [PrimitiveSetLog] {
        guard limit > 0 else { return [] }
        let matching = seed.primitiveSetLogs.filter { log in
            log.resultSemantics.isByExerciseEligible
                && ((log.performedExerciseID ?? log.plannedExerciseID) == exerciseID)
        }
        return Array(matching.sorted { $0.completedAt > $1.completedAt }.prefix(limit))
    }

    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        guard limit > 0 else { return [] }
        let itemIDs = Set(
            seed.items.filter { $0.exerciseID == exerciseID }.map(\.id)
        )
        let matching = seed.setLogs.filter { log in
            if log.performedExerciseID == exerciseID { return true }
            return log.performedExerciseID == nil
                && itemIDs.contains(log.workoutItemID)
        }
        return Array(
            matching.sorted { $0.completedAt > $1.completedAt }.prefix(limit)
        )
    }

    func loadOrphanedSetLogs() async throws -> [SetLog] { [] }

    func saveSetLogs(_ setLogs: [SetLog], workoutID: WorkoutID) async throws {}

    func savePrimitiveSetLogs(_ setLogs: [PrimitiveSetLog], workoutID: WorkoutID) async throws {}

    func resetWorkout(workoutID: WorkoutID) async throws {}

    func saveWorkout(_ workout: Workout) async throws {}

    func saveUserParameter(_ param: UserParameter) async throws {}

    func clear() async throws {}
}

#endif
