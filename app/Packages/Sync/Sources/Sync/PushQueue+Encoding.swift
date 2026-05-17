// PushQueue+Encoding.swift
//
// Body-encoding and endpoint-routing helpers for `PushQueue`, split out
// of `PushQueue.swift` so the actor body stays under SwiftLint's
// `type_body_length` cap. `pushOne` inside the actor calls into these
// from the same module; both helpers read the actor's `encoder` (shared
// `JSONEncoder.workoutDB()` instance) which is `internal` (not
// `private`) so this extension can see it.

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
import WorkoutDBSchema

extension PushQueue {

    /// Route a payload to its endpoint. Set logs + status updates share
    /// `/api/sync/results`; telemetry has its own endpoint so failures on
    /// one path don't block the other; user_parameters have their own
    /// endpoint and are append-only.
    func pushPath(for payload: PushItem.Payload) -> String {
        switch payload {
        case .setLogs, .primitiveSetLogs, .statusUpdate, .completionResults, .workoutReset:
            return "/api/sync/results"
        case .events:
            return "/api/telemetry/events"
        case .userParameter:
            return "/api/user-parameters"
        }
    }

    /// Encode the HTTP body for a queued item. Each payload case maps to
    /// its own wire shape (see `pushPath(for:)` for the endpoint). Throws
    /// on a JSON encode failure — `pushOne` wraps the throw into
    /// `SyncError.encode`.
    func encodeBody(for item: PushItem) throws -> Data {
        switch item.payload {
        case .setLogs(let logs):
            return try encodeSetLogs(logs)
        case .primitiveSetLogs(let logs):
            return try encodePrimitiveSetLogs(logs)
        case .statusUpdate(let workoutID, let status, let completedAt, let notes):
            return try encodeStatusUpdate(
                workoutID: workoutID,
                status: status,
                completedAt: completedAt,
                notes: notes
            )
        case .completionResults(let workoutID, let completedAt, let notes, let logs, let primitiveLogs):
            return try encodeCompletionResults(
                workoutID: workoutID,
                completedAt: completedAt,
                notes: notes,
                logs: logs,
                primitiveLogs: primitiveLogs
            )
        case .workoutReset(let workoutID):
            return try encodeWorkoutReset(workoutID: workoutID)
        case .events(let events):
            return try encodeEvents(events)
        case .userParameter(let param):
            // Server's `POST /api/user-parameters` expects an array of
            // `UserParameterIn` — `{id, key, value, source, updated_at}`.
            // The client owns `id` end-to-end so retries upsert on id;
            // `user_id` stays server-derived (from the bearer token).
            return try encoder.encode([DTOMapping.toInDTO(param)])
        }
    }

    private func encodeSetLogs(_ logs: [CoreDomain.SetLog]) throws -> Data {
        let payload = WorkoutDBSchema.SyncResultsPayload(
            setLogs: logs.map(DTOMapping.toDTO),
            statusUpdates: [],
            workoutResets: []
        )
        return try encoder.encode(payload)
    }

    private func encodePrimitiveSetLogs(_ logs: [CoreDomain.PrimitiveSetLog]) throws -> Data {
        try requirePrimitiveWorkoutIDs(logs)
        let payload = WorkoutDBSchema.SyncResultsPayload(
            primitiveSetLogs: logs.map(DTOMapping.toDTO),
            statusUpdates: [],
            workoutResets: []
        )
        return try encoder.encode(payload)
    }

    private func encodeStatusUpdate(
        workoutID: WorkoutID,
        status: CoreDomain.WorkoutStatus,
        completedAt: Date?,
        notes: String?
    ) throws -> Data {
        // `CoreDomain.WorkoutStatus` and `WorkoutDBSchema.WorkoutStatus`
        // share their string-backed cases by construction (contract test
        // `test_swift_schema_parity.py` enforces parity). The force-unwrap
        // cannot fail without a concurrent schema drift that CI would
        // have rejected.
        // swiftlint:disable:next force_unwrapping
        let wireStatus = WorkoutDBSchema.WorkoutStatus(rawValue: status.rawValue)!
        let dto = WorkoutDBSchema.WorkoutStatusUpdate(
            workoutId: workoutID.wireID,
            status: wireStatus,
            completedAt: completedAt,
            notes: notes
        )
        let payload = WorkoutDBSchema.SyncResultsPayload(
            setLogs: [],
            statusUpdates: [dto],
            workoutResets: []
        )
        return try encoder.encode(payload)
    }

    private func encodeCompletionResults(
        workoutID: WorkoutID,
        completedAt: Date?,
        notes: String?,
        logs: [CoreDomain.SetLog],
        primitiveLogs: [CoreDomain.PrimitiveSetLog]
    ) throws -> Data {
        // swiftlint:disable:next force_unwrapping
        let wireStatus = WorkoutDBSchema.WorkoutStatus(rawValue: CoreDomain.WorkoutStatus.completed.rawValue)!
        let dto = WorkoutDBSchema.WorkoutStatusUpdate(
            workoutId: workoutID.wireID,
            status: wireStatus,
            completedAt: completedAt,
            notes: notes
        )
        let payload = WorkoutDBSchema.SyncResultsPayload(
            setLogs: logs.map(DTOMapping.toDTO),
            primitiveSetLogs: try primitiveLogs.map { log in
                let stamped = try primitiveLog(log, stampedWith: workoutID)
                return DTOMapping.toDTO(stamped)
            },
            statusUpdates: [dto],
            workoutResets: []
        )
        return try encoder.encode(payload)
    }

    private func primitiveLog(
        _ log: CoreDomain.PrimitiveSetLog,
        stampedWith workoutID: WorkoutID
    ) throws -> CoreDomain.PrimitiveSetLog {
        var stamped = log
        if stamped.workoutID == nil {
            stamped.workoutID = workoutID
        }
        return stamped
    }

    private func requirePrimitiveWorkoutIDs(_ logs: [CoreDomain.PrimitiveSetLog]) throws {
        if logs.contains(where: { $0.workoutID == nil }) {
            throw EncodingError.invalidValue(
                logs,
                .init(
                    codingPath: [],
                    debugDescription: "primitive set logs require workoutID before sync encoding"
                )
            )
        }
    }

    private func encodeWorkoutReset(workoutID: WorkoutID) throws -> Data {
        let dto = WorkoutDBSchema.WorkoutReset(workoutId: workoutID.wireID)
        let payload = WorkoutDBSchema.SyncResultsPayload(
            setLogs: [],
            statusUpdates: [],
            workoutResets: [dto]
        )
        return try encoder.encode(payload)
    }

    private func encodeEvents(_ events: [CoreTelemetry.Event]) throws -> Data {
        let dtoEvents = events.map { event -> WorkoutDBSchema.TelemetryEvent in
            WorkoutDBSchema.TelemetryEvent(
                id: event.id.wireID,
                timestamp: event.timestamp,
                sessionId: event.sessionID.wireID,
                kind: event.kind,
                name: event.name,
                dataJson: event.dataJSON,
                workoutId: event.workoutID?.wireID,
                setLogId: event.setLogID?.wireID
            )
        }
        let payload = WorkoutDBSchema.TelemetryEventsPayload(events: dtoEvents)
        return try encoder.encode(payload)
    }
}
