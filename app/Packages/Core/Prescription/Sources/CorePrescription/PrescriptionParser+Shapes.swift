// PrescriptionParser+Shapes.swift
//
// Per-shape parsers for the prescription JSON: straight sets, percent of 1RM,
// rep range, sets detail, cluster, amrap token, bodyweight, warmup. Split out
// of `PrescriptionParser.swift` so the parent file stays under SwiftLint's
// `type_body_length` and `file_length` caps.

import Foundation

extension PrescriptionParser {

    // MARK: - straightSets

    func parseStraightSets(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "straightSets"
        switch readStraightSetsLoad(obj, shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let load):
            switch readStraightSetsMods(obj, shape: shape) {
            case .failure(let e): return .failure(e)
            case .success(let mods):
                return .success(.straightSets(
                    sets: load.sets,
                    reps: load.reps,
                    loadKg: load.loadKg,
                    targetRir: load.targetRir,
                    autoreg: load.autoreg,
                    tempo: mods.tempo,
                    perSide: mods.perSide
                ))
            }
        }
    }

    private struct StraightSetsLoad {
        let sets: Int?
        let reps: RepCount?
        let loadKg: Double?
        let targetRir: Int?
        let autoreg: Autoreg?
    }

    private struct StraightSetsMods {
        let tempo: String?
        let perSide: Bool
    }

    private func readStraightSetsLoad(
        _ obj: [String: Any],
        shape: String
    ) -> Result<StraightSetsLoad, ParseError> {
        let sets: Int?
        switch readOptionalInt(obj, "sets") {
        case .failure(let e): return .failure(e)
        case .success(let v): sets = v
        }
        let reps: RepCount?
        switch readRepCount(obj, "reps") {
        case .failure(let e): return .failure(e)
        case .success(let v): reps = v
        }
        let loadKg: Double?
        switch readOptionalDouble(obj, "load_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): loadKg = v
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        let autoreg: Autoreg?
        switch parseAutoreg(obj, shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): autoreg = v
        }
        return .success(StraightSetsLoad(
            sets: sets,
            reps: reps,
            loadKg: loadKg,
            targetRir: targetRir,
            autoreg: autoreg
        ))
    }

    private func readStraightSetsMods(
        _ obj: [String: Any],
        shape: String
    ) -> Result<StraightSetsMods, ParseError> {
        let tempo: String?
        switch readOptionalString(obj, "tempo") {
        case .failure(let e): return .failure(e)
        case .success(let v): tempo = v
        }
        let perSide: Bool
        switch readOptionalBool(obj, "per_side") {
        case .failure(let e): return .failure(e)
        case .success(let v): perSide = v ?? false
        }
        return .success(StraightSetsMods(tempo: tempo, perSide: perSide))
    }

    // MARK: - percentOf1RM

    func parsePercentOf1RM(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "percentOf1RM"
        let sets: Int
        switch readRequiredInt(obj, "sets", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): sets = v
        }
        let reps: Int
        switch readRequiredInt(obj, "reps", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): reps = v
        }
        let percent: Double
        switch readRequiredDouble(obj, "percent_1rm", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): percent = v
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        return .success(.percentOf1RM(
            sets: sets,
            reps: reps,
            percent: percent,
            targetRir: targetRir
        ))
    }

    // MARK: - repRange

    func parseRepRange(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "repRange"
        switch readRepRangeBounds(obj, shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let bounds):
            switch readRepRangeLoad(obj, shape: shape) {
            case .failure(let e): return .failure(e)
            case .success(let load):
                return .success(.repRange(
                    sets: bounds.sets,
                    repsMin: bounds.lo,
                    repsMax: bounds.hi,
                    loadKg: load.loadKg,
                    targetRir: load.targetRir,
                    autoreg: load.autoreg
                ))
            }
        }
    }

    private struct RepRangeBounds {
        let sets: Int
        let lo: Int
        let hi: Int
    }

    private struct RepRangeLoad {
        let loadKg: Double?
        let targetRir: Int?
        let autoreg: Autoreg?
    }

    private func readRepRangeBounds(
        _ obj: [String: Any],
        shape: String
    ) -> Result<RepRangeBounds, ParseError> {
        let sets: Int
        switch readRequiredInt(obj, "sets", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): sets = v
        }
        let lo: Int
        switch readRequiredInt(obj, "reps_min", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): lo = v
        }
        let hi: Int
        switch readRequiredInt(obj, "reps_max", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): hi = v
        }
        return .success(RepRangeBounds(sets: sets, lo: lo, hi: hi))
    }

    private func readRepRangeLoad(
        _ obj: [String: Any],
        shape: String
    ) -> Result<RepRangeLoad, ParseError> {
        let loadKg: Double?
        switch readOptionalDouble(obj, "load_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): loadKg = v
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        let autoreg: Autoreg?
        switch parseAutoreg(obj, shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): autoreg = v
        }
        return .success(RepRangeLoad(
            loadKg: loadKg,
            targetRir: targetRir,
            autoreg: autoreg
        ))
    }

    // setsDetail / cluster / amrapToken / bodyweight / warmup parsers live
    // in `PrescriptionParser+SetsDetail.swift` so neither this file nor
    // that one exceeds SwiftLint's `file_length` cap.
}
