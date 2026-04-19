// SessionSeeder+RoundBased.swift
//
// Mode-aware seeding helpers split out of `SessionSeeder.swift` so the
// enum body stays under SwiftLint's `type_body_length` cap. These power
// the round-based modes (circuit / superset / forTime / tabata / amrap /
// emom) and the single-shot / interval-count modes (intervals /
// continuous) — per-item prescription-reading for the set-major modes
// (straight_sets / custom / rep_range / bodyweight / warmup / cluster /
// percent_1rm) lives in the main file.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

extension SessionSeeder {

    /// Produce the SetPlan rows for an item within a block. Mode-aware:
    /// round-based modes seed `block.rounds` rows per item (regardless
    /// of the item's own `sets` field); Tabata seeds 8; intervals seeds
    /// `interval_count`; continuous seeds 1; AMRAP/EMOM seed a sentinel
    /// cap (see `unboundedRoundsSentinel`) and let the VM's time-cap path
    /// terminate the block. Other modes (straight_sets / rep_range /
    /// bodyweight / warmup / cluster / percent_1rm / custom) fall through
    /// to per-item prescription-reading via `seedSets(for:parser:)`.
    static func setRowsForBlock(
        block: Block?,
        item: WorkoutItem,
        parser: PrescriptionParser = PrescriptionParser()
    ) -> [SetPlan] {
        guard let block else {
            return seedSets(for: item, parser: parser)
        }
        let (reps, loadKg, unit) = itemRepsAndLoad(for: item, parser: parser)
        switch block.timingMode {
        case .circuit, .superset, .forTime:
            let rounds = max(block.rounds ?? 1, 1)
            // Authored-nil load stays nil — a BW station in a circuit or
            // superset must render "BW" end-to-end, not "0 lb".
            return seedUniform(sets: rounds, loadKg: loadKg, unit: unit, reps: reps)
        case .tabata:
            return seedUniform(sets: 8, loadKg: loadKg, unit: unit, reps: reps)
        case .intervals:
            let count = intervalCount(from: block, parser: parser)
            // Cardio intervals carry no external load — seed loadKg: nil.
            return seedUniform(sets: max(count, 1), loadKg: nil, unit: unit, reps: reps)
        case .continuous:
            // Continuous cardio — no external load. Seed loadKg: nil.
            return seedUniform(sets: 1, loadKg: nil, unit: unit, reps: reps)
        case .amrap, .emom:
            return seedUniform(
                sets: unboundedRoundsSentinel,
                loadKg: loadKg,
                unit: unit,
                reps: reps
            )
        case .rest:
            return []
        case .straightSets, .custom:
            // Straight sets and custom read per-item prescriptions
            // unchanged — preserves behavior for all the sparse shapes
            // (rep_range, sets_detail, bodyweight, warmup, cluster,
            // percent_1rm) that author their own `sets`.
            return seedSets(for: item, parser: parser)
        }
    }

    /// Pull `(reps, optional load_kg, unit)` off an item's prescription
    /// for the round-based seeders. Defensive across every Prescription
    /// shape: unknown/empty shapes collapse to (0, nil, .lb) — `.lb` is
    /// the R2.10 default when no unit signal is available.
    static func itemRepsAndLoad(
        for item: WorkoutItem,
        parser: PrescriptionParser
    ) -> (reps: Int, loadKg: Double?, unit: WeightUnit) {
        switch parser.parseTolerantOfAutoreg(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            switch p {
            case .straightSets(_, let reps, let loadKg, let unit, _, _, _, _):
                let n: Int
                if let rc = reps, case .count(let k) = rc { n = k } else { n = 0 }
                return (n, loadKg, unit)
            case .bodyweight(_, let reps, _):
                return (reps, nil, .lb)
            case .repRange(_, _, let repsMax, let loadKg, let unit, _, _):
                return (repsMax, loadKg, unit)
            case .cluster(_, let reps, let loadKg, let unit, _, _, _):
                return (reps, loadKg, unit)
            case .warmup(_, let reps, let loadKg, let unit):
                return (reps, loadKg, unit)
            case .percentOf1RM(_, let reps, _, _):
                return (reps, nil, .lb)
            case .amrapToken(let loadKg, let unit, _):
                // AMRAP token inside a round-based block (e.g. a superset
                // finisher or a circuit station) — preserve authored
                // load/unit so a weighted AMRAP token renders its load.
                // `reps=0` is the open-entry sentinel (the user enters the
                // observed count at log time).
                return (0, loadKg, unit)
            case .setsDetail, .empty:
                return (0, nil, .lb)
            }
        case .failure:
            return (0, nil, .lb)
        }
    }

    /// Read `interval_count` off an intervals block's timing config.
    /// Defaults to 1 on parse failure so the seeder still produces a row.
    static func intervalCount(
        from block: Block,
        parser: PrescriptionParser
    ) -> Int {
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            if case .intervals(_, _, _, _, let count, _) = config {
                return count
            }
            return 1
        case .failure:
            return 1
        }
    }

    /// Decide the advancement policy for a block. Round-based modes use
    /// `roundRobin`; set-major modes (straight_sets, rep_range, sets_detail,
    /// bodyweight, warmup, cluster, percent_1rm, custom) use `setMajor`;
    /// single-item unbounded and single-shot modes (intervals, continuous)
    /// collapse to `setMajor` since there's only one item to walk; and
    /// AMRAP/EMOM use `roundRobin` so the cursor cycles items per round.
    /// Zero-item blocks (rest) are `zeroItem`.
    static func advancement(
        for block: Block?,
        itemCount: Int
    ) -> SessionState.BlockAdvancement {
        if itemCount == 0 { return .zeroItem }
        guard let block else { return .setMajor }
        switch block.timingMode {
        case .circuit, .superset, .forTime, .tabata, .amrap, .emom:
            return .roundRobin
        case .straightSets, .custom, .intervals, .continuous:
            return .setMajor
        case .rest:
            return .zeroItem
        }
    }
}
