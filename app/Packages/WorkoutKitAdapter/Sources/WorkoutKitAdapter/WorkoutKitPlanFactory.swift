import Foundation
import WorkoutKitExportProfile

enum WorkoutKitPlanFactory {
    static func descriptor(for plan: WorkoutKitExportPlan) throws -> WorkoutKitPlanDescriptor {
        guard plan.supportState != .unsupported,
              plan.supportState != .setmarkOnly,
              plan.payload.shape != .noPayload
        else {
            throw WorkoutKitAdapterError.unsupportedPayloadShape(plan.payload.shape)
        }

        let family = try candidateFamily(from: plan.selectionPolicy)
        return WorkoutKitPlanDescriptor(
            id: plan.workoutID,
            displayName: plan.workoutName,
            family: family,
            activity: activity(from: plan.payload.activitySelection),
            location: location(from: plan.payload.activitySelection),
            goal: goal(from: plan.payload.goal),
            intervalSteps: intervalSteps(from: plan.payload)
        )
    }

    private static func candidateFamily(
        from policy: WorkoutKitSelectionPolicy
    ) throws -> WorkoutKitCandidateFamily {
        switch policy {
        case .exact(let family):
            return family
        case .firstSupported(let families):
            guard let family = families.first else {
                throw WorkoutKitAdapterError.unsupportedSelectionPolicy
            }
            return family
        case .none:
            throw WorkoutKitAdapterError.unsupportedSelectionPolicy
        }
    }

    private static func activity(
        from selection: WorkoutKitActivitySelection
    ) -> WorkoutKitAdapterActivity {
        switch selection {
        case .cardio:
            .other
        case .functionalStrength:
            .functionalStrength
        case .mixed:
            .mixedCardio
        case .carry:
            .walking
        case .recovery:
            .flexibility
        case .unknown:
            .other
        }
    }

    private static func location(
        from selection: WorkoutKitActivitySelection
    ) -> WorkoutKitAdapterLocation {
        .unknown
    }

    private static func goal(from blueprint: WorkoutKitGoalBlueprint) -> WorkoutKitAdapterGoal {
        switch blueprint {
        case .open, .none:
            .open
        case .time:
            .timeSeconds(20 * 60)
        case .distance:
            .distanceMeters(5_000)
        case .intervalSteps:
            .open
        }
    }

    private static func intervalSteps(
        from payload: WorkoutKitPayloadBlueprint
    ) -> [WorkoutKitAdapterIntervalStep] {
        guard payload.shape == .customIntervals else { return [] }
        let work = WorkoutKitAdapterIntervalStep(
            purpose: .work,
            goal: payload.goal == .intervalSteps ? .timeSeconds(60) : goal(from: payload.goal)
        )
        let recovery = WorkoutKitAdapterIntervalStep(
            purpose: .recovery,
            goal: .timeSeconds(30)
        )
        return payload.steps.contains { $0.preservesWorkRestCadence } ? [work, recovery] : [work]
    }
}
