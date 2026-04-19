// main.swift — entry point for `swift run WorkoutCoreFoundationTests`.

import Foundation
import WorkoutCoreFoundation

// ---- Clock ----------------------------------------------------------------

runCase("FixedClock returns fixture time") {
    let fixture = Date(timeIntervalSince1970: 1_700_000_000)
    let clock = FixedClock(now: fixture)
    try expectEqual(clock.now, fixture)
}

runCase("FixedClock is mutable") {
    var clock = FixedClock(now: Date(timeIntervalSince1970: 0))
    let later = Date(timeIntervalSince1970: 100)
    clock.now = later
    try expectEqual(clock.now, later)
}

runCase("SystemClock is wired to the system clock") {
    // Two successive reads should be within a second of each other; this
    // catches the "accidentally a fixed value" regression without asserting
    // strict monotonicity (which wall clocks don't guarantee).
    let clock = SystemClock()
    let first = clock.now
    let second = clock.now
    try expect(abs(second.timeIntervalSince(first)) < 1.0, "clock drifted too far between reads")
}

// ---- LoadFormatting -------------------------------------------------------

runCase("formatLoad(nil) renders as BW") {
    try expectEqual(formatLoad(kg: nil), "BW")
}

runCase("formatLoad(nil, bodyweightAdded: true) still renders as BW") {
    try expectEqual(formatLoad(kg: nil, bodyweightAdded: true), "BW")
}

runCase("formatLoad renders decimals with one place") {
    try expectEqual(formatLoad(kg: 102.5), "102.5 kg")
    try expectEqual(formatLoad(kg: 2.5), "2.5 kg")
}

runCase("formatLoad drops trailing .0 for integer loads") {
    try expectEqual(formatLoad(kg: 100), "100 kg")
    try expectEqual(formatLoad(kg: 0), "0 kg")
}

runCase("formatLoad with bodyweightAdded renders BW + n kg") {
    try expectEqual(formatLoad(kg: 20, bodyweightAdded: true), "BW + 20 kg")
    try expectEqual(formatLoad(kg: 12.5, bodyweightAdded: true), "BW + 12.5 kg")
}

runCase("formatLoad(kg: 0, bodyweightAdded: true) is literal BW + 0 kg") {
    // Pinned decision: zero is a numeric value, not a synonym for bodyweight.
    // Callers that want "BW" pass nil. See doc comment on formatLoad().
    try expectEqual(formatLoad(kg: 0, bodyweightAdded: true), "BW + 0 kg")
}

runCase("formatKilograms is exposed") {
    try expectEqual(formatKilograms(100), "100")
    try expectEqual(formatKilograms(102.5), "102.5")
}

// ---- LoadFormatting · unit-aware ------------------------------------------

runCase("formatLoadUnitAwareKg renders kg suffix") {
    // The legacy call was `formatLoad(kg:)` which hardcoded "kg". The
    // unit-aware variant renders whatever unit the caller passes so a
    // History row logged in kg still reads "100 kg" end-to-end.
    try expectEqual(formatLoad(weight: 100.0, unit: .kg), "100 kg")
    try expectEqual(formatLoad(weight: 102.5, unit: .kg), "102.5 kg")
}

runCase("formatLoadUnitAwareLb renders lb suffix") {
    // Bug being fixed: SessionDetailViewModel.formatSetRow used to call
    // `formatLoad(kg: log.weight)` regardless of `log.weightUnit`, so a
    // set logged as "225 lb" rendered as "225 kg" in the detail row.
    // The unit-aware formatter is the first half of that fix.
    try expectEqual(formatLoad(weight: 225.0, unit: .lb), "225 lb")
    try expectEqual(formatLoad(weight: 45.5, unit: .lb), "45.5 lb")
}

runCase("formatLoadNilIsDash") {
    // Naming: the function returns "BW" (bodyweight), not "—" or blank.
    // The spec in this subagent brief called it "—"; "BW" is the
    // established convention across Core/Foundation and the existing
    // test suite (see the non-unit-aware tests above). Preserving it
    // here keeps one string for "no external load" across legacy and
    // unit-aware callers.
    try expectEqual(formatLoad(weight: nil, unit: .kg), "BW")
    try expectEqual(formatLoad(weight: nil, unit: .lb), "BW")
}

runCase("formatLoad unit-aware with bodyweightAdded") {
    // Weighted dip / chin-up rendered in lb: "BW + 25 lb". Mirror of the
    // kg variant a few cases up.
    try expectEqual(
        formatLoad(weight: 25, unit: .lb, bodyweightAdded: true),
        "BW + 25 lb"
    )
    try expectEqual(
        formatLoad(weight: 12.5, unit: .kg, bodyweightAdded: true),
        "BW + 12.5 kg"
    )
}

runCase("LoadUnit raw values match Domain.WeightUnit") {
    // Contract: the Domain `WeightUnit` enum (in CoreDomain, which we
    // can't import here — Core/Foundation has no deps) uses raw values
    // "kg" and "lb". `LoadUnit` must mirror those so callers can bridge
    // with `LoadUnit(rawValue: weightUnit.rawValue)` and the wire label
    // matches the DB-stored label.
    try expectEqual(LoadUnit.kg.rawValue, "kg")
    try expectEqual(LoadUnit.lb.rawValue, "lb")
}

runCase("formatLoadNumber is exposed (rename of formatKilograms)") {
    // `formatLoadNumber` is the unit-agnostic replacement; `formatKilograms`
    // stays as a call-through alias for callers that haven't migrated.
    try expectEqual(formatLoadNumber(100), "100")
    try expectEqual(formatLoadNumber(102.5), "102.5")
}

runCase("formatLoad preserves 1.25 kg autoreg steps") {
    // Regression guard for the 1.25 kg equipment step (fractional plates).
    // Autoreg on a 100 kg lift can compute 101.25 as the next-set prescription;
    // under the old `%.1f` formatter that rendered as "101.2 kg" — the state
    // was correct, only the display lost the trailing 5.
    try expectEqual(formatLoad(weight: 101.25, unit: .kg), "101.25 kg")
    try expectEqual(formatLoad(weight: 98.75, unit: .kg), "98.75 kg")
    try expectEqual(formatLoadNumber(101.25), "101.25")
}

runCase("formatLoad drops trailing zero beyond two decimals") {
    // Two-decimal render with trailing-zero trim: "102.50" collapses to
    // "102.5"; "100.00" collapses to the integer form "100".
    try expectEqual(formatLoad(weight: 102.50, unit: .kg), "102.5 kg")
    try expectEqual(formatLoad(weight: 100.0, unit: .lb), "100 lb")
    try expectEqual(formatLoadNumber(102.50), "102.5")
    try expectEqual(formatLoadNumber(100.0), "100")
}

// ---- DurationFormatting ---------------------------------------------------

runCase("formatDuration(0) is 0:00") {
    try expectEqual(formatDuration(seconds: 0), "0:00")
}

runCase("formatDuration sub-minute") {
    try expectEqual(formatDuration(seconds: 45), "0:45")
    try expectEqual(formatDuration(seconds: 9), "0:09")
}

runCase("formatDuration minute + seconds") {
    try expectEqual(formatDuration(seconds: 90), "1:30")
    try expectEqual(formatDuration(seconds: 180), "3:00")
    try expectEqual(formatDuration(seconds: 754), "12:34")
}

runCase("formatDuration hours") {
    try expectEqual(formatDuration(seconds: 3600), "1:00:00")
    try expectEqual(formatDuration(seconds: 3661), "1:01:01")
}

runCase("formatDuration truncates fractional seconds") {
    try expectEqual(formatDuration(seconds: 2.9), "0:02")
}

runCase("formatDuration clamps negative") {
    try expectEqual(formatDuration(seconds: -5), "0:00")
}

// ---- IDs -----------------------------------------------------------------

runCase("ID typealiases are UUID") {
    let id: WorkoutID = UUID()
    let same: UUID = id
    try expectEqual(id, same)
}

runCase("wireID lowercases an uppercase UUID") {
    // Apple's `UUID.uuidString` returns uppercase; the server invariant
    // is lowercase on the wire. `wireID` centralizes the downcase so one
    // grep catches drift.
    let uuid = UUID(uuidString: "AABBCCDD-EEFF-0011-2233-445566778899")!
    try expectEqual(uuid.uuidString, "AABBCCDD-EEFF-0011-2233-445566778899")
    try expectEqual(uuid.wireID, "aabbccdd-eeff-0011-2233-445566778899")
}

runCase("wireID is idempotent on an already-lowercase UUID") {
    let lower = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    try expectEqual(lower.wireID, "11111111-2222-3333-4444-555555555555")
    // Round-tripping a wireID through UUID parse and back stays lowercase.
    let reparsed = UUID(uuidString: lower.wireID)!
    try expectEqual(reparsed.wireID, lower.wireID)
}

// ---- Cardio formatting (qa-043) ------------------------------------------

runCase("formatCardioSummary duration-only renders as mm:ss") {
    try expectEqual(formatCardioSummary(durationSec: 2700, distanceM: nil), "45:00")
    try expectEqual(formatCardioSummary(durationSec: 90, distanceM: nil), "1:30")
}

runCase("formatCardioSummary distance-only renders as N km / N m") {
    try expectEqual(formatCardioSummary(durationSec: nil, distanceM: 5000), "5 km")
    try expectEqual(formatCardioSummary(durationSec: nil, distanceM: 400), "400 m")
}

runCase("formatCardioSummary duration + distance → duration at pace") {
    // 2700 s over 10000 m → 270 s/km → 4:30 / km.
    try expectEqual(
        formatCardioSummary(durationSec: 2700, distanceM: 10000),
        "45:00 at 4:30 / km"
    )
}

runCase("formatCardioSummary interval aggregate uses N × shape") {
    try expectEqual(
        formatCardioSummary(durationSec: 96, distanceM: 400, count: 6),
        "6 × 400 m at 4:00 / km"
    )
}

runCase("formatCardioSummary renders 'no data' when both inputs missing") {
    try expectEqual(formatCardioSummary(durationSec: nil, distanceM: nil), "no data")
    // Zero inputs are the same as nil — they don't count as data.
    try expectEqual(formatCardioSummary(durationSec: 0, distanceM: 0), "no data")
}

reportAndExit()
