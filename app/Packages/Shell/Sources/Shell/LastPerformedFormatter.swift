// LastPerformedFormatter.swift
//
// Turns `PullService`'s raw `[LastPerformed]` into the pre-formatted
// per-exercise `[UUID: String]` map Today / SwapSheet render directly.
// One place so the chip string stays consistent between the Today card
// ("LAST TIME — 4 × 5 @ 100 kg · RIR 2") and the SwapSheet row
// ("LAST · 5×5 @ 100 kg · RIR 2"), both of which just look up the
// exercise id in the map.
//
// The shape of the summary matches the hi-fi reference (see
// `docs/design/src/hifi.jsx`) and the preview seeds
// (`TodayPreviewSeed.lastPerformed`, `ExecutionPreviewSeed.lastPerformed`):
//
//     "<workingSets>×<reps> @ <weight> <unit> · RIR <rir>"
//
// Derivation (working sets only — warmups are excluded from the count and
// from the representative-set pick):
//   1. Filter out warmups. If nothing remains, skip the exercise entirely
//      (we have no history to show).
//   2. Working-sets count is the post-filter count.
//   3. Pick the heaviest working set as the representative "reps @ weight"
//      line — top-set is what the user cares about at a glance. Ties break
//      on `setIndex` ascending so the output is deterministic.
//   4. Use that set's weight_unit if present; fall back to lb (Eric trains
//      mostly in pounds — see the user preference note in CLAUDE.md).
//   5. RIR segment is appended when the representative set carries a
//      non-nil `rir`; omitted otherwise so bodyweight / cardio logs don't
//      render a dangling "· RIR" suffix.
//
// Sets that carry no weight at all (pure bodyweight rows) render as
// "N×reps BW" — mirrors the preview seed for weighted-dips style entries
// where the load is the BW increment, not the raw number.

import Foundation
import CoreDomain
import Sync
import WorkoutCoreFoundation

enum LastPerformedFormatter {

    /// Turn a pulled `[LastPerformed]` list into the `[UUID: String]` map
    /// rendered by Today / SwapSheet. Exercises whose history contains
    /// only warmups, or contains no set_logs at all, are omitted — a
    /// missing key tells the UI to hide the chip rather than render an
    /// empty line.
    static func buildMap(from snapshots: [LastPerformed]) -> [UUID: String] {
        var out: [UUID: String] = [:]
        out.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            guard let summary = format(snapshot: snapshot) else { continue }
            out[snapshot.exerciseID] = summary
        }
        return out
    }

    /// Produce the summary line for a single per-exercise snapshot, or
    /// `nil` when there's nothing usable to render.
    static func format(snapshot: LastPerformed) -> String? {
        let workingSets = snapshot.lastSetLogs.filter { !$0.isWarmup }
        guard !workingSets.isEmpty else { return nil }

        // Representative set: heaviest weight wins; ties resolved by the
        // lowest setIndex so the output is deterministic when weights
        // tie (which is the straight-sets case).
        let rep = workingSets.max { lhs, rhs in
            let lw = lhs.weight ?? 0
            let rw = rhs.weight ?? 0
            if lw != rw { return lw < rw }
            // Equal weights — prefer the earlier set so the output is
            // stable across repeated calls on the same snapshot. `max`
            // keeps the right-hand element when the predicate returns
            // `true`, so we return `true` when `lhs` has the higher
            // (i.e. less-preferred) setIndex.
            return lhs.setIndex > rhs.setIndex
        }
        guard let rep else { return nil }

        let sets = workingSets.count
        let reps = rep.reps.map(String.init) ?? "?"
        let coreLine = "\(sets)×\(reps)"

        let loadPart: String
        if let weight = rep.weight, weight > 0 {
            let unit = rep.weightUnit ?? .lb
            // WeightUnit.rawValue already matches LoadUnit.rawValue
            // ("kg" / "lb") — no conversion needed.
            loadPart = " @ \(formatLoadNumber(weight)) \(unit.rawValue)"
        } else {
            // Pure bodyweight row — surface it explicitly so the user
            // can tell a zero-load row apart from a missing load.
            loadPart = " BW"
        }

        var summary = coreLine + loadPart
        if let rir = rep.rir {
            summary += " · RIR \(rir)"
        }
        return summary
    }
}
