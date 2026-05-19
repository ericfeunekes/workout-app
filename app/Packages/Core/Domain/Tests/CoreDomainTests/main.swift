// main.swift — entry point for `swift run CoreDomainTests`.

import Foundation
import WorkoutCoreFoundation
import CoreDomain

// ---- Enums ---------------------------------------------------------------

runCase("TimingMode has 12 cases") {
    try expectEqual(TimingMode.allCases.count, 12)
}

runCase("TimingMode snake_case raw values round-trip") {
    try expectEqual(TimingMode(rawValue: "straight_sets"), .straightSets)
    try expectEqual(TimingMode(rawValue: "for_time"), .forTime)
    try expectEqual(TimingMode(rawValue: "emom"), .emom)
    try expectEqual(TimingMode(rawValue: "tabata"), .tabata)
    try expectEqual(TimingMode(rawValue: "rest"), .rest)
}

runCase("TimingMode full case coverage matches spec") {
    // Belt + braces on the 12-count test. If someone adds a case, this
    // assertion breaks loudly instead of silently drifting.
    let expected: Set<String> = [
        "straight_sets", "superset", "circuit", "emom", "amrap",
        "for_time", "intervals", "tabata", "continuous", "accumulate",
        "custom", "rest",
    ]
    let actual = Set(TimingMode.allCases.map(\.rawValue))
    try expectEqual(actual, expected)
}

runCase("WorkoutStatus has 4 cases") {
    try expectEqual(WorkoutStatus.allCases.count, 4)
    try expectEqual(WorkoutStatus(rawValue: "planned"), .planned)
    try expectEqual(WorkoutStatus(rawValue: "skipped"), .skipped)
}

runCase("WorkoutStatus raw values are non-empty snake_case and unique") {
    // Same pattern as the TimingMode uniqueness test: guard against a typo
    // that silently collides two cases, or a case that slips through with an
    // empty rawValue.
    let raws = WorkoutStatus.allCases.map(\.rawValue)
    try expectEqual(Set(raws).count, raws.count)
    for raw in raws {
        try expect(!raw.isEmpty, "empty rawValue")
        try expect(raw == raw.lowercased(), "expected snake_case, got \(raw)")
    }
}

runCase("WeightUnit has kg and lb") {
    try expectEqual(WeightUnit.allCases.count, 2)
    try expectEqual(WeightUnit(rawValue: "kg"), .kg)
    try expectEqual(WeightUnit(rawValue: "lb"), .lb)
}

runCase("WeightUnit raw values are non-empty and unique") {
    let raws = WeightUnit.allCases.map(\.rawValue)
    try expectEqual(Set(raws).count, raws.count)
    for raw in raws {
        try expect(!raw.isEmpty, "empty rawValue")
        try expect(raw == raw.lowercased(), "expected lowercase, got \(raw)")
    }
}

runCase("SetLogSide has left, right, and bilateral") {
    try expectEqual(SetLogSide.allCases.count, 3)
    try expectEqual(
        Set(SetLogSide.allCases.map(\.rawValue)),
        ["left", "right", "bilateral"]
    )
    try expectEqual(SetLogSide(rawValue: "bilateral"), .bilateral)
}

runCase("SetLogSide raw values are non-empty and unique") {
    let raws = SetLogSide.allCases.map(\.rawValue)
    try expectEqual(Set(raws).count, raws.count)
    for raw in raws {
        try expect(!raw.isEmpty, "empty rawValue")
        try expect(raw == raw.lowercased(), "expected lowercase, got \(raw)")
    }
}

runCase("WorkoutSource has exactly claude and manual") {
    // Spec (docs/specs/v2-architecture.md line 147) restricts workout.source
    // to {claude, manual}. The separate WorkoutSource type (vs the unified
    // enum with .appLog) is the type-system fence that enforces it.
    try expectEqual(WorkoutSource.allCases.count, 2)
    try expectEqual(Set(WorkoutSource.allCases.map(\.rawValue)), ["claude", "manual"])
    try expectEqual(WorkoutSource.claude.rawValue, "claude")
    try expectEqual(WorkoutSource.manual.rawValue, "manual")
}

runCase("WorkoutSource raw values are non-empty and unique") {
    let raws = WorkoutSource.allCases.map(\.rawValue)
    try expectEqual(Set(raws).count, raws.count)
    for raw in raws {
        try expect(!raw.isEmpty, "empty rawValue")
        try expect(raw == raw.lowercased(), "expected lowercase, got \(raw)")
    }
}

runCase("Primitive enums match accepted wire raw values") {
    try expectEqual(Set(PrimitiveTimingMode.allCases.map(\.rawValue)), [
        "set_bounded", "time_bounded", "cap_bounded", "target_bounded",
    ])
    try expectEqual(Set(PrimitiveTraversal.allCases.map(\.rawValue)), [
        "sequential", "round_robin", "amrap",
    ])
    try expectEqual(Set(PrimitiveLogRole.allCases.map(\.rawValue)), [
        "slot", "set_result", "block_result",
    ])
}

runCase("Primitive workout can express strength and cap-bounded AMRAP slices") {
    let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    let slot = PrimitiveSlot(
        id: slotID,
        exerciseID: exerciseID,
        workTargets: [PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 5, role: .completion)],
        load: PrimitiveLoad(value: 100, unit: .kg, unitType: .absolute),
        stimuli: [PrimitiveStimulus(type: .rir, target: 2)]
    )
    let set = PrimitiveSet(
        id: setID,
        timing: PrimitiveTiming(mode: .setBounded),
        repeatCount: 3,
        slots: [slot]
    )
    let workout = PrimitiveWorkout(
        id: workoutID,
        name: "Primitive strength",
        blocks: [PrimitiveBlock(id: blockID, sets: [set])]
    )
    try expectEqual(workout.blocks[0].sets[0].slots[0].id, slotID)
    try expectEqual(workout.blocks[0].sets[0].repeatCount, 3)
    try expectEqual(workout.blocks[0].sets[0].slots[0].stimuli[0].type, .rir)
}

runCase("UserParameterSource has claude, app_log, manual") {
    // Spec line 190 allows all three for user_parameters — app_log is the
    // app writing rows itself (e.g. bodyweight_kg captured at completion).
    try expectEqual(UserParameterSource.allCases.count, 3)
    try expectEqual(
        Set(UserParameterSource.allCases.map(\.rawValue)),
        ["claude", "app_log", "manual"]
    )
    try expectEqual(UserParameterSource.claude.rawValue, "claude")
    try expectEqual(UserParameterSource.appLog.rawValue, "app_log")
    try expectEqual(UserParameterSource.manual.rawValue, "manual")
}

runCase("UserParameterSource raw values are non-empty snake_case and unique") {
    let raws = UserParameterSource.allCases.map(\.rawValue)
    try expectEqual(Set(raws).count, raws.count)
    for raw in raws {
        try expect(!raw.isEmpty, "empty rawValue")
        try expect(raw == raw.lowercased(), "expected snake_case, got \(raw)")
    }
}

// ---- Workout -------------------------------------------------------------

runCase("Workout builds from minimum required fields") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let workout = Workout(
        id: UUID(),
        userID: UUID(),
        name: "Tuesday Pull Day",
        status: .planned,
        source: .claude,
        createdAt: now,
        updatedAt: now
    )
    try expectEqual(workout.name, "Tuesday Pull Day")
    try expectEqual(workout.status, .planned)
    try expect(workout.scheduledDate == nil)
    try expect(workout.completedAt == nil)
    try expect(workout.tagsJSON == nil)
}

// ---- SetLog Equatable / Hashable -----------------------------------------

private func makeSetLog(rir: Int? = 2) -> SetLog {
    SetLog(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        workoutItemID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        setIndex: 1,
        reps: 8,
        weight: 100,
        weightUnit: .kg,
        rir: rir,
        completedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

runCase("SetLog Equatable: identical rows are equal") {
    try expectEqual(makeSetLog(), makeSetLog())
}

runCase("SetLog Equatable: differing rir breaks equality") {
    try expectNotEqual(makeSetLog(rir: 2), makeSetLog(rir: 3))
}

runCase("SetLog defaults to non-skipped bilateral") {
    let log = makeSetLog()
    try expectEqual(log.skipped, false)
    try expectEqual(log.side, .bilateral)
}

runCase("SetLog preserves skipped per-side values") {
    let log = SetLog(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        workoutItemID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        setIndex: 2,
        reps: nil,
        weight: nil,
        skipped: true,
        side: .left,
        completedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try expectEqual(log.skipped, true)
    try expectEqual(log.side, .left)
}

// ---- Hashable: usable in Sets --------------------------------------------

runCase("WorkoutID works in a Set") {
    let a: WorkoutID = UUID()
    let b: WorkoutID = UUID()
    let set: Set<WorkoutID> = [a, b, a]
    try expectEqual(set.count, 2)
}

runCase("Workout is Hashable and can be put into a Set") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let w = Workout(
        id: UUID(),
        userID: UUID(),
        name: "A",
        status: .planned,
        source: .claude,
        createdAt: now,
        updatedAt: now
    )
    let set: Set<Workout> = [w]
    try expectEqual(set.count, 1)
}

// ---- Exercise demoURL upgrade --------------------------------------------

runCase("Exercise holds a parsed URL") {
    let url = URL(string: "https://example.com/squat.mp4")
    let ex = Exercise(id: UUID(), name: "Back Squat", demoURL: url)
    try expectEqual(ex.demoURL, url)
}

runCase("Exercise equality — same ID, identical other fields") {
    let id = UUID()
    let a = Exercise(id: id, name: "Back Squat")
    let b = Exercise(id: id, name: "Back Squat")
    try expectEqual(a, b)
}

runCase("Exercise inequality — different IDs") {
    let a = Exercise(id: UUID(), name: "Back Squat")
    let b = Exercise(id: UUID(), name: "Back Squat")
    try expectNotEqual(a, b)
}

runCase("Exercise is Hashable into a Set") {
    let id = UUID()
    let a = Exercise(id: id, name: "Back Squat")
    let b = Exercise(id: id, name: "Back Squat")
    let c = Exercise(id: UUID(), name: "Deadlift")
    let set: Set<Exercise> = [a, b, c]
    try expectEqual(set.count, 2)
}

// ---- Block roundtrip of opaque JSON --------------------------------------

runCase("Block round-trips JSON fields unchanged") {
    let block = Block(
        id: UUID(),
        workoutID: UUID(),
        position: 0,
        timingMode: .forTime,
        timingConfigJSON: "{\"time_cap_sec\":600}",
        rounds: 3,
        roundsRepSchemeJSON: "[21,15,9]",
        intent: "Move steady"
    )
    try expectEqual(block.timingConfigJSON, "{\"time_cap_sec\":600}")
    try expectEqual(block.roundsRepSchemeJSON, "[21,15,9]")
    try expectEqual(block.timingMode, .forTime)
    try expectEqual(block.intent, "Move steady")
}

// ---- PrimitiveSetLog overlays -------------------------------------------

runCase("PrimitiveSetLog defaults overlay fields") {
    let log = PrimitiveSetLog(
        id: UUID(),
        role: .slot,
        slotID: UUID(),
        setID: UUID(),
        blockID: UUID(),
        workoutID: UUID(),
        setIndex: 0,
        completedAt: Date(timeIntervalSince1970: 1)
    )
    try expectEqual(log.skipped, false)
    try expectEqual(log.side, .bilateral)
    try expectEqual(log.notes, nil)
}

runCase("PrimitiveSetLog preserves explicit overlay fields") {
    let log = PrimitiveSetLog(
        id: UUID(),
        role: .slot,
        slotID: UUID(),
        setID: UUID(),
        blockID: UUID(),
        workoutID: UUID(),
        setIndex: 0,
        weightUnit: .lb,
        isWarmup: true,
        skipped: true,
        side: .left,
        notes: "skipped left side",
        completedAt: Date(timeIntervalSince1970: 1)
    )
    try expectEqual(log.weightUnit, .lb)
    try expectEqual(log.isWarmup, true)
    try expectEqual(log.skipped, true)
    try expectEqual(log.side, .left)
    try expectEqual(log.notes, "skipped left side")
}

// ---- UserParameter append-only shape -------------------------------------

runCase("UserParameter carries a single key/value pair") {
    let p = UserParameter(
        id: UUID(),
        userID: UUID(),
        key: "one_rep_max_2bc0cb7c-9d20-43c0-938b-8e1a8d75a91d_kg",
        value: "140",
        updatedAt: Date(timeIntervalSince1970: 0),
        source: .claude
    )
    try expectEqual(p.key, "one_rep_max_2bc0cb7c-9d20-43c0-938b-8e1a8d75a91d_kg")
    try expectEqual(p.value, "140")
    try expectEqual(p.source, .claude)
}

reportAndExit()
