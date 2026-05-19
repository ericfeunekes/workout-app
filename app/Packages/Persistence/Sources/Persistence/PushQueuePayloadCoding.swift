// PushQueuePayloadCoding.swift
//
// Serialization boundary for `PushItem.Payload`. Lives beside
// `PushQueueStoreImpl` so the actor body can stay under SwiftLint's
// `type_body_length` cap. The envelope types are Codable mirrors of
// primitive result logs, `CoreTelemetry.Event`, and the statusUpdate
// parameters — those domain types are deliberately Codable-free (see the
// module-level docs on `CoreDomain` and `CoreTelemetry`).
//
// Contract: `encodePayload` and `decodePayload` are inverses. Adding a new
// case to `PushItem.Payload` means adding a case to `EnvelopeKind` and
// wiring it into both functions. Old rows written before a new case
// landed still decode cleanly because the envelope's per-case fields are
// optional — the kind tag picks the branch.

import Foundation
import CoreDomain
import CoreTelemetry
import Sync

enum PushQueuePayloadCoding {

    /// Tag discriminator for the `Envelope` payload.
    enum EnvelopeKind: String, Codable {
        case primitiveSetLogs
        case statusUpdate
        case completionResults
        case workoutReset
        case events
        case userParameter
    }

    /// Serialization boundary — `PushItem.Payload` itself isn't Codable so
    /// we define an envelope here. Versioned implicitly by the "kind" tag.
    /// Every case-specific field is optional; the "kind" discriminator
    /// picks the branch on decode. Adding a new case is: add a `kind`,
    /// add an optional field, wire both encode + decode.
    struct Envelope: Codable {
        let kind: EnvelopeKind
        var primitiveSetLogs: [CodablePrimitiveSetLog]?
        var statusWorkoutID: UUID?
        var statusRaw: String?
        var statusCompletedAt: Date?
        /// User-authored post-workout note that rides on the terminal
        /// status push. Optional on disk so envelopes written before
        /// this field landed still decode cleanly (they default to nil,
        /// which is the pre-bug behavior).
        var statusNotes: String?
        var completionWorkoutID: UUID?
        var completionCompletedAt: Date?
        var completionNotes: String?
        var completionPrimitiveSetLogs: [CodablePrimitiveSetLog]?
        var resetWorkoutID: UUID?
        var events: [CodableEvent]?
        var userParameter: CodableUserParameter?

        static func empty(kind: EnvelopeKind) -> Envelope {
            Envelope(
                kind: kind,
                primitiveSetLogs: nil,
                statusWorkoutID: nil,
                statusRaw: nil,
                statusCompletedAt: nil,
                statusNotes: nil,
                completionWorkoutID: nil,
                completionCompletedAt: nil,
                completionNotes: nil,
                completionPrimitiveSetLogs: nil,
                resetWorkoutID: nil,
                events: nil,
                userParameter: nil
            )
        }
    }

    struct CodablePrimitiveSetLog: Codable {
        let id: UUID
        let role: String
        let slotID: UUID?
        let setID: UUID?
        let blockID: UUID?
        let workoutID: UUID?
        let plannedExerciseID: UUID?
        let performedExerciseID: UUID?
        let setIndex: Int
        let setRepeatIndex: Int
        let blockRepeatIndex: Int
        let reps: Int?
        let weight: Double?
        let weightUnit: String?
        let durationSec: Double?
        let distanceM: Double?
        let rounds: Int?
        let rir: Int?
        let hrAvgBpm: Int?
        let hrMaxBpm: Int?
        let isWarmup: Bool
        let skipped: Bool?
        let side: String?
        let notes: String?
        let completedAt: Date

        init(_ log: PrimitiveSetLog) {
            id = log.id
            role = log.role.rawValue
            slotID = log.slotID
            setID = log.setID
            blockID = log.blockID
            workoutID = log.workoutID
            plannedExerciseID = log.plannedExerciseID
            performedExerciseID = log.performedExerciseID
            setIndex = log.setIndex
            setRepeatIndex = log.setRepeatIndex
            blockRepeatIndex = log.blockRepeatIndex
            reps = log.reps
            weight = log.weight
            weightUnit = log.weightUnit?.rawValue
            durationSec = log.durationSec
            distanceM = log.distanceM
            rounds = log.rounds
            rir = log.rir
            hrAvgBpm = log.hrAvgBpm
            hrMaxBpm = log.hrMaxBpm
            isWarmup = log.isWarmup
            skipped = log.skipped
            side = log.side.rawValue
            notes = log.notes
            completedAt = log.completedAt
        }

        func toDomain() throws -> PrimitiveSetLog {
            guard let role = PrimitiveLogRole(rawValue: role) else {
                throw PersistenceError.decode("invalid primitiveSetLog role")
            }
            return PrimitiveSetLog(
                id: id,
                role: role,
                slotID: slotID,
                setID: setID,
                blockID: blockID,
                workoutID: workoutID,
                plannedExerciseID: plannedExerciseID,
                performedExerciseID: performedExerciseID,
                setIndex: setIndex,
                setRepeatIndex: setRepeatIndex,
                blockRepeatIndex: blockRepeatIndex,
                reps: reps,
                weight: weight,
                weightUnit: weightUnit.flatMap { WeightUnit(rawValue: $0) },
                durationSec: durationSec,
                distanceM: distanceM,
                rounds: rounds,
                rir: rir,
                hrAvgBpm: hrAvgBpm,
                hrMaxBpm: hrMaxBpm,
                isWarmup: isWarmup,
                skipped: skipped ?? false,
                side: side.flatMap { SetLogSide(rawValue: $0) } ?? .bilateral,
                notes: notes,
                completedAt: completedAt
            )
        }
    }

    /// Mirror of `CoreTelemetry.Event` with `Codable`.
    struct CodableEvent: Codable {
        let id: UUID
        let timestamp: Date
        let sessionID: UUID
        let kind: String
        let name: String
        let dataJSON: String?
        let workoutID: UUID?
        let setLogID: UUID?

        init(_ e: CoreTelemetry.Event) {
            id = e.id
            timestamp = e.timestamp
            sessionID = e.sessionID
            kind = e.kind
            name = e.name
            dataJSON = e.dataJSON
            workoutID = e.workoutID
            setLogID = e.setLogID
        }

        func toDomain() -> CoreTelemetry.Event {
            CoreTelemetry.Event(
                id: id,
                timestamp: timestamp,
                sessionID: sessionID,
                kind: kind,
                name: name,
                dataJSON: dataJSON,
                workoutID: workoutID,
                setLogID: setLogID
            )
        }
    }

    static func encode(_ payload: PushItem.Payload) throws -> Data {
        var envelope: Envelope
        switch payload {
        case .primitiveSetLogs(let logs):
            envelope = .empty(kind: .primitiveSetLogs)
            envelope.primitiveSetLogs = logs.map(CodablePrimitiveSetLog.init)
        case .statusUpdate(let workoutID, let status, let completedAt, let notes):
            envelope = .empty(kind: .statusUpdate)
            envelope.statusWorkoutID = workoutID
            envelope.statusRaw = status.rawValue
            envelope.statusCompletedAt = completedAt
            envelope.statusNotes = notes
        case .completionResults(let workoutID, let completedAt, let notes, let primitiveLogs):
            envelope = .empty(kind: .completionResults)
            envelope.completionWorkoutID = workoutID
            envelope.completionCompletedAt = completedAt
            envelope.completionNotes = notes
            envelope.completionPrimitiveSetLogs = primitiveLogs.map(CodablePrimitiveSetLog.init)
        case .workoutReset(let workoutID):
            envelope = .empty(kind: .workoutReset)
            envelope.resetWorkoutID = workoutID
        case .events(let events):
            envelope = .empty(kind: .events)
            envelope.events = events.map(CodableEvent.init)
        case .userParameter(let param):
            envelope = .empty(kind: .userParameter)
            envelope.userParameter = CodableUserParameter(param)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> PushItem.Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        switch envelope.kind {
        case .primitiveSetLogs:
            let logs = try (envelope.primitiveSetLogs ?? []).map { try $0.toDomain() }
            return .primitiveSetLogs(logs)
        case .statusUpdate:
            guard let workoutID = envelope.statusWorkoutID,
                  let raw = envelope.statusRaw,
                  let status = WorkoutStatus(rawValue: raw) else {
                throw PersistenceError.decode("invalid statusUpdate envelope")
            }
            return .statusUpdate(
                workoutID: workoutID,
                status: status,
                completedAt: envelope.statusCompletedAt,
                notes: envelope.statusNotes
            )
        case .completionResults:
            guard let workoutID = envelope.completionWorkoutID else {
                throw PersistenceError.decode("invalid completionResults envelope")
            }
            return .completionResults(
                workoutID: workoutID,
                completedAt: envelope.completionCompletedAt,
                notes: envelope.completionNotes,
                primitiveSetLogs: try (envelope.completionPrimitiveSetLogs ?? []).map { try $0.toDomain() }
            )
        case .workoutReset:
            guard let workoutID = envelope.resetWorkoutID else {
                throw PersistenceError.decode("invalid workoutReset envelope")
            }
            return .workoutReset(workoutID: workoutID)
        case .events:
            let events = (envelope.events ?? []).map { $0.toDomain() }
            return .events(events)
        case .userParameter:
            guard let param = envelope.userParameter else {
                throw PersistenceError.decode("invalid userParameter envelope")
            }
            return .userParameter(param.toDomain())
        }
    }
}
