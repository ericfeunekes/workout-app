import Foundation
import WorkoutKitExportProfile

#if (os(iOS) || os(watchOS)) && canImport(WorkoutKit) && canImport(HealthKit)
import HealthKit
import WorkoutKit

@available(iOS 17.0, watchOS 10.0, *)
struct LiveWorkoutKitSchedulingClient: WorkoutKitSchedulingClient {
    init() {}

    func support() async throws -> WorkoutKitScheduleSupport {
        WorkoutKitScheduleSupport(
            isSupported: WorkoutScheduler.isSupported,
            scheduledCount: await WorkoutScheduler.shared.scheduledWorkouts.count,
            maxAllowedCount: WorkoutScheduler.maxAllowedScheduledWorkoutCount
        )
    }

    func scheduledWorkouts() async throws -> [WorkoutKitScheduledWorkoutSnapshot] {
        await WorkoutScheduler.shared.scheduledWorkouts.map { scheduled in
            WorkoutKitScheduledWorkoutSnapshot(
                workoutPlanID: scheduled.plan.id,
                occurrence: scheduled.date,
                complete: scheduled.complete
            )
        }
    }

    func schedule(
        _ descriptor: WorkoutKitPlanDescriptor,
        at occurrence: DateComponents
    ) async throws {
        let plan = try makeWorkoutPlan(from: descriptor)
        await WorkoutScheduler.shared.schedule(plan, at: occurrence)
    }

    func open(_ descriptor: WorkoutKitPlanDescriptor) async throws {
        let plan = try makeWorkoutPlan(from: descriptor)
        #if os(watchOS)
        try await plan.openInWorkoutApp()
        #else
        throw WorkoutKitAdapterError.unsupportedPlatform(
            "WorkoutPlan.openInWorkoutApp() is watchOS-only."
        )
        #endif
    }

    private func makeWorkoutPlan(from descriptor: WorkoutKitPlanDescriptor) throws -> WorkoutPlan {
        switch descriptor.family {
        case .pacer:
            guard case .pacer(let distanceMeters, let timeSeconds) = descriptor.goal else {
                throw WorkoutKitAdapterError.incompleteWorkoutKitDescriptor
            }
            return WorkoutPlan(.pacer(PacerWorkout(
                activity: hkActivity(from: descriptor.activity),
                location: hkLocation(from: descriptor.location),
                distance: Measurement(value: distanceMeters, unit: UnitLength.meters),
                time: Measurement(value: timeSeconds, unit: UnitDuration.seconds)
            )), id: descriptor.id)
        case .singleGoal:
            return WorkoutPlan(.goal(SingleGoalWorkout(
                activity: hkActivity(from: descriptor.activity),
                location: hkLocation(from: descriptor.location),
                goal: workoutGoal(from: descriptor.goal)
            )), id: descriptor.id)
        case .customWorkout:
            let steps = descriptor.intervalSteps.map { step in
                IntervalStep(
                    step.purpose == .work ? .work : .recovery,
                    goal: workoutGoal(from: step.goal)
                )
            }
            let block = IntervalBlock(steps: steps, iterations: descriptor.intervalIterations)
            return WorkoutPlan(.custom(CustomWorkout(
                activity: hkActivity(from: descriptor.activity),
                location: hkLocation(from: descriptor.location),
                displayName: descriptor.displayName,
                blocks: [block]
            )), id: descriptor.id)
        case .swimBikeRun, .none:
            throw WorkoutKitAdapterError.unsupportedSelectionPolicy
        }
    }

    private func workoutGoal(from goal: WorkoutKitResolvedGoal) -> WorkoutGoal {
        switch goal {
        case .open:
            .open
        case .timeSeconds(let seconds):
            .time(seconds, .seconds)
        case .distanceMeters(let meters):
            .distance(meters, .meters)
        case .pacer:
            .open
        }
    }

    private func hkActivity(from activity: WorkoutKitResolvedActivity) -> HKWorkoutActivityType {
        switch activity {
        case .running:
            .running
        case .cycling:
            .cycling
        case .rowing:
            .rowing
        case .swimming:
            .swimming
        case .hiking:
            .hiking
        case .functionalStrength:
            .functionalStrengthTraining
        case .traditionalStrength:
            .traditionalStrengthTraining
        case .hiit:
            .highIntensityIntervalTraining
        case .mixedCardio:
            .mixedCardio
        case .walking:
            .walking
        case .flexibility:
            .flexibility
        case .other:
            .other
        }
    }

    private func hkLocation(from location: WorkoutKitResolvedLocation) -> HKWorkoutSessionLocationType {
        switch location {
        case .unknown:
            .unknown
        case .indoor:
            .indoor
        case .outdoor:
            .outdoor
        }
    }
}
#else
struct LiveWorkoutKitSchedulingClient: WorkoutKitSchedulingClient {
    init() {}

    func support() async throws -> WorkoutKitScheduleSupport {
        throw WorkoutKitAdapterError.liveWorkoutKitUnavailable
    }

    func scheduledWorkouts() async throws -> [WorkoutKitScheduledWorkoutSnapshot] {
        throw WorkoutKitAdapterError.liveWorkoutKitUnavailable
    }

    func schedule(
        _ descriptor: WorkoutKitPlanDescriptor,
        at occurrence: DateComponents
    ) async throws {
        _ = descriptor
        _ = occurrence
        throw WorkoutKitAdapterError.liveWorkoutKitUnavailable
    }

    func open(_ descriptor: WorkoutKitPlanDescriptor) async throws {
        _ = descriptor
        throw WorkoutKitAdapterError.liveWorkoutKitUnavailable
    }
}
#endif
