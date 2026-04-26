// PushQueue+DeadLetter.swift
//
// Dead-letter telemetry payload builders for `PushQueue`, split out of
// `PushQueue.swift` so the actor body stays under SwiftLint's
// `type_body_length` cap. These helpers build the `dataJSON` blob that
// rides on the `execution.push_item_dead_lettered` event; the actor
// calls into them from `handlePersistent4xx`.

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation

extension PushQueue {

    /// Build the `dataJSON` payload for the dead-letter event. Shape is
    /// stable — the server's telemetry consumer reads these fields.
    ///
    /// A correlation field (`set_log_id` / `user_parameter_id` /
    /// `workout_id`) is included when the payload carries a single
    /// logical id so an operator can trace the dropped row back to the
    /// specific entity. `.events` payloads have no single id (a batch
    /// of telemetry events) — the correlation field is omitted there.
    /// `.setLogs` batches use the first log's id; single-log enqueues
    /// (the dominant shape via per-id dedup) are unambiguous, and the
    /// first id still lets an operator pull the batch.
    func deadLetterDataJSON(
        item: PushItem,
        status: Int,
        attempts: Int
    ) -> String {
        let kind = payloadKind(for: item.payload)
        let correlation = correlationField(for: item.payload)
        let base = #""payload_kind":"\#(kind)","http_status":\#(status),"attempts":\#(attempts)"#
        if let correlation {
            return "{\(base),\(correlation)}"
        }
        return "{\(base)}"
    }

    /// Stable string key for the payload's kind — rides in the dead-letter
    /// event's `payload_kind` field so the telemetry consumer can bucket by
    /// shape.
    func payloadKind(for payload: PushItem.Payload) -> String {
        switch payload {
        case .setLogs: return "set_logs"
        case .statusUpdate: return "status_update"
        case .workoutReset: return "workout_reset"
        case .events: return "events"
        case .userParameter: return "user_parameter"
        }
    }

    /// Correlation field (`"key":"uuid"`) for a payload, or `nil` when
    /// the payload has no single id we can surface. IDs are rendered via
    /// `.wireID` so the dead-letter event matches every other outbound
    /// id's lowercasing convention.
    ///
    /// `.events` was previously always nil, which made QA11 dead-letter
    /// rows untraceable (qa-037 — payload landed as
    /// `{payload_kind, http_status, attempts}` only). The first event's
    /// `setLogID` is preferred correlation when present; failing that,
    /// `workoutID` lets the operator at least trace the drop back to
    /// the workout the event was tagged with. Batches with neither id
    /// still return nil — we do not synthesize correlation out of thin
    /// air.
    private func correlationField(for payload: PushItem.Payload) -> String? {
        switch payload {
        case .setLogs(let logs):
            guard let first = logs.first else { return nil }
            return #""set_log_id":"\#(first.id.wireID)""#
        case .statusUpdate(let workoutID, _, _, _):
            return #""workout_id":"\#(workoutID.wireID)""#
        case .workoutReset(let workoutID):
            return #""workout_id":"\#(workoutID.wireID)""#
        case .userParameter(let param):
            return #""user_parameter_id":"\#(param.id.wireID)""#
        case .events(let events):
            guard let first = events.first else { return nil }
            if let setLogID = first.setLogID {
                return #""set_log_id":"\#(setLogID.wireID)""#
            }
            if let workoutID = first.workoutID {
                return #""workout_id":"\#(workoutID.wireID)""#
            }
            return nil
        }
    }
}
