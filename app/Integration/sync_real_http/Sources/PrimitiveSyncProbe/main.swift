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
