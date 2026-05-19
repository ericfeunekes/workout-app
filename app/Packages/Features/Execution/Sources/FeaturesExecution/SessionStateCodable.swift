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
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

struct SessionStateCodable: Codable, Sendable {
    /// Persistence-format marker for snapshots written after straight sets
    /// gained an explicit Set Start boundary. Older snapshots can have
    /// `workStartedAt` stamped by workout start/rest advance, so restore
    /// normalization treats them as READY rather than already-started.
    let explicitSetStartAware: Bool
    let state: SessionState
    let primitiveSetLogs: [PrimitiveSetLog]

    init(state: SessionState, primitiveSetLogs: [PrimitiveSetLog] = []) {
        self.explicitSetStartAware = true
        self.state = state
        self.primitiveSetLogs = primitiveSetLogs
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID
        case route
        case cursor
        case items
        case compositeSets
        case restEndsAt
        case blockEndsAt
        case workEndsAt
        case intervalAnchorAt
        case workReadyAt
        case workStartedAt
        case note
        case structure
        case explicitSetStartAware
        case primitiveSetLogs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let workoutID = try c.decode(UUID.self, forKey: .workoutID)
        let route = try c.decode(SessionState.Route.self, forKey: .route)
        let cursor = try c.decode(CursorCodable.self, forKey: .cursor).value
        let items = try c.decode([ItemLogCodable].self, forKey: .items).map(\.value)
        let compositeSets = try c.decodeIfPresent(
            [CompositeSetProgressCodable].self,
            forKey: .compositeSets
        )?.map { try $0.decodedValue() } ?? []
        let restEndsAt = try c.decodeIfPresent(Date.self, forKey: .restEndsAt)
        let blockEndsAt = try c.decodeIfPresent(Date.self, forKey: .blockEndsAt)
        let workEndsAt = try c.decodeIfPresent(Date.self, forKey: .workEndsAt)
        // Optional for back-compat — payloads persisted before the EMOM
        // boundary-anchor fix decode cleanly with `intervalAnchorAt = nil`;
        // the VM's restore normalization path restamps on block entry.
        let intervalAnchorAt = try c.decodeIfPresent(Date.self, forKey: .intervalAnchorAt)
        // Optional for back-compat — older payloads had no ready/prep
        // anchor because work started immediately on Active entry.
        let workReadyAt = try c.decodeIfPresent(Date.self, forKey: .workReadyAt)
        // Optional for back-compat — payloads persisted before the
        // working-time anchor fix decode cleanly with
        // `workStartedAt = nil`. A restored mid-set session with a nil
        // anchor will stamp `SetPlan.startedAt` as nil on the NEXT log;
        // downstream analysis treats that as "work window unknown"
        // rather than collapsing start + complete onto the same instant.
        let workStartedAt = try c.decodeIfPresent(Date.self, forKey: .workStartedAt)
        let explicitSetStartAware = try c.decodeIfPresent(
            Bool.self,
            forKey: .explicitSetStartAware
        ) ?? false
        let note = try c.decode(String.self, forKey: .note)
        // `StructureCodable.decodedValue()` throws on unknown or count-
        // mismatched `advancementByBlock`. Propagating the throw makes
        // `restoreIfPossible` treat the payload as "no saved state" and
        // re-seed from the pulled workout rather than silently dropping
        // an unknown enum case and mis-aligning later blocks' policies.
        let structure = try c.decode(StructureCodable.self, forKey: .structure).decodedValue()
        let primitiveSetLogs = try c.decodeIfPresent(
            [PrimitiveSetLogCodable].self,
            forKey: .primitiveSetLogs
        )?.map { try $0.decodedValue() } ?? []
        self.explicitSetStartAware = explicitSetStartAware
        self.state = SessionState(
            workoutID: workoutID,
            route: route,
            cursor: cursor,
            items: items,
            compositeSets: compositeSets,
            restEndsAt: restEndsAt,
            blockEndsAt: blockEndsAt,
            workEndsAt: workEndsAt,
            intervalAnchorAt: intervalAnchorAt,
            workReadyAt: workReadyAt,
            workStartedAt: workStartedAt,
            note: note,
            structure: structure
        )
        self.primitiveSetLogs = primitiveSetLogs
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state.workoutID, forKey: .workoutID)
        try c.encode(state.route, forKey: .route)
        try c.encode(CursorCodable(value: state.cursor), forKey: .cursor)
        try c.encode(state.items.map(ItemLogCodable.init(value:)), forKey: .items)
        try c.encode(state.compositeSets.map(CompositeSetProgressCodable.init(value:)), forKey: .compositeSets)
        try c.encodeIfPresent(state.restEndsAt, forKey: .restEndsAt)
        try c.encodeIfPresent(state.blockEndsAt, forKey: .blockEndsAt)
        try c.encodeIfPresent(state.workEndsAt, forKey: .workEndsAt)
        try c.encodeIfPresent(state.intervalAnchorAt, forKey: .intervalAnchorAt)
        try c.encodeIfPresent(state.workReadyAt, forKey: .workReadyAt)
        try c.encodeIfPresent(state.workStartedAt, forKey: .workStartedAt)
        try c.encode(state.note, forKey: .note)
        try c.encode(StructureCodable(value: state.structure), forKey: .structure)
        try c.encode(explicitSetStartAware, forKey: .explicitSetStartAware)
        try c.encode(primitiveSetLogs.map(PrimitiveSetLogCodable.init(value:)), forKey: .primitiveSetLogs)
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

    /// Decode `Structure`, refusing payloads whose `advancementByBlock`
    /// carries an unknown raw value or a count that doesn't match
    /// `itemsPerBlock`. The old shape used `compactMap(rawValue:)`, which
    /// silently dropped unknown entries and shifted later block policies
    /// onto earlier block indices — a future enum case landing on a phone
    /// still running an older build would corrupt the round-robin policy
    /// of every subsequent block. Throwing here forces the caller
    /// (`restoreIfPossible`) down the "no saved state" path so the
    /// session re-seeds rather than silently mis-advancing.
    func decodedValue() throws -> SessionState.Structure {
        guard let raws = advancementByBlock else {
            return .init(
                itemsPerBlock: itemsPerBlock,
                setsPerItem: setsPerItem,
                advancementByBlock: nil
            )
        }
        var advancement: [SessionState.BlockAdvancement] = []
        advancement.reserveCapacity(raws.count)
        for raw in raws {
            guard let decoded = SessionState.BlockAdvancement(rawValue: raw) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: [],
                        debugDescription: "Unknown BlockAdvancement rawValue: \(raw). "
                            + "Refusing to restore — the session will re-seed from the "
                            + "pulled workout rather than silently drop the policy and "
                            + "shift later blocks onto earlier indices."
                    )
                )
            }
            advancement.append(decoded)
        }
        guard advancement.count == itemsPerBlock.count else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "advancementByBlock count (\(advancement.count)) "
                        + "must equal itemsPerBlock count (\(itemsPerBlock.count)). "
                        + "Refusing to restore — a size mismatch would shift policies "
                        + "off their blocks."
                )
            )
        }
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

private struct CompositeSetProgressCodable: Codable {
    let itemID: UUID
    let setIndex: Int
    let kind: String
    let targetRepsPerSlot: Int
    let slotCount: Int
    let intraRestSec: Double
    let firstStartedAt: Date?
    let phase: CompositeSetPhaseCodable
    let completedSlots: Int

    init(value: SessionState.CompositeSetProgress) {
        itemID = value.itemID
        setIndex = value.setIndex
        kind = value.kind.rawValue
        targetRepsPerSlot = value.targetRepsPerSlot
        slotCount = value.slotCount
        intraRestSec = value.intraRestSec
        firstStartedAt = value.firstStartedAt
        phase = CompositeSetPhaseCodable(value: value.phase)
        completedSlots = value.completedSlots
    }

    func decodedValue() throws -> SessionState.CompositeSetProgress {
        .init(
            itemID: itemID,
            setIndex: setIndex,
            kind: SessionState.CompositeSetProgress.Kind(rawValue: kind) ?? .cluster,
            targetRepsPerSlot: targetRepsPerSlot,
            slotCount: slotCount,
            intraRestSec: intraRestSec,
            firstStartedAt: firstStartedAt,
            phase: try phase.decodedValue(),
            completedSlots: completedSlots
        )
    }
}

private struct PrimitiveSetLogCodable: Codable {
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
    let isWarmup: Bool
    let skipped: Bool?
    let side: String?
    let notes: String?
    let completedAt: Date

    init(value: PrimitiveSetLog) {
        id = value.id
        role = value.role.rawValue
        slotID = value.slotID
        setID = value.setID
        blockID = value.blockID
        workoutID = value.workoutID
        plannedExerciseID = value.plannedExerciseID
        performedExerciseID = value.performedExerciseID
        setIndex = value.setIndex
        setRepeatIndex = value.setRepeatIndex
        blockRepeatIndex = value.blockRepeatIndex
        reps = value.reps
        weight = value.weight
        weightUnit = value.weightUnit?.rawValue
        durationSec = value.durationSec
        distanceM = value.distanceM
        rounds = value.rounds
        rir = value.rir
        isWarmup = value.isWarmup
        skipped = value.skipped
        side = value.side.rawValue
        notes = value.notes
        completedAt = value.completedAt
    }

    func decodedValue() throws -> PrimitiveSetLog {
        guard let role = PrimitiveLogRole(rawValue: role) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unknown primitive log role: \(role)")
            )
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
            isWarmup: isWarmup,
            skipped: skipped ?? false,
            side: side.flatMap { SetLogSide(rawValue: $0) } ?? .bilateral,
            notes: notes,
            completedAt: completedAt
        )
    }
}

private struct CompositeSetPhaseCodable: Codable {
    let name: String
    let slotIndex: Int?
    let afterSlotIndex: Int?
    let startedAt: Date?
    let endsAt: Date?

    init(value: SessionState.CompositeSetProgress.Phase) {
        switch value {
        case .ready(let slotIndex):
            name = "ready"
            self.slotIndex = slotIndex
            afterSlotIndex = nil
            startedAt = nil
            endsAt = nil
        case .working(let slotIndex, let startedAt):
            name = "working"
            self.slotIndex = slotIndex
            afterSlotIndex = nil
            self.startedAt = startedAt
            endsAt = nil
        case .intraRest(let afterSlotIndex, let endsAt):
            name = "intraRest"
            slotIndex = nil
            self.afterSlotIndex = afterSlotIndex
            startedAt = nil
            self.endsAt = endsAt
        case .completePendingLog:
            name = "completePendingLog"
            slotIndex = nil
            afterSlotIndex = nil
            startedAt = nil
            endsAt = nil
        }
    }

    func decodedValue() throws -> SessionState.CompositeSetProgress.Phase {
        switch name {
        case "ready":
            guard let slotIndex else {
                throw Self.missingField("slotIndex", phase: name)
            }
            return .ready(slotIndex: slotIndex)
        case "working":
            guard let slotIndex else {
                throw Self.missingField("slotIndex", phase: name)
            }
            guard let startedAt else {
                throw Self.missingField("startedAt", phase: name)
            }
            return .working(slotIndex: slotIndex, startedAt: startedAt)
        case "intraRest":
            guard let afterSlotIndex else {
                throw Self.missingField("afterSlotIndex", phase: name)
            }
            guard let endsAt else {
                throw Self.missingField("endsAt", phase: name)
            }
            return .intraRest(
                afterSlotIndex: afterSlotIndex,
                endsAt: endsAt
            )
        case "completePendingLog":
            return .completePendingLog
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unknown composite set phase '\(name)'"
                )
            )
        }
    }

    private static func missingField(_ field: String, phase: String) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Composite set phase '\(phase)' missing required field '\(field)'"
            )
        )
    }
}

private struct AlternativeOverridesCodable: Codable {
    let sets: Int?
    let reps: Int?
    let loadKg: Double?
    /// Persisted override unit. Optional on the wire; `nil` means the
    /// override inherits the parent SetPlan's unit. Back-compat: payloads
    /// persisted before R2.10 decode with `unit == nil`, which preserves
    /// the pre-cutover behavior.
    let unit: String?
    let targetRir: Int?
    let perSide: Bool?
    let autoreg: AutoregOverridesCodable?

    init(value: AlternativeOverrides) {
        sets = value.sets
        reps = value.reps
        loadKg = value.loadKg
        unit = value.unit?.rawValue
        targetRir = value.targetRir
        perSide = value.perSide
        autoreg = value.autoreg.map(AutoregOverridesCodable.init(value:))
    }

    var value: AlternativeOverrides {
        AlternativeOverrides(
            sets: sets,
            reps: reps,
            loadKg: loadKg,
            unit: unit.flatMap(WeightUnit.init(rawValue:)),
            targetRir: targetRir,
            perSide: perSide,
            autoreg: autoreg?.value
        )
    }
}

private struct AutoregOverridesCodable: Codable {
    let overshootAt: Int?
    let overshootStepKg: Double?
    let undershootAt: Int?
    let undershootStepKg: Double?
    let applyTo: String?

    init(value: AutoregOverrides) {
        overshootAt = value.overshootAt
        overshootStepKg = value.overshootStepKg
        undershootAt = value.undershootAt
        undershootStepKg = value.undershootStepKg
        applyTo = value.applyTo?.rawValue
    }

    var value: AutoregOverrides {
        AutoregOverrides(
            overshootAt: overshootAt,
            overshootStepKg: overshootStepKg,
            undershootAt: undershootAt,
            undershootStepKg: undershootStepKg,
            applyTo: applyTo.flatMap(Autoreg.ApplyTo.init(rawValue:))
        )
    }
}

private struct SetPlanCodable: Codable {
    let setIndex: Int
    /// Persisted load. Optional end-to-end: `nil` means loadless (BW /
    /// loadless AMRAP token / `.empty` placeholder). Payloads persisted
    /// before this field flipped optional carry a numeric value and
    /// decode cleanly — after the cutover new writes use nil for
    /// loadless rows so display, push, and History stay coherent.
    let loadKg: Double?
    /// Persisted unit. Optional on decode only — payloads persisted
    /// before R2.10 have no `unit` field and fall back to `.lb` (the
    /// post-R2.10 default matches pound-first authoring). Always non-nil
    /// on encode.
    let unit: String?
    let reps: Int
    let workTarget: WorkTargetCodable?
    let done: Bool
    let adjust: String?
    let rir: Int?
    /// Wall-clock stamp for when the user logged this set. Optional
    /// because (a) pending sets have no stamp, (b) payloads persisted
    /// before the field existed decode cleanly as nil. Encoded
    /// losslessly via `Date`'s default Codable (timeIntervalSinceReferenceDate).
    let completedAt: Date?
    /// Elapsed/cardio metric fields. All optional for back-compat:
    /// payloads persisted before the R2.11 cardio cutover decode cleanly
    /// with every metric nil. Composed strength rows may carry
    /// `durationSec`; distance/HR/cadence remain cardio metrics.
    let durationSec: Double?
    let distanceM: Double?
    let hrAvgBpm: Int?
    let cadenceAvgSpm: Int?
    let startedAt: Date?
    let skipped: Bool?
    let side: String?

    init(value: SetPlan) {
        setIndex = value.setIndex
        loadKg = value.loadKg
        unit = value.unit.rawValue
        reps = value.reps
        workTarget = value.workTarget.map(WorkTargetCodable.init(value:))
        done = value.done
        adjust = value.adjust?.rawValue
        rir = value.rir
        completedAt = value.completedAt
        durationSec = value.durationSec
        distanceM = value.distanceM
        hrAvgBpm = value.hrAvgBpm
        cadenceAvgSpm = value.cadenceAvgSpm
        startedAt = value.startedAt
        skipped = value.skipped
        side = value.side.rawValue
    }

    var value: SetPlan {
        .init(
            setIndex: setIndex,
            loadKg: loadKg,
            unit: unit.flatMap(WeightUnit.init(rawValue:)) ?? .lb,
            reps: reps,
            workTarget: workTarget?.value,
            done: done,
            adjust: adjust.flatMap(SetPlan.Adjust.init(rawValue:)),
            rir: rir,
            completedAt: completedAt,
            durationSec: durationSec,
            distanceM: distanceM,
            hrAvgBpm: hrAvgBpm,
            cadenceAvgSpm: cadenceAvgSpm,
            startedAt: startedAt,
            skipped: skipped ?? false,
            side: side.flatMap(SetLogSide.init(rawValue:)) ?? .bilateral
        )
    }
}

private struct WorkTargetCodable: Codable {
    let kind: String
    let amount: Double
    let unit: String

    init(value: WorkTarget) {
        kind = value.kind.rawValue
        amount = value.value
        unit = value.unit.rawValue
    }

    var value: WorkTarget? {
        guard let kind = WorkTarget.Kind(rawValue: kind),
              let unit = WorkTarget.Unit(rawValue: unit) else {
            return nil
        }
        return WorkTarget(kind: kind, value: amount, unit: unit)
    }
}
