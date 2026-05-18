import CoreDomain
import CoreSession
import Foundation
import Persistence
import Sync
import WorkoutCoreFoundation

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
        let persistence = try PersistenceFactory.makeInMemory()
        let api = SyncAPI(
            transport: transport,
            store: persistence.pushQueueStore,
            tokenProvider: { token }
        )

        let pull = try await api.pullLatest(since: nil as Date?)
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
        try await persistence.workoutCache.save(dataset)

        let primitiveWorkouts = try await persistence.workoutCache.loadPrimitiveWorkouts()
        try expect(primitiveWorkouts.count == 1, "expected one primitive workout")
        let workout = primitiveWorkouts[0]
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
