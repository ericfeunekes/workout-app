import CoreDomain
import CoreSession
import Foundation
import Persistence
import Sync
import WorkoutCoreFoundation
import WorkoutKitExportProfile

@main
struct PrimitiveSyncProbe {
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let baseURLString = env["WORKOUTDB_SYNC_PROBE_BASE_URL"],
              let baseURL = URL(string: baseURLString)
        else {
            throw ProbeError.missingEnvironment("WORKOUTDB_SYNC_PROBE_BASE_URL")
        }
        guard let token = env["WORKOUTDB_SYNC_PROBE_TOKEN"] else {
            throw ProbeError.missingEnvironment("WORKOUTDB_SYNC_PROBE_TOKEN")
        }

        try await expectBadTokenIsRejected(baseURL: baseURL)

        let transport = URLSessionTransport(baseURL: baseURL)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimitiveSyncProbe-\(UUID().uuidString).store")
        let initialPersistence = try PersistenceFactory.makeOnDisk(storeURL: storeURL)
        let pullAPI = SyncAPI(
            transport: transport,
            store: initialPersistence.pushQueueStore,
            tokenProvider: { token }
        )

        let pull = try await pullAPI.pullLatest(since: nil as Date?)
        let dataset = PulledDataset(
            workouts: pull.workouts.map { $0.workout },
            primitiveWorkouts: pull.primitiveWorkouts,
            primitiveWorkoutIDsToDelete: pull.primitiveWorkoutIDsToDelete,
            blocks: pull.workouts.flatMap { $0.blocks },
            items: pull.workouts.flatMap { $0.items },
            alternatives: pull.workouts.flatMap { $0.alternatives },
            exercises: pull.exercises,
            userParameters: pull.userParameters
        )
        try await initialPersistence.workoutCache.save(dataset)

        let persistence = try PersistenceFactory.makeOnDisk(storeURL: storeURL)
        let api = SyncAPI(
            transport: transport,
            store: persistence.pushQueueStore,
            tokenProvider: { token }
        )
        let primitiveWorkouts = try await persistence.workoutCache.loadPrimitiveWorkouts()
        try expect(
            primitiveWorkouts.contains { $0.id == ProbeIDs.executionWorkout },
            "expected execution primitive workout"
        )
        try expect(
            primitiveWorkouts.contains { $0.id == ProbeIDs.sourceFactWorkout },
            "expected source-fact primitive workout"
        )
        guard let workout = primitiveWorkouts.first(where: { $0.id == ProbeIDs.executionWorkout }) else {
            throw ProbeError.failedExpectation("expected execution primitive workout")
        }
        guard let sourceFactWorkout = primitiveWorkouts.first(where: { $0.id == ProbeIDs.sourceFactWorkout }) else {
            throw ProbeError.failedExpectation("expected source-fact primitive workout")
        }
        try expectSourceFactClassification(sourceFactWorkout)
        let plan = try ExecutionPlan.validated(workout: workout, userParameters: [:])

        guard let block = workout.blocks.first,
              let set = block.sets.first,
              let slot = set.slots.first
        else {
            throw ProbeError.failedExpectation("expected seeded primitive block, set, and slot")
        }

        let firstLog = makeSetLog(
            reps: 5,
            workoutID: workout.id,
            blockID: block.id,
            setID: set.id,
            slotID: slot.id,
            exerciseID: slot.exerciseID
        )
        try await push(log: firstLog, workoutID: workout.id, api: api, persistence: persistence)

        let updatedLog = makeSetLog(
            reps: 7,
            workoutID: workout.id,
            blockID: block.id,
            setID: set.id,
            slotID: slot.id,
            exerciseID: slot.exerciseID
        )
        try await push(log: updatedLog, workoutID: workout.id, api: api, persistence: persistence)

        let aggregateLog = plan.setResultLog(
            blockIndex: 0,
            setIndexInBlock: 0,
            blockRepeatIndex: 0,
            setRepeatIndex: 0,
            rounds: 3,
            durationSec: 300,
            completedAt: Date(timeIntervalSince1970: 1_768_516_860)
        )
        try expect(aggregateLog.role == .setResult, "expected aggregate set-result log")
        try await push(log: aggregateLog, workoutID: workout.id, api: api, persistence: persistence)

        try await pushMixedRoleCompletion(
            plan: plan,
            pulledWorkout: pull.workouts.first { $0.workout.id == workout.id }!.workout,
            api: api,
            persistence: persistence
        )
        try await uploadHealthArchive(api: api, baseURL: baseURL)
        try await expectInvalidPerformedExerciseRejected(baseURL: baseURL, token: token)
    }

    private static func expectBadTokenIsRejected(baseURL: URL) async throws {
        let service = PullService(transport: URLSessionTransport(baseURL: baseURL))
        do {
            _ = try await service.pull(since: nil, bearerToken: "bad-token")
        } catch SyncError.tokenRejected {
            return
        } catch {
            throw ProbeError.failedExpectation("expected token rejection, got \(error)")
        }
        throw ProbeError.failedExpectation("expected token rejection")
    }

    private static func expectSourceFactClassification(_ workout: PrimitiveWorkout) throws {
        try expect(
            workout.activityIntent?.activityDomain == .running,
            "expected running activity intent after SwiftData reopen"
        )
        try expect(
            workout.activityIntent?.preservationPolicy == .preservePrimaryActivity,
            "expected preservation policy after SwiftData reopen"
        )
        try expect(
            workout.activityIntent?.environment == .unspecified,
            "expected defaulted environment after SwiftData reopen"
        )
        let report = try WorkoutKitExportClassifier().report(for: workout)
        try expect(report.plan.rowID == .continuousCardio, "expected continuous cardio source-fact row")
        try expect(report.plan.payload.activitySelection == .running, "expected running WorkoutKit activity")
        try expect(report.missingSourceChoices.isEmpty, "expected no missing source choices")
        try expect(
            !report.blockingReasons.contains(.sourceAmbiguity),
            "expected no source ambiguity after source-fact readback"
        )
        try expect(
            report.plan.admissionState == .proofBlocked,
            "expected source-fact proof to remain separate from WorkoutKit push readiness"
        )
    }

    private static func push(
        log: PrimitiveSetLog,
        workoutID: WorkoutID,
        api: SyncAPI,
        persistence: PersistenceFactory
    ) async throws {
        try await persistence.workoutCache.savePrimitiveSetLogs([log], workoutID: workoutID)
        let cached = try await persistence.workoutCache.loadPrimitiveSetLogs(workoutID: workoutID)
        try expect(cached.contains(log), "expected primitive log in SwiftData cache")
        try await api.pushPrimitiveLog([log])
        let result = try await api.flushPushQueue()
        try expect(result.remaining == 0, "expected empty push queue")
        try expect(result.pushed == 1, "expected one primitive set log push")
    }

    private static func pushMixedRoleCompletion(
        plan: ExecutionPlan,
        pulledWorkout: Workout,
        api: SyncAPI,
        persistence: PersistenceFactory
    ) async throws {
        guard let firstSet = plan.blocks.first?.sets.first,
              let firstSlot = firstSet.slots.first
        else {
            throw ProbeError.failedExpectation("expected execution plan with one slot")
        }
        let completedAt = Date(timeIntervalSince1970: 1_768_516_920)
        let slotLog = firstSlot.slotLog(
            workoutID: plan.workoutID,
            blockRepeatIndex: 0,
            setRepeatIndex: 0,
            setIndex: 1,
            reps: 9,
            weight: 42,
            weightUnit: .kg,
            rir: 1,
            completedAt: completedAt
        )
        let setLog = plan.setResultLog(
            blockIndex: 0,
            setIndexInBlock: 0,
            blockRepeatIndex: 0,
            setRepeatIndex: 0,
            rounds: 4,
            durationSec: 360,
            completedAt: completedAt
        )
        let blockLog = plan.blockResultLog(
            blockIndex: 0,
            blockRepeatIndex: 0,
            durationSec: 360,
            completedAt: completedAt
        )
        var completedWorkout = pulledWorkout
        completedWorkout.status = .completed
        completedWorkout.notes = "mixed role completion probe"
        completedWorkout.completedAt = completedAt
        completedWorkout.updatedAt = completedAt
        let record = WorkoutCompletionRecord(
            workout: completedWorkout,
            primitiveSetLogs: [slotLog, setLog, blockLog]
        )

        try await persistence.workoutCache.save(
            PulledDataset(workouts: [completedWorkout])
        )
        try await persistence.workoutCache.savePrimitiveSetLogs(
            record.primitiveSetLogs,
            workoutID: plan.workoutID
        )
        let cached = try await persistence.workoutCache.loadPrimitiveSetLogs(workoutID: plan.workoutID)
        try expect(
            Set(cached.map(\.role)).isSuperset(of: [.slot, .setResult, .blockResult]),
            "expected mixed-role completion artifact in SwiftData cache"
        )
        guard let cachedSlot = cached.first(where: { $0.id == slotLog.id }) else {
            throw ProbeError.failedExpectation("expected grouped slot in SwiftData cache")
        }
        try expect(cachedSlot.setIndex == 1, "expected grouped slot commit coordinate")
        try expect(cachedSlot.weight == 42, "expected grouped slot weight in SwiftData cache")
        try expect(cachedSlot.weightUnit == .kg, "expected grouped slot weight unit in SwiftData cache")
        try await api.pushCompletion(record)
        let result = try await api.flushPushQueue()
        try expect(
            result.remaining == 0,
            "expected empty push queue after completion, got pushed=\(result.pushed) remaining=\(result.remaining)"
        )
        try expect(
            result.pushed == 1,
            "expected one grouped completion push, got pushed=\(result.pushed) remaining=\(result.remaining)"
        )
    }

    private static func expectInvalidPerformedExerciseRejected(
        baseURL: URL,
        token: String
    ) async throws {
        let url = baseURL.appendingPathComponent("api/sync/results")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        {
          "primitive_set_logs": [
            {
              "id": "88888888-8888-4888-8888-888888888888",
              "role": "slot",
              "slot_id": "66666666-6666-4666-8666-666666666666",
              "set_id": "55555555-5555-4555-8555-555555555555",
              "block_id": "44444444-4444-4444-8444-444444444444",
              "workout_id": "22222222-2222-4222-8222-222222222222",
              "planned_exercise_id": "33333333-3333-4333-8333-333333333333",
              "performed_exercise_id": "99999999-9999-4999-8999-999999999999",
              "set_index": 0,
              "reps": 7,
              "weight": 40,
              "weight_unit": "kg",
              "rir": 2,
              "completed_at": "2026-01-15T12:00:00Z"
            }
          ]
        }
        """.utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.failedExpectation("expected HTTP response for invalid primitive log")
        }
        try expect(http.statusCode == 422, "expected invalid primitive log to return 422")
    }

    private static func uploadHealthArchive(api: SyncAPI, baseURL: URL) async throws {
        let result = try await api.uploadHealthArchive(HealthArchiveUploadRequest(
            requestSetKey: "sync-probe-health-archive",
            serverNamespace: HealthArchiveServerNamespace.normalized(from: baseURL),
            descriptorFingerprint: "sync-probe-fingerprint",
            nextCursor: "sync-probe-cursor-1",
            records: [
                HealthArchiveUploadRecord(
                    id: "aaaa1111-1111-4111-8111-111111111111",
                    externalID: "hk-quantity-heart-rate-1",
                    descriptorID: "HKQuantityTypeIdentifierHeartRate",
                    sampleKind: .quantity,
                    sourceBundleIdentifier: "com.apple.Health",
                    start: Date(timeIntervalSince1970: 1_768_516_800),
                    end: Date(timeIntervalSince1970: 1_768_516_860),
                    value: HealthArchiveUploadValue(
                        kind: .quantity,
                        quantityValue: 142,
                        unit: "count/min"
                    ),
                    metadata: ["probe": "real-http"]
                ),
                HealthArchiveUploadRecord(
                    id: "aaaa2222-2222-4222-8222-222222222222",
                    externalID: "hk-category-sleep-1",
                    descriptorID: "HKCategoryTypeIdentifierSleepAnalysis",
                    sampleKind: .category,
                    sourceBundleIdentifier: "com.apple.Health",
                    start: Date(timeIntervalSince1970: 1_768_513_200),
                    end: Date(timeIntervalSince1970: 1_768_538_400),
                    value: HealthArchiveUploadValue(kind: .category, categoryValue: 1),
                    metadata: ["probe": "real-http"]
                ),
                HealthArchiveUploadRecord(
                    id: "aaaa3333-3333-4333-8333-333333333333",
                    externalID: "hk-workout-run-1",
                    descriptorID: "HKWorkoutTypeIdentifier",
                    sampleKind: .workout,
                    sourceBundleIdentifier: "com.workoutdb.probe",
                    start: Date(timeIntervalSince1970: 1_768_516_800),
                    end: Date(timeIntervalSince1970: 1_768_518_600),
                    value: HealthArchiveUploadValue(
                        kind: .workout,
                        workoutActivityType: "running",
                        durationSeconds: 1_800,
                        totalEnergyKcal: 320
                    ),
                    metadata: ["probe": "real-http"]
                ),
            ],
            tombstones: [
                HealthArchiveUploadTombstone(
                    id: "aaaa4444-4444-4444-8444-444444444444",
                    descriptorID: "HKQuantityTypeIdentifierStepCount",
                    externalID: "hk-step-deleted-1",
                    observedAt: Date(timeIntervalSince1970: 1_768_518_900)
                )
            ]
        ))
        try expect(result.requestSetKey == "sync-probe-health-archive", "expected echoed request set")
        try expect(result.acknowledgedCursor == "sync-probe-cursor-1", "expected acknowledged cursor")
        try expect(result.recordsReceived == 3, "expected three health archive records")
        try expect(result.tombstonesReceived == 1, "expected one health archive tombstone")
    }

    private static func makeSetLog(
        reps: Int,
        workoutID: WorkoutID,
        blockID: BlockID,
        setID: PrimitiveSetID,
        slotID: PrimitiveSlotID,
        exerciseID: ExerciseID
    ) -> PrimitiveSetLog {
        PrimitiveSetLog(
            id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
            role: .slot,
            slotID: slotID,
            setID: setID,
            blockID: blockID,
            workoutID: workoutID,
            plannedExerciseID: exerciseID,
            performedExerciseID: exerciseID,
            setIndex: 0,
            reps: reps,
            weight: 40,
            weightUnit: .kg,
            rir: 2,
            completedAt: Date(timeIntervalSince1970: 1_768_516_800)
        )
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw ProbeError.failedExpectation(message)
        }
    }
}

private enum ProbeIDs {
    static let executionWorkout = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let sourceFactWorkout = UUID(uuidString: "22222222-2222-4222-8222-222222222223")!
}

private enum ProbeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case failedExpectation(String)

    var description: String {
        switch self {
        case let .missingEnvironment(name):
            "Missing required environment variable: \(name)"
        case let .failedExpectation(message):
            message
        }
    }
}
