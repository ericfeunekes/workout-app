// JSONHelpers.swift
//
// Small internal helpers for reading typed values out of a
// `[String: Any]` dictionary with structured errors. The parsers are not
// Codable-based because the shapes are discriminated dynamically (the JSON
// does not carry a shape tag — we infer from keys), and building a
// Codable-enum decoder for that ends up uglier than a direct key-walk.
//
// All helpers return `Result` so callers can flatMap cleanly.

import Foundation
import CoreDomain

/// Parse a JSON string into a top-level `[String: Any]`. Non-object roots
/// (arrays, primitives) are rejected — every prescription and timing-config
/// payload is an object.
func parseRootObject(
    _ jsonString: String,
    shape: String
) -> Result<[String: Any], ParseError> {
    guard let data = jsonString.data(using: .utf8) else {
        return .failure(.invalidJSON("could not encode string as UTF-8"))
    }
    let any: Any
    do {
        any = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
    } catch {
        return .failure(.invalidJSON(error.localizedDescription))
    }
    guard let obj = any as? [String: Any] else {
        return .failure(.invalidJSON("expected top-level object for shape \(shape)"))
    }
    return .success(obj)
}

/// Int? — returns nil if the key is absent. Fails if the key is present
/// but not an integer-valued number.
///
/// JSONSerialization decodes numeric JSON as `NSNumber`. `NSNumber` has an
/// `.intValue` but we check `is Int` first to reject floats-that-look-like-
/// ints (e.g. `3.5` shouldn't satisfy a request for Int).
func readOptionalInt(
    _ dict: [String: Any],
    _ key: String
) -> Result<Int?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    // NSNumber is both Int and Double-convertible; require the JSON value
    // is integer-valued. The cleanest test: cast to Double, check integrality.
    if let n = raw as? NSNumber {
        // Reject booleans (NSNumber in Foundation models bool as a number on
        // some platforms; we don't want `true` to read as 1).
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .failure(.wrongType(key: key, expected: "int"))
        }
        let d = n.doubleValue
        if d.rounded() == d && d >= Double(Int.min) && d <= Double(Int.max) {
            return .success(Int(d))
        }
    }
    return .failure(.wrongType(key: key, expected: "int"))
}

func readRequiredInt(
    _ dict: [String: Any],
    _ key: String,
    shape: String
) -> Result<Int, ParseError> {
    switch readOptionalInt(dict, key) {
    case .success(.some(let v)): return .success(v)
    case .success(.none): return .failure(.missingKey(key, inShape: shape))
    case .failure(let e): return .failure(e)
    }
}

/// Double? — accepts JSON int or double. Returns nil if key is absent or
/// if the key is present with JSON `null`.
func readOptionalDouble(
    _ dict: [String: Any],
    _ key: String
) -> Result<Double?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    if raw is NSNull { return .success(nil) }
    if let n = raw as? NSNumber {
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .failure(.wrongType(key: key, expected: "double"))
        }
        return .success(n.doubleValue)
    }
    return .failure(.wrongType(key: key, expected: "double"))
}

func readRequiredDouble(
    _ dict: [String: Any],
    _ key: String,
    shape: String
) -> Result<Double, ParseError> {
    switch readOptionalDouble(dict, key) {
    case .success(.some(let v)): return .success(v)
    case .success(.none): return .failure(.missingKey(key, inShape: shape))
    case .failure(let e): return .failure(e)
    }
}

func readOptionalString(
    _ dict: [String: Any],
    _ key: String
) -> Result<String?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    if raw is NSNull { return .success(nil) }
    if let s = raw as? String { return .success(s) }
    return .failure(.wrongType(key: key, expected: "string"))
}

func readOptionalBool(
    _ dict: [String: Any],
    _ key: String
) -> Result<Bool?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    if raw is NSNull { return .success(nil) }
    if let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
        return .success(n.boolValue)
    }
    return .failure(.wrongType(key: key, expected: "bool"))
}

func readOptionalObject(
    _ dict: [String: Any],
    _ key: String
) -> Result<[String: Any]?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    if raw is NSNull { return .success(nil) }
    if let obj = raw as? [String: Any] { return .success(obj) }
    return .failure(.wrongType(key: key, expected: "object"))
}

func readOptionalArray(
    _ dict: [String: Any],
    _ key: String
) -> Result<[Any]?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    if raw is NSNull { return .success(nil) }
    if let arr = raw as? [Any] { return .success(arr) }
    return .failure(.wrongType(key: key, expected: "array"))
}

/// Read `weight_unit` from a prescription dict. Returns `.lb` when the
/// key is absent — R2.10 default for Eric's pound-first gym setup
/// (`docs/prescription.md` § "Units"). A present but invalid value
/// surfaces as `.failure(.wrongType)`.
func readWeightUnit(
    _ dict: [String: Any]
) -> Result<WeightUnit, ParseError> {
    switch readOptionalString(dict, "weight_unit") {
    case .failure(let e): return .failure(e)
    case .success(.none): return .success(.lb)
    case .success(.some(let raw)):
        guard let unit = WeightUnit(rawValue: raw) else {
            return .failure(.wrongType(key: "weight_unit", expected: "\"kg\" or \"lb\""))
        }
        return .success(unit)
    }
}

/// Default autoreg step for a given weight unit. `.kg → 1.25` (fractional
/// plate), `.lb → 5.0` (smallest commonly available loadable plate pair).
/// Used by the parser when the prescription authors an `autoreg` block
/// without an explicit `overshoot_step_kg` / `undershoot_step_kg`.
func defaultAutoregStep(for unit: WeightUnit) -> Double {
    switch unit {
    case .kg: return 1.25
    case .lb: return 5.0
    }
}

/// A rep count is either an integer or the string "amrap". Anything else
/// is a wrongType failure.
func readRepCount(
    _ dict: [String: Any],
    _ key: String
) -> Result<RepCount?, ParseError> {
    guard let raw = dict[key] else { return .success(nil) }
    if raw is NSNull { return .success(nil) }
    if let s = raw as? String {
        if s == "amrap" { return .success(.amrap) }
        return .failure(.wrongType(key: key, expected: "int or \"amrap\""))
    }
    if let n = raw as? NSNumber {
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .failure(.wrongType(key: key, expected: "int or \"amrap\""))
        }
        let d = n.doubleValue
        if d.rounded() == d {
            return .success(.count(Int(d)))
        }
    }
    return .failure(.wrongType(key: key, expected: "int or \"amrap\""))
}
