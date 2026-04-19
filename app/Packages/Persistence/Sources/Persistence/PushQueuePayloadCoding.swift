// PushQueuePayloadCoding.swift
//
// Serialization boundary for `PushItem.Payload`. Lives beside
// `PushQueueStoreImpl` so the actor body can stay under SwiftLint's
// `type_body_length` cap. The envelope types are Codable mirrors of
// `CoreDomain.SetLog`, `CoreTelemetry.Event`, and the statusUpdate
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
        case setLogs
        case statusUpdate
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
        var setLogs: [CodableSetLog]?
        var statusWorkoutID: UUID?
        var statusRaw: String?
        var statusCompletedAt: Date?
        /// User-authored post-workout note that rides on the terminal
        /// status push. Optional on disk so envelopes written before
        /// this field landed still decode cleanly (they default to nil,
        /// which is the pre-bug behavior).
        var statusNotes: String?
        var events: [CodableEvent]?
        var userParameter: CodableUserParameter?

        static func empty(kind: EnvelopeKind) -> Envelope {
            Envelope(
                kind: kind,
                setLogs: nil,
                statusWorkoutID: nil,
                statusRaw: nil,
                statusCompletedAt: nil,
                statusNotes: nil,
                events: nil,
                userParameter: nil
            )
        }
    }

    /// Mirror of `CoreDomain.SetLog` with `Codable`.
    struct CodableSetLog: Codable {
        let id: UUID
        let workoutItemID: UUID
        let performedExerciseID: UUID?
        let setIndex: Int
        let reps: Int?
        let weight: Double?
        let weightUnit: String?
        let durationSec: Double?
        let distanceM: Double?
        let rir: Int?
        let isWarmup: Bool
        let startedAt: Date?
        let completedAt: Date
        let hrAvgBpm: Int?
        let hrMaxBpm: Int?
        let cadenceAvgSpm: Int?
        let motionSamplesRef: String?
        let notes: String?

        init(_ s: SetLog) {
            id = s.id
            workoutItemID = s.workoutItemID
            performedExerciseID = s.performedExerciseID
            setIndex = s.setIndex
            reps = s.reps
            weight = s.weight
            weightUnit = s.weightUnit?.rawValue
            durationSec = s.durationSec
            distanceM = s.distanceM
            rir = s.rir
            isWarmup = s.isWarmup
            startedAt = s.startedAt
            completedAt = s.completedAt
            hrAvgBpm = s.hrAvgBpm
            hrMaxBpm = s.hrMaxBpm
            cadenceAvgSpm = s.cadenceAvgSpm
            motionSamplesRef = s.motionSamplesRef
            notes = s.notes
        }

        func toDomain() -> SetLog {
            SetLog(
                id: id,
                workoutItemID: workoutItemID,
                performedExerciseID: performedExerciseID,
                setIndex: setIndex,
                reps: reps,
                weight: weight,
                weightUnit: weightUnit.flatMap { WeightUnit(rawValue: $0) },
                durationSec: durationSec,
                distanceM: distanceM,
                rir: rir,
                isWarmup: isWarmup,
                startedAt: startedAt,
                completedAt: completedAt,
                hrAvgBpm: hrAvgBpm,
                hrMaxBpm: hrMaxBpm,
                cadenceAvgSpm: cadenceAvgSpm,
                motionSamplesRef: motionSamplesRef,
                notes: notes
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
        case .setLogs(let logs):
            envelope = .empty(kind: .setLogs)
            envelope.setLogs = logs.map(CodableSetLog.init)
        case .statusUpdate(let workoutID, let status, let completedAt, let notes):
            envelope = .empty(kind: .statusUpdate)
            envelope.statusWorkoutID = workoutID
            envelope.statusRaw = status.rawValue
            envelope.statusCompletedAt = completedAt
            envelope.statusNotes = notes
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
        case .setLogs:
            let logs = (envelope.setLogs ?? []).map { $0.toDomain() }
            return .setLogs(logs)
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
