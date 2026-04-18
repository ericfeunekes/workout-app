// Prescription.swift
//
// The top-level typed representation of `workout_item.prescription_json`.
// Each case represents a distinct authoring shape from
// docs/prescription.md. Modifiers that layer onto any shape (`per_side`,
// `tempo`) live as optional fields on individual cases rather than as their
// own cases — per the doc, they are decorators on an existing shape, not a
// standalone shape.
//
// Design notes:
// * Enum (not one big optional-heavy struct) makes illegal combinations
//   unrepresentable. Straight-sets + sets_detail can't coexist by accident.
// * `.empty` covers items inside `continuous`, `intervals`, `tabata`,
//   `rest`, and `custom` where the prescription body is literally `{}` and
//   all state lives on the block.
// * `sets` is optional on `.straightSets` because superset / circuit / emom
//   / amrap / for_time items don't carry `sets` — the round count lives on
//   the block (`rounds` / `interval_count` / `total_minutes`). The doc's
//   per-mode examples are consistent with this (see "superset" and
//   "circuit" items in docs/prescription.md).
// * `reps` is optional on `.straightSets` because for_time items can
//   carry only `load_kg` when the rep count comes from the block's
//   `rounds_rep_scheme`.
// * "Weighted bodyweight" (weighted dip, weighted pull-up) is NOT a distinct
//   case here because structurally the JSON is identical to straight-sets
//   — `{sets, reps, load_kg, target_rir, autoreg}`. The weighted-bodyweight
//   render ("BW + 20 kg") is a UI concern driven by the Exercise reference,
//   not by the prescription JSON alone. The fixture
//   prescription_weighted_bodyweight.json parses as .straightSets. This is
//   a parser/doc mismatch flagged in the Chunk 5 return summary.

import Foundation

public enum Prescription: Equatable, Sendable, Hashable {

    /// Default strength shape. `tempo` and `perSide` are modifiers per the
    /// doc (§ "Per-side", § "Tempo"). `sets` and `reps` are optional to
    /// accommodate superset / circuit / emom / for_time items where the
    /// block carries the round count or rep scheme.
    case straightSets(
        sets: Int?,
        reps: RepCount?,
        loadKg: Double?,
        targetRir: Int?,
        autoreg: Autoreg?,
        tempo: String?,
        perSide: Bool
    )

    /// `{ "sets": n, "reps": r, "percent_1rm": 0.85, "target_rir": rir? }`
    /// — load resolves at execution time by reading `1rm_<slug>_kg` from
    /// user_parameters.
    case percentOf1RM(
        sets: Int,
        reps: Int,
        percent: Double,
        targetRir: Int?
    )

    /// `{ "sets": n, "reps_min": lo, "reps_max": hi, "load_kg": kg?, "target_rir": rir? }`
    case repRange(
        sets: Int,
        repsMin: Int,
        repsMax: Int,
        loadKg: Double?,
        targetRir: Int?,
        autoreg: Autoreg?
    )

    /// `{ "sets_detail": [...], "target_rir": rir?, "autoreg": {...}? }`
    /// — also covers drop sets and per-set warm-ups via flags on each
    /// SetDetail.
    case setsDetail(
        sets: [SetDetail],
        targetRir: Int?,
        autoreg: Autoreg?
    )

    /// `{ "sets": n, "reps": r, "load_kg": kg, "sub_sets": k, "intra_set_rest_sec": s, "target_rir": rir? }`
    case cluster(
        sets: Int,
        reps: Int,
        loadKg: Double,
        subSets: Int,
        intraSetRestSec: Double,
        targetRir: Int?
    )

    /// `{ "reps": "amrap", "load_kg": kg?, "target_rir": rir? }`
    /// — used at a circuit station or as a drop terminal, distinct from the
    /// `amrap` timing mode. The doc calls this an "AMRAP token".
    case amrapToken(
        loadKg: Double?,
        targetRir: Int?
    )

    /// `{ "sets": n, "reps": r, "target_rir": rir? }` with no `load_kg` and
    /// no `percent_1rm` and no `warmup`. Per the doc, "Bodyweight only ...
    /// omit `load_kg` entirely. App displays BW."
    case bodyweight(
        sets: Int,
        reps: Int,
        targetRir: Int?
    )

    /// `{ "warmup": true, "sets": n, "reps": r, "load_kg": kg? }`
    /// — a whole-item warm-up. Per-set warm-ups live inside `.setsDetail`.
    case warmup(
        sets: Int,
        reps: Int,
        loadKg: Double?
    )

    /// The prescription body is `{}`. Used by items whose work is described
    /// entirely by the block (continuous, intervals, tabata, rest, custom).
    case empty
}
