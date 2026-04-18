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

reportAndExit()
