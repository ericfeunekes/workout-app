// PrescriptionParser.swift
//
// Per-shape parsers for the prescription_json blob on a WorkoutItem and the
// timing_config_json blob on a Block. Returns `Result` — no throws. See
// docs/prescription.md for the authoring vocabulary and
// docs/architecture/swift-packages.md for package rules.
//
// ---------------------------------------------------------------------------
// Prescription discrimination rules (in order — first match wins)
// ---------------------------------------------------------------------------
//
// 1. Root is `{}`                                → .empty
// 2. `"sets_detail"` present                     → .setsDetail
//    (drop sets and per-set warm-ups live here as per-element flags)
// 3. `"sub_sets"` present                        → .cluster
// 4. `"percent_1rm"` present                     → .percentOf1RM
// 5. `"reps_min"` or `"reps_max"` present        → .repRange
// 6. `"warmup" == true` at item level            → .warmup
// 7. `"reps" == "amrap"` and no `"sets"`         → .amrapToken
// 8. `"sets"` + `"reps"` present, no `"load_kg"` → .bodyweight
//    and no `"percent_1rm"` / `"sub_sets"` / `"warmup"`
// 9. Otherwise                                   → .straightSets
//    (catch-all — covers straight_sets, superset items, circuit items,
//    emom items, for_time items, weighted bodyweight, tempo, per_side)
//
// The `tempo` and `per_side` keys are modifiers — they layer onto whatever
// shape the other keys decided, but in practice only .straightSets carries
// them. The bodyweight rule is specifically checked-for because the doc
// draws a hard line between "bodyweight" (load_kg omitted ⇒ "BW") and
// "weighted bodyweight" / straight sets (load_kg present).
//
// Parser/doc mismatch (Chunk 5 flag):
// * weighted_bodyweight cannot be distinguished from straight_sets at the
//   JSON layer — both are `{sets, reps, load_kg, target_rir, autoreg}`.
//   The UI decides "BW + 20 kg" from the Exercise reference. Fixture
//   `prescription_weighted_bodyweight.json` is exercised in tests as a
//   .straightSets.
// * for_time items with only `{"load_kg": 43}` route to .straightSets with
//   nil sets/reps; reps come from the block's `rounds_rep_scheme`.
// * amrap items with `{"reps": 10}` route to .straightSets (no sets key
//   at item level; rounds live on the block).
//
// File layout: this file holds the discriminator and the public entry
// points. Per-shape parsers live in `PrescriptionParser+Shapes.swift`,
// timing-config parsers in `PrescriptionParser+TimingConfig.swift` and
// `PrescriptionParser+IntervalConfigs.swift`, and the autoreg sub-parser in
// `PrescriptionParser+Autoreg.swift`. The split is there to keep each file
// under SwiftLint's `type_body_length` / `file_length` caps.

import Foundation

public struct PrescriptionParser: Sendable {

    public init() {}

    // MARK: - Prescription

    public func parse(
        prescriptionJSON: String
    ) -> Result<Prescription, ParseError> {
        switch parseRootObject(prescriptionJSON, shape: "prescription") {
        case .failure(let e): return .failure(e)
        case .success(let obj):
            return parse(dictionary: obj)
        }
    }

    /// Used by fixture tests that already have a decoded dict in hand.
    public func parse(
        dictionary obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        // 1. Empty object.
        if obj.isEmpty { return .success(.empty) }

        // 2. sets_detail present → .setsDetail (also handles drop sets and
        //    per-set warm-ups via SetDetail flags).
        if obj["sets_detail"] != nil {
            return parseSetsDetail(obj)
        }

        // 3. sub_sets present → .cluster
        if obj["sub_sets"] != nil {
            return parseCluster(obj)
        }

        // 4. percent_1rm present → .percentOf1RM
        if obj["percent_1rm"] != nil {
            return parsePercentOf1RM(obj)
        }

        // 5. reps_min / reps_max → .repRange
        if obj["reps_min"] != nil || obj["reps_max"] != nil {
            return parseRepRange(obj)
        }

        // 6. Whole-item warmup flag → .warmup
        //    (Per-set warmups are handled inside sets_detail, already
        //    covered above.)
        if let isWarmup = obj["warmup"] as? Bool, isWarmup {
            return parseWarmup(obj)
        }

        // 7. {"reps": "amrap"} with no "sets" → .amrapToken
        //    (A sets-carrying shape with reps:"amrap" is a full straight-
        //    sets prescription that happens to use the amrap token; we
        //    reach that via the catch-all in step 9.)
        if obj["sets"] == nil, let reps = obj["reps"] as? String, reps == "amrap" {
            return parseAmrapToken(obj)
        }

        // 8. bodyweight: sets + reps present, no load_kg, no percent_1rm,
        //    no warmup, no sub_sets, no sets_detail.
        if isBodyweightShape(obj) {
            return parseBodyweight(obj)
        }

        // 9. Catch-all → .straightSets.
        return parseStraightSets(obj)
    }

    private func isBodyweightShape(_ obj: [String: Any]) -> Bool {
        obj["sets"] != nil &&
        obj["reps"] != nil &&
        obj["load_kg"] == nil &&
        obj["percent_1rm"] == nil &&
        obj["sub_sets"] == nil &&
        obj["sets_detail"] == nil &&
        obj["warmup"] == nil
    }
}
