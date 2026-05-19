import Foundation
import WorkoutKitExportProfile

struct WorkoutKitDiagnosticProbeEvent: Sendable, Hashable, Codable {
    var label: String
    var outcome: String
    var workoutPlanID: UUID?
    var scheduledCount: Int?
    var maxAllowedCount: Int?
    var errorDescription: String?

    init(
        label: String,
        outcome: String,
        workoutPlanID: UUID? = nil,
        scheduledCount: Int? = nil,
        maxAllowedCount: Int? = nil,
        errorDescription: String? = nil
    ) {
        self.label = label
        self.outcome = outcome
        self.workoutPlanID = workoutPlanID
        self.scheduledCount = scheduledCount
        self.maxAllowedCount = maxAllowedCount
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
        plan: WorkoutKitExportPlan,
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
            let descriptor = try WorkoutKitPlanFactory.descriptor(for: plan)
            try await client.schedule(descriptor, at: occurrence)
            let after = try await client.support()
            events.append(WorkoutKitDiagnosticProbeEvent(
                label: "after schedule",
                outcome: "scheduled",
                workoutPlanID: descriptor.id,
                scheduledCount: after.scheduledCount,
                maxAllowedCount: after.maxAllowedCount
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

    func runOpenProbe(plan: WorkoutKitExportPlan) async -> WorkoutKitDiagnosticProbeEvent {
        do {
            let descriptor = try WorkoutKitPlanFactory.descriptor(for: plan)
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
    static func scheduleProbePlan() -> WorkoutKitExportPlan {
        WorkoutKitExportPlan(
            workoutID: UUID(uuidString: "10000000-0000-4000-8000-000000000201")!,
            workoutName: "Setmark WorkoutKit Probe",
            rowID: .continuousCardio,
            deliveryPaths: [.scheduleOnPhone, .openOnWatch],
            selectionPolicy: .exact(.singleGoal),
            supportState: .native,
            payload: WorkoutKitPayloadBlueprint(
                shape: .singleGoal,
                activitySelection: .cardio,
                goal: .time
            ),
            pushIdentity: WorkoutKitPushIdentity(requirements: [
                .stableWorkoutPlanID,
                .payloadFingerprint,
                .occurrenceDateComponents,
            ]),
            degradation: nil,
            proofRequirements: [.sdkCompile, .simulatorConstruction],
            unresolvedRequirements: [.exactTargetValuesUnavailable],
            sourceAmbiguities: []
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
                plan: WorkoutKitDiagnosticProbeFixture.scheduleProbePlan(),
                occurrence: WorkoutKitDiagnosticProbeFixture.scheduleProbeOccurrence()
            )
            return WorkoutKitDiagnosticProbeRunner.encodedJSON(events)
        }
        return "[]"
    }
}
#endif
