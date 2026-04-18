// SessionStateCodable.swift
//
// Features-layer Codable adapter around the pure `SessionState` value
// type in Core/Session. Core/Session intentionally does not declare
// `Codable` — the package stays clean of encoder dependencies and the
// Features layer owns the on-disk shape (see
// `Persistence/SessionStore.swift` header: "Persistence is the opaque
// bucket. This keeps the runtime-state type out of the storage layer.").
//
// The bytes persisted here are not a public contract — they're read
// and written by this same layer, and if the shape changes we migrate
// (export → transform → re-import, per `docs/MIGRATIONS.md`). For v0
// we keep it straightforward and JSON-friendly.

import Foundation
import CoreAutoreg
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

struct SessionStateCodable: Codable {
    let state: SessionState

    init(state: SessionState) {
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID
        case route
        case cursor
        case items
        case restEndsAt
        case blockEndsAt
        case workEndsAt
        case note
        case structure
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let workoutID = try c.decode(UUID.self, forKey: .workoutID)
        let route = try c.decode(SessionState.Route.self, forKey: .route)
        let cursor = try c.decode(CursorCodable.self, forKey: .cursor).value
        let items = try c.decode([ItemLogCodable].self, forKey: .items).map(\.value)
        let restEndsAt = try c.decodeIfPresent(Date.self, forKey: .restEndsAt)
        let blockEndsAt = try c.decodeIfPresent(Date.self, forKey: .blockEndsAt)
        let workEndsAt = try c.decodeIfPresent(Date.self, forKey: .workEndsAt)
        let note = try c.decode(String.self, forKey: .note)
        let structure = try c.decode(StructureCodable.self, forKey: .structure).value
        self.state = SessionState(
            workoutID: workoutID,
            route: route,
            cursor: cursor,
            items: items,
            restEndsAt: restEndsAt,
            blockEndsAt: blockEndsAt,
            workEndsAt: workEndsAt,
            note: note,
            structure: structure
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state.workoutID, forKey: .workoutID)
        try c.encode(state.route, forKey: .route)
        try c.encode(CursorCodable(value: state.cursor), forKey: .cursor)
        try c.encode(state.items.map(ItemLogCodable.init(value:)), forKey: .items)
        try c.encodeIfPresent(state.restEndsAt, forKey: .restEndsAt)
        try c.encodeIfPresent(state.blockEndsAt, forKey: .blockEndsAt)
        try c.encodeIfPresent(state.workEndsAt, forKey: .workEndsAt)
        try c.encode(state.note, forKey: .note)
        try c.encode(StructureCodable(value: state.structure), forKey: .structure)
    }
}

// MARK: - Route conformance

extension SessionState.Route: @retroactive Decodable {}
extension SessionState.Route: @retroactive Encodable {}

// MARK: - Nested codable shims

private struct CursorCodable: Codable {
    let blockIndex: Int
    let itemIndex: Int
    let setIndex: Int

    init(value: SessionState.Cursor) {
        blockIndex = value.blockIndex
        itemIndex = value.itemIndex
        setIndex = value.setIndex
    }

    var value: SessionState.Cursor {
        .init(blockIndex: blockIndex, itemIndex: itemIndex, setIndex: setIndex)
    }
}

private struct StructureCodable: Codable {
    let itemsPerBlock: [Int]
    let setsPerItem: [[Int]]
    // Optional for back-compat — payloads persisted before this field
    // existed decode cleanly and fall back to the `Structure`'s default
    // (zero-item blocks → `.zeroItem`, everything else → `.setMajor`).
    let advancementByBlock: [String]?

    init(value: SessionState.Structure) {
        itemsPerBlock = value.itemsPerBlock
        setsPerItem = value.setsPerItem
        advancementByBlock = value.advancementByBlock.map(\.rawValue)
    }

    var value: SessionState.Structure {
        let advancement = advancementByBlock?.compactMap(SessionState.BlockAdvancement.init(rawValue:))
        return .init(
            itemsPerBlock: itemsPerBlock,
            setsPerItem: setsPerItem,
            advancementByBlock: advancement
        )
    }
}

private struct ItemLogCodable: Codable {
    let itemID: UUID
    let autoregHeld: Bool
    let sets: [SetPlanCodable]
    let performedExerciseID: UUID?
    // Optional for back-compat — payloads persisted before this field
    // existed decode cleanly (no overrides in play).
    let overrides: AlternativeOverridesCodable?

    init(value: SessionState.ItemLog) {
        itemID = value.itemID
        autoregHeld = value.autoregHeld
        sets = value.sets.map(SetPlanCodable.init(value:))
        performedExerciseID = value.performedExerciseID
        overrides = value.overrides.map(AlternativeOverridesCodable.init(value:))
    }

    var value: SessionState.ItemLog {
        .init(
            itemID: itemID,
            autoregHeld: autoregHeld,
            sets: sets.map(\.value),
            performedExerciseID: performedExerciseID,
            overrides: overrides?.value
        )
    }
}

private struct AlternativeOverridesCodable: Codable {
    let reps: Int?
    let loadKg: Double?
    let targetRir: Int?

    init(value: AlternativeOverrides) {
        reps = value.reps
        loadKg = value.loadKg
        targetRir = value.targetRir
    }

    var value: AlternativeOverrides {
        AlternativeOverrides(reps: reps, loadKg: loadKg, targetRir: targetRir)
    }
}

private struct SetPlanCodable: Codable {
    let setIndex: Int
    let loadKg: Double
    let reps: Int
    let done: Bool
    let adjust: String?
    let rir: Int?

    init(value: SetPlan) {
        setIndex = value.setIndex
        loadKg = value.loadKg
        reps = value.reps
        done = value.done
        adjust = value.adjust?.rawValue
        rir = value.rir
    }

    var value: SetPlan {
        .init(
            setIndex: setIndex,
            loadKg: loadKg,
            reps: reps,
            done: done,
            adjust: adjust.flatMap(SetPlan.Adjust.init(rawValue:)),
            rir: rir
        )
    }
}
