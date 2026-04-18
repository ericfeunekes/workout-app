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

        return PreviewSeed(
            exercises: ids.exercises,
            workouts: built.map(\.workout),
            blocks: built.flatMap(\.blocks),
            items: built.flatMap(\.items),
            setLogs: built.flatMap(\.setLogs)
        )
    }

    /// Flat bag the cache adapter consumes.
    public struct PreviewSeed: Sendable {
        public let exercises: [Exercise]
        public let workouts: [Workout]
        public let blocks: [Block]
        public let items: [WorkoutItem]
        public let setLogs: [SetLog]
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

    private static func encodeTags(_ tags: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(tags) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deterministic set_log timeline: 4 bench sets 3 minutes apart
    /// starting from `startedAt`, then 3 OHP sets 10 minutes later.
    private static func makeSetLogs(
        primaryItemID: UUID,
        secondaryItemID: UUID,
        startedAt: Date
    ) -> [SetLog] {
        var setLogs: [SetLog] = []
        for i in 0..<4 {
            let completedAt = startedAt.addingTimeInterval(TimeInterval(i * 180))
            setLogs.append(SetLog(
                id: UUID(), workoutItemID: primaryItemID,
                performedExerciseID: nil, setIndex: i,
                reps: i == 3 ? 4 : 5, weight: 100, weightUnit: .kg,
                rir: i == 2 ? 1 : 2, isWarmup: false,
                startedAt: completedAt.addingTimeInterval(-60),
                completedAt: completedAt,
                notes: nil
            ))
        }
        let ohpStart = startedAt.addingTimeInterval(TimeInterval(4 * 180 + 600))
        for i in 0..<3 {
            let completedAt = ohpStart.addingTimeInterval(TimeInterval(i * 150))
            setLogs.append(SetLog(
                id: UUID(), workoutItemID: secondaryItemID,
                performedExerciseID: nil, setIndex: i,
                reps: i == 2 ? 6 : 8, weight: 52.5, weightUnit: .kg,
                rir: 2, isWarmup: false,
                startedAt: completedAt.addingTimeInterval(-45),
                completedAt: completedAt,
                notes: nil
            ))
        }
        return setLogs
    }
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

    func loadBlocks(workoutID: WorkoutID) async throws -> [Block] {
        seed.blocks.filter { $0.workoutID == workoutID }
    }

    func loadItems(blockID: BlockID) async throws -> [WorkoutItem] {
        seed.items.filter { $0.blockID == blockID }
    }

    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        []
    }

    func loadExercises() async throws -> [Exercise] {
        seed.exercises
    }

    func loadUserParametersLatest() async throws -> [String: UserParameter] {
        [:]
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

    func saveSetLogs(_ setLogs: [SetLog]) async throws {}

    func saveWorkout(_ workout: Workout) async throws {}

    func saveUserParameter(_ param: UserParameter) async throws {}

    func clear() async throws {}
}

#endif
