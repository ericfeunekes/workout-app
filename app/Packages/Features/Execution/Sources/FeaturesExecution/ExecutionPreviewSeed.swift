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
                        name: "Carry test",
                        timingMode: .straightSets,
                        timingConfigJSON: #"{"rest_between_sets_sec":6,"rest_between_exercises_sec":6}"#,
                        items: [
                            (
                                "Farmer Carry",
                                #"{"sets":1,"target":{"kind":"distance","value":100,"unit":"ft"},"load_kg":53,"weight_unit":"lb"}"#
                            ),
                        ]
                    ),
                ]
            )
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
        var resolvedBlocks: [Block] = []
        var itemsByBlock: [[WorkoutItem]] = []

        for (blockPosition, fixtureBlock) in blocks.enumerated() {
            let blockID = UUID()
            var workoutItems: [WorkoutItem] = []

            for (itemPosition, item) in fixtureBlock.items.enumerated() {
                let exerciseID = UUID()
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
}

#endif
