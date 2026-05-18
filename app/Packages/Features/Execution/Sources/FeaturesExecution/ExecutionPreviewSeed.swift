// ExecutionPreviewSeed.swift
//
// DEBUG-only fixture that mirrors `TodayPreviewSeed.pushA(...)` but
// returns a `WorkoutContext` (the shape Execution consumes).
//
// Used by:
//   - SwiftUI `#Preview`s for ActiveView / RestView / CompleteView
//   - early runtime before a real loader lands
//
// Not shipped in Release builds (wrapped in `#if DEBUG`).

#if DEBUG

import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

public enum ExecutionPreviewSeed {
    public static func pushA() -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let now = Date()
        let catalog = ExerciseCatalog()
        return WorkoutContext(
            workout: makePushAWorkout(workoutID: workoutID, userID: userID, now: now),
            blocks: [makePushABlock(blockID: blockID, workoutID: workoutID)],
            itemsByBlock: [makePushAItems(blockID: blockID, catalog: catalog)],
            exercises: catalog.exercises,
            lastPerformed: catalog.lastPerformed
        )
    }

    /// DEBUG-only execution fixtures for simulator QA. These are deliberately
    /// short so timer boundaries can be observed without waiting through a
    /// full workout.
    public static func timingMode(_ mode: TimingMode) -> WorkoutContext {
        switch mode {
        case .straightSets:
            return pushA()
        case .superset:
            return makeFixture(
                name: "QA Superset",
                timingMode: .superset,
                timingConfigJSON: #"{"rest_between_rounds_sec":20}"#,
                rounds: 3,
                items: [
                    ("DB Bench Press", #"{"reps":10,"load_kg":24,"weight_unit":"kg","target_rir":2}"#),
                    ("Chest-Supported Row", #"{"reps":12,"load_kg":20,"weight_unit":"kg","target_rir":2}"#),
                ]
            )
        case .circuit:
            return makeFixture(
                name: "QA Circuit",
                timingMode: .circuit,
                timingConfigJSON: #"{"rest_between_exercises_sec":5,"rest_between_rounds_sec":20}"#,
                rounds: 2,
                items: [
                    ("Goblet Squat", #"{"reps":12,"load_kg":24,"weight_unit":"kg"}"#),
                    ("Push-Up", #"{"reps":15}"#),
                    ("Kettlebell Swing", #"{"reps":20,"load_kg":24,"weight_unit":"kg"}"#),
                ]
            )
        case .emom:
            return makeFixture(
                name: "QA EMOM",
                timingMode: .emom,
                timingConfigJSON: #"{"interval_sec":20,"total_minutes":2}"#,
                items: [
                    ("Thruster", #"{"reps":8,"load_kg":30,"weight_unit":"kg"}"#),
                    ("Burpee", #"{"reps":10}"#),
                ]
            )
        case .amrap:
            return makeFixture(
                name: "QA AMRAP",
                timingMode: .amrap,
                timingConfigJSON: #"{"time_cap_sec":45}"#,
                items: [
                    ("Wall Ball", #"{"reps":10,"load_kg":9,"weight_unit":"kg"}"#),
                    ("Box Jump", #"{"reps":12}"#),
                ]
            )
        case .forTime:
            return makeFixture(
                name: "QA For Time",
                timingMode: .forTime,
                timingConfigJSON: #"{"time_cap_sec":60}"#,
                rounds: 3,
                roundsRepSchemeJSON: "[21,15,9]",
                items: [
                    ("Thruster", #"{"load_kg":43,"weight_unit":"kg"}"#),
                    ("Pull-Up", #"{}"#),
                ]
            )
        case .intervals:
            return makeFixture(
                name: "QA Intervals",
                timingMode: .intervals,
                timingConfigJSON: #"{"work_distance_m":400,"rest_distance_m":100,"interval_count":3,"target_pace_sec_per_km":300}"#,
                items: [("Run", #"{}"#)]
            )
        case .tabata:
            return makeFixture(
                name: "QA Tabata",
                timingMode: .tabata,
                timingConfigJSON: #"{}"#,
                items: [("Air Bike", #"{}"#)]
            )
        case .continuous:
            return makeFixture(
                name: "QA Continuous",
                timingMode: .continuous,
                timingConfigJSON: #"{"target_duration_sec":120,"target_distance_m":null,"target_pace_sec_per_km":360,"target_hr_zone":2}"#,
                items: [("Zone 2 Run", #"{}"#)]
            )
        case .accumulate:
            return makeFixture(
                name: "QA Accumulate",
                timingMode: .accumulate,
                timingConfigJSON: #"{"target_reps":100}"#,
                items: [("Push-Up", #"{"reps":25}"#)]
            )
        case .custom:
            return makeFixture(
                name: "QA Custom",
                timingMode: .custom,
                timingConfigJSON: #"{"segments":[{"type":"work","duration_sec":15,"label":"hard"},{"type":"rest","duration_sec":10,"label":"easy"},{"type":"work","duration_sec":15,"label":"hard"}]}"#,
                items: [("Threshold Run", #"{}"#)]
            )
        case .rest:
            return makeFixture(
                name: "QA Rest Block",
                timingMode: .rest,
                timingConfigJSON: #"{"duration_sec":20}"#,
                items: []
            )
        }
    }

    /// Composed DEBUG workouts for simulator QA. Single-mode fixtures catch
    /// driver bugs; these catch cross-block handoff bugs and UX gaps that
    /// only appear when different timer contracts sit next to each other.
    public static func qaScenario(_ name: String) -> WorkoutContext? {
        switch name {
        case "timer_gauntlet_strength":
            return makeFixture(
                name: "QA Timer Gauntlet · Strength",
                blocks: [
                    FixtureBlock(
                        name: "Opening prep",
                        timingMode: .rest,
                        timingConfigJSON: #"{"duration_sec":8}"#,
                        items: []
                    ),
                    FixtureBlock(
                        name: "Heavy press",
                        timingMode: .straightSets,
                        timingConfigJSON: #"{"rest_between_sets_sec":8,"rest_between_exercises_sec":10}"#,
                        items: [
                            ("DB Bench Press", #"{"sets":2,"reps":8,"load_kg":28,"weight_unit":"kg","target_rir":2}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Push pull superset",
                        timingMode: .superset,
                        timingConfigJSON: #"{"rest_between_rounds_sec":8}"#,
                        rounds: 2,
                        items: [
                            ("Incline DB Press", #"{"reps":10,"load_kg":24,"weight_unit":"kg","target_rir":2}"#),
                            ("Chest-Supported Row", #"{"reps":12,"load_kg":22,"weight_unit":"kg","target_rir":2}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Accessory circuit",
                        timingMode: .circuit,
                        timingConfigJSON: #"{"rest_between_exercises_sec":4,"rest_between_rounds_sec":8}"#,
                        rounds: 2,
                        items: [
                            ("Goblet Squat", #"{"reps":12,"load_kg":24,"weight_unit":"kg"}"#),
                            ("Push-Up", #"{"reps":15}"#),
                            ("Kettlebell Swing", #"{"reps":20,"load_kg":24,"weight_unit":"kg"}"#),
                        ]
                    ),
                ]
            )
        case "timer_gauntlet_clocked":
            return makeFixture(
                name: "QA Timer Gauntlet · Clocked",
                blocks: [
                    FixtureBlock(
                        name: "EMOM primer",
                        timingMode: .emom,
                        timingConfigJSON: #"{"interval_sec":12,"total_minutes":1}"#,
                        items: [
                            ("Thruster", #"{"reps":6,"load_kg":30,"weight_unit":"kg"}"#),
                            ("Burpee", #"{"reps":8}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "AMRAP couplet",
                        timingMode: .amrap,
                        timingConfigJSON: #"{"time_cap_sec":45}"#,
                        items: [
                            ("Wall Ball", #"{"reps":10,"load_kg":9,"weight_unit":"kg"}"#),
                            ("Box Jump", #"{"reps":12}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "For-time chipper",
                        timingMode: .forTime,
                        timingConfigJSON: #"{"time_cap_sec":60}"#,
                        rounds: 3,
                        roundsRepSchemeJSON: "[21,15,9]",
                        items: [
                            ("Thruster", #"{"load_kg":43,"weight_unit":"kg"}"#),
                            ("Pull-Up", #"{}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Tabata finisher",
                        timingMode: .tabata,
                        timingConfigJSON: #"{}"#,
                        items: [
                            ("Air Bike", #"{}"#),
                        ]
                    ),
                ]
            )
        case "timer_gauntlet_endurance":
            return makeFixture(
                name: "QA Timer Gauntlet · Endurance",
                blocks: [
                    FixtureBlock(
                        name: "Run intervals",
                        timingMode: .intervals,
                        timingConfigJSON: #"{"work_sec":15,"rest_sec":8,"interval_count":2,"target_pace_sec_per_km":300}"#,
                        items: [
                            ("Run", #"{"duration_sec":15,"target_pace_sec_per_km":300}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Zone 2",
                        timingMode: .continuous,
                        timingConfigJSON: #"{"target_duration_sec":45,"target_distance_m":null,"target_pace_sec_per_km":360,"target_hr_zone":2}"#,
                        items: [
                            ("Zone 2 Run", #"{}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Threshold ladder",
                        timingMode: .custom,
                        timingConfigJSON: #"{"segments":[{"type":"work","duration_sec":12,"label":"hard"},{"type":"rest","duration_sec":6,"label":"easy"},{"type":"work","duration_sec":12,"label":"hard"}]}"#,
                        items: [
                            ("Threshold Run", #"{}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Push-up accumulate",
                        timingMode: .accumulate,
                        timingConfigJSON: #"{"target_reps":100}"#,
                        items: [
                            ("Push-Up", #"{"reps":25}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Cooldown",
                        timingMode: .rest,
                        timingConfigJSON: #"{"duration_sec":10}"#,
                        items: []
                    ),
                ]
            )
        case "cluster_straight":
            return makeFixture(
                name: "QA Cluster · Straight",
                timingMode: .straightSets,
                timingConfigJSON: #"{"rest_between_sets_sec":8,"rest_between_exercises_sec":10}"#,
                items: [
                    (
                        "DB Bench Cluster",
                        #"{"sets":2,"reps":5,"load_kg":28,"weight_unit":"kg","sub_sets":2,"intra_set_rest_sec":6,"target_rir":1,"autoreg":{}}"#
                    ),
                ]
            )
        case "cluster_autoreg":
            return makeFixture(
                name: "QA Cluster · Autoreg",
                timingMode: .straightSets,
                timingConfigJSON: #"{"rest_between_sets_sec":8,"rest_between_exercises_sec":10}"#,
                items: [
                    (
                        "Bench Cluster Autoreg",
                        #"{"sets":2,"reps":4,"load_kg":80,"weight_unit":"kg","sub_sets":3,"intra_set_rest_sec":5,"target_rir":1,"autoreg":{"overshoot_at":2,"overshoot_step_kg":2.5,"undershoot_at":2,"undershoot_step_kg":2.5,"apply_to":"remaining"}}"#
                    ),
                ]
            )
        case "cluster_superset":
            return makeFixture(
                name: "QA Cluster · Superset",
                timingMode: .superset,
                timingConfigJSON: #"{"rest_between_rounds_sec":8}"#,
                rounds: 2,
                items: [
                    (
                        "Incline DB Cluster",
                        #"{"reps":5,"load_kg":24,"weight_unit":"kg","sub_sets":2,"intra_set_rest_sec":5,"target_rir":1}"#
                    ),
                    (
                        "Chest-Supported Row",
                        #"{"reps":10,"load_kg":22,"weight_unit":"kg","target_rir":2}"#
                    ),
                ]
            )
        case "cluster_circuit":
            return makeFixture(
                name: "QA Cluster · Circuit",
                timingMode: .circuit,
                timingConfigJSON: #"{"rest_between_exercises_sec":4,"rest_between_rounds_sec":8}"#,
                rounds: 2,
                items: [
                    (
                        "Goblet Squat Cluster",
                        #"{"reps":6,"load_kg":24,"weight_unit":"kg","sub_sets":2,"intra_set_rest_sec":5}"#
                    ),
                    ("Push-Up", #"{"reps":12}"#),
                    ("Kettlebell Swing", #"{"reps":15,"load_kg":24,"weight_unit":"kg"}"#),
                ]
            )
        case "cluster_composed":
            return makeFixture(
                name: "QA Cluster · Composed",
                blocks: [
                    FixtureBlock(
                        name: "Warm-up transition",
                        timingMode: .rest,
                        timingConfigJSON: #"{"duration_sec":6}"#,
                        items: []
                    ),
                    FixtureBlock(
                        name: "Press cluster",
                        timingMode: .straightSets,
                        timingConfigJSON: #"{"rest_between_sets_sec":8,"rest_between_exercises_sec":10}"#,
                        items: [
                            (
                                "DB Bench Cluster",
                                #"{"sets":1,"reps":5,"load_kg":28,"weight_unit":"kg","sub_sets":2,"intra_set_rest_sec":5,"target_rir":1}"#
                            ),
                        ]
                    ),
                    FixtureBlock(
                        name: "Push-up finish",
                        timingMode: .accumulate,
                        timingConfigJSON: #"{"target_reps":30}"#,
                        items: [
                            ("Push-Up", #"{"reps":10}"#),
                        ]
                    ),
                ]
            )
        case "transition_setup":
            return makeFixture(
                name: "QA Transition Setup",
                blocks: [
                    FixtureBlock(
                        name: "Press primer",
                        timingMode: .straightSets,
                        timingConfigJSON: #"{"rest_between_sets_sec":6,"rest_between_exercises_sec":6}"#,
                        items: [
                            ("DB Bench Press", #"{"sets":1,"reps":5,"load_kg":28,"weight_unit":"kg","target_rir":2}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Press repeat",
                        timingMode: .straightSets,
                        timingConfigJSON: #"{"rest_between_sets_sec":6,"rest_between_exercises_sec":6}"#,
                        items: [
                            ("DB Bench Press", #"{"sets":2,"reps":8,"load_kg":24,"weight_unit":"kg","target_rir":3}"#),
                        ]
                    ),
                    FixtureBlock(
                        name: "Carry test",
                        timingMode: .straightSets,
                        timingConfigJSON: #"{"rest_between_sets_sec":6,"rest_between_exercises_sec":6}"#,
                        items: [
                            (
                                "Farmer Carry",
                                #"{"sets":3,"target":{"kind":"distance","value":100,"unit":"ft"},"load_kg":53,"weight_unit":"lb"}"#
                            ),
                        ]
                    ),
                ]
            )
        case "primitive_strength":
            return makePrimitiveStrengthFixture()
        case "primitive_circuit":
            return makePrimitiveCircuitFixture()
        case "primitive_for_time":
            return makePrimitiveForTimeFixture()
        case "primitive_amrap":
            return makePrimitiveAMRAPFixture(capSec: 45)
        case "primitive_capstone":
            return makePrimitiveCapstoneFixture(capSec: 20 * 60)
        case "primitive_capstone_fast":
            return makePrimitiveCapstoneFixture(capSec: 45)
        case "primitive_chipper":
            return makePrimitiveChipperFixture()
        case "primitive_intervals":
            return makePrimitiveIntervalsFixture()
        case "primitive_carry_circuit":
            return makePrimitiveCarryCircuitFixture()
        case "primitive_strength_density":
            return makePrimitiveStrengthDensityFixture()
        default:
            return nil
        }
    }

    private struct FixtureBlock {
        let name: String
        let timingMode: TimingMode
        let timingConfigJSON: String
        let rounds: Int?
        let roundsRepSchemeJSON: String?
        let items: [(name: String, prescriptionJSON: String)]

        init(
            name: String,
            timingMode: TimingMode,
            timingConfigJSON: String,
            rounds: Int? = nil,
            roundsRepSchemeJSON: String? = nil,
            items: [(name: String, prescriptionJSON: String)]
        ) {
            self.name = name
            self.timingMode = timingMode
            self.timingConfigJSON = timingConfigJSON
            self.rounds = rounds
            self.roundsRepSchemeJSON = roundsRepSchemeJSON
            self.items = items
        }
    }

    /// Stable exercise IDs + invented "last performed" strings. Kept as a
    /// value type so the dictionaries stay tied to the same UUIDs.
    private struct ExerciseCatalog {
        let benchID = UUID()
        let rowID = UUID()
        let ohpID = UUID()
        let dipID = UUID()

        var exercises: [UUID: Exercise] {
            [
                benchID: Exercise(id: benchID, name: "Barbell Bench Press"),
                rowID: Exercise(id: rowID, name: "Barbell Row"),
                ohpID: Exercise(id: ohpID, name: "Overhead Press"),
                dipID: Exercise(id: dipID, name: "Weighted Dip"),
            ]
        }

        var lastPerformed: [UUID: String] {
            [
                benchID: "5×5 @ 100 kg · RIR 2",
                rowID: "3×8 @ 77.5 kg · RIR 1",
                ohpID: "3×6 @ 52.5 kg · RIR 2",
                dipID: "3×10 @ BW+12.5 · RIR 1",
            ]
        }
    }

    private static func makePushAWorkout(
        workoutID: UUID,
        userID: UUID,
        now: Date
    ) -> Workout {
        Workout(
            id: workoutID,
            userID: userID,
            name: "Push A",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
    }

    private static func makePushABlock(blockID: UUID, workoutID: UUID) -> Block {
        Block(
            id: blockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: "main",
            timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":180,"rest_between_exercises_sec":180}"#,
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
    }

    private static func makePushAItems(
        blockID: UUID,
        catalog: ExerciseCatalog
    ) -> [WorkoutItem] {
        [
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 0,
                exerciseID: catalog.benchID,
                prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5,"target_rir":2,"autoreg":{}}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 1,
                exerciseID: catalog.rowID,
                prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80,"target_rir":1,"autoreg":{}}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 2,
                exerciseID: catalog.ohpID,
                prescriptionJSON: #"{"sets":3,"reps":6,"load_kg":55,"target_rir":2,"autoreg":{}}"#
            ),
            WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 3,
                exerciseID: catalog.dipID,
                prescriptionJSON: #"{"sets":3,"reps":10,"load_kg":15,"target_rir":1,"autoreg":{}}"#
            ),
        ]
    }

    private static func makeFixture(
        name: String,
        timingMode: TimingMode,
        timingConfigJSON: String,
        rounds: Int? = nil,
        roundsRepSchemeJSON: String? = nil,
        items: [(name: String, prescriptionJSON: String)]
    ) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let now = Date()
        var exercises: [UUID: Exercise] = [:]
        var lastPerformed: [UUID: String] = [:]
        var workoutItems: [WorkoutItem] = []

        for (position, item) in items.enumerated() {
            let exerciseID = UUID()
            exercises[exerciseID] = Exercise(id: exerciseID, name: item.name)
                lastPerformed[exerciseID] = "recent: target hit"
            workoutItems.append(WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: position,
                exerciseID: exerciseID,
                prescriptionJSON: item.prescriptionJSON
            ))
        }

        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: name,
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: #"["demo"]"#
        )

        let block = Block(
            id: blockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: name,
            timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: rounds,
            roundsRepSchemeJSON: roundsRepSchemeJSON,
            notes: nil
        )

        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises,
            lastPerformed: lastPerformed
        )
    }

    private static func makeFixture(
        name: String,
        blocks: [FixtureBlock]
    ) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        var exercises: [UUID: Exercise] = [:]
        var lastPerformed: [UUID: String] = [:]
        var exerciseIDByName: [String: UUID] = [:]
        var resolvedBlocks: [Block] = []
        var itemsByBlock: [[WorkoutItem]] = []

        for (blockPosition, fixtureBlock) in blocks.enumerated() {
            let blockID = UUID()
            var workoutItems: [WorkoutItem] = []

            for (itemPosition, item) in fixtureBlock.items.enumerated() {
                let exerciseID = exerciseIDByName[item.name] ?? UUID()
                exerciseIDByName[item.name] = exerciseID
                exercises[exerciseID] = Exercise(id: exerciseID, name: item.name)
                lastPerformed[exerciseID] = "recent: target hit"
                workoutItems.append(WorkoutItem(
                    id: UUID(),
                    blockID: blockID,
                    position: itemPosition,
                    exerciseID: exerciseID,
                    prescriptionJSON: item.prescriptionJSON
                ))
            }

            resolvedBlocks.append(Block(
                id: blockID,
                workoutID: workoutID,
                parentBlockID: nil,
                position: blockPosition,
                name: fixtureBlock.name,
                timingMode: fixtureBlock.timingMode,
                timingConfigJSON: fixtureBlock.timingConfigJSON,
                rounds: fixtureBlock.rounds,
                roundsRepSchemeJSON: fixtureBlock.roundsRepSchemeJSON,
                notes: nil
            ))
            itemsByBlock.append(workoutItems)
        }

        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: name,
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: "Composed session with warm-up, heavy work, supersets, and accessory conditioning.",
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: #"["demo","timer_gauntlet"]"#
        )

        return WorkoutContext(
            workout: workout,
            blocks: resolvedBlocks,
            itemsByBlock: itemsByBlock,
            exercises: exercises,
            lastPerformed: lastPerformed
        )
    }

    private static func makePrimitiveStrengthFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · Strength",
            timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":8,"rest_between_exercises_sec":10}"#,
            items: [
                ("DB Bench Press", #"{"sets":2,"reps":8,"load_kg":28,"weight_unit":"kg","target_rir":2}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .setBounded),
            primitiveTraversal: .sequential,
            primitiveWorkTargets: [],
            slotTargets: [
                [.init(metric: .reps, valueForm: .single, value: 8, role: .completion)],
            ],
            slotLoads: [
                PrimitiveLoad(value: 28, unit: .kg, unitType: .absolute),
            ]
        )
    }

    private static func makePrimitiveCircuitFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · Circuit",
            timingMode: .circuit,
            timingConfigJSON: #"{"rest_between_exercises_sec":4,"rest_between_rounds_sec":8}"#,
            rounds: 2,
            items: [
                ("Goblet Squat", #"{"reps":12,"load_kg":24,"weight_unit":"kg"}"#),
                ("Push-Up", #"{"reps":15}"#),
                ("Kettlebell Swing", #"{"reps":20,"load_kg":24,"weight_unit":"kg"}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .setBounded),
            primitiveTraversal: .roundRobin,
            primitiveWorkTargets: [],
            slotTargets: [
                [.init(metric: .reps, valueForm: .single, value: 12, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 15, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 20, role: .completion)],
            ],
            slotLoads: [
                PrimitiveLoad(value: 24, unit: .kg, unitType: .absolute),
                nil,
                PrimitiveLoad(value: 24, unit: .kg, unitType: .absolute),
            ]
        )
    }

    private static func makePrimitiveForTimeFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · For Time",
            timingMode: .forTime,
            timingConfigJSON: #"{"time_cap_sec":60}"#,
            rounds: 3,
            roundsRepSchemeJSON: "[21,15,9]",
            items: [
                ("Thruster", #"{"load_kg":43,"weight_unit":"kg"}"#),
                ("Pull-Up", #"{}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .setBounded),
            primitiveTraversal: .sequential,
            blockTargets: [
                .init(metric: .duration, valueForm: .open, role: .observation),
            ],
            primitiveWorkTargets: [],
            slotTargets: [
                [.init(metric: .reps, valueForm: .range, role: .completion)],
                [.init(metric: .reps, valueForm: .range, role: .completion)],
            ],
            slotLoads: [
                PrimitiveLoad(value: 43, unit: .kg, unitType: .absolute),
                nil,
            ]
        )
    }

    private static func makePrimitiveAMRAPFixture(capSec: Int) -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · AMRAP",
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":\#(capSec)}"#,
            items: [
                ("Wall Ball", #"{"reps":10,"load_kg":9,"weight_unit":"kg"}"#),
                ("Box Jump", #"{"reps":12}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .capBounded, capSec: capSec),
            primitiveTraversal: .amrap,
            primitiveWorkTargets: [
                .init(metric: .rounds, valueForm: .open, role: .observation),
            ],
            slotTargets: [
                [.init(metric: .reps, valueForm: .single, value: 10, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 12, role: .completion)],
            ],
            slotLoads: [
                PrimitiveLoad(value: 9, unit: .kg, unitType: .absolute),
                nil,
            ]
        )
    }

    private static func makePrimitiveCapstoneFixture(capSec: Int) -> WorkoutContext {
        let name = capSec == 20 * 60
            ? "QA Primitive · 20 min Mixed AMRAP"
            : "QA Primitive · Fast Mixed AMRAP"
        return makePrimitiveSingleBlockFixture(
            name: name,
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":\#(capSec)}"#,
            rounds: nil,
            items: [
                ("Burpee", #"{"reps":10}"#),
                ("Weighted Pull-Up", #"{"reps":5,"load_kg":10,"weight_unit":"kg"}"#),
                ("Burpee", #"{"reps":10}"#),
                ("Weighted Pull-Up", #"{"reps":5,"load_kg":10,"weight_unit":"kg"}"#),
                ("Burpee", #"{"reps":10}"#),
                ("Weighted Pull-Up", #"{"reps":5,"load_kg":10,"weight_unit":"kg"}"#),
                ("Run", #"{"distance_m":1000}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .capBounded, capSec: capSec),
            primitiveTraversal: .amrap,
            primitiveWorkTargets: [
                .init(metric: .rounds, valueForm: .open, role: .observation),
                .init(metric: .distance, valueForm: .open, role: .observation),
            ],
            slotTargets: [
                [.init(metric: .reps, valueForm: .single, value: 10, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 10, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 10, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                [
                    .init(metric: .distance, valueForm: .single, value: 1_000, role: .completion),
                    .init(metric: .duration, valueForm: .single, value: 360, role: .observation),
                ],
            ],
            slotLoads: [
                nil,
                PrimitiveLoad(value: 10, unit: .kg, unitType: .absolute),
                nil,
                PrimitiveLoad(value: 10, unit: .kg, unitType: .absolute),
                nil,
                PrimitiveLoad(value: 10, unit: .kg, unitType: .absolute),
                nil,
            ]
        )
    }

    private static func makePrimitiveChipperFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · For Time Chipper",
            timingMode: .forTime,
            timingConfigJSON: #"{"time_cap_sec":75}"#,
            rounds: 2,
            items: [
                ("Row", #"{"distance_m":500}"#),
                ("Thruster", #"{"reps":15,"load_kg":35,"weight_unit":"kg"}"#),
                ("Pull-Up", #"{"reps":12}"#),
                ("Run", #"{"distance_m":400}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .capBounded, capSec: 75),
            primitiveTraversal: .sequential,
            blockTargets: [
                .init(metric: .duration, valueForm: .open, role: .observation),
            ],
            primitiveWorkTargets: [
                .init(metric: .completion, valueForm: .single, value: 1, role: .completion),
                .init(metric: .duration, valueForm: .open, role: .observation),
            ],
            slotTargets: [
                [
                    .init(metric: .distance, valueForm: .single, value: 500, role: .completion),
                    .init(metric: .duration, valueForm: .open, role: .observation),
                ],
                [.init(metric: .reps, valueForm: .single, value: 15, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 12, role: .completion)],
                [
                    .init(metric: .distance, valueForm: .single, value: 400, role: .completion),
                    .init(metric: .duration, valueForm: .single, value: 120, role: .observation),
                ],
            ],
            slotLoads: [
                nil,
                PrimitiveLoad(value: 35, unit: .kg, unitType: .absolute),
                nil,
                nil,
            ]
        )
    }

    private static func makePrimitiveIntervalsFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · Mixed Intervals",
            timingMode: .intervals,
            timingConfigJSON: #"{"work_sec":12,"rest_sec":6,"interval_count":3,"target_pace_sec_per_km":300}"#,
            items: [
                ("Run", #"{"distance_m":200}"#),
                ("Shuttle Run", #"{"distance_m":100}"#),
                ("Plank", #"{"duration_sec":20}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .timeBounded, intervalSec: 12, rounds: 3),
            primitiveTraversal: .roundRobin,
            primitiveWorkTargets: [
                .init(metric: .rounds, valueForm: .single, value: 3, role: .completion),
                .init(metric: .duration, valueForm: .open, role: .observation),
            ],
            slotTargets: [
                [
                    .init(metric: .distance, valueForm: .single, value: 200, role: .completion),
                    .init(metric: .duration, valueForm: .single, value: 60, role: .observation),
                ],
                [.init(metric: .distance, valueForm: .single, value: 100, role: .completion)],
                [.init(metric: .duration, valueForm: .single, value: 20, role: .completion)],
            ],
            slotLoads: [nil, nil, nil]
        )
    }

    private static func makePrimitiveCarryCircuitFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · Loaded Carry Circuit",
            timingMode: .circuit,
            timingConfigJSON: #"{"rest_between_exercises_sec":4,"rest_between_rounds_sec":8}"#,
            rounds: 2,
            items: [
                ("Farmer Carry", #"{"distance_m":50,"load_kg":32,"weight_unit":"kg"}"#),
                ("Sandbag Bear Hug Carry", #"{"distance_m":30,"load_kg":45,"weight_unit":"kg"}"#),
                ("Walking Lunge", #"{"reps":20,"load_kg":16,"weight_unit":"kg"}"#),
                ("Sled Push", #"{"distance_m":20,"load_kg":60,"weight_unit":"kg"}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .setBounded),
            primitiveTraversal: .roundRobin,
            primitiveWorkTargets: [
                .init(metric: .rounds, valueForm: .single, value: 2, role: .completion),
            ],
            slotTargets: [
                [
                    .init(metric: .distance, valueForm: .single, value: 50, role: .completion),
                    .init(metric: .loadCarried, valueForm: .single, value: 32, role: .observation),
                ],
                [
                    .init(metric: .distance, valueForm: .single, value: 30, role: .completion),
                    .init(metric: .loadCarried, valueForm: .single, value: 45, role: .observation),
                ],
                [.init(metric: .reps, valueForm: .single, value: 20, role: .completion)],
                [
                    .init(metric: .distance, valueForm: .single, value: 20, role: .completion),
                    .init(metric: .loadCarried, valueForm: .single, value: 60, role: .observation),
                ],
            ],
            slotLoads: [
                PrimitiveLoad(value: 32, unit: .kg, unitType: .absolute),
                PrimitiveLoad(value: 45, unit: .kg, unitType: .absolute),
                PrimitiveLoad(value: 16, unit: .kg, unitType: .absolute),
                PrimitiveLoad(value: 60, unit: .kg, unitType: .absolute),
            ]
        )
    }

    private static func makePrimitiveStrengthDensityFixture() -> WorkoutContext {
        makePrimitiveSingleBlockFixture(
            name: "QA Primitive · Strength Density EMOM",
            timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":20,"total_minutes":1}"#,
            items: [
                ("Deadlift", #"{"reps":3,"load_kg":140,"weight_unit":"kg","target_rir":2}"#),
                ("Handstand Push-Up", #"{"reps":6}"#),
                ("SkiErg", #"{"duration_sec":12}"#),
            ],
            primitiveTiming: PrimitiveTiming(mode: .timeBounded, intervalSec: 20, rounds: 3),
            primitiveTraversal: .roundRobin,
            primitiveWorkTargets: [
                .init(metric: .rounds, valueForm: .single, value: 3, role: .completion),
                .init(metric: .duration, valueForm: .single, value: 60, role: .observation),
            ],
            slotTargets: [
                [.init(metric: .reps, valueForm: .single, value: 3, role: .completion)],
                [.init(metric: .reps, valueForm: .single, value: 6, role: .completion)],
                [.init(metric: .duration, valueForm: .single, value: 12, role: .completion)],
            ],
            slotLoads: [
                PrimitiveLoad(value: 140, unit: .kg, unitType: .absolute),
                nil,
                nil,
            ]
        )
    }

    private static func makePrimitiveSingleBlockFixture(
        name: String,
        timingMode: TimingMode,
        timingConfigJSON: String,
        rounds: Int? = nil,
        roundsRepSchemeJSON: String? = nil,
        items: [(name: String, prescriptionJSON: String)],
        primitiveTiming: PrimitiveTiming,
        primitiveTraversal: PrimitiveTraversal,
        blockTargets: [PrimitiveWorkTarget] = [],
        primitiveWorkTargets: [PrimitiveWorkTarget],
        slotTargets: [[PrimitiveWorkTarget]],
        slotLoads: [PrimitiveLoad?]
    ) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let setID = UUID()
        let now = Date()
        var exercises: [UUID: Exercise] = [:]
        var lastPerformed: [UUID: String] = [:]
        var exerciseIDByName: [String: UUID] = [:]
        var workoutItems: [WorkoutItem] = []
        var slots: [PrimitiveSlot] = []

        for (position, item) in items.enumerated() {
            let exerciseID = exerciseIDByName[item.name] ?? UUID()
            exerciseIDByName[item.name] = exerciseID
            exercises[exerciseID] = Exercise(id: exerciseID, name: item.name)
            lastPerformed[exerciseID] = "recent: target hit"
            workoutItems.append(WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: position,
                exerciseID: exerciseID,
                prescriptionJSON: item.prescriptionJSON
            ))
            slots.append(PrimitiveSlot(
                id: UUID(),
                exerciseID: exerciseID,
                workTargets: slotTargets[position],
                load: slotLoads[position]
            ))
        }

        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: name,
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: "DEBUG primitive QA fixture",
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: #"["debug","primitive_qa"]"#
        )
        let block = Block(
            id: blockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: name,
            timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: rounds,
            roundsRepSchemeJSON: roundsRepSchemeJSON,
            notes: nil
        )
        let primitiveWorkout = PrimitiveWorkout(
            id: workoutID,
            name: name,
            blocks: [
                PrimitiveBlock(
                    id: blockID,
                    title: name,
                    workTargets: blockTargets,
                    sets: [
                        PrimitiveSet(
                            id: setID,
                            title: name,
                            timing: primitiveTiming,
                            traversal: primitiveTraversal,
                            workTargets: primitiveWorkTargets,
                            slots: slots
                        ),
                    ]
                ),
            ]
        )

        return WorkoutContext(
            workout: workout,
            primitiveWorkout: primitiveWorkout,
            primitiveExecutionPlan: try! ExecutionPlan.validated(workout: primitiveWorkout),
            blocks: [block],
            itemsByBlock: [workoutItems],
            exercises: exercises,
            lastPerformed: lastPerformed
        )
    }
}

#endif
