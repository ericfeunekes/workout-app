// PullService.swift
//
// GET /api/sync/pull → Domain values. One of the three responsibilities
// split out of the SyncManager per HS-1; stays small and testable.
//
// The service does not know about persistence — it returns `PullResult` and
// a consumer (`SyncAPI` at the moment, Persistence later) decides what to do
// with the rows. That keeps `PullService` trivially fakeable and keeps the
// "where do pulled rows get written?" decision out of this file.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

/// The Domain-typed result of a successful pull. `serverTime` is fed back as
/// the next `since` — see `docs/sync.md` § "Pull protocol".
public struct PullResult: Sendable, Equatable {
    public let serverTime: Date
    public let exercises: [CoreDomain.Exercise]
    public let userParameters: [CoreDomain.UserParameter]
    public let workouts: [MappedWorkout]
    public let primitiveWorkouts: [CoreDomain.PrimitiveWorkout]
    public let primitiveWorkoutIDsToDelete: [WorkoutID]
    public let lastPerformed: [LastPerformed]

    public init(
        serverTime: Date,
        exercises: [CoreDomain.Exercise],
        userParameters: [CoreDomain.UserParameter],
        workouts: [MappedWorkout],
        primitiveWorkouts: [CoreDomain.PrimitiveWorkout] = [],
        primitiveWorkoutIDsToDelete: [WorkoutID] = [],
        lastPerformed: [LastPerformed]
    ) {
        self.serverTime = serverTime
        self.exercises = exercises
        self.userParameters = userParameters
        self.workouts = workouts
        self.primitiveWorkouts = primitiveWorkouts
        self.primitiveWorkoutIDsToDelete = primitiveWorkoutIDsToDelete
        self.lastPerformed = lastPerformed
    }
}

/// Per-exercise history fragment piggybacked on the pull. The primitive slot
/// result logs have already been mapped to Domain.
public struct LastPerformed: Sendable, Equatable {
    public let exerciseID: ExerciseID
    public let lastSetLogs: [CoreDomain.PrimitiveSetLog]

    public init(
        exerciseID: ExerciseID,
        lastSetLogs: [CoreDomain.PrimitiveSetLog]
    ) {
        self.exerciseID = exerciseID
        self.lastSetLogs = lastSetLogs
    }
}

/// Owns `GET /api/sync/pull`. Stateless — the caller supplies the transport,
/// token, and `since`.
public struct PullService: Sendable {
    private let transport: HTTPTransport
    private let decoder: JSONDecoder

    public init(transport: HTTPTransport) {
        self.transport = transport
        self.decoder = JSONDecoder.workoutDB()
    }

    /// Issue a pull. Throws `SyncError` on any failure. Callers should feed
    /// `SyncError.tokenRejected` / `.network` into `ConnectionManager.observe`
    /// — `PullService` is intentionally ignorant of the manager so it stays
    /// trivially mockable.
    public func pull(since: Date?, bearerToken: String) async throws -> PullResult {
        var query: [(String, String)] = []
        if let since {
            query.append(("since", iso8601(since)))
        }
        let response: HTTPResponse
        do {
            response = try await transport.get(
                path: "/api/sync/pull",
                query: query,
                bearerToken: bearerToken
            )
        } catch let err as SyncError {
            throw err
        } catch {
            throw SyncError.network(error.localizedDescription)
        }

        switch response.status {
        case 200...299:
            break
        case 401:
            throw SyncError.tokenRejected
        default:
            let body = String(data: response.body, encoding: .utf8)
            throw SyncError.server(status: response.status, message: body)
        }

        let dto: WorkoutDBSchema.SyncPullResponse
        do {
            dto = try decoder.decode(WorkoutDBSchema.SyncPullResponse.self, from: response.body)
        } catch {
            throw SyncError.decode("sync pull body: \(error)")
        }

        return try mapResponse(dto)
    }

    // MARK: - Private

    private func mapResponse(_ dto: WorkoutDBSchema.SyncPullResponse) throws -> PullResult {
        var exercises: [CoreDomain.Exercise] = []
        for ex in dto.exercises {
            exercises.append(try unwrap(DTOMapping.mapExercise(ex)))
        }
        var params: [CoreDomain.UserParameter] = []
        for p in dto.userParameters {
            params.append(try unwrap(DTOMapping.mapUserParameter(p)))
        }
        var workouts: [MappedWorkout] = []
        var primitiveWorkouts: [CoreDomain.PrimitiveWorkout] = []
        for w in dto.workouts {
            if w.primitiveBlocks.isEmpty {
                throw SyncError.decode("Workout \(w.id) has empty primitive_blocks")
            }
            let mappedWorkout = try unwrap(DTOMapping.mapWorkout(w))
            workouts.append(mappedWorkout)
            let primitiveDTO = WorkoutDBSchema.PrimitiveWorkout(
                id: w.id,
                name: w.name,
                activityIntent: w.activityIntent,
                primitiveBlocks: w.primitiveBlocks
            )
            primitiveWorkouts.append(try unwrap(DTOMapping.mapPrimitiveWorkout(primitiveDTO)))
        }
        var lastPerformed: [LastPerformed] = []
        for lp in dto.lastPerformed {
            guard let exerciseID = UUID(uuidString: lp.exerciseId) else {
                throw SyncError.decode("last_performed.exercise_id is not a UUID: \(lp.exerciseId)")
            }
            var mappedLogs: [CoreDomain.PrimitiveSetLog] = []
            for log in lp.lastSetLogs {
                mappedLogs.append(try unwrap(DTOMapping.mapPrimitiveSetLog(log)))
            }
            lastPerformed.append(LastPerformed(
                exerciseID: exerciseID,
                lastSetLogs: mappedLogs
            ))
        }
        return PullResult(
            serverTime: dto.serverTime,
            exercises: exercises,
            userParameters: params,
            workouts: workouts,
            primitiveWorkouts: primitiveWorkouts,
            lastPerformed: lastPerformed
        )
    }

    private func unwrap<T>(_ result: Result<T, SyncError>) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let err): throw err
        }
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
