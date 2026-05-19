import Foundation
import WorkoutKitExportProfile

enum WorkoutKitPlanFactory {
    static func descriptor(for plan: WorkoutKitExportPlan) throws -> WorkoutKitPlanDescriptor {
        do {
            return try plan.resolvedPlanDescriptor()
        } catch let error as WorkoutKitDescriptorResolutionError {
            throw adapterError(from: error)
        }
    }

    private static func adapterError(
        from error: WorkoutKitDescriptorResolutionError
    ) -> WorkoutKitAdapterError {
        switch error {
        case .nonConstructible:
            .incompleteWorkoutKitDescriptor
        case .unsupportedSelectionPolicy:
            .unsupportedSelectionPolicy
        case .unsupportedPayloadShape(let shape):
            .unsupportedPayloadShape(shape)
        }
    }
}
