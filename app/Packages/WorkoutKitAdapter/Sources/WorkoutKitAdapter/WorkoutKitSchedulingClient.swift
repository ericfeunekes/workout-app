import Foundation

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

protocol WorkoutKitSchedulingClient: Sendable {
    func support() async throws -> WorkoutKitScheduleSupport
    func schedule(_ descriptor: WorkoutKitPlanDescriptor, at occurrence: DateComponents) async throws
    func open(_ descriptor: WorkoutKitPlanDescriptor) async throws
}

actor FakeWorkoutKitSchedulingClient: WorkoutKitSchedulingClient {
    private(set) var scheduledRequests: [(WorkoutKitPlanDescriptor, DateComponents)] = []
    private(set) var openedDescriptors: [WorkoutKitPlanDescriptor] = []
    private var currentSupport: WorkoutKitScheduleSupport
    private var scheduleError: WorkoutKitAdapterError?
    private var openError: WorkoutKitAdapterError?

    init(
        support: WorkoutKitScheduleSupport = WorkoutKitScheduleSupport(
            isSupported: true,
            scheduledCount: 0,
            maxAllowedCount: 15
        ),
        scheduleError: WorkoutKitAdapterError? = nil,
        openError: WorkoutKitAdapterError? = nil
    ) {
        self.currentSupport = support
        self.scheduleError = scheduleError
        self.openError = openError
    }

    func support() async throws -> WorkoutKitScheduleSupport {
        currentSupport
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
