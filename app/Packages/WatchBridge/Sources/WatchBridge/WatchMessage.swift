// WatchMessage.swift
//
// The wire-level message vocabulary for iPhone ↔ Watch IPC. Both sides
// send and receive; the enum is symmetric:
//
//   iPhone → Watch:
//     - pushActiveBlock      (tells the watch what to display for the live set)
//     - pushRestTimer        (start a rest countdown on the watch face)
//     - pushWorkoutComplete  (end of session — watch returns to idle)
//
//   Watch → iPhone:
//     - setStarted           (user tapped "start set" on the watch)
//     - setEnded             (user tapped "end set"; carries HR samples)
//     - quickLog             (user logged reps + optional RIR from the watch)
//
// The watch never talks to the server. It hands logged work to the phone via
// `setEnded` / `quickLog`; the phone's `WatchBridge` consumer forwards those
// into `Sync.PushQueue`. See docs/sync.md § "Watch sync" and
// docs/architecture/swift-packages.md row "WatchBridge".
//
// Codable is the wire format — JSON, encoded once per message. We use
// string-tagged discriminators (`type` + `payload`) so logs and breakpoints
// stay legible, and so a future Swift-side addition doesn't silently corrupt
// older peers that decode by ordinal.

import Foundation

public enum WatchMessage: Sendable, Equatable, Codable {
    // MARK: iPhone → Watch

    case pushActiveBlock(ActiveBlockPayload)
    case pushRestTimer(endsAt: Date)
    case pushWorkoutComplete

    // MARK: Watch → iPhone

    case setStarted(workoutItemID: UUID, setIndex: Int, at: Date)
    case setEnded(
        workoutItemID: UUID,
        setIndex: Int,
        at: Date,
        bpmAvg: Int?,
        bpmMax: Int?
    )
    case quickLog(
        workoutItemID: UUID,
        setIndex: Int,
        reps: Int,
        rir: Int?
    )

    // MARK: - Codable (tagged representation)

    private enum CodingKeys: String, CodingKey { case type, payload }

    private enum Tag: String, Codable {
        case pushActiveBlock
        case pushRestTimer
        case pushWorkoutComplete
        case setStarted
        case setEnded
        case quickLog
    }

    private struct PushRestTimerPayload: Codable, Sendable {
        let endsAt: Date
    }

    private struct SetStartedPayload: Codable, Sendable {
        let workoutItemID: UUID
        let setIndex: Int
        let at: Date
    }

    private struct SetEndedPayload: Codable, Sendable {
        let workoutItemID: UUID
        let setIndex: Int
        let at: Date
        let bpmAvg: Int?
        let bpmMax: Int?
    }

    private struct QuickLogPayload: Codable, Sendable {
        let workoutItemID: UUID
        let setIndex: Int
        let reps: Int
        let rir: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .type)
        switch tag {
        case .pushActiveBlock:
            let payload = try container.decode(ActiveBlockPayload.self, forKey: .payload)
            self = .pushActiveBlock(payload)
        case .pushRestTimer:
            let payload = try container.decode(PushRestTimerPayload.self, forKey: .payload)
            self = .pushRestTimer(endsAt: payload.endsAt)
        case .pushWorkoutComplete:
            self = .pushWorkoutComplete
        case .setStarted:
            let payload = try container.decode(SetStartedPayload.self, forKey: .payload)
            self = .setStarted(
                workoutItemID: payload.workoutItemID,
                setIndex: payload.setIndex,
                at: payload.at
            )
        case .setEnded:
            let payload = try container.decode(SetEndedPayload.self, forKey: .payload)
            self = .setEnded(
                workoutItemID: payload.workoutItemID,
                setIndex: payload.setIndex,
                at: payload.at,
                bpmAvg: payload.bpmAvg,
                bpmMax: payload.bpmMax
            )
        case .quickLog:
            let payload = try container.decode(QuickLogPayload.self, forKey: .payload)
            self = .quickLog(
                workoutItemID: payload.workoutItemID,
                setIndex: payload.setIndex,
                reps: payload.reps,
                rir: payload.rir
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pushActiveBlock(let payload):
            try container.encode(Tag.pushActiveBlock, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pushRestTimer(let endsAt):
            try container.encode(Tag.pushRestTimer, forKey: .type)
            try container.encode(PushRestTimerPayload(endsAt: endsAt), forKey: .payload)
        case .pushWorkoutComplete:
            try container.encode(Tag.pushWorkoutComplete, forKey: .type)
        case let .setStarted(workoutItemID, setIndex, at):
            try encodeSetStarted(&container, workoutItemID: workoutItemID, setIndex: setIndex, at: at)
        case let .setEnded(workoutItemID, setIndex, at, bpmAvg, bpmMax):
            try encodeSetEnded(
                &container,
                payload: SetEndedPayload(
                    workoutItemID: workoutItemID,
                    setIndex: setIndex,
                    at: at,
                    bpmAvg: bpmAvg,
                    bpmMax: bpmMax
                )
            )
        case let .quickLog(workoutItemID, setIndex, reps, rir):
            try encodeQuickLog(
                &container,
                workoutItemID: workoutItemID,
                setIndex: setIndex,
                reps: reps,
                rir: rir
            )
        }
    }

    private func encodeSetStarted(
        _ container: inout KeyedEncodingContainer<CodingKeys>,
        workoutItemID: UUID,
        setIndex: Int,
        at: Date
    ) throws {
        try container.encode(Tag.setStarted, forKey: .type)
        try container.encode(
            SetStartedPayload(workoutItemID: workoutItemID, setIndex: setIndex, at: at),
            forKey: .payload
        )
    }

    private func encodeSetEnded(
        _ container: inout KeyedEncodingContainer<CodingKeys>,
        payload: SetEndedPayload
    ) throws {
        try container.encode(Tag.setEnded, forKey: .type)
        try container.encode(payload, forKey: .payload)
    }

    private func encodeQuickLog(
        _ container: inout KeyedEncodingContainer<CodingKeys>,
        workoutItemID: UUID,
        setIndex: Int,
        reps: Int,
        rir: Int?
    ) throws {
        try container.encode(Tag.quickLog, forKey: .type)
        try container.encode(
            QuickLogPayload(
                workoutItemID: workoutItemID,
                setIndex: setIndex,
                reps: reps,
                rir: rir
            ),
            forKey: .payload
        )
    }
}

public struct ActiveBlockPayload: Sendable, Equatable, Codable {
    public let exerciseName: String
    /// Pre-formatted human string, e.g. "5 reps @ 102.5 kg". WatchBridge does
    /// no formatting of its own — the iPhone builds the string using Core
    /// helpers and ships the rendered result.
    public let prescription: String
    public let setNumber: Int
    public let setCount: Int
    public let targetRir: Int?

    public init(
        exerciseName: String,
        prescription: String,
        setNumber: Int,
        setCount: Int,
        targetRir: Int?
    ) {
        self.exerciseName = exerciseName
        self.prescription = prescription
        self.setNumber = setNumber
        self.setCount = setCount
        self.targetRir = targetRir
    }
}
