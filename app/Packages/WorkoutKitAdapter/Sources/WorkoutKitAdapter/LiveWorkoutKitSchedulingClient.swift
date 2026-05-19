import Foundation

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
            let block = IntervalBlock(steps: steps, iterations: 1)
            return WorkoutPlan(.custom(CustomWorkout(
                activity: hkActivity(from: descriptor.activity),
                location: hkLocation(from: descriptor.location),
                displayName: descriptor.displayName,
                blocks: [block]
            )), id: descriptor.id)
        case .pacer, .swimBikeRun, .none:
            throw WorkoutKitAdapterError.unsupportedSelectionPolicy
        }
    }

    private func workoutGoal(from goal: WorkoutKitAdapterGoal) -> WorkoutGoal {
        switch goal {
        case .open:
            .open
        case .timeSeconds(let seconds):
            .time(seconds, .seconds)
        case .distanceMeters(let meters):
            .distance(meters, .meters)
        }
    }

    private func hkActivity(from activity: WorkoutKitAdapterActivity) -> HKWorkoutActivityType {
        switch activity {
        case .cycling:
            .cycling
        case .functionalStrength:
            .functionalStrengthTraining
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

    private func hkLocation(from location: WorkoutKitAdapterLocation) -> HKWorkoutSessionLocationType {
        switch location {
        case .unknown:
            .unknown
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
