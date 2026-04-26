// PrescriptionParser+SetsDetail.swift
//
// setsDetail / cluster / amrapToken / bodyweight / warmup shape parsers.
// Split out of `PrescriptionParser+Shapes.swift` so neither file exceeds
// SwiftLint's `file_length` cap.

import Foundation
import CoreDomain

extension PrescriptionParser {

    // MARK: - setsDetail

    func parseSetsDetail(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "setsDetail"
        let arr: [Any]
        switch readOptionalArray(obj, "sets_detail") {
        case .failure(let e): return .failure(e)
        case .success(.none):
            return .failure(.missingKey("sets_detail", inShape: shape))
        case .success(.some(let a)): arr = a
        }
        var details: [SetDetail] = []
        details.reserveCapacity(arr.count)
        for (i, raw) in arr.enumerated() {
            guard let el = raw as? [String: Any] else {
                return .failure(.wrongType(key: "sets_detail[\(i)]", expected: "object"))
            }
            switch parseSetDetail(el, index: i) {
            case .failure(let e): return .failure(e)
            case .success(let d): details.append(d)
            }
        }
        let unit: WeightUnit
        switch readWeightUnit(obj) {
        case .failure(let e): return .failure(e)
        case .success(let v): unit = v
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        let autoreg: Autoreg?
        switch parseAutoreg(obj, shape: shape, unit: unit) {
        case .failure(let e): return .failure(e)
        case .success(let v): autoreg = v
        }
        return .success(.setsDetail(
            sets: details,
            unit: unit,
            targetRir: targetRir,
            autoreg: autoreg
        ))
    }

    private func parseSetDetail(
        _ obj: [String: Any],
        index: Int
    ) -> Result<SetDetail, ParseError> {
        let shape = "setsDetail[\(index)]"
        let reps: RepCount
        switch readRepCount(obj, "reps") {
        case .failure(let e): return .failure(e)
        case .success(.none):
            return .failure(.missingKey("reps", inShape: shape))
        case .success(.some(let v)): reps = v
        }
        let loadKg: Double?
        switch readOptionalDouble(obj, "load_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): loadKg = v
        }
        let drop: Bool
        switch readOptionalBool(obj, "drop") {
        case .failure(let e): return .failure(e)
        case .success(let v): drop = v ?? false
        }
        let warmup: Bool
        switch readOptionalBool(obj, "warmup") {
        case .failure(let e): return .failure(e)
        case .success(let v): warmup = v ?? false
        }
        return .success(SetDetail(
            reps: reps,
            loadKg: loadKg,
            drop: drop,
            warmup: warmup
        ))
    }

    // MARK: - cluster

    // swiftlint:disable:next function_body_length
    func parseCluster(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "cluster"
        let sets: Int
        switch readOptionalInt(obj, "sets") {
        case .failure(let e): return .failure(e)
        case .success(let v): sets = v ?? 1
        }
        let reps: Int
        switch readRequiredInt(obj, "reps", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): reps = v
        }
        let loadKg: Double
        switch readRequiredDouble(obj, "load_kg", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): loadKg = v
        }
        let unit: WeightUnit
        switch readWeightUnit(obj) {
        case .failure(let e): return .failure(e)
        case .success(let v): unit = v
        }
        let subSets: Int
        switch readRequiredInt(obj, "sub_sets", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): subSets = v
        }
        let intra: Double
        switch readRequiredDouble(obj, "intra_set_rest_sec", shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): intra = v
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        let autoreg: Autoreg?
        switch parseAutoreg(obj, shape: shape, unit: unit) {
        case .failure(let e): return .failure(e)
        case .success(let v): autoreg = v
        }
        return .success(.cluster(
            sets: sets,
            reps: reps,
            loadKg: loadKg,
            unit: unit,
            subSets: subSets,
            intraSetRestSec: intra,
            targetRir: targetRir,
            autoreg: autoreg
        ))
    }

    // MARK: - amrapToken / bodyweight / warmup

    func parseAmrapToken(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        // Reps must be the literal string "amrap"; discrimination already
        // confirmed this. We still surface optional load and target_rir.
        let loadKg: Double?
        switch readOptionalDouble(obj, "load_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): loadKg = v
        }
        let unit: WeightUnit
        switch readWeightUnit(obj) {
        case .failure(let e): return .failure(e)
        case .success(let v): unit = v
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        return .success(.amrapToken(loadKg: loadKg, unit: unit, targetRir: targetRir))
    }

    func parseBodyweight(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "bodyweight"
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
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        return .success(.bodyweight(
            sets: sets,
            reps: reps,
            targetRir: targetRir
        ))
    }

    func parseWarmup(
        _ obj: [String: Any]
    ) -> Result<Prescription, ParseError> {
        let shape = "warmup"
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
        let loadKg: Double?
        switch readOptionalDouble(obj, "load_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): loadKg = v
        }
        let unit: WeightUnit
        switch readWeightUnit(obj) {
        case .failure(let e): return .failure(e)
        case .success(let v): unit = v
        }
        return .success(.warmup(sets: sets, reps: reps, loadKg: loadKg, unit: unit))
    }
}
