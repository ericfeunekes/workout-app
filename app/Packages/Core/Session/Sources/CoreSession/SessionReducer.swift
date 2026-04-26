// SessionReducer.swift
//
// Pure value-type reducer: `reduce(state, mutation) -> state`. No throws,
// no I/O, no observability. Invalid mutations (e.g., `logSet` with an
// unknown itemID, or a setIndex that doesn't exist) are silent no-ops —
// the reducer returns the unchanged state. This matches the project's
// "dumb app" posture: the app never panics on bad input, it just keeps
// showing the last known good state.
//
// Rules reference (authoritative sources):
//   - app/README.md § "Core loop", "Autoregulation", "Tap-to-edit",
//     "Swap", "Persistence (local session)"
//   - docs/prescription.md § "Autoregulation" ("Hold scope",
//     "Autoreg + manual edit", "Edits don't retrigger")
//
// Notes on the reducer's API shape:
//   - `reduce` takes and returns `SessionState` by value. Swift's
//     copy-on-write keeps this cheap for arrays; the win is that every
//     state transition is a pure function that a test can call with a
//     constructed state and compare the output against an expected
//     state. No persistence, no UI, no scheduling inside here.
//   - Mutations that require external data (e.g., `.save` needing fresh
//     items seeded from the prescription) accept that data as
//     associated values. Core/Session doesn't read the prescription —
//     the Features layer does, and passes the result in.

import Foundation
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

public enum SessionReducer {

    public static func reduce(
        _ state: SessionState,
        _ mutation: SessionMutation
    ) -> SessionState {
        switch mutation {
        case .start, .enterRest, .extendRest, .advanceFromRest,
             .enterTransition, .beginTransition, .complete:
            return reduceRouteMutation(state, mutation)
        case .save, .logSet, .skipSet, .startCompositeSlot, .completeCompositeSlot,
             .finalizeCompositeSet, .logCardioSet, .editPendingSet,
             .markPendingSetStarted, .editPastSet, .applyAutoregProposal:
            return reduceSetMutation(state, mutation)
        case .swap, .holdAutoreg, .appendNote:
            return reduceItemOrNoteMutation(state, mutation)
        }
    }

    /// Handle the route-level mutations — pure state-route transitions that
    /// don't touch per-set data.
    private static func reduceRouteMutation(
        _ state: SessionState,
        _ mutation: SessionMutation
    ) -> SessionState {
        switch mutation {
        case .start:
            var next = state
            next.route = .active
            return next
        case .enterRest(let durationSec, let now):
            var next = state
            next.restEndsAt = now.addingTimeInterval(durationSec)
            // Tabata's per-round work window ends at .enterRest — the
            // VM dispatched this transition precisely because the work
            // window (or the user logging mid-window) closed.
            next.workEndsAt = nil
            next.route = .rest
            return next
        case .extendRest(let durationSec):
            guard state.route == .rest,
                  durationSec > 0,
                  let restEndsAt = state.restEndsAt else {
                return state
            }
            var next = state
            next.restEndsAt = restEndsAt.addingTimeInterval(durationSec)
            return next
        case .advanceFromRest:
            return advanceCursor(from: state)
        case .enterTransition:
            var next = state
            next.route = .transition
            next.restEndsAt = nil
            next.workStartedAt = nil
            next.workReadyAt = nil
            return next
        case .beginTransition:
            var next = state
            guard next.route == .transition else { return state }
            next.route = .active
            return next
        case .complete:
            var next = state
            next.route = .complete
            return next
        default:
            return state
        }
    }

    /// Handle the mutations that produce or modify logged set data.
    private static func reduceSetMutation(
        _ state: SessionState,
        _ mutation: SessionMutation
    ) -> SessionState {
        switch mutation {
        case .save(let freshItems, let freshStructure):
            return applySave(state: state, freshItems: freshItems, freshStructure: freshStructure)
        case .logSet(let itemID, let setIndex, let loggedReps, let loggedRir, let now):
            let log = LogSetInput(
                itemID: itemID,
                setIndex: setIndex,
                loggedReps: loggedReps,
                loggedRir: loggedRir,
                now: now
            )
            return applyLogSet(state: state, input: log)
        case .skipSet(let itemID, let setIndex, let now):
            return applySkipSet(
                state: state,
                itemID: itemID,
                setIndex: setIndex,
                now: now
            )
        case .startCompositeSlot(let itemID, let setIndex, let slotIndex, let startedAt):
            return applyStartCompositeSlot(
                state: state,
                itemID: itemID,
                setIndex: setIndex,
                slotIndex: slotIndex,
                startedAt: startedAt
            )
        case .completeCompositeSlot(let itemID, let setIndex, let now):
            return applyCompleteCompositeSlot(
                state: state,
                itemID: itemID,
                setIndex: setIndex,
                now: now
            )
        case .finalizeCompositeSet(let itemID, let setIndex, let loggedReps, let loggedRir, let now):
            let log = LogSetInput(
                itemID: itemID,
                setIndex: setIndex,
                loggedReps: loggedReps,
                loggedRir: loggedRir,
                now: now
            )
            return applyFinalizeCompositeSet(state: state, input: log)
        case .logCardioSet:
            return reduceLogCardioSet(state: state, mutation: mutation)
        case .editPendingSet(let itemID, let setIndex, let loadKg, let reps, let rir, let startedAt):
            return applyEditPendingSet(
                state: state,
                itemID: itemID,
                setIndex: setIndex,
                loadKg: loadKg,
                reps: reps,
                rir: rir,
                startedAt: startedAt
            )
        case .markPendingSetStarted(let itemID, let setIndex, let startedAt):
            return applyMarkPendingSetStarted(
                state: state,
                itemID: itemID,
                setIndex: setIndex,
                startedAt: startedAt
            )
        case .editPastSet(let itemID, let setIndex, let loadKg, let reps, let rir):
            let edit = PastSetEdit(
                itemID: itemID,
                setIndex: setIndex,
                loadKg: loadKg,
                reps: reps,
                rir: rir
            )
            return applyEditPastSet(state: state, edit: edit)
        case .applyAutoregProposal(let itemID, let proposal):
            return applyAutoregProposal(state: state, itemID: itemID, proposal: proposal)
        default:
            return state
        }
    }

    /// Unpack a `.logCardioSet` mutation into `LogCardioSetInput` and
    /// hand it to the handler. Split out so `reduceSetMutation` stays
    /// under SwiftLint's `function_body_length` cap — the 8-field
    /// cardio tuple alone pushes the switch body past 40 lines.
    private static func reduceLogCardioSet(
        state: SessionState,
        mutation: SessionMutation
    ) -> SessionState {
        guard case let .logCardioSet(
            itemID,
            setIndex,
            durationSec,
            distanceM,
            hrAvgBpm,
            cadenceAvgSpm,
            startedAt,
            now
        ) = mutation else { return state }
        let log = LogCardioSetInput(
            itemID: itemID,
            setIndex: setIndex,
            durationSec: durationSec,
            distanceM: distanceM,
            hrAvgBpm: hrAvgBpm,
            cadenceAvgSpm: cadenceAvgSpm,
            startedAt: startedAt,
            now: now
        )
        return applyLogCardioSet(state: state, input: log)
    }

    /// Handle item-level and note-level mutations.
    private static func reduceItemOrNoteMutation(
        _ state: SessionState,
        _ mutation: SessionMutation
    ) -> SessionState {
        switch mutation {
        case .swap(let itemID, let toExerciseID, let overrides):
            return applySwap(
                state: state,
                itemID: itemID,
                toExerciseID: toExerciseID,
                overrides: overrides
            )
        case .holdAutoreg(let itemID):
            return applyHoldAutoreg(state: state, itemID: itemID)
        case .appendNote(let text):
            return applyAppendNote(state: state, text: text)
        default:
            return state
        }
    }

    /// A bundle of the fields that identify a past-set edit. Keeps
    /// `applyEditPastSet` under the `function_parameter_count` cap.
    struct PastSetEdit {
        let itemID: WorkoutItemID
        let setIndex: Int
        let loadKg: Double?
        let reps: Int?
        let rir: Int?
    }

    /// A bundle of the fields that identify a log-set action. Keeps
    /// `applyLogSet` under the `function_parameter_count` cap and
    /// mirrors the `PastSetEdit` pattern already in use here.
    struct LogSetInput {
        let itemID: WorkoutItemID
        let setIndex: Int
        let loggedReps: Int
        let loggedRir: Int?
        let now: Date
    }

    /// Sibling of `LogSetInput` for the cardio path. Every metric is
    /// optional — a time-only interval carries only `durationSec`;
    /// a distance-only piece carries only `distanceM`; HR and cadence
    /// are populated when a sensor is connected.
    struct LogCardioSetInput {
        let itemID: WorkoutItemID
        let setIndex: Int
        let durationSec: Double?
        let distanceM: Double?
        let hrAvgBpm: Int?
        let cadenceAvgSpm: Int?
        let startedAt: Date?
        let now: Date
    }

}

// The per-mutation handlers (`applyLogSet` etc.) and the cursor helpers live
// in `SessionReducer+Handlers.swift` so the enum body here stays under
// SwiftLint's `type_body_length` cap.
