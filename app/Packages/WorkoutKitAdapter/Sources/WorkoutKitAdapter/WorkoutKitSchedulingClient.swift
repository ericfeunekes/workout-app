import Foundation
import WorkoutKitExportProfile

public struct WorkoutKitScheduleSupport: Sendable, Hashable, Codable {
    public var isSupported: Bool
    public var scheduledCount: Int
    public var maxAllowedCount: Int

    public init(isSupported: Bool, scheduledCount: Int, maxAllowedCount: Int) {
        self.isSupported = isSupported
        self.scheduledCount = scheduledCount
        self.maxAllowedCount = maxAllowedCount
    }
}

public struct WorkoutKitScheduledWorkoutSnapshot: Sendable, Hashable, Codable {
    public var workoutPlanID: UUID
    public var occurrence: DateComponents
    public var complete: Bool

    public init(
        workoutPlanID: UUID,
        occurrence: DateComponents,
        complete: Bool
    ) {
        self.workoutPlanID = workoutPlanID
        self.occurrence = occurrence
        self.complete = complete
    }
}

protocol WorkoutKitSchedulingClient: Sendable {
    func support() async throws -> WorkoutKitScheduleSupport
    func scheduledWorkouts() async throws -> [WorkoutKitScheduledWorkoutSnapshot]
    func schedule(_ descriptor: WorkoutKitPlanDescriptor, at occurrence: DateComponents) async throws
    func open(_ descriptor: WorkoutKitPlanDescriptor) async throws
}

actor FakeWorkoutKitSchedulingClient: WorkoutKitSchedulingClient {
    private(set) var scheduledRequests: [(WorkoutKitPlanDescriptor, DateComponents)] = []
    private(set) var openedDescriptors: [WorkoutKitPlanDescriptor] = []
    private var currentSupport: WorkoutKitScheduleSupport
    private var scheduleError: WorkoutKitAdapterError?
    private var openError: WorkoutKitAdapterError?
    private var hidesScheduledReadback: Bool

    init(
        support: WorkoutKitScheduleSupport = WorkoutKitScheduleSupport(
            isSupported: true,
            scheduledCount: 0,
            maxAllowedCount: 15
        ),
        scheduleError: WorkoutKitAdapterError? = nil,
        openError: WorkoutKitAdapterError? = nil,
        hidesScheduledReadback: Bool = false
    ) {
        self.currentSupport = support
        self.scheduleError = scheduleError
        self.openError = openError
        self.hidesScheduledReadback = hidesScheduledReadback
    }

    func support() async throws -> WorkoutKitScheduleSupport {
        currentSupport
    }

    func scheduledWorkouts() async throws -> [WorkoutKitScheduledWorkoutSnapshot] {
        if hidesScheduledReadback {
            return []
        }
        return scheduledRequests.map { descriptor, occurrence in
            WorkoutKitScheduledWorkoutSnapshot(
                workoutPlanID: descriptor.id,
                occurrence: occurrence,
                complete: false
            )
        }
    }

    func scheduledRequestCount() -> Int {
        scheduledRequests.count
    }

    func openedDescriptorCount() -> Int {
        openedDescriptors.count
    }

    func schedule(
        _ descriptor: WorkoutKitPlanDescriptor,
        at occurrence: DateComponents
    ) async throws {
        if let scheduleError { throw scheduleError }
        scheduledRequests.append((descriptor, occurrence))
        currentSupport.scheduledCount += 1
    }

    func open(_ descriptor: WorkoutKitPlanDescriptor) async throws {
        if let openError { throw openError }
        openedDescriptors.append(descriptor)
    }
}
