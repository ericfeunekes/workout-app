// SchemaMigrationTests.swift
//
// Proves that SwiftData stores written by older app builds open cleanly
// under the current schema and their rows round-trip. If this breaks, a
// real user's store is stranded and they lose access to their local
// set_logs — the one piece of client data we can't rebuild by re-pulling
// from the server.
//
// Covers:
//   • V1 → V3 — pre-006 store opens under the R1.4 schema. This is the
//     multi-hop case SwiftData's migration planner stitches together.
//   • V2 → V3 — post-006 store opens under R1.4 AND the SetLog
//     denormalization backfill resolves `workoutID` + `plannedExerciseID`
//     from the parent WorkoutItem → Block chain for rows that predate
//     the column.
//
// Strategy per test: spin up an on-disk ModelContainer scoped to the old
// version, insert a few rows via the shadow types, tear the container
// down, then reopen the same on-disk URL with a V3-configured container
// (migration plan runs on open). Read the rows back through the V3
// models and the backfill helper.

import XCTest
import SwiftData
import CoreDomain
import WorkoutCoreFoundation
@testable import Persistence

final class SchemaMigrationTests: XCTestCase {

    /// Shared on-disk URL for the test store. Set in `setUp`, cleared in
    /// `tearDown`. Optional rather than implicitly-unwrapped so SwiftLint's
    /// `implicitly_unwrapped_optional` rule stays happy — every read
    /// guards the unwrap.
    private var storeURL: URL?

    override func setUp() {
        super.setUp()
        let name = "WorkoutDBSchemaMigrationTest-\(UUID().uuidString).store"
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        removeStore()
    }

    override func tearDown() {
        removeStore()
        super.tearDown()
    }

    private func removeStore() {
        guard let url = storeURL else { return }
        // SwiftData writes a .store, .store-shm, .store-wal trio; remove
        // all three to ensure the next test starts clean.
        let fm = FileManager.default
        _ = try? fm.removeItem(at: url)
        for ext in ["store-shm", "store-wal"] {
            let side = url.deletingPathExtension().appendingPathExtension(ext)
            _ = try? fm.removeItem(at: side)
        }
    }

    // MARK: - Container factories

    /// Build a V1-only ModelContainer (no migration plan — V1 is the
    /// only known schema from that container's perspective). This simulates
    /// what a pre-006 app build would have installed on the device.
    private func makeV1Container(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Build a V2-only ModelContainer (no migration plan). Simulates a
    /// post-006, pre-R1.4 store.
    private func makeV2Container(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Build a V3 ModelContainer pointing at the same on-disk URL, with
    /// the full migration plan so the appropriate stage(s) fire at open.
    private func makeV3Container(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: WorkoutDBMigrationPlan.self,
            configurations: [configuration]
        )
    }

    // MARK: - Fixture IDs

    /// IDs chosen by the test so assertions can pin on them after
    /// migration. One row per table we care about.
    private struct FixtureIDs {
        let workoutID: UUID
        let blockID: UUID
        let itemID: UUID
        let exerciseID: UUID
        let userID: UUID
        let setLogID: UUID
        let baseDate: Date

        static func make() -> FixtureIDs {
            FixtureIDs(
                workoutID: UUID(),
                blockID: UUID(),
                itemID: UUID(),
                exerciseID: UUID(),
                userID: UUID(),
                setLogID: UUID(),
                baseDate: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
    }

    // MARK: - V1 fixture seeding

    private func seedV1Store(at url: URL, ids: FixtureIDs) throws {
        let v1Container = try makeV1Container(at: url)
        let context = ModelContext(v1Container)
        context.insert(makeV1Workout(ids: ids))
        context.insert(makeV1Block(ids: ids))
        context.insert(makeV1Item(ids: ids))
        context.insert(makeV1Exercise(ids: ids))
        try context.save()
    }

    private func makeV1Workout(ids: FixtureIDs) -> WorkoutDBSchemaV1.WorkoutModel {
        WorkoutDBSchemaV1.WorkoutModel(
            id: ids.workoutID,
            userID: ids.userID,
            name: "Pre-006 workout",
            scheduledDate: ids.baseDate,
            statusRaw: WorkoutStatus.planned.rawValue,
            sourceRaw: WorkoutSource.claude.rawValue,
            notes: nil,
            createdAt: ids.baseDate,
            updatedAt: ids.baseDate,
            completedAt: nil,
            tagsJSON: nil
        )
    }

    private func makeV1Block(ids: FixtureIDs) -> WorkoutDBSchemaV1.BlockModel {
        WorkoutDBSchemaV1.BlockModel(
            id: ids.blockID,
            workoutID: ids.workoutID,
            parentBlockID: nil,
            position: 0,
            name: "Main",
            timingModeRaw: TimingMode.straightSets.rawValue,
            timingConfigJSON: "{\"rest_between_sets_sec\":120}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
    }

    private func makeV1Item(ids: FixtureIDs) -> WorkoutDBSchemaV1.WorkoutItemModel {
        WorkoutDBSchemaV1.WorkoutItemModel(
            id: ids.itemID,
            blockID: ids.blockID,
            position: 0,
            exerciseID: ids.exerciseID,
            prescriptionJSON: "{\"sets\":5,\"reps\":5}"
        )
    }

    private func makeV1Exercise(ids: FixtureIDs) -> WorkoutDBSchemaV1.ExerciseModel {
        WorkoutDBSchemaV1.ExerciseModel(
            id: ids.exerciseID,
            name: "Back Squat",
            notes: "pre-006 row",
            demoURLString: nil
        )
    }

    // MARK: - V2 fixture seeding

    private func seedV2Store(at url: URL, ids: FixtureIDs) throws {
        let v2Container = try makeV2Container(at: url)
        let context = ModelContext(v2Container)
        context.insert(makeV2Workout(ids: ids))
        context.insert(makeV2Block(ids: ids))
        context.insert(makeV2Item(ids: ids))
        context.insert(makeV2Exercise(ids: ids))
        context.insert(makeV2SetLog(ids: ids))
        try context.save()
    }

    private func makeV2Workout(ids: FixtureIDs) -> WorkoutDBSchemaV2.WorkoutModel {
        WorkoutDBSchemaV2.WorkoutModel(
            id: ids.workoutID,
            userID: ids.userID,
            name: "Pre-R1.4 workout",
            scheduledDate: ids.baseDate,
            statusRaw: WorkoutStatus.completed.rawValue,
            sourceRaw: WorkoutSource.claude.rawValue,
            notes: nil,
            createdAt: ids.baseDate,
            updatedAt: ids.baseDate,
            completedAt: ids.baseDate.addingTimeInterval(3_600),
            tagsJSON: nil
        )
    }

    private func makeV2Block(ids: FixtureIDs) -> WorkoutDBSchemaV2.BlockModel {
        WorkoutDBSchemaV2.BlockModel(
            id: ids.blockID,
            workoutID: ids.workoutID,
            parentBlockID: nil,
            position: 0,
            name: "Main",
            timingModeRaw: TimingMode.straightSets.rawValue,
            timingConfigJSON: "{\"rest_between_sets_sec\":120}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
    }

    private func makeV2Item(ids: FixtureIDs) -> WorkoutDBSchemaV2.WorkoutItemModel {
        WorkoutDBSchemaV2.WorkoutItemModel(
            id: ids.itemID,
            blockID: ids.blockID,
            position: 0,
            exerciseID: ids.exerciseID,
            prescriptionJSON: "{\"sets\":5,\"reps\":5}",
            prescriptionJSONRaw: nil
        )
    }

    private func makeV2Exercise(ids: FixtureIDs) -> WorkoutDBSchemaV2.ExerciseModel {
        WorkoutDBSchemaV2.ExerciseModel(
            id: ids.exerciseID,
            name: "Back Squat",
            notes: "pre-R1.4 row",
            demoURLString: nil,
            defaultPrescriptionJSON: nil,
            defaultAlternativesJSON: nil
        )
    }

    private func makeV2SetLog(ids: FixtureIDs) -> WorkoutDBSchemaV2.SetLogModel {
        WorkoutDBSchemaV2.SetLogModel(
            id: ids.setLogID,
            workoutItemID: ids.itemID,
            performedExerciseID: nil,
            setIndex: 1,
            reps: 5,
            weight: 100.0,
            weightUnitRaw: "kg",
            durationSec: nil,
            distanceM: nil,
            rir: 2,
            isWarmup: false,
            startedAt: ids.baseDate,
            completedAt: ids.baseDate.addingTimeInterval(60),
            hrAvgBpm: nil,
            hrMaxBpm: nil,
            cadenceAvgSpm: nil,
            motionSamplesRef: nil,
            notes: nil
        )
    }

    // MARK: - V1 → V3 (multi-hop lightweight)

    @MainActor
    func testSchemaV3UpgradeFromV1Fixture() async throws {
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()

        // 1. Write a V1-shaped store to disk. Nested do-block so the
        //    container ref is released before we reopen the same URL.
        do {
            try seedV1Store(at: url, ids: ids)
        }

        // 2. Reopen as V3. The planner chains V1→V2 (lightweight) and
        //    V2→V3 (lightweight + backfill) automatically.
        let v3Container = try makeV3Container(at: url)
        let context = ModelContext(v3Container)

        // 3. Read back the Exercise row and confirm V1 data survived
        //    with the new-in-V2 fields defaulted to nil.
        let exercises = try context.fetch(FetchDescriptor<ExerciseModel>())
        XCTAssertEqual(exercises.count, 1, "V1 exercise row must survive V3 migration")
        let exercise = try XCTUnwrap(exercises.first)
        XCTAssertEqual(exercise.id, ids.exerciseID)
        XCTAssertEqual(exercise.name, "Back Squat")
        XCTAssertEqual(exercise.notes, "pre-006 row")
        XCTAssertNil(exercise.defaultPrescriptionJSON)
        XCTAssertNil(exercise.defaultAlternativesJSON)

        // 4. Same round-trip check for WorkoutItem and Workout.
        let items = try context.fetch(FetchDescriptor<WorkoutItemModel>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, ids.itemID)
        XCTAssertEqual(item.prescriptionJSON, "{\"sets\":5,\"reps\":5}")
        XCTAssertNil(item.prescriptionJSONRaw)

        let workouts = try context.fetch(FetchDescriptor<WorkoutModel>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.id, ids.workoutID)
        XCTAssertEqual(workouts.first?.name, "Pre-006 workout")
    }

    // MARK: - V2 → V3 backfill

    /// Seed a V2 store that mirrors what R1.3's detach-on-reconcile
    /// shipped: two workouts with one block and one item each, plus
    /// a SetLog pointing at `deletedItem` whose row is NOT inserted
    /// (simulating the case where the parent item was reconciled
    /// away BEFORE the V3 upgrade). The surviving item belongs to a
    /// *different* workout, so the backfill cannot guess the lost
    /// workout's ID from any row — the orphan stays orphan.
    private func seedV2StoreWithPreUpgradeOrphan(
        at url: URL,
        ids: FixtureIDs,
        orphanSetLogID: UUID,
        deletedItemID: UUID,
        extraSetLogID: UUID,
        secondItemID: UUID
    ) throws {
        let v2Container = try makeV2Container(at: url)
        let context = ModelContext(v2Container)

        // Workout A — the "surviving" workout. Its block + item are
        // both present; its extra SetLog (extraSetLogID) points at
        // `ids.itemID` which is inserted normally.
        context.insert(makeV2Workout(ids: ids))
        context.insert(makeV2Block(ids: ids))
        context.insert(makeV2Item(ids: ids))
        context.insert(makeV2Exercise(ids: ids))
        context.insert(makeV2SetLog(ids: ids))

        // Second SetLog in workout A pointing at a different item that
        // also survives — this proves backfill handles >1 SetLog per
        // workout and resolves both via the map scan.
        context.insert(
            WorkoutDBSchemaV2.WorkoutItemModel(
                id: secondItemID,
                blockID: ids.blockID,
                position: 1,
                exerciseID: ids.exerciseID,
                prescriptionJSON: "{\"sets\":3,\"reps\":8}",
                prescriptionJSONRaw: nil
            )
        )
        context.insert(
            WorkoutDBSchemaV2.SetLogModel(
                id: extraSetLogID,
                workoutItemID: secondItemID,
                performedExerciseID: nil,
                setIndex: 1,
                reps: 8,
                weight: 80.0,
                weightUnitRaw: "kg",
                durationSec: nil,
                distanceM: nil,
                rir: 2,
                isWarmup: false,
                startedAt: ids.baseDate,
                completedAt: ids.baseDate.addingTimeInterval(120),
                hrAvgBpm: nil,
                hrMaxBpm: nil,
                cadenceAvgSpm: nil,
                motionSamplesRef: nil,
                notes: nil
            )
        )

        // The "pre-upgrade orphan" SetLog. Its `workoutItemID` points
        // at `deletedItemID`, which is NOT inserted — simulating the
        // R1.3 detach path where reconcile removed the parent item
        // before V3 shipped. No surviving row can tell the backfill
        // which workout this log belonged to.
        context.insert(
            WorkoutDBSchemaV2.SetLogModel(
                id: orphanSetLogID,
                workoutItemID: deletedItemID,
                performedExerciseID: nil,
                setIndex: 1,
                reps: 5,
                weight: 60.0,
                weightUnitRaw: "kg",
                durationSec: nil,
                distanceM: nil,
                rir: 3,
                isWarmup: false,
                startedAt: ids.baseDate,
                completedAt: ids.baseDate.addingTimeInterval(30),
                hrAvgBpm: nil,
                hrMaxBpm: nil,
                cadenceAvgSpm: nil,
                motionSamplesRef: nil,
                notes: "pre-upgrade orphan"
            )
        )
        try context.save()
    }

    @MainActor
    func testV2toV3BackfillScansAllSurvivingItemsForMapping() async throws {
        // Proves the fix-it: pre-V3 orphaned SetLogs whose parent item is
        // gone leave `workoutID` nil (they're truly unresolvable), while
        // SetLogs whose parent item survives get `workoutID` populated in
        // ONE pass — the original backfill's per-log fetch that bailed on
        // the first missing item couldn't handle the orphan case at all.
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()
        let orphanSetLogID = UUID()
        let deletedItemID = UUID()
        let extraSetLogID = UUID()
        let secondItemID = UUID()

        do {
            try seedV2StoreWithPreUpgradeOrphan(
                at: url,
                ids: ids,
                orphanSetLogID: orphanSetLogID,
                deletedItemID: deletedItemID,
                extraSetLogID: extraSetLogID,
                secondItemID: secondItemID
            )
        }

        let v3Container = try makeV3Container(at: url)
        let context = ModelContext(v3Container)
        try backfillSetLogDenormalization(context: context)

        let setLogs = try context.fetch(FetchDescriptor<SetLogModel>())
        XCTAssertEqual(setLogs.count, 3, "All three SetLogs must survive V3 migration")
        let byID = Dictionary(uniqueKeysWithValues: setLogs.map { ($0.id, $0) })

        let firstSurvivor = try XCTUnwrap(byID[ids.setLogID])
        XCTAssertEqual(
            firstSurvivor.workoutID,
            ids.workoutID,
            "Backfill must populate workoutID for logs whose parent item survives"
        )
        XCTAssertEqual(firstSurvivor.plannedExerciseID, ids.exerciseID)

        let secondSurvivor = try XCTUnwrap(byID[extraSetLogID])
        XCTAssertEqual(
            secondSurvivor.workoutID,
            ids.workoutID,
            "Backfill must handle multiple SetLogs per workout in one scan"
        )
        XCTAssertEqual(secondSurvivor.plannedExerciseID, ids.exerciseID)

        let orphan = try XCTUnwrap(byID[orphanSetLogID])
        XCTAssertNil(
            orphan.workoutID,
            "Pre-upgrade orphan (parent item deleted before V3) must stay nil"
        )
        XCTAssertNil(
            orphan.plannedExerciseID,
            "Pre-upgrade orphan cannot resolve plannedExerciseID either"
        )
        XCTAssertEqual(
            orphan.workoutItemID,
            deletedItemID,
            "Orphan keeps its original workoutItemID for debug / recovery"
        )
    }

    @MainActor
    func testV2toV3UpgradeBackfillsSetLogDenormalization() async throws {
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()

        // 1. Seed a V2-shaped store with a SetLog whose denormalized
        //    columns (workoutID, plannedExerciseID) don't exist yet.
        do {
            try seedV2Store(at: url, ids: ids)
        }

        // 2. Reopen as V3. The V2→V3 lightweight stage adds the two
        //    nullable columns; the rows land with both nil until the
        //    backfill runs.
        let v3Container = try makeV3Container(at: url)
        let context = ModelContext(v3Container)

        // 3. Drive the backfill helper (the factory runs this once at
        //    open time; here we call it directly so the test owns the
        //    timing).
        try backfillSetLogDenormalization(context: context)

        // 4. The SetLog's denormalized columns must match the parent
        //    chain: workoutID = block.workoutID, plannedExerciseID =
        //    item.exerciseID.
        let setLogs = try context.fetch(FetchDescriptor<SetLogModel>())
        XCTAssertEqual(setLogs.count, 1, "V2 SetLog row must survive V3 migration")
        let setLog = try XCTUnwrap(setLogs.first)
        XCTAssertEqual(setLog.id, ids.setLogID)
        XCTAssertEqual(
            setLog.workoutID,
            ids.workoutID,
            "Backfill must resolve workoutID from block.workoutID"
        )
        XCTAssertEqual(
            setLog.plannedExerciseID,
            ids.exerciseID,
            "Backfill must resolve plannedExerciseID from item.exerciseID"
        )

        // 5. The public history query now surfaces the row via the
        //    denormalized column. SwiftData predicates on optional
        //    columns need the RHS to be the matching Optional shape,
        //    hence the explicit `UUID?` rebind.
        let expectedWorkoutID: UUID? = ids.workoutID
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.workoutID == expectedWorkoutID }
        )
        let byWorkoutID = try context.fetch(descriptor)
        XCTAssertEqual(byWorkoutID.count, 1)
        XCTAssertEqual(byWorkoutID.first?.id, ids.setLogID)
    }
}
