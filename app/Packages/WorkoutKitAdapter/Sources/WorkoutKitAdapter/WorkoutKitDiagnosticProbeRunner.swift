import Foundation
import WorkoutKitExportProfile

struct WorkoutKitDiagnosticProbeEvent: Sendable, Hashable, Codable {
    var label: String
    var outcome: String
    var workoutPlanID: UUID?
    var scheduledCount: Int?
    var maxAllowedCount: Int?
    var scheduledWorkoutPlanIDs: [UUID]
    var errorDescription: String?

    init(
        label: String,
        outcome: String,
        workoutPlanID: UUID? = nil,
        scheduledCount: Int? = nil,
        maxAllowedCount: Int? = nil,
        scheduledWorkoutPlanIDs: [UUID] = [],
        errorDescription: String? = nil
    ) {
        self.label = label
        self.outcome = outcome
        self.workoutPlanID = workoutPlanID
        self.scheduledCount = scheduledCount
        self.maxAllowedCount = maxAllowedCount
        self.scheduledWorkoutPlanIDs = scheduledWorkoutPlanIDs
        self.errorDescription = errorDescription
    }
}

/// DEBUG/test evidence collection only. This runner intentionally bypasses
/// production proof gates so first real-device WorkoutKit behavior can be
/// measured. Do not call it from user-facing export flows.
struct WorkoutKitDiagnosticProbeRunner: Sendable {
    private let client: any WorkoutKitSchedulingClient

    init(client: any WorkoutKitSchedulingClient) {
        self.client = client
    }

    func runScheduleProbe(
        descriptor: WorkoutKitPlanDescriptor,
        occurrence: DateComponents
    ) async -> [WorkoutKitDiagnosticProbeEvent] {
        var events: [WorkoutKitDiagnosticProbeEvent] = []
        do {
            let support = try await client.support()
            events.append(WorkoutKitDiagnosticProbeEvent(
                label: "before schedule",
                outcome: support.isSupported ? "supported" : "unsupported",
                scheduledCount: support.scheduledCount,
                maxAllowedCount: support.maxAllowedCount
            ))
            try await client.schedule(descriptor, at: occurrence)
            let after = try await client.support()
            let readback = try await client.scheduledWorkouts()
            events.append(WorkoutKitDiagnosticProbeEvent(
                label: "after schedule",
                outcome: "scheduled",
                workoutPlanID: descriptor.id,
                scheduledCount: after.scheduledCount,
                maxAllowedCount: after.maxAllowedCount,
                scheduledWorkoutPlanIDs: readback.map(\.workoutPlanID)
            ))
        } catch {
            events.append(WorkoutKitDiagnosticProbeEvent(
                label: "schedule error",
                outcome: "failed",
                errorDescription: String(describing: error)
            ))
        }
        return events
    }

    func runOpenProbe(descriptor: WorkoutKitPlanDescriptor) async -> WorkoutKitDiagnosticProbeEvent {
        do {
            try await client.open(descriptor)
            return WorkoutKitDiagnosticProbeEvent(
                label: "open",
                outcome: "opened",
                workoutPlanID: descriptor.id
            )
        } catch {
            return WorkoutKitDiagnosticProbeEvent(
                label: "open error",
                outcome: "failed",
                errorDescription: String(describing: error)
            )
        }
    }

    static func encodedJSON(_ events: [WorkoutKitDiagnosticProbeEvent]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(events),
              let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }
}

enum WorkoutKitDiagnosticProbeFixture {
    static func scheduleProbeDescriptor() -> WorkoutKitPlanDescriptor {
        WorkoutKitPlanDescriptor(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000201")!,
            displayName: "Setmark WorkoutKit Probe",
            family: .singleGoal,
            activity: .other,
            goal: .timeSeconds(20 * 60)
        )
    }

    static func scheduleProbeOccurrence(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateComponents {
        let scheduled = now.addingTimeInterval(10 * 60)
        return calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: scheduled
        )
    }
}

#if DEBUG
public enum WorkoutKitDiagnosticProbe {
    public static func runScheduleProbeJSON() async -> String {
        if #available(iOS 17.0, watchOS 10.0, *) {
            let runner = WorkoutKitDiagnosticProbeRunner(client: LiveWorkoutKitSchedulingClient())
            let events = await runner.runScheduleProbe(
                descriptor: WorkoutKitDiagnosticProbeFixture.scheduleProbeDescriptor(),
                occurrence: WorkoutKitDiagnosticProbeFixture.scheduleProbeOccurrence()
            )
            return WorkoutKitDiagnosticProbeRunner.encodedJSON(events)
        }
        return "[]"
    }
}
#endif
