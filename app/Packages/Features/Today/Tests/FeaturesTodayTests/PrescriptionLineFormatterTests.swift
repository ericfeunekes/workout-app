// PrescriptionLineFormatterTests.swift
//
// Verifies the one-line summary strings rendered on the Today row.
// Cases cover the common shapes (straight_sets, percent_1rm, bodyweight)
// plus a couple of the fallbacks so the view never renders nil / panics
// on an unfamiliar shape.

import XCTest
import CoreDomain
import CorePrescription
@testable import FeaturesToday

final class PrescriptionLineFormatterTests: XCTestCase {

    func testStraightSets_integerLoad_kg() {
        let p = Prescription.straightSets(
            sets: 3, reps: .count(8), loadKg: 100, unit: .kg,
            targetRir: 1, autoreg: nil, tempo: nil, perSide: false
        )
        XCTAssertEqual(formatPrescriptionLine(p), "3 \u{00D7} 8 @ 100 kg")
    }

    func testStraightSets_lbSuffix() {
        // R2.10: pound-default prescriptions render with " lb" suffix.
        let p = Prescription.straightSets(
            sets: 4, reps: .count(5), loadKg: 225, unit: .lb,
            targetRir: 2, autoreg: nil, tempo: nil, perSide: false
        )
        XCTAssertEqual(formatPrescriptionLine(p), "4 \u{00D7} 5 @ 225 lb")
    }

    func testStraightSets_fractionalLoad_kg() {
        let p = Prescription.straightSets(
            sets: 4, reps: .count(5), loadKg: 102.5, unit: .kg,
            targetRir: 2, autoreg: nil, tempo: nil, perSide: false
        )
        XCTAssertEqual(formatPrescriptionLine(p), "4 \u{00D7} 5 @ 102.5 kg")
    }

    func testStraightSets_bodyweightNoLoad() {
        // Straight sets without a load_kg (bodyweight-ish but still
        // straight-sets shape; weighted bodyweight is same shape with a
        // load_kg present — that path covered by fractionalLoad).
        let p = Prescription.straightSets(
            sets: 3, reps: .count(10), loadKg: nil, unit: .lb,
            targetRir: nil, autoreg: nil, tempo: nil, perSide: false
        )
        XCTAssertEqual(formatPrescriptionLine(p), "3 \u{00D7} 10")
    }

    func testStraightSets_amrapReps() {
        let p = Prescription.straightSets(
            sets: 3, reps: .amrap, loadKg: 80, unit: .kg,
            targetRir: nil, autoreg: nil, tempo: nil, perSide: false
        )
        XCTAssertEqual(formatPrescriptionLine(p), "3 \u{00D7} AMRAP @ 80 kg")
    }

    func testPercentOf1RM_rendersIntegerPct() {
        let p = Prescription.percentOf1RM(
            sets: 5, reps: 3, percent: 0.85, targetRir: 1
        )
        XCTAssertEqual(formatPrescriptionLine(p), "5 \u{00D7} 3 @ 85% 1RM")
    }

    func testPercentOf1RM_roundsPct() {
        let p = Prescription.percentOf1RM(
            sets: 5, reps: 3, percent: 0.725, targetRir: 1
        )
        XCTAssertEqual(formatPrescriptionLine(p), "5 \u{00D7} 3 @ 73% 1RM")
    }

    func testBodyweight() {
        let p = Prescription.bodyweight(sets: 3, reps: 10, targetRir: 1)
        XCTAssertEqual(formatPrescriptionLine(p), "3 \u{00D7} 10 BW")
    }

    func testRepRange_withLoad() {
        let p = Prescription.repRange(
            sets: 3, repsMin: 8, repsMax: 12, loadKg: 60, unit: .kg,
            targetRir: 2, autoreg: nil
        )
        XCTAssertEqual(formatPrescriptionLine(p), "3 \u{00D7} 8\u{2013}12 @ 60 kg")
    }

    func testRepRange_withoutLoad() {
        let p = Prescription.repRange(
            sets: 3, repsMin: 8, repsMax: 12, loadKg: nil, unit: .lb,
            targetRir: nil, autoreg: nil
        )
        XCTAssertEqual(formatPrescriptionLine(p), "3 \u{00D7} 8\u{2013}12")
    }

    func testAmrapToken_withLoad() {
        let p = Prescription.amrapToken(loadKg: 40, unit: .kg, targetRir: nil)
        XCTAssertEqual(formatPrescriptionLine(p), "AMRAP @ 40 kg")
    }

    func testAmrapToken_bodyweight() {
        let p = Prescription.amrapToken(loadKg: nil, unit: .lb, targetRir: nil)
        XCTAssertEqual(formatPrescriptionLine(p), "AMRAP")
    }

    func testEmpty_rendersEmptyString() {
        XCTAssertEqual(formatPrescriptionLine(.empty), "")
    }
}
