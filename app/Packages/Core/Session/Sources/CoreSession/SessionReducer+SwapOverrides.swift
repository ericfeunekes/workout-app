// SessionReducer+SwapOverrides.swift
//
// Swap-override helpers, split out of `SessionReducer+Handlers.swift` so
// neither file exceeds SwiftLint's `file_length` cap. These helpers mirror
// `AlternativeOverrides` onto the runtime SetPlan rows and Structure that
// the reducer operates on.
//
// Everything here is pure — no I/O, no state outside the arguments — and
// package-internal.

import Foundation
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

extension SessionReducer {

    /// Mirror `reps` / `load_kg` / `sets` from `AlternativeOverrides` onto
    /// the non-done SetPlan rows. A `.manual` row has been explicitly
    /// edited by the user before the swap — we preserve that choice so
    /// the swap doesn't silently undo manual work. Done rows are history
    /// and never touched. `adjust` is left unchanged for the overridden
    /// rows — autoreg is still free to propose against them in subsequent
    /// logs.
    ///
    /// When `overrides.sets` is set AND `allowSetsResize` is true, the
    /// non-done tail is extended (new rows seeded at the override
    /// load/reps) or truncated (pending rows past the new end are
    /// dropped). Done rows are never truncated — history is sacred — so
    /// if the user has already logged more sets than the override
    /// specifies, the override's `sets` is effectively a floor and the
    /// done count wins.
    ///
    /// `allowSetsResize` is false for blocks whose advancement policy is
    /// not `.setMajor` (superset / circuit / AMRAP / EMOM / Tabata / forTime).
    /// In round-robin blocks the per-item `sets` counts are a shared
    /// `rounds` invariant — mutating one item's count would either skew
    /// the cursor walk or implicitly collapse/extend the whole block.
    /// Rather than guess the caller's intent, we drop the `sets` override
    /// and apply the rest of the override fields. Documented in
    /// `docs/prescription.md` § "Alternative prescription (overrides)".
    static func applyOverridesToSetPlans(
        _ sets: [SetPlan],
        overrides: AlternativeOverrides,
        allowSetsResize: Bool = true
    ) -> [SetPlan] {
        let mirrored = sets.map { set -> SetPlan in
            if set.done { return set }
            if set.adjust == .manual { return set }
            // `overrides.loadKg == nil` means the override doesn't
            // specify a load — inherit the SetPlan's existing load
            // (which itself may be nil for a BW row). This preserves
            // loadless-ness across a swap that only adjusts reps or
            // target_rir.
            let newLoad: Double? = overrides.loadKg ?? set.loadKg
            let newReps = overrides.reps ?? set.reps
            // Unit inheritance: when the override declares `weight_unit`,
            // the override wins; otherwise the parent SetPlan's unit is
            // preserved. Documented in `docs/prescription.md` § "Units
            // · alternative overrides".
            let newUnit = overrides.unit ?? set.unit
            if newLoad == set.loadKg && newReps == set.reps && newUnit == set.unit { return set }
            return SetPlan(
                setIndex: set.setIndex,
                loadKg: newLoad,
                unit: newUnit,
                reps: newReps,
                done: set.done,
                adjust: set.adjust,
                rir: set.rir
            )
        }
        guard allowSetsResize, let target = overrides.sets else { return mirrored }
        return resizedSetPlans(mirrored, targetCount: target, overrides: overrides)
    }

    /// Resize a SetPlan array to `targetCount` rows, preserving all done
    /// rows. When `targetCount` is below the done count, the done count
    /// wins (history is never truncated); the caller gets an array with
    /// all done rows plus any non-done rows whose setIndex is ≤ targetCount.
    private static func resizedSetPlans(
        _ sets: [SetPlan],
        targetCount: Int,
        overrides: AlternativeOverrides
    ) -> [SetPlan] {
        let doneCount = sets.filter { $0.done }.count
        let effective = max(targetCount, doneCount)
        var trimmed = sets.filter { $0.done || $0.setIndex <= effective }
        let currentMax = trimmed.map(\.setIndex).max() ?? 0
        if effective > currentMax {
            let tailSeed = trimmed.last(where: { !$0.done })
            // Nil-safe: override's nil `loadKg` inherits the tail's load
            // (which itself may be nil). Preserves the loadless semantic
            // when extending a BW item's set count via swap override.
            let seedLoad: Double? = overrides.loadKg ?? tailSeed?.loadKg
            let seedReps = overrides.reps ?? tailSeed?.reps ?? 0
            // Seed-row unit: override wins, else inherit the tail's unit;
            // fall back to .lb for a fully empty tail (R2.10 default).
            let seedUnit = overrides.unit ?? tailSeed?.unit ?? .lb
            for i in (currentMax + 1)...effective {
                trimmed.append(SetPlan(
                    setIndex: i,
                    loadKg: seedLoad,
                    unit: seedUnit,
                    reps: seedReps,
                    done: false,
                    adjust: nil
                ))
            }
        }
        return trimmed.sorted { $0.setIndex < $1.setIndex }
    }

    /// Map a flat `state.items` index back to the block/item-in-block
    /// coordinates used by `structure.setsPerItem`. Returns nil when the
    /// structure is malformed (shouldn't happen in practice — the seeder
    /// walks the same order).
    ///
    /// `public` so companion layers (FeaturesExecution) can classify a
    /// pending swap identically to `applySwap`. Telemetry in particular
    /// needs the block index to decide whether a `sets`-override will be
    /// rejected.
    public static func findBlockItemPosition(
        flatIndex: Int,
        in structure: SessionState.Structure
    ) -> (blockIndex: Int, itemInBlock: Int)? {
        var running = 0
        for (b, count) in structure.itemsPerBlock.enumerated() {
            if flatIndex < running + count {
                return (b, flatIndex - running)
            }
            running += count
        }
        return nil
    }

    /// Produce a new `Structure` with `setsPerItem[blockIndex][itemInBlock]`
    /// set to `newCount`. Everything else is carried over verbatim so the
    /// cursor-advance policy and itemsPerBlock stay in lockstep.
    static func updatingSetsPerItem(
        _ structure: SessionState.Structure,
        blockIndex: Int,
        itemInBlock: Int,
        newCount: Int
    ) -> SessionState.Structure {
        guard blockIndex < structure.setsPerItem.count,
              itemInBlock < structure.setsPerItem[blockIndex].count else {
            return structure
        }
        var setsPerItem = structure.setsPerItem
        setsPerItem[blockIndex][itemInBlock] = newCount
        return SessionState.Structure(
            itemsPerBlock: structure.itemsPerBlock,
            setsPerItem: setsPerItem,
            advancementByBlock: structure.advancementByBlock
        )
    }
}
