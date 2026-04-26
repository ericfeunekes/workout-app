// main.swift — entry point for `swift run CorePrescriptionTests`.
//
// Coverage (target: every fixture in schema/fixtures/prescription_*.json +
// negative paths + discrimination rules + autoreg round-trip).

import Foundation
import CorePrescription

let parser = PrescriptionParser()

// ===========================================================================
// Fixture-driven tests (one per fixture — 23 total)
// ===========================================================================

// --- Wrapped fixtures: timing_mode + timing_config_json + prescription_json ---

runCase("fixture · straight_sets · parses prescription as .straightSets with full autoreg") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("straight_sets")
    try expectEqual(mode, "straight_sets")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(let sets, let reps, let loadKg, _, let targetRir, let autoreg, let tempo, let perSide) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 4)
    try expectEqual(reps, .count(5))
    try expectEqual(loadKg, 102.5)
    try expectEqual(targetRir, 2)
    try expect(autoreg != nil, "autoreg should be present")
    try expectEqual(tempo, nil)
    try expectEqual(perSide, false)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .straightSets(let rbs, let rbe) = c else {
        throw ExpectationFailure(message: "expected .straightSets config", file: #file, line: #line)
    }
    try expectEqual(rbs, 180.0)
    try expectEqual(rbe, 180.0)
}

runCase("fixture · superset · parses item as .straightSets with nil sets") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("superset")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(let sets, let reps, let loadKg, _, _, let autoreg, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, nil)
    try expectEqual(reps, .count(10))
    try expectEqual(loadKg, 60.0)
    try expect(autoreg != nil, "superset item should carry autoreg")

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .superset(let rbr, let loggingMode) = c else {
        throw ExpectationFailure(message: "expected .superset config", file: #file, line: #line)
    }
    try expectEqual(rbr, 120.0)
    try expectEqual(loggingMode, .batchAtRoundRest)
}

runCase("fixture · circuit · parses .straightSets item + .circuit config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("circuit")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(_, let reps, let loadKg, _, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(reps, .count(12))
    try expectEqual(loadKg, 20.0)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .circuit(let rbe, let rbr, let loggingMode) = c else {
        throw ExpectationFailure(message: "expected .circuit config", file: #file, line: #line)
    }
    try expectEqual(rbe, 0.0)
    try expectEqual(rbr, 120.0)
    try expectEqual(loggingMode, .stationByStation)
}

runCase("fixture · emom · parses .straightSets item + .emom config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("emom")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(_, let reps, let loadKg, _, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(reps, .count(10))
    try expectEqual(loadKg, 95.0)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .emom(let iv, let tm) = c else {
        throw ExpectationFailure(message: "expected .emom config", file: #file, line: #line)
    }
    try expectEqual(iv, 60.0)
    try expectEqual(tm, 12)
}

runCase("fixture · amrap · parses .straightSets item + .amrap config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("amrap")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(_, let reps, _, _, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(reps, .count(10))

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .amrap(let cap) = c else {
        throw ExpectationFailure(message: "expected .amrap config", file: #file, line: #line)
    }
    try expectEqual(cap, 900.0)
}

runCase("fixture · for_time · parses .straightSets (load-only) + .forTime config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("for_time")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(let sets, let reps, let loadKg, _, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, nil)
    try expectEqual(reps, nil)
    try expectEqual(loadKg, 43.0)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .forTime(let cap) = c else {
        throw ExpectationFailure(message: "expected .forTime config", file: #file, line: #line)
    }
    try expectEqual(cap, 600.0)
}

runCase("fixture · intervals · parses .empty + .intervals config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("intervals")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    try expectEqual(p, .empty)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .intervals(_, _, let workDist, let restDist, let count, let pace) = c else {
        throw ExpectationFailure(message: "expected .intervals config", file: #file, line: #line)
    }
    try expectEqual(workDist, 400.0)
    try expectEqual(restDist, 200.0)
    try expectEqual(count, 10)
    try expectEqual(pace, 270.0)
}

runCase("fixture · tabata · parses .empty + .tabata config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("tabata")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    try expectEqual(p, .empty)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    try expectEqual(c, .tabata)
}

runCase("fixture · continuous · parses .empty + .continuous config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("continuous")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    try expectEqual(p, .empty)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .continuous(let dur, let dist, let pace, let zone) = c else {
        throw ExpectationFailure(message: "expected .continuous config", file: #file, line: #line)
    }
    try expectEqual(dur, 3600.0)
    try expectEqual(dist, nil)  // JSON null → nil
    try expectEqual(pace, 360.0)
    try expectEqual(zone, 2)
}

runCase("fixture · accumulate · parses reps item + .accumulate config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("accumulate")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(let sets, let reps, let loadKg, _, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, nil)
    try expectEqual(reps, .count(25))
    try expectEqual(loadKg, nil)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .accumulate(let dur, let targetReps, let dist) = c else {
        throw ExpectationFailure(message: "expected .accumulate config", file: #file, line: #line)
    }
    try expectEqual(dur, nil)
    try expectEqual(targetReps, 100)
    try expectEqual(dist, nil)
}

runCase("fixture · custom · parses .empty + .custom config with 5 segments") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("custom")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    try expectEqual(p, .empty)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .custom(let segments) = c else {
        throw ExpectationFailure(message: "expected .custom config", file: #file, line: #line)
    }
    try expectEqual(segments.count, 5)
    try expectEqual(segments[0].type, .work)
    try expectEqual(segments[0].durationSec, 300.0)
    try expectEqual(segments[0].label, "Z4 threshold")
    try expectEqual(segments[0].targetHrZone, 4)
    try expectEqual(segments[1].type, .rest)
    try expectEqual(segments[1].label, "easy")
    try expectEqual(segments[1].targetHrZone, nil)
}

runCase("fixture · rest_block · parses .empty + .rest config") {
    let (pre, mode, cfg) = try FixtureLoader.wrapped("rest_block")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    try expectEqual(p, .empty)

    let c = try unwrap(parser.parseTimingConfig(timingMode: mode, configJSON: cfg))
    guard case .rest(let d) = c else {
        throw ExpectationFailure(message: "expected .rest config", file: #file, line: #line)
    }
    try expectEqual(d, 180.0)
}

// --- Bare parametric fixtures ---

runCase("fixture · percent_1rm · parses as .percentOf1RM") {
    let json = try FixtureLoader.bare("percent_1rm")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .percentOf1RM(let sets, let reps, let pct, let rir) = p else {
        throw ExpectationFailure(message: "expected .percentOf1RM, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 5)
    try expectEqual(reps, 3)
    try expectEqual(pct, 0.85)
    try expectEqual(rir, 1)
}

runCase("fixture · rep_range · parses as .repRange") {
    let json = try FixtureLoader.bare("rep_range")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .repRange(let sets, let lo, let hi, let loadKg, _, let rir, _) = p else {
        throw ExpectationFailure(message: "expected .repRange, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 3)
    try expectEqual(lo, 8)
    try expectEqual(hi, 12)
    try expectEqual(loadKg, 70.0)
    try expectEqual(rir, 1)
}

runCase("fixture · sets_detail · parses as .setsDetail with 4 entries + autoreg") {
    let json = try FixtureLoader.bare("sets_detail")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .setsDetail(let details, _, let rir, let autoreg) = p else {
        throw ExpectationFailure(message: "expected .setsDetail, got \(p)", file: #file, line: #line)
    }
    try expectEqual(details.count, 4)
    try expectEqual(details[0].reps, .count(12))
    try expectEqual(details[0].loadKg, 60.0)
    try expectEqual(details[3].reps, .count(6))
    try expectEqual(details[3].loadKg, 75.0)
    try expectEqual(rir, 2)
    try expect(autoreg != nil, "sets_detail fixture carries autoreg")
}

runCase("fixture · drop_set · parses as .setsDetail with drop flags on sets 1..2") {
    let json = try FixtureLoader.bare("drop_set")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .setsDetail(let details, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .setsDetail, got \(p)", file: #file, line: #line)
    }
    try expectEqual(details.count, 3)
    try expectEqual(details[0].drop, false)
    try expectEqual(details[0].reps, .count(10))
    try expectEqual(details[1].drop, true)
    try expectEqual(details[1].reps, .amrap)
    try expectEqual(details[1].loadKg, 15.0)
    try expectEqual(details[2].drop, true)
    try expectEqual(details[2].reps, .amrap)
}

runCase("fixture · cluster · parses as .cluster") {
    let json = try FixtureLoader.bare("cluster")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .cluster(let sets, let reps, let load, _, let sub, let intra, let rir, _) = p else {
        throw ExpectationFailure(message: "expected .cluster, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 4)
    try expectEqual(reps, 5)
    try expectEqual(load, 100.0)
    try expectEqual(sub, 4)
    try expectEqual(intra, 15.0)
    try expectEqual(rir, 1)
}

runCase("cluster · parses optional autoreg for top-level set") {
    let json = """
    {"sets":2,"reps":5,"load_kg":100,"weight_unit":"lb",
     "sub_sets":2,"intra_set_rest_sec":15,"target_rir":1,
     "autoreg":{"overshoot_at":2,"overshoot_step_kg":5,
                 "undershoot_at":2,"undershoot_step_kg":5,
                 "apply_to":"remaining"}}
    """
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .cluster(_, _, _, _, _, _, let rir, let autoreg) = p else {
        throw ExpectationFailure(message: "expected .cluster, got \(p)", file: #file, line: #line)
    }
    try expectEqual(rir, 1)
    try expectEqual(autoreg?.targetRir, 1)
    try expectEqual(autoreg?.overshootStepKg, 5.0)
    try expectEqual(autoreg?.undershootStepKg, 5.0)
}

runCase("fixture · amrap_token · parses as .amrapToken") {
    let json = try FixtureLoader.bare("amrap_token")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .amrapToken(let loadKg, _, let rir) = p else {
        throw ExpectationFailure(message: "expected .amrapToken, got \(p)", file: #file, line: #line)
    }
    try expectEqual(loadKg, nil)
    try expectEqual(rir, nil)
}

runCase("fixture · per_side · parses as .straightSets with perSide=true") {
    let json = try FixtureLoader.bare("per_side")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .straightSets(let sets, let reps, let loadKg, _, _, _, _, let perSide) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 3)
    try expectEqual(reps, .count(10))
    try expectEqual(loadKg, 20.0)
    try expectEqual(perSide, true)
}

runCase("fixture · tempo · parses as .straightSets with tempo string") {
    let json = try FixtureLoader.bare("tempo")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .straightSets(_, _, _, _, _, _, let tempo, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(tempo, "3-0-1-0")
}

runCase("fixture · bodyweight · parses as .bodyweight") {
    let json = try FixtureLoader.bare("bodyweight")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .bodyweight(let sets, let reps, let rir) = p else {
        throw ExpectationFailure(message: "expected .bodyweight, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 3)
    try expectEqual(reps, 10)
    try expectEqual(rir, 2)
}

runCase("fixture · weighted_bodyweight · parses as .straightSets (no JSON-level discriminator)") {
    // Flagged mismatch: doc describes "weighted bodyweight" as a distinct
    // shape, but the JSON is identical to straight-sets. UI decides render
    // from the Exercise reference, not the prescription. Covered here to
    // pin the parser's behavior and surface the mismatch in tests.
    let json = try FixtureLoader.bare("weighted_bodyweight")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .straightSets(let sets, let reps, let loadKg, _, let rir, let autoreg, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 4)
    try expectEqual(reps, .count(6))
    try expectEqual(loadKg, 20.0)
    try expectEqual(rir, 2)
    try expect(autoreg != nil, "weighted_bodyweight fixture carries autoreg")
}

runCase("fixture · warmup · parses as .warmup") {
    let json = try FixtureLoader.bare("warmup")
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .warmup(let sets, let reps, let loadKg, _) = p else {
        throw ExpectationFailure(message: "expected .warmup, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 3)
    try expectEqual(reps, 5)
    try expectEqual(loadKg, 40.0)
}

runCase("fixture · parameter_overrides · inner overrides parse as .straightSets") {
    // parameter_overrides is an exercise_alternative row; the inner
    // parameter_overrides_json is a prescription-shaped override. We parse
    // that inner dict to confirm it's a valid prescription shape.
    let raw = try FixtureLoader.loadRaw("parameter_overrides")
    guard let inner = raw["parameter_overrides_json"] as? [String: Any] else {
        throw ExpectationFailure(
            message: "parameter_overrides fixture missing parameter_overrides_json",
            file: #file, line: #line
        )
    }
    let innerData = try JSONSerialization.data(withJSONObject: inner)
    let innerJSON = String(data: innerData, encoding: .utf8) ?? ""
    let p = try unwrap(parser.parse(prescriptionJSON: innerJSON))
    guard case .straightSets(let sets, let reps, let loadKg, _, let rir, _, _, let perSide) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(sets, 3)
    try expectEqual(reps, .count(10))
    try expectEqual(loadKg, 32.5)
    try expectEqual(rir, 2)
    try expectEqual(perSide, true)
}

// ===========================================================================
// Autoreg round-trip — every field
// ===========================================================================

runCase("autoreg · every field round-trips from straight_sets fixture") {
    let (pre, _, _) = try FixtureLoader.wrapped("straight_sets")
    let p = try unwrap(parser.parse(prescriptionJSON: pre))
    guard case .straightSets(_, _, _, _, _, let autoreg, _, _) = p, let a = autoreg else {
        throw ExpectationFailure(message: "expected .straightSets with autoreg", file: #file, line: #line)
    }
    try expectEqual(a.targetRir, 2)
    try expectEqual(a.overshootAt, 2)
    try expectEqual(a.overshootStepKg, 2.5)
    try expectEqual(a.undershootAt, 2)
    try expectEqual(a.undershootStepKg, 2.5)
    try expectEqual(a.applyTo, .remaining)
}

runCase("autoreg · defaults applied when inner keys omitted (lb default)") {
    // Opt into autoreg but omit every inner key — no `weight_unit` means
    // .lb (R2.10 default), so the step default is 5.0 (loadable-plate
    // increment in pounds). See docs/prescription.md § "Autoregulation
    // · Load step and equipment".
    let json = """
    {"sets": 3, "reps": 5, "load_kg": 80, "target_rir": 3, "autoreg": {}}
    """
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .straightSets(_, _, _, _, _, let autoreg, _, _) = p, let a = autoreg else {
        throw ExpectationFailure(message: "expected straightSets with defaulted autoreg", file: #file, line: #line)
    }
    try expectEqual(a.targetRir, 3)
    try expectEqual(a.overshootAt, 2)
    try expectEqual(a.overshootStepKg, 5.0)
    try expectEqual(a.undershootAt, 2)
    try expectEqual(a.undershootStepKg, 5.0)
    try expectEqual(a.applyTo, .remaining)
}

runCase("autoreg · defaults applied when inner keys omitted (kg unit)") {
    // Same prescription with explicit `weight_unit: "kg"` — step default
    // is 1.25 (fractional plate increment in kilograms).
    let json = """
    {"sets": 3, "reps": 5, "load_kg": 80, "weight_unit": "kg", "target_rir": 3, "autoreg": {}}
    """
    let p = try unwrap(parser.parse(prescriptionJSON: json))
    guard case .straightSets(_, _, _, _, _, let autoreg, _, _) = p, let a = autoreg else {
        throw ExpectationFailure(message: "expected straightSets with defaulted autoreg", file: #file, line: #line)
    }
    try expectEqual(a.overshootStepKg, 1.25)
    try expectEqual(a.undershootStepKg, 1.25)
}

runCase("autoreg · target_rir required when autoreg present") {
    let json = """
    {"sets": 3, "reps": 5, "load_kg": 80, "autoreg": {"overshoot_at": 2}}
    """
    switch parser.parse(prescriptionJSON: json) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got success \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .missingKey(let key, let shape) = e {
            try expectEqual(key, "target_rir")
            try expect(shape.contains("autoreg"), "shape should name autoreg, got \(shape)")
        } else {
            throw ExpectationFailure(message: "expected missingKey, got \(e)", file: #file, line: #line)
        }
    }
}

// ===========================================================================
// Discrimination rules
// ===========================================================================

runCase("discrimination · {} → .empty") {
    let p = try unwrap(parser.parse(prescriptionJSON: "{}"))
    try expectEqual(p, .empty)
}

runCase("discrimination · {reps: amrap} → .amrapToken (not .straightSets)") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"{"reps": "amrap"}"#))
    if case .amrapToken(let loadKg, _, let rir) = p {
        try expectEqual(loadKg, nil)
        try expectEqual(rir, nil)
    } else {
        throw ExpectationFailure(message: "expected .amrapToken, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · sets_detail wins over sets/reps") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"sets": 3, "reps": 10, "sets_detail": [{"reps": 5, "load_kg": 80}]}
    """#))
    if case .setsDetail = p { } else {
        throw ExpectationFailure(message: "expected .setsDetail, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · sub_sets → .cluster") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"sets": 3, "reps": 5, "load_kg": 100, "sub_sets": 4, "intra_set_rest_sec": 15}
    """#))
    if case .cluster = p { } else {
        throw ExpectationFailure(message: "expected .cluster, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · percent_1rm → .percentOf1RM") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"sets": 5, "reps": 3, "percent_1rm": 0.8}
    """#))
    if case .percentOf1RM = p { } else {
        throw ExpectationFailure(message: "expected .percentOf1RM, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · reps_min present → .repRange") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"sets": 3, "reps_min": 8, "reps_max": 12, "load_kg": 50}
    """#))
    if case .repRange = p { } else {
        throw ExpectationFailure(message: "expected .repRange, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · warmup:true at item level → .warmup") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"warmup": true, "sets": 2, "reps": 8, "load_kg": 40}
    """#))
    if case .warmup = p { } else {
        throw ExpectationFailure(message: "expected .warmup, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · sets+reps without load → .bodyweight") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"sets": 3, "reps": 10}
    """#))
    if case .bodyweight = p { } else {
        throw ExpectationFailure(message: "expected .bodyweight, got \(p)", file: #file, line: #line)
    }
}

runCase("discrimination · sets+reps+load → .straightSets (catch-all)") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"""
    {"sets": 3, "reps": 10, "load_kg": 40}
    """#))
    if case .straightSets = p { } else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
}

// ===========================================================================
// Negative paths
// ===========================================================================

runCase("negative · invalid JSON → .invalidJSON") {
    switch parser.parse(prescriptionJSON: "not json {") {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .invalidJSON = e { } else {
            throw ExpectationFailure(message: "expected .invalidJSON, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("negative · top-level array → .invalidJSON") {
    switch parser.parse(prescriptionJSON: "[1,2,3]") {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .invalidJSON = e { } else {
            throw ExpectationFailure(message: "expected .invalidJSON, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("negative · percent_1rm missing reps → .missingKey(\"reps\")") {
    switch parser.parse(prescriptionJSON: #"{"sets": 5, "percent_1rm": 0.85}"#) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .missingKey(let k, let shape) = e {
            try expectEqual(k, "reps")
            try expectEqual(shape, "percentOf1RM")
        } else {
            throw ExpectationFailure(message: "expected .missingKey, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("negative · cluster missing load_kg → .missingKey(\"load_kg\")") {
    switch parser.parse(prescriptionJSON: #"""
    {"sets": 3, "reps": 5, "sub_sets": 4, "intra_set_rest_sec": 15}
    """#) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .missingKey(let k, let s) = e {
            try expectEqual(k, "load_kg")
            try expectEqual(s, "cluster")
        } else {
            throw ExpectationFailure(message: "expected .missingKey, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("negative · sets: \"three\" → .wrongType") {
    switch parser.parse(prescriptionJSON: #"{"sets": "three", "reps": 5, "load_kg": 80}"#) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .wrongType(let k, let exp) = e {
            try expectEqual(k, "sets")
            try expect(exp.contains("int"), "expected type hint 'int', got \(exp)")
        } else {
            throw ExpectationFailure(message: "expected .wrongType, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("negative · reps: 3.5 (non-integer number) → .wrongType") {
    switch parser.parse(prescriptionJSON: #"{"sets": 3, "reps": 3.5, "load_kg": 80}"#) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .wrongType = e { } else {
            throw ExpectationFailure(message: "expected .wrongType, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("negative · unknown timing mode → .unknownTimingMode") {
    switch parser.parseTimingConfig(timingMode: "bogus_mode", configJSON: "{}") {
    case .success(let c):
        throw ExpectationFailure(message: "expected failure, got \(c)", file: #file, line: #line)
    case .failure(let e):
        if case .unknownTimingMode(let name) = e {
            try expectEqual(name, "bogus_mode")
        } else {
            throw ExpectationFailure(message: "expected .unknownTimingMode, got \(e)", file: #file, line: #line)
        }
    }
}

// bug-039: straight_sets timing config is lenient — each rest field is
// independently optional. When one is absent, it defaults to the other
// (so a single-field config still produces a functional between-sets
// rest). When both are absent, both are zero. Previously the parser
// required both fields and `StraightSetsDriver.restDuration` fell
// through to its parse-failure 0 branch — so a single-field config
// silently dropped the authored rest.
runCase("bug-039 · straight_sets · only rest_between_sets_sec → both fields equal") {
    let c = try unwrap(parser.parseTimingConfig(
        timingMode: "straight_sets",
        configJSON: #"{"rest_between_sets_sec": 15}"#
    ))
    guard case .straightSets(let rbs, let rbe) = c else {
        throw ExpectationFailure(message: "expected .straightSets, got \(c)", file: #file, line: #line)
    }
    try expectEqual(rbs, 15)
    try expectEqual(rbe, 15)
}

runCase("bug-039 · straight_sets · only rest_between_exercises_sec → both fields equal") {
    let c = try unwrap(parser.parseTimingConfig(
        timingMode: "straight_sets",
        configJSON: #"{"rest_between_exercises_sec": 30}"#
    ))
    guard case .straightSets(let rbs, let rbe) = c else {
        throw ExpectationFailure(message: "expected .straightSets, got \(c)", file: #file, line: #line)
    }
    try expectEqual(rbs, 30)
    try expectEqual(rbe, 30)
}

runCase("bug-039 · straight_sets · both absent → both fields zero") {
    let c = try unwrap(parser.parseTimingConfig(
        timingMode: "straight_sets",
        configJSON: "{}"
    ))
    guard case .straightSets(let rbs, let rbe) = c else {
        throw ExpectationFailure(message: "expected .straightSets, got \(c)", file: #file, line: #line)
    }
    try expectEqual(rbs, 0)
    try expectEqual(rbe, 0)
}

// ===========================================================================
// AlternativeOverrides — widened parser (bug P1 · swap overrides)
// ===========================================================================

runCase("AlternativeOverrides · accepts full documented key set") {
    // Every key from docs/prescription.md § "Alternative prescription
    // (overrides)" lands on the parsed struct. The fixture matches the
    // example in the doc: dumbbell-bench override carrying sets/reps/
    // load/per_side/target_rir plus an autoreg step override.
    let json = #"""
    {
      "sets": 3,
      "reps": 10,
      "load_kg": 32.5,
      "target_rir": 2,
      "per_side": true,
      "autoreg": {
        "overshoot_at": 1,
        "overshoot_step_kg": 1.25,
        "undershoot_at": 1,
        "undershoot_step_kg": 1.25,
        "apply_to": "remaining"
      }
    }
    """#
    switch AlternativeOverrides.parse(json) {
    case .success(let overrides):
        try expectEqual(overrides.sets, 3)
        try expectEqual(overrides.reps, 10)
        try expectEqual(overrides.loadKg, 32.5)
        try expectEqual(overrides.targetRir, 2)
        try expectEqual(overrides.perSide, true)
        try expect(overrides.autoreg != nil, "autoreg overrides should parse")
        try expectEqual(overrides.autoreg?.overshootAt, 1)
        try expectEqual(overrides.autoreg?.overshootStepKg, 1.25)
        try expectEqual(overrides.autoreg?.undershootAt, 1)
        try expectEqual(overrides.autoreg?.undershootStepKg, 1.25)
        try expectEqual(overrides.autoreg?.applyTo, .remaining)
        try expect(!overrides.isEmpty, "non-empty override")
    case .failure(let e):
        throw ExpectationFailure(message: "expected success, got \(e)", file: #file, line: #line)
    }
}

runCase("AlternativeOverrides · nil / empty input → success with empty struct") {
    switch AlternativeOverrides.parse(nil) {
    case .success(let o):
        try expect(o.isEmpty, "nil input should yield empty")
    case .failure:
        throw ExpectationFailure(message: "nil input should not fail", file: #file, line: #line)
    }
    switch AlternativeOverrides.parse("") {
    case .success(let o):
        try expect(o.isEmpty, "empty input should yield empty")
    case .failure:
        throw ExpectationFailure(message: "empty input should not fail", file: #file, line: #line)
    }
}

runCase("AlternativeOverrides · rejects malformed key whole-struct (wrong type)") {
    // A single bad key rejects the whole override — we do NOT silently
    // drop `reps` and keep `load_kg`; that would leave the user in a
    // half-swapped state with no feedback. See the header comment on
    // AlternativeOverrides.swift.
    let json = #"{"reps":"many","load_kg":72.5}"#
    switch AlternativeOverrides.parse(json) {
    case .success(let o):
        throw ExpectationFailure(message: "expected failure, got \(o)", file: #file, line: #line)
    case .failure(let e):
        if case .wrongType(let key, _) = e {
            try expectEqual(key, "reps")
        } else {
            throw ExpectationFailure(message: "expected .wrongType(reps), got \(e)", file: #file, line: #line)
        }
    }
}

runCase("AlternativeOverrides · rejects malformed autoreg inner key (whole-struct)") {
    // An unsupported `apply_to` value fails the autoreg-override parser
    // and bubbles up as a whole-struct failure — the caller drops the
    // entire override, rather than accepting a half-parsed struct.
    let json = #"{"reps":8,"autoreg":{"apply_to":"all"}}"#
    switch AlternativeOverrides.parse(json) {
    case .success(let o):
        throw ExpectationFailure(message: "expected failure, got \(o)", file: #file, line: #line)
    case .failure(let e):
        if case .wrongType(let key, _) = e {
            try expectEqual(key, "apply_to")
        } else {
            throw ExpectationFailure(message: "expected .wrongType(apply_to), got \(e)", file: #file, line: #line)
        }
    }
}

runCase("AlternativeOverrides · partial autoreg override (only one inner key)") {
    // Inner autoreg keys are optional — an override can carry just one
    // without tripping parse. The unauthored keys remain nil and the
    // driver falls back to the prescription's authored value.
    let json = #"{"autoreg":{"overshoot_step_kg":1.25}}"#
    switch AlternativeOverrides.parse(json) {
    case .success(let o):
        try expectEqual(o.autoreg?.overshootStepKg, 1.25)
        try expectEqual(o.autoreg?.overshootAt, nil)
        try expectEqual(o.autoreg?.undershootAt, nil)
    case .failure(let e):
        throw ExpectationFailure(message: "expected success, got \(e)", file: #file, line: #line)
    }
}

// ===========================================================================
// parseTolerantOfAutoreg — isolate autoreg parse failures (bug P2)
// ===========================================================================

runCase("parseTolerantOfAutoreg · unsupported apply_to → base prescription seeds, autoreg dropped") {
    // Bug: autoreg with `apply_to: "all"` used to fail the whole
    // prescription parse; SessionSeeder caught the failure and replaced
    // the item's SetPlan with a `0 kg / 0 reps` placeholder, wiping the
    // authored base values. The tolerant parser strips the autoreg block
    // on retry so the base reps/load still seed.
    let json = #"""
    {"sets": 4, "reps": 5, "load_kg": 102.5,
     "target_rir": 2,
     "autoreg": {"apply_to": "all", "overshoot_step_kg": 2.5}}
    """#
    switch parser.parseTolerantOfAutoreg(prescriptionJSON: json) {
    case .success(let p):
        guard case .straightSets(let sets, let reps, let loadKg, _, let rir, let autoreg, _, _) = p else {
            throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
        }
        try expectEqual(sets, 4)
        try expectEqual(reps, .count(5))
        try expectEqual(loadKg, 102.5)
        try expectEqual(rir, 2)
        try expectEqual(autoreg, nil, "autoreg stripped on retry")
    case .failure(let e):
        throw ExpectationFailure(message: "expected success, got \(e)", file: #file, line: #line)
    }
}

runCase("parseTolerantOfAutoreg · valid autoreg passes through untouched") {
    // When the autoreg block is valid, the tolerant parser returns the
    // full prescription (autoreg included) — the retry-without-autoreg
    // path only fires on failure.
    let json = #"""
    {"sets": 3, "reps": 5, "load_kg": 80, "target_rir": 2,
     "autoreg": {"overshoot_at": 2, "overshoot_step_kg": 2.5,
                 "undershoot_at": 2, "undershoot_step_kg": 2.5,
                 "apply_to": "remaining"}}
    """#
    switch parser.parseTolerantOfAutoreg(prescriptionJSON: json) {
    case .success(let p):
        guard case .straightSets(_, _, _, _, _, let autoreg, _, _) = p else {
            throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
        }
        try expect(autoreg != nil, "valid autoreg preserved")
    case .failure(let e):
        throw ExpectationFailure(message: "expected success, got \(e)", file: #file, line: #line)
    }
}

runCase("parseTolerantOfAutoreg · non-autoreg failure surfaces unchanged") {
    // A malformed base-prescription key (not inside autoreg) is not
    // masked by the tolerant parser — the caller still sees the original
    // failure, which SessionSeeder translates into the zero-row
    // placeholder.
    let json = #"{"sets":"three","reps":5,"load_kg":80}"#
    switch parser.parseTolerantOfAutoreg(prescriptionJSON: json) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .wrongType(let key, _) = e {
            try expectEqual(key, "sets")
        } else {
            throw ExpectationFailure(message: "expected .wrongType, got \(e)", file: #file, line: #line)
        }
    }
}

// ===========================================================================
// weight_unit (R2.10)
// ===========================================================================

import CoreDomain

runCase("weight_unit · straightSets defaults to .lb when omitted") {
    // R2.10: Eric trains primarily in pounds; new default is .lb when
    // `weight_unit` is absent on the prescription.
    let p = try unwrap(parser.parse(prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":225}"#))
    guard case .straightSets(_, _, _, let unit, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(unit, WeightUnit.lb)
}

runCase("weight_unit · straightSets respects explicit kg") {
    let p = try unwrap(parser.parse(prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5,"weight_unit":"kg"}"#))
    guard case .straightSets(_, _, _, let unit, _, _, _, _) = p else {
        throw ExpectationFailure(message: "expected .straightSets, got \(p)", file: #file, line: #line)
    }
    try expectEqual(unit, WeightUnit.kg)
}

runCase("weight_unit · invalid value rejected") {
    let json = #"{"sets":4,"reps":5,"load_kg":102.5,"weight_unit":"grams"}"#
    switch parser.parse(prescriptionJSON: json) {
    case .success(let p):
        throw ExpectationFailure(message: "expected failure, got \(p)", file: #file, line: #line)
    case .failure(let e):
        if case .wrongType(let key, _) = e {
            try expectEqual(key, "weight_unit")
        } else {
            throw ExpectationFailure(message: "expected .wrongType, got \(e)", file: #file, line: #line)
        }
    }
}

runCase("weight_unit · repRange / cluster / setsDetail / amrapToken / warmup inherit the same default") {
    let repRangeJSON = #"{"sets":3,"reps_min":8,"reps_max":12,"load_kg":70}"#
    guard case .repRange(_, _, _, _, let rrUnit, _, _) = try unwrap(parser.parse(prescriptionJSON: repRangeJSON)) else {
        throw ExpectationFailure(message: "expected .repRange", file: #file, line: #line)
    }
    try expectEqual(rrUnit, WeightUnit.lb)

    let clusterJSON = #"{"sets":4,"reps":5,"load_kg":100,"sub_sets":4,"intra_set_rest_sec":15}"#
    guard case .cluster(_, _, _, let cUnit, _, _, _, _) = try unwrap(parser.parse(prescriptionJSON: clusterJSON)) else {
        throw ExpectationFailure(message: "expected .cluster", file: #file, line: #line)
    }
    try expectEqual(cUnit, WeightUnit.lb)

    let detailJSON = #"{"sets_detail":[{"reps":5,"load_kg":60}]}"#
    guard case .setsDetail(_, let sdUnit, _, _) = try unwrap(parser.parse(prescriptionJSON: detailJSON)) else {
        throw ExpectationFailure(message: "expected .setsDetail", file: #file, line: #line)
    }
    try expectEqual(sdUnit, WeightUnit.lb)

    let amrapJSON = #"{"reps":"amrap","load_kg":95}"#
    guard case .amrapToken(_, let aUnit, _) = try unwrap(parser.parse(prescriptionJSON: amrapJSON)) else {
        throw ExpectationFailure(message: "expected .amrapToken", file: #file, line: #line)
    }
    try expectEqual(aUnit, WeightUnit.lb)

    let warmupJSON = #"{"warmup":true,"sets":2,"reps":5,"load_kg":40}"#
    guard case .warmup(_, _, _, let wUnit) = try unwrap(parser.parse(prescriptionJSON: warmupJSON)) else {
        throw ExpectationFailure(message: "expected .warmup", file: #file, line: #line)
    }
    try expectEqual(wUnit, WeightUnit.lb)
}

runCase("work_target · structured duration separates kind from display unit") {
    guard let target = parser.parseWorkTarget(
        prescriptionJSON: #"{"target":{"kind":"duration","value":2,"unit":"min"}}"#
    ) else {
        throw ExpectationFailure(message: "expected work target", file: #file, line: #line)
    }
    try expectEqual(target.kind, .duration)
    try expectEqual(target.value, 2)
    try expectEqual(target.unit, .minutes)
    try expectEqual(target.canonicalReps, nil)
    try expectEqual(target.canonicalDurationSec, 120)
    try expectEqual(target.canonicalDistanceM, nil)
}

runCase("work_target · structured distance converts display unit to canonical metres") {
    guard let target = parser.parseWorkTarget(
        prescriptionJSON: #"{"target":{"kind":"distance","value":200,"unit":"ft"}}"#
    ) else {
        throw ExpectationFailure(message: "expected work target", file: #file, line: #line)
    }
    try expectEqual(target.kind, .distance)
    try expectEqual(target.value, 200)
    try expectEqual(target.unit, .feet)
    try expectEqual(target.canonicalReps, nil)
    try expectEqual(target.canonicalDurationSec, nil)
    try expect(
        abs((target.canonicalDistanceM ?? 0) - 60.96) < 0.001,
        "200 ft should canonicalize to 60.96 m"
    )
}

runCase("work_target · flat scalar keys still map to the same typed target") {
    guard let duration = parser.parseWorkTarget(
        prescriptionJSON: #"{"duration":90,"duration_unit":"sec"}"#
    ) else {
        throw ExpectationFailure(message: "expected duration target", file: #file, line: #line)
    }
    try expectEqual(duration.kind, .duration)
    try expectEqual(duration.value, 90)
    try expectEqual(duration.unit, .seconds)
    try expectEqual(duration.canonicalDurationSec, 90)

    guard let reps = parser.parseWorkTarget(prescriptionJSON: #"{"reps":12}"#) else {
        throw ExpectationFailure(message: "expected reps target", file: #file, line: #line)
    }
    try expectEqual(reps.kind, .reps)
    try expectEqual(reps.value, 12)
    try expectEqual(reps.unit, .reps)
    try expectEqual(reps.canonicalReps, 12)
}

runCase("work_target · structured units must match target kind") {
    try expectEqual(
        parser.parseWorkTarget(
            prescriptionJSON: #"{"target":{"kind":"duration","value":400,"unit":"m"}}"#
        ),
        nil
    )
    try expectEqual(
        parser.parseWorkTarget(
            prescriptionJSON: #"{"target":{"kind":"distance","value":2,"unit":"min"}}"#
        ),
        nil
    )
    try expectEqual(
        parser.parseWorkTarget(
            prescriptionJSON: #"{"target":{"kind":"reps","value":12,"unit":"ft"}}"#
        ),
        nil
    )
}

runCase("AlternativeOverrides · weight_unit is optional (nil means inherit)") {
    let json = #"{"load_kg":225}"#
    let o = try unwrap(AlternativeOverrides.parse(json))
    try expectEqual(o.unit, nil)
    try expectEqual(o.loadKg, 225)
}

runCase("AlternativeOverrides · weight_unit parses when authored") {
    let json = #"{"load_kg":100,"weight_unit":"kg"}"#
    let o = try unwrap(AlternativeOverrides.parse(json))
    try expectEqual(o.unit, WeightUnit.kg)
}

reportAndExit()
