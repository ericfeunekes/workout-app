// ExecutionViewModel+Telemetry.swift
//
// Telemetry emit helpers split out of `ExecutionViewModel+Push.swift` so
// both files stay under SwiftLint's `file_length` cap. The split is by
// concern: `+Push.swift` owns the push-queue enqueue path and the
// deterministic-UUID helpers; this file owns the `TelemetryEmitter` emits
// and their `Encodable` payload structs.
//
// Every emit here is fire-and-forget — the `TelemetryEmitter` protocol
// contract is that `emit(_:)` never blocks the caller. Payloads are
// encoded via `encodeTelemetryPayload` (sortedKeys JSON, force-try) so
// the event_log analytic queries see deterministic key ordering.

import Foundation
import CoreAutoreg
import CoreDomain
import CoreSession
import CoreTelemetry
import WorkoutCoreFoundation

extension ExecutionViewModel {

    /// Emit a single `execution.session_mutation` event tagged with the
    /// current workout. The mutation name rides in `data_json` so the
    /// server's `name` column stays bounded.
    func emitSessionMutation(_ which: String) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.session_mutation",
            dataJSON: #"{"mutation":"\#(which)"}"#,
            workoutID: context.workout.id
        ))
    }

    /// Emit an `execution.autoreg_*` event tagged with the current workout.
    func emitAutoreg(_ name: String) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: name,
            workoutID: context.workout.id
        ))
    }

    /// Emit `execution.autoreg_proposed` with the full documented
    /// payload — `{item_id, set_index, proposed_load_kg, step_kg,
    /// reason}` per `docs/observability-map.md`. `step_kg` is derived
    /// from `|proposal.newLoadKg - prescribedLoadKg|` rather than read
    /// from the autoreg config so a BW row (prescribed load nil) or a
    /// zero-floor clamp still carries the actual delta the user saw.
    /// `item_id` rides through `.wireID` so the "every id on the wire
    /// is a lowercase UUID" invariant holds.
    func emitAutoregProposed(
        itemID: UUID,
        setIndex: Int,
        proposal: AutoregProposal,
        prescribedLoadKg: Double?
    ) {
        let stepKg: Double = prescribedLoadKg.map { abs(proposal.newLoadKg - $0) } ?? 0
        let payload = AutoregProposedEventPayload(
            itemID: itemID.wireID,
            setIndex: setIndex,
            proposedLoadKg: proposal.newLoadKg,
            stepKg: stepKg,
            reason: Self.autoregReasonToken(proposal.reason)
        )
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.autoreg_proposed",
            dataJSON: Self.encodeTelemetryPayload(payload),
            workoutID: context.workout.id
        ))
    }

    /// Canonical snake_case token for an `AutoregProposal.Reason`.
    /// Matches `docs/features/autoreg.md` — the analyst-facing name is
    /// what shows up in event_log queries, not the Swift enum label.
    static func autoregReasonToken(_ reason: AutoregProposal.Reason) -> String {
        switch reason {
        case .overshoot: return "overshoot"
        case .undershootReps: return "undershoot_reps"
        case .hitFailure: return "hit_failure"
        }
    }

    /// Emit an `execution.exercise_swap` event capturing the from/to
    /// exerciseIDs + whether the alternative authored any parameter
    /// overrides. Analyzed downstream for swap rate / override uptake.
    ///
    /// Payload is built from a typed `Encodable` struct rather than hand-
    /// formatted so every UUID rides through `.wireID` (lowercased) — the
    /// system-wide invariant is "every id + *_id on the wire is a
    /// lowercase UUID". See `docs/sync.md` § "Wire identifiers".
    func emitSwapTelemetry(
        itemID: UUID,
        fromExerciseID: UUID?,
        toExerciseID: UUID,
        hadOverrides: Bool
    ) {
        let payload = SwapEventPayload(
            itemID: itemID.wireID,
            fromExerciseID: fromExerciseID?.wireID ?? "",
            toExerciseID: toExerciseID.wireID,
            hadOverrides: hadOverrides
        )
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.exercise_swap",
            dataJSON: Self.encodeTelemetryPayload(payload),
            workoutID: context.workout.id
        ))
    }

    /// Emit one `execution.tabata_multi_item_collapsed` event per
    /// collapse the seeder reported. Called from `init` right after the
    /// seed — keeping the emit loop here (instead of inline in `init`)
    /// keeps the main class body under SwiftLint's `type_body_length`.
    /// Empty input is a no-op: the clean-author path pays no cost.
    func emitSeedNormalizationTelemetry(_ collapses: [SessionSeeder.TabataCollapse]) {
        for collapse in collapses {
            emitTabataMultiItemCollapse(collapse)
        }
    }

    /// Emit an `execution.tabata_multi_item_collapsed` telemetry event
    /// announcing that a tabata block authored with N>1 items was
    /// collapsed to its first item. The seed-time collapse is deliberate
    /// (see `SessionSeeder.normalizeBlockItems`) but silent — a user who
    /// authors a multi-item tabata and sees a single-item render had no
    /// signal that the drop happened. This event is that signal. Payload
    /// carries the block index, the count dropped, and the lowercase
    /// exercise ids for each dropped item so an analyst can trace back
    /// to the offending prescription.
    func emitTabataMultiItemCollapse(_ collapse: SessionSeeder.TabataCollapse) {
        let payload = TabataMultiItemCollapsePayload(
            blockIndex: collapse.blockIndex,
            droppedItemCount: collapse.droppedItemCount,
            droppedExerciseIDs: collapse.droppedExerciseIDs.map(\.wireID)
        )
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.tabata_multi_item_collapsed",
            dataJSON: Self.encodeTelemetryPayload(payload),
            workoutID: context.workout.id
        ))
    }

    /// Emit the `execution.past_set_edited` telemetry event. Fixes
    /// bug-017 — past-set edits previously bypassed `emitSessionMutation`
    /// so the corrective-edit trail was missing from the event log.
    /// The `setLogID` in the payload matches the deterministic UUID used
    /// to push the corrected SetLog, so an analyst can join the event to
    /// the SetLog it mutated.
    ///
    /// Both ids are emitted via `.wireID` so the payload obeys the
    /// "every id on the wire is lowercase UUID" invariant (Codex R1.3).
    func emitPastSetEdited(itemID: UUID, setIndex: Int, setLogID: UUID) {
        let payload = PastSetEditedEventPayload(
            itemID: itemID.wireID,
            setIndex: setIndex,
            setLogID: setLogID.wireID
        )
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.past_set_edited",
            dataJSON: Self.encodeTelemetryPayload(payload),
            workoutID: context.workout.id,
            setLogID: setLogID
        ))
    }

    /// Emit that Save & Done has materialized the transport-neutral
    /// completion record from live session state. This is the first proof
    /// point for completion durability: after this event, every persistence
    /// or replication surface should consume the same record rather than
    /// re-reading `SessionState`.
    func emitCompletionRecordBuilt(_ record: WorkoutCompletionRecord) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.completion_record_built",
            dataJSON: Self.encodeTelemetryPayload(Self.completionPayload(record)),
            workoutID: record.workoutID
        ))
    }

    /// Emit the result of handing the completion record to the configured
    /// publisher. `publisherInstalled == false` is the DEBUG / pure-offline
    /// path where no publisher is installed; production shell wiring should
    /// emit success or failure with `publisherInstalled == true`.
    func emitCompletionPublishResult(
        _ record: WorkoutCompletionRecord,
        publisherInstalled: Bool,
        errorDescription: String?
    ) {
        let base = Self.completionPayload(record)
        let payload = CompletionPublishEventPayload(
            workoutID: base.workoutID,
            setLogCount: base.setLogCount,
            primitiveSetLogCount: base.primitiveSetLogCount,
            hasNote: base.hasNote,
            publisherInstalled: publisherInstalled,
            error: errorDescription.map(Self.trimTelemetryError)
        )
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: errorDescription == nil ? "state" : "error",
            name: errorDescription == nil
                ? "execution.completion_publish_finished"
                : "execution.completion_publish_failed",
            dataJSON: Self.encodeTelemetryPayload(payload),
            workoutID: record.workoutID
        ))
    }

    /// Emit after the local completion writer returns to the view model.
    /// This proves ordering relative to session clear. The shell writer
    /// emits lower-level cache success/failure events for actual SwiftData
    /// write outcomes.
    func emitCompletionLocalWriterCompleted(_ record: WorkoutCompletionRecord) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.completion_local_writer_completed",
            dataJSON: Self.encodeTelemetryPayload(Self.completionPayload(record)),
            workoutID: record.workoutID
        ))
    }

    // MARK: - Telemetry payload encoding

    /// Encode an `Encodable` telemetry payload into a JSON string for
    /// `Event.dataJSON`. Uses a local `JSONEncoder` per call — the
    /// payload is a handful of fields and the allocation overhead is
    /// well below the push queue's dispatch cost. Encoding cannot fail
    /// for the payloads below (all fields are `String` / `Int` / `Bool`),
    /// so we force-try rather than propagating a throws up a telemetry
    /// emit path that is fire-and-forget by contract.
    static func encodeTelemetryPayload<Payload: Encodable>(_ payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(payload)
        // swiftlint:disable:next force_unwrapping
        return String(data: data, encoding: .utf8)!
    }

    private static func completionPayload(_ record: WorkoutCompletionRecord) -> CompletionEventPayload {
        CompletionEventPayload(
            workoutID: record.workoutID.wireID,
            setLogCount: record.setLogs.count,
            primitiveSetLogCount: record.primitiveSetLogs.count,
            hasNote: record.notes != nil
        )
    }

    private static func trimTelemetryError(_ description: String) -> String {
        String(description.prefix(240))
    }
}

// MARK: - Telemetry payloads

/// Payload for `execution.exercise_swap`. `itemID` / `fromExerciseID` /
/// `toExerciseID` are pre-lowercased via `.wireID` by the emitter; keys
/// are snake_case to match the server's analytics conventions (and the
/// existing invariants documented in `docs/sync.md` § "Wire identifiers").
private struct SwapEventPayload: Encodable {
    let itemID: String
    let fromExerciseID: String
    let toExerciseID: String
    let hadOverrides: Bool
    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case fromExerciseID = "from_exercise_id"
        case toExerciseID = "to_exercise_id"
        case hadOverrides = "had_overrides"
    }
}

/// Payload for `execution.past_set_edited`. Historical field names use
/// camelCase here (not snake_case) because the History surface's
/// `history.past_set_edited` event already ships the same shape and flipping
/// both in one cutover is out of scope for R1.3 — the fix is ID casing, not
/// field-name normalization.
private struct PastSetEditedEventPayload: Encodable {
    let itemID: String
    let setIndex: Int
    let setLogID: String
}

/// Payload for `execution.autoreg_proposed`. Keys are snake_case to
/// match the documented shape in `docs/observability-map.md` ("Log
/// with RIR that triggers autoreg" row). `itemID` is pre-lowercased via
/// `.wireID` by the emitter; `reason` carries the canonical
/// `overshoot` / `undershoot_reps` / `hit_failure` token.
private struct AutoregProposedEventPayload: Encodable {
    let itemID: String
    let setIndex: Int
    let proposedLoadKg: Double
    let stepKg: Double
    let reason: String
    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case setIndex = "set_index"
        case proposedLoadKg = "proposed_load_kg"
        case stepKg = "step_kg"
        case reason
    }
}

/// Common completion event payload. `workout_id` is repeated in `data_json`
/// even though `Event.workoutID` is also populated so JSONL exports can be
/// inspected without joining the typed columns.
private struct CompletionEventPayload: Encodable {
    let workoutID: String
    let setLogCount: Int
    let primitiveSetLogCount: Int
    let hasNote: Bool
    enum CodingKeys: String, CodingKey {
        case workoutID = "workout_id"
        case setLogCount = "set_log_count"
        case primitiveSetLogCount = "primitive_set_log_count"
        case hasNote = "has_note"
    }
}

private struct CompletionPublishEventPayload: Encodable {
    let workoutID: String
    let setLogCount: Int
    let primitiveSetLogCount: Int
    let hasNote: Bool
    let publisherInstalled: Bool
    let error: String?
    enum CodingKeys: String, CodingKey {
        case workoutID = "workout_id"
        case setLogCount = "set_log_count"
        case primitiveSetLogCount = "primitive_set_log_count"
        case hasNote = "has_note"
        case publisherInstalled = "publisher_installed"
        case error
    }
}

/// Payload for `execution.tabata_multi_item_collapsed`. Keys are
/// snake_case — matches the wire convention set by `SwapEventPayload`.
/// Dropped exercise ids are pre-lowercased via `.wireID` so the
/// "every id on the wire is lowercase UUID" invariant holds. See
/// `docs/sync.md` § "Wire identifiers".
private struct TabataMultiItemCollapsePayload: Encodable {
    let blockIndex: Int
    let droppedItemCount: Int
    let droppedExerciseIDs: [String]
    enum CodingKeys: String, CodingKey {
        case blockIndex = "block_index"
        case droppedItemCount = "dropped_item_count"
        case droppedExerciseIDs = "dropped_exercise_ids"
    }
}
