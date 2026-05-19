// SchemaMigrationTests.swift
//
// Proves that SwiftData stores written by older app builds open cleanly
// under the current schema and their rows round-trip. If this breaks, a
// real user's store is stranded and they lose access to their local
// set_logs — the one piece of client data we can't rebuild by re-pulling
// from the server.
//
// Covers:
//   • V1 → V9 — pre-006 store opens under the current schema. The
//     planner chains V1→V2→V3→V4→V5→V6→V7→V8→V9 lightweight stages.
//   • V2 → V9 — post-006, pre-R1.4 store opens under V9 AND the SetLog
//     denormalization backfill resolves `workoutID` + `plannedExerciseID`
//     from the parent WorkoutItem → Block chain for rows that predate
//     the column.
//   • V3 → V9 — R1.4-era store opens under the current schema AND the
//     PushItem priority + dedupKey backfill populates the new columns
//     from each row's decoded envelope.
//   • V4 → V9 — perf-002-era store opens with skipped/side/intent defaults.
//   • V5 → V9 — the primitive-workout cache table is introduced without
//     stranding existing workout logs.
//   • V6 → V9 — the first-class primitive result table is introduced;
//     V6 QA primitive result data is intentionally reset.
//   • V7 → V9 — the HealthKit archive projection tables are introduced and
//     writable without stranding existing primitive cache/log rows.
//
// Strategy per test: spin up an on-disk ModelContainer scoped to the old
// version, insert a few rows via the shadow types, tear the container
// down, then reopen the same on-disk URL with the current configured
// container (migration plan runs on open). Read the rows back through the
// models and the backfill helper(s).

import XCTest
import SwiftData
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
import Sync
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

    /// Build a current ModelContainer pointing at the same on-disk URL, with
    /// the full migration plan so the appropriate stage(s) fire at open.
    /// V9 is the current runtime schema (per `SchemaVersions.swift`);
    /// older stores chain forward through the plan.
    private func makeCurrentContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV9.self)
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

        // 2. Reopen as V6 — the current runtime schema. The planner
        //    chains V1→V2→V3→V4→V5→V6 lightweight stages automatically.
        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

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

        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)
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

        // 2. Reopen as V6. The V2→V3 lightweight stage adds the two
        //    nullable columns; the rows land with both nil until the
        //    backfill runs.
        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

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

    // MARK: - V3 → V4 backfill (perf-002)

    /// Build a V3-only ModelContainer (no migration plan). Simulates an
    /// R1.4-era, pre-perf-002 store.
    private func makeV3OnlyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Build a V4-only ModelContainer (no migration plan). Simulates the
    /// perf-002 build immediately before the skipped/side/intent cutover.
    private func makeV4OnlyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Build a V5-only ModelContainer (no migration plan). Simulates the
    /// build immediately before the primitive workout cache table existed.
    private func makeV5OnlyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Build a V6-only ModelContainer (no migration plan). Simulates the
    /// primitive-workout-cache build before primitive logs became first-class.
    private func makeV6OnlyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Build a V7-only ModelContainer (no migration plan). Simulates the
    /// primitive-result-row build before HealthKit archive projection existed.
    private func makeV7OnlyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV7.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    /// Seed a V3-shaped store with three `PushItemModel` rows — one for
    /// each dedup class (single-log primitiveSetLog, statusUpdate, userParameter)
    /// — plus one batch setLog and one telemetry event to exercise the
    /// "no dedup key" side of the backfill. The rows are written via the
    /// V3 shadow type which has no `priority` or `dedupKey` columns, so
    /// the V4 migration must introduce them and the backfill must
    /// populate them from each row's encoded envelope.
    private func seedV3PushItemStore(
        at url: URL,
        singleLogEnvelope: Data,
        singleLogID: UUID,
        statusEnvelope: Data,
        statusID: UUID,
        userParamEnvelope: Data,
        userParamID: UUID,
        batchEnvelope: Data,
        batchID: UUID,
        eventsEnvelope: Data,
        eventsID: UUID,
        baseDate: Date
    ) throws {
        let container = try makeV3OnlyContainer(at: url)
        let context = ModelContext(container)
        context.insert(WorkoutDBSchemaV3.PushItemModel(
            id: singleLogID,
            enqueuedAt: baseDate.addingTimeInterval(1),
            attempts: 0,
            payloadJSON: singleLogEnvelope
        ))
        context.insert(WorkoutDBSchemaV3.PushItemModel(
            id: statusID,
            enqueuedAt: baseDate.addingTimeInterval(2),
            attempts: 0,
            payloadJSON: statusEnvelope
        ))
        context.insert(WorkoutDBSchemaV3.PushItemModel(
            id: userParamID,
            enqueuedAt: baseDate.addingTimeInterval(3),
            attempts: 0,
            payloadJSON: userParamEnvelope
        ))
        context.insert(WorkoutDBSchemaV3.PushItemModel(
            id: batchID,
            enqueuedAt: baseDate.addingTimeInterval(4),
            attempts: 0,
            payloadJSON: batchEnvelope
        ))
        context.insert(WorkoutDBSchemaV3.PushItemModel(
            id: eventsID,
            enqueuedAt: baseDate.addingTimeInterval(5),
            attempts: 0,
            payloadJSON: eventsEnvelope
        ))
        try context.save()
    }

    @MainActor
    func testV3toV4UpgradeBackfillsPushItemPriorityAndDedupKey() async throws {
        let url = try XCTUnwrap(storeURL)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Build the five envelopes via the real payload coder (the same
        // code that writes them at enqueue time). This is important:
        // the backfill decodes via the same coder, so a round-trip via
        // the public API is the tightest regression guard.
        let singleLogID = UUID()
        let singlePrimitiveSetLogID = UUID()
        let singleLog = CoreDomain.PrimitiveSetLog(
            id: singlePrimitiveSetLogID,
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: UUID(),
            plannedExerciseID: UUID(),
            performedExerciseID: nil,
            setIndex: 1,
            reps: 5,
            weight: 100,
            weightUnit: .lb,
            rir: 2,
            completedAt: baseDate
        )
        let singleLogEnvelope = try PushQueuePayloadCoding.encode(
            .primitiveSetLogs([singleLog])
        )

        let statusID = UUID()
        let statusWorkoutID = UUID()
        let statusEnvelope = try PushQueuePayloadCoding.encode(
            .statusUpdate(
                workoutID: statusWorkoutID,
                status: .completed,
                completedAt: baseDate,
                notes: nil
            )
        )

        let userParamID = UUID()
        let userParamLogicalID = UUID()
        let userParamEnvelope = try PushQueuePayloadCoding.encode(
            .userParameter(CoreDomain.UserParameter(
                id: userParamLogicalID,
                userID: UUID(),
                key: "bodyweight_lb",
                value: "185.0",
                updatedAt: baseDate,
                source: .appLog
            ))
        )

        let batchID = UUID()
        let batchEnvelope = try PushQueuePayloadCoding.encode(
            .primitiveSetLogs([
                CoreDomain.PrimitiveSetLog(
                    id: UUID(),
                    role: .slot,
                    slotID: UUID(),
                    setID: UUID(),
                    blockID: UUID(),
                    workoutID: UUID(),
                    plannedExerciseID: UUID(),
                    performedExerciseID: nil,
                    setIndex: 1,
                    reps: 5,
                    weight: 100,
                    weightUnit: .lb,
                    rir: 2,
                    completedAt: baseDate
                ),
                CoreDomain.PrimitiveSetLog(
                    id: UUID(),
                    role: .slot,
                    slotID: UUID(),
                    setID: UUID(),
                    blockID: UUID(),
                    workoutID: UUID(),
                    plannedExerciseID: UUID(),
                    performedExerciseID: nil,
                    setIndex: 2,
                    reps: 5,
                    weight: 100,
                    weightUnit: .lb,
                    rir: 2,
                    completedAt: baseDate
                ),
            ])
        )

        let eventsID = UUID()
        let eventsEnvelope = try PushQueuePayloadCoding.encode(
            .events([CoreTelemetry.Event(
                sessionID: UUID(), kind: "state", name: "ev"
            )])
        )

        // 1. Seed a V3-shaped store with no priority / dedupKey columns.
        do {
            try seedV3PushItemStore(
                at: url,
                singleLogEnvelope: singleLogEnvelope,
                singleLogID: singleLogID,
                statusEnvelope: statusEnvelope,
                statusID: statusID,
                userParamEnvelope: userParamEnvelope,
                userParamID: userParamID,
                batchEnvelope: batchEnvelope,
                batchID: batchID,
                eventsEnvelope: eventsEnvelope,
                eventsID: eventsID,
                baseDate: baseDate
            )
        }

        // 2. Reopen as V6. The V3→V4 lightweight stage adds the two
        //    columns with defaults (priority=0, dedupKey=nil); the
        //    backfill then rewrites them from each envelope.
        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

        // 3. Drive the backfill helper directly — same pattern as the
        //    V2→V3 test above. The factory runs this once at open time
        //    in production.
        try backfillPushItemPriorityAndDedupKey(context: context)

        // 4. Read every row back and assert priority + dedupKey.
        let rows = try context.fetch(FetchDescriptor<PushItemModel>())
        XCTAssertEqual(rows.count, 5, "All five V3 rows must survive V4 migration")
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        let single = try XCTUnwrap(byID[singleLogID])
        XCTAssertEqual(single.priority, 0, "single-log primitiveSetLog is a result (priority 0)")
        XCTAssertEqual(
            single.dedupKey,
            "primitiveSetLog:\(singlePrimitiveSetLogID.uuidString.lowercased())"
        )

        let status = try XCTUnwrap(byID[statusID])
        XCTAssertEqual(status.priority, 0, "statusUpdate is a result (priority 0)")
        XCTAssertEqual(
            status.dedupKey,
            "status:\(statusWorkoutID.uuidString.lowercased()):completed"
        )

        let userParam = try XCTUnwrap(byID[userParamID])
        XCTAssertEqual(userParam.priority, 0, "userParameter is a result (priority 0)")
        XCTAssertEqual(
            userParam.dedupKey,
            "userParam:\(userParamLogicalID.uuidString.lowercased())"
        )

        let batch = try XCTUnwrap(byID[batchID])
        XCTAssertEqual(batch.priority, 0, "batch primitiveSetLogs still priority 0 (result)")
        XCTAssertNil(batch.dedupKey, "batch primitiveSetLogs do not dedup — key stays nil")

        let events = try XCTUnwrap(byID[eventsID])
        XCTAssertEqual(events.priority, 1, "events are telemetry — priority 1")
        XCTAssertNil(events.dedupKey, "events do not dedup — key stays nil")
    }

    // MARK: - V4 → V5 skipped/side/intent defaults

    private func seedV4WorkoutAndSetLogStore(at url: URL, ids: FixtureIDs) throws {
        let container = try makeV4OnlyContainer(at: url)
        let context = ModelContext(container)
        context.insert(WorkoutDBSchemaV4.WorkoutModel(
            id: ids.workoutID,
            userID: ids.userID,
            name: "Pre-schema-2026-04-26 workout",
            scheduledDate: ids.baseDate,
            statusRaw: WorkoutStatus.completed.rawValue,
            sourceRaw: WorkoutSource.claude.rawValue,
            notes: nil,
            createdAt: ids.baseDate,
            updatedAt: ids.baseDate,
            completedAt: ids.baseDate.addingTimeInterval(3_600),
            tagsJSON: nil
        ))
        context.insert(WorkoutDBSchemaV4.BlockModel(
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
        ))
        context.insert(WorkoutDBSchemaV4.WorkoutItemModel(
            id: ids.itemID,
            blockID: ids.blockID,
            position: 0,
            exerciseID: ids.exerciseID,
            prescriptionJSON: "{\"sets\":5,\"reps\":5}",
            prescriptionJSONRaw: nil
        ))
        context.insert(WorkoutDBSchemaV4.ExerciseModel(
            id: ids.exerciseID,
            name: "Back Squat",
            notes: nil,
            demoURLString: nil,
            defaultPrescriptionJSON: nil,
            defaultAlternativesJSON: nil
        ))
        context.insert(WorkoutDBSchemaV4.SetLogModel(
            id: ids.setLogID,
            workoutItemID: ids.itemID,
            workoutID: ids.workoutID,
            plannedExerciseID: ids.exerciseID,
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
        ))
        try context.save()
    }

    @MainActor
    func testV4toV5UpgradeDefaultsSkippedSideAndIntent() async throws {
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()

        do {
            try seedV4WorkoutAndSetLogStore(at: url, ids: ids)
        }

        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

        let blocks = try context.fetch(FetchDescriptor<BlockModel>())
        XCTAssertEqual(blocks.count, 1, "V4 Block row must survive V5 migration")
        let block = try XCTUnwrap(blocks.first)
        XCTAssertEqual(block.id, ids.blockID)
        XCTAssertNil(block.intent, "Existing blocks default to no intent")

        let setLogs = try context.fetch(FetchDescriptor<SetLogModel>())
        XCTAssertEqual(setLogs.count, 1, "V4 SetLog row must survive V5 migration")
        let setLog = try XCTUnwrap(setLogs.first)
        XCTAssertEqual(setLog.id, ids.setLogID)
        XCTAssertFalse(setLog.skipped, "Existing logs default to non-skipped")
        XCTAssertEqual(setLog.sideRaw, SetLogSide.bilateral.rawValue)
    }

    // MARK: - V5 → V6 primitive workout cache

    private func seedV5WorkoutAndSetLogStore(at url: URL, ids: FixtureIDs) throws {
        let container = try makeV5OnlyContainer(at: url)
        let context = ModelContext(container)
        context.insert(WorkoutModel(
            id: ids.workoutID,
            userID: ids.userID,
            name: "Pre-primitive workout",
            scheduledDate: ids.baseDate,
            statusRaw: WorkoutStatus.completed.rawValue,
            sourceRaw: WorkoutSource.claude.rawValue,
            notes: nil,
            createdAt: ids.baseDate,
            updatedAt: ids.baseDate,
            completedAt: ids.baseDate.addingTimeInterval(3_600),
            tagsJSON: nil
        ))
        context.insert(BlockModel(
            id: ids.blockID,
            workoutID: ids.workoutID,
            parentBlockID: nil,
            position: 0,
            name: "Main",
            timingModeRaw: TimingMode.straightSets.rawValue,
            timingConfigJSON: "{\"rest_between_sets_sec\":120}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil,
            intent: nil
        ))
        context.insert(WorkoutItemModel(
            id: ids.itemID,
            blockID: ids.blockID,
            position: 0,
            exerciseID: ids.exerciseID,
            prescriptionJSON: "{\"sets\":5,\"reps\":5}",
            prescriptionJSONRaw: nil
        ))
        context.insert(ExerciseModel(
            id: ids.exerciseID,
            name: "Back Squat",
            notes: nil,
            demoURLString: nil,
            defaultPrescriptionJSON: nil,
            defaultAlternativesJSON: nil
        ))
        context.insert(SetLogModel(
            id: ids.setLogID,
            workoutItemID: ids.itemID,
            workoutID: ids.workoutID,
            plannedExerciseID: ids.exerciseID,
            performedExerciseID: nil,
            setIndex: 1,
            reps: 5,
            weight: 100.0,
            weightUnitRaw: "kg",
            durationSec: nil,
            distanceM: nil,
            rir: 2,
            isWarmup: false,
            skipped: false,
            sideRaw: SetLogSide.bilateral.rawValue,
            startedAt: ids.baseDate,
            completedAt: ids.baseDate.addingTimeInterval(60),
            hrAvgBpm: nil,
            hrMaxBpm: nil,
            cadenceAvgSpm: nil,
            motionSamplesRef: nil,
            notes: nil
        ))
        try context.save()
    }

    @MainActor
    func testV5toV6UpgradeAddsPrimitiveWorkoutCacheWithoutLosingLogs() async throws {
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()

        do {
            try seedV5WorkoutAndSetLogStore(at: url, ids: ids)
        }

        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

        let workouts = try context.fetch(FetchDescriptor<WorkoutModel>())
        XCTAssertEqual(workouts.count, 1, "V5 Workout row must survive V6 migration")
        XCTAssertEqual(workouts.first?.id, ids.workoutID)

        let setLogs = try context.fetch(FetchDescriptor<SetLogModel>())
        XCTAssertEqual(setLogs.count, 1, "V5 SetLog row must survive V6 migration")
        let setLog = try XCTUnwrap(setLogs.first)
        XCTAssertEqual(setLog.id, ids.setLogID)
        XCTAssertEqual(setLog.workoutID, ids.workoutID)
        XCTAssertEqual(setLog.plannedExerciseID, ids.exerciseID)
        XCTAssertEqual(setLog.sideRaw, SetLogSide.bilateral.rawValue)

        let primitiveRowsBeforeInsert = try context.fetch(FetchDescriptor<PrimitiveWorkoutModel>())
        XCTAssertTrue(
            primitiveRowsBeforeInsert.isEmpty,
            "V6 should introduce an empty primitive cache table for existing stores"
        )

        context.insert(PrimitiveWorkoutModel(
            id: ids.workoutID,
            name: "Primitive mirror",
            payloadJSON: "{}"
        ))
        try context.save()

        let primitiveRowsAfterInsert = try context.fetch(FetchDescriptor<PrimitiveWorkoutModel>())
        XCTAssertEqual(
            primitiveRowsAfterInsert.count,
            1,
            "New V6 primitive cache table must be writable after migration"
        )
    }

    // MARK: - V6 → V7 primitive set log rows

    private func seedV6PrimitiveWorkoutStore(at url: URL, ids: FixtureIDs) throws {
        let container = try makeV6OnlyContainer(at: url)
        let context = ModelContext(container)
        let primitive = PrimitiveWorkout(
            id: ids.workoutID,
            name: "Primitive workout",
            blocks: []
        )
        let model = WorkoutDBSchemaV6.PrimitiveWorkoutModel(
            id: ids.workoutID,
            name: primitive.name,
            payloadJSON: try encodePrimitiveWorkout(primitive),
            primitiveSetLogsJSON: """
            [{
              "id":"\(ids.setLogID.uuidString)",
              "role":"slot",
              "slotID":"\(ids.itemID.uuidString)",
              "workoutID":"\(ids.workoutID.uuidString)",
              "plannedExerciseID":"\(ids.exerciseID.uuidString)",
              "setIndex":0,
              "setRepeatIndex":0,
              "blockRepeatIndex":0,
              "reps":5,
              "completedAt":"2026-05-18T12:00:00Z"
            }]
            """
        )
        context.insert(model)
        try context.save()
    }

    private func encodePrimitiveWorkout(_ workout: PrimitiveWorkout) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workout)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    @MainActor
    func testV6toV7UpgradeIntroducesPrimitiveSetLogTable() async throws {
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()

        do {
            try seedV6PrimitiveWorkoutStore(at: url, ids: ids)
        }

        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

        let rows = try context.fetch(FetchDescriptor<PrimitiveSetLogModel>())
        XCTAssertTrue(
            rows.isEmpty,
            "V6 QA primitive result data is intentionally reset by the V7 cutover"
        )

        context.insert(PrimitiveSetLogModel.from(
            PrimitiveSetLog(
                id: ids.setLogID,
                role: .slot,
                slotID: ids.itemID,
                blockID: ids.blockID,
                workoutID: ids.workoutID,
                plannedExerciseID: ids.exerciseID,
                setIndex: 1,
                setRepeatIndex: 0,
                blockRepeatIndex: 0,
                reps: 5,
                weight: 100.0,
                weightUnit: .kg,
                rir: 2,
                completedAt: ids.baseDate.addingTimeInterval(60)
            ),
            workoutID: ids.workoutID
        ))
        try context.save()

        let rowsAfterInsert = try context.fetch(FetchDescriptor<PrimitiveSetLogModel>())
        XCTAssertEqual(rowsAfterInsert.count, 1, "V7 primitive set log table must be writable")
    }

    // MARK: - V7 → V8 HealthKit archive projection rows

    private func seedV7PrimitiveStore(at url: URL, ids: FixtureIDs) throws {
        let container = try makeV7OnlyContainer(at: url)
        let context = ModelContext(container)

        context.insert(PrimitiveWorkoutModel(
            id: ids.workoutID,
            name: "Primitive workout",
            payloadJSON: "{}"
        ))
        context.insert(WorkoutDBSchemaV7.PrimitiveSetLogModel(
            id: ids.setLogID,
            roleRaw: PrimitiveLogRole.slot.rawValue,
            slotID: ids.itemID,
            setID: nil,
            blockID: ids.blockID,
            workoutID: ids.workoutID,
            plannedExerciseID: ids.exerciseID,
            performedExerciseID: nil,
            setIndex: 0,
            setRepeatIndex: 0,
            blockRepeatIndex: 0,
            reps: 5,
            weight: nil,
            weightUnitRaw: nil,
            durationSec: nil,
            distanceM: nil,
            rounds: nil,
            rir: nil,
            isWarmup: false,
            completedAt: ids.baseDate
        ))
        try context.save()
    }

    @MainActor
    func testV7toV8UpgradeIntroducesWritableHealthArchiveTables() async throws {
        let url = try XCTUnwrap(storeURL)
        let ids = FixtureIDs.make()

        do {
            try seedV7PrimitiveStore(at: url, ids: ids)
        }

        let currentContainer = try makeCurrentContainer(at: url)
        let context = ModelContext(currentContainer)

        let primitiveWorkouts = try context.fetch(FetchDescriptor<PrimitiveWorkoutModel>())
        XCTAssertEqual(primitiveWorkouts.count, 1)
        XCTAssertEqual(primitiveWorkouts.first?.id, ids.workoutID)

        let primitiveLogs = try context.fetch(FetchDescriptor<PrimitiveSetLogModel>())
        XCTAssertEqual(primitiveLogs.count, 1)
        XCTAssertEqual(primitiveLogs.first?.id, ids.setLogID)

        context.insert(HealthDataRecordModel(
            id: UUID(),
            externalID: "health-sample-1",
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            sampleKindRaw: "quantity",
            sourceBundleIdentifier: "com.apple.Health",
            start: ids.baseDate,
            end: ids.baseDate,
            unit: "count/min",
            valueJSON: #"{"quantity":{"_0":120,"unit":"count/min"}}"#,
            metadataJSON: #"{"setmark_probe_run_id":"migration"}"#,
            firstSeenAt: ids.baseDate,
            lastSeenAt: ids.baseDate
        ))
        context.insert(HealthDataDeletionModel(
            id: UUID(),
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            externalID: "deleted-health-sample",
            observedAt: ids.baseDate
        ))
        context.insert(HealthBatchCursorModel(
            id: UUID(),
            requestSetKey: "archive-all",
            cursor: "cursor-1",
            updatedAt: ids.baseDate
        ))
        try context.save()

        let healthRows = try context.fetch(FetchDescriptor<HealthDataRecordModel>())
        let deletionRows = try context.fetch(FetchDescriptor<HealthDataDeletionModel>())
        let cursorRows = try context.fetch(FetchDescriptor<HealthBatchCursorModel>())
        XCTAssertEqual(healthRows.count, 1)
        XCTAssertEqual(deletionRows.count, 1)
        XCTAssertEqual(cursorRows.count, 1)
    }

}
