import Foundation
import CoreDomain
import CoreTelemetry
import Persistence
import WorkoutCoreFoundation
import WorkoutKitAdapter
import WorkoutKitExportProfile

public enum WorkoutKitHandoffProofState: String, Sendable, Hashable, Codable {
    case incomplete
    case proofCollection
    case complete
}

public struct WorkoutKitHandoffProofSource: Sendable {
    public var state: @Sendable () -> WorkoutKitHandoffProofState
    public var proofs: @Sendable () -> WorkoutKitDeliveryProofs

    public init(
        state: @escaping @Sendable () -> WorkoutKitHandoffProofState,
        proofs: @escaping @Sendable () -> WorkoutKitDeliveryProofs
    ) {
        self.state = state
        self.proofs = proofs
    }

    public static let incomplete = WorkoutKitHandoffProofSource(
        state: { .incomplete },
        proofs: { WorkoutKitDeliveryProofs() }
    )

    public static let proofCollection = WorkoutKitHandoffProofSource(
        state: { .proofCollection },
        proofs: {
            WorkoutKitDeliveryProofs(proven: [
                .sdkCompile,
                .simulatorConstruction,
            ])
        }
    )

    public static let complete = WorkoutKitHandoffProofSource(
        state: { .complete },
        proofs: {
            WorkoutKitDeliveryProofs(proven: [
                .sdkCompile,
                .simulatorConstruction,
                .realDeviceScheduleVisibility,
                .duplicateUpdateBehavior,
            ])
        }
    )
}

public enum WorkoutKitHandoffPresentationState: String, Sendable, Hashable, Codable {
    case hidden
    case unavailable
    case ready
    case pending
    case scheduled
    case failed
}

public struct WorkoutKitHandoffPresentation: Sendable, Hashable, Codable {
    public var state: WorkoutKitHandoffPresentationState
    public var title: String
    public var message: String
    public var actionTitle: String?
    public var isActionable: Bool

    public init(
        state: WorkoutKitHandoffPresentationState,
        title: String,
        message: String,
        actionTitle: String? = nil,
        isActionable: Bool = false
    ) {
        self.state = state
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.isActionable = isActionable
    }
}

public struct WorkoutKitHandoffScheduleResult: Sendable, Hashable {
    public var presentation: WorkoutKitHandoffPresentation
    public var receipt: WorkoutKitHandoffReceipt?

    public init(
        presentation: WorkoutKitHandoffPresentation,
        receipt: WorkoutKitHandoffReceipt?
    ) {
        self.presentation = presentation
        self.receipt = receipt
    }
}

public struct WorkoutKitHandoffCoordinator: Sendable {
    private let classifier: WorkoutKitExportClassifier
    private let attemptStore: any WorkoutKitHandoffAttemptStore
    private let telemetry: any TelemetryEmitter
    private let proofSource: WorkoutKitHandoffProofSource
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let push: @Sendable (WorkoutKitPushRequest) async -> WorkoutKitPushOutcome

    public init(
        classifier: WorkoutKitExportClassifier = WorkoutKitExportClassifier(),
        attemptStore: any WorkoutKitHandoffAttemptStore,
        telemetry: any TelemetryEmitter = NoopTelemetryEmitter(),
        proofSource: WorkoutKitHandoffProofSource = .incomplete,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = WorkoutKitHandoffCoordinator.defaultCalendar(),
        push: @escaping @Sendable (WorkoutKitPushRequest) async -> WorkoutKitPushOutcome = {
            await WorkoutKitPushCoordinator.live().push($0)
        }
    ) {
        self.classifier = classifier
        self.attemptStore = attemptStore
        self.telemetry = telemetry
        self.proofSource = proofSource
        self.now = now
        self.calendar = calendar
        self.push = push
    }

    public static func defaultCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public func presentation(
        workout: PrimitiveWorkout,
        scheduledDate: Date?
    ) async -> WorkoutKitHandoffPresentation? {
        guard let plan = try? classifier.classify(workout: workout),
              plan.rowID == .paceTargetRun
        else {
            emit(.presentationEvaluated, workoutID: workout.id, plan: nil, extra: [
                "proofState": proofSource.state().rawValue,
                "blockerClass": "not_pace_target_run",
            ])
            return nil
        }
        emit(.presentationEvaluated, workoutID: workout.id, plan: plan)
        return await presentation(for: plan, scheduledDate: scheduledDate)
    }

    public func schedule(
        workout: PrimitiveWorkout,
        scheduledDate: Date?
    ) async -> WorkoutKitHandoffScheduleResult {
        guard let plan = try? classifier.classify(workout: workout),
              plan.rowID == .paceTargetRun
        else {
            let presentation = unavailable("This workout is not a single-pace scheduled run.")
            emit(.blockedBeforeScheduling, workoutID: workout.id, plan: nil, extra: [
                "blockerClass": "not_pace_target_run",
            ])
            return WorkoutKitHandoffScheduleResult(presentation: presentation, receipt: nil)
        }
        guard let occurrence = occurrence(for: scheduledDate) else {
            emit(.blockedBeforeScheduling, workoutID: workout.id, plan: plan, extra: [
                "blockerClass": "unsupported_scheduled_date",
            ])
            return await persistBlocked(
                plan: plan,
                occurrenceKey: scheduledDate.map { Self.occurrenceKey(for: dateOnlyComponents(from: $0)) }
                    ?? "missing_scheduled_date",
                payloadFingerprint: "unavailable",
                failureClass: "unsupported_scheduled_date",
                message: "This run needs a scheduled calendar date inside Apple's supported window."
            )
        }

        let fingerprint: WorkoutKitPayloadFingerprint
        do {
            fingerprint = try WorkoutKitPayloadFingerprint.make(
                plan: plan,
                descriptor: try plan.resolvedPlanDescriptor(),
                occurrence: occurrence
            )
        } catch {
            emit(.blockedBeforeScheduling, workoutID: workout.id, plan: plan, extra: [
                "blockerClass": "descriptor_incomplete",
            ])
            return await persistBlocked(
                plan: plan,
                occurrenceKey: Self.occurrenceKey(for: occurrence),
                payloadFingerprint: "descriptor_incomplete",
                failureClass: "descriptor_incomplete",
                message: "Apple Workout scheduling is missing exact target values."
            )
        }

        let proofs = proofSource.proofs()
        let assessment = deliveryAssessment(plan: plan, proofs: proofs)
        guard assessment.blockingReasons.isEmpty else {
            let blocker = stableClass(assessment.blockingReasons)
            emit(.blockedBeforeScheduling, workoutID: workout.id, plan: plan, extra: [
                "blockerClass": blocker,
            ])
            return await persistBlocked(
                plan: plan,
                occurrenceKey: Self.occurrenceKey(for: occurrence),
                payloadFingerprint: fingerprint.value,
                failureClass: blocker,
                message: "Apple Workout scheduling is blocked by \(blocker)."
            )
        }

        let occurrenceKey = Self.occurrenceKey(for: occurrence)
        if let latest = await attemptStore.latestSuccessfulSchedule(
            workoutID: plan.workoutID,
            occurrenceKey: occurrenceKey,
            path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue
        ),
           latest.outcome == "scheduled"
        {
            let blockerClass = latest.payloadFingerprint == fingerprint.value
                ? "same_payload_already_scheduled"
                : "changed_payload_already_scheduled"
            emit(.repeatBlocked, workoutID: workout.id, plan: plan, extra: [
                "occurrenceKey": occurrenceKey,
                "payloadFingerprint": fingerprint.value,
                "previousPayloadFingerprint": latest.payloadFingerprint,
                "blockerClass": blockerClass,
            ])
            if latest.payloadFingerprint != fingerprint.value {
                return await persistBlocked(
                    plan: plan,
                    occurrenceKey: occurrenceKey,
                    payloadFingerprint: fingerprint.value,
                    failureClass: blockerClass,
                    message: "This run changed after it was scheduled. Edit/update proof is not available yet."
                )
            }
            return await persistBlocked(
                plan: plan,
                occurrenceKey: occurrenceKey,
                payloadFingerprint: fingerprint.value,
                failureClass: blockerClass,
                message: scheduledCopy(date: scheduledDate).message,
                state: .scheduled
            )
        }

        emit(.actionTapped, workoutID: workout.id, plan: plan, extra: [
            "occurrenceKey": occurrenceKey,
            "payloadFingerprint": fingerprint.value,
        ])
        emit(.schedulerSupportChecked, workoutID: workout.id, plan: plan)

        let outcome = await push(WorkoutKitPushRequest(
            plan: plan,
            path: .scheduleOnPhone,
            occurrence: occurrence,
            proofs: proofs,
            proofMode: proofSource.state() == .proofCollection ? .proofCollection : .complete
        ))
        return await persist(
            outcome: outcome,
            plan: plan,
            occurrenceKey: occurrenceKey,
            scheduledDate: scheduledDate,
            expectedFingerprint: fingerprint.value
        )
    }

    private func presentation(
        for plan: WorkoutKitExportPlan,
        scheduledDate: Date?
    ) async -> WorkoutKitHandoffPresentation? {
        guard let occurrence = occurrence(for: scheduledDate) else {
            emit(.actionBlocked, workoutID: plan.workoutID, plan: plan, extra: [
                "blockerClass": "unsupported_scheduled_date",
            ])
            return unavailable("This run needs a scheduled calendar date inside Apple's supported window.")
        }
        let proofState = proofSource.state()
        guard proofState != .incomplete else {
            emit(.actionBlocked, workoutID: plan.workoutID, plan: plan, extra: [
                "blockerClass": "delivery_proof_incomplete",
            ])
            return nil
        }

        let assessment = deliveryAssessment(plan: plan, proofs: proofSource.proofs())
        guard assessment.blockingReasons.isEmpty else {
            let blocker = stableClass(assessment.blockingReasons)
            emit(.actionBlocked, workoutID: plan.workoutID, plan: plan, extra: [
                "blockerClass": blocker,
            ])
            return unavailable("Apple Workout scheduling is blocked by \(blocker).")
        }

        let occurrenceKey = Self.occurrenceKey(for: occurrence)
        guard let fingerprint = try? WorkoutKitPayloadFingerprint.make(
            plan: plan,
            descriptor: plan.resolvedPlanDescriptor(),
            occurrence: occurrence
        ) else {
            emit(.actionBlocked, workoutID: plan.workoutID, plan: plan, extra: [
                "blockerClass": "descriptor_incomplete",
            ])
            return unavailable("Apple Workout scheduling is missing exact target values.")
        }
        if let latest = await attemptStore.latestSuccessfulSchedule(
            workoutID: plan.workoutID,
            occurrenceKey: occurrenceKey,
            path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue
        ),
           latest.outcome == "scheduled"
        {
            guard latest.payloadFingerprint == fingerprint.value else {
                emit(.actionBlocked, workoutID: plan.workoutID, plan: plan, extra: [
                    "occurrenceKey": occurrenceKey,
                    "payloadFingerprint": fingerprint.value,
                    "previousPayloadFingerprint": latest.payloadFingerprint,
                    "blockerClass": "changed_payload_already_scheduled",
                ])
                return unavailable(
                    "This run changed after it was scheduled. Edit/update proof is not available yet."
                )
            }
            return scheduledCopy(date: scheduledDate)
        }
        emit(.actionExposed, workoutID: plan.workoutID, plan: plan, extra: [
            "occurrenceKey": occurrenceKey,
            "payloadFingerprint": fingerprint.value,
        ])
        return readyCopy(plan: plan, date: scheduledDate)
    }

    private func deliveryAssessment(
        plan: WorkoutKitExportPlan,
        proofs: WorkoutKitDeliveryProofs
    ) -> WorkoutKitDeliveryAssessment {
        var assessment = classifier.assessDelivery(
            plan,
            path: .scheduleOnPhone,
            proofs: proofs
        )
        guard proofSource.state() == .proofCollection else {
            return assessment
        }
        assessment.blockingReasons.remove(.scheduleVisibilityProofRequired)
        assessment.blockingReasons.remove(.duplicateUpdateProofRequired)
        assessment.unmetProofRequirements.remove(.realDeviceScheduleVisibility)
        assessment.unmetProofRequirements.remove(.duplicateUpdateBehavior)
        return assessment
    }

    private func persist(
        outcome: WorkoutKitPushOutcome,
        plan: WorkoutKitExportPlan,
        occurrenceKey: String,
        scheduledDate: Date?,
        expectedFingerprint: String
    ) async -> WorkoutKitHandoffScheduleResult {
        let date = now()
        let resolved = resolvedOutcome(outcome, expectedFingerprint: expectedFingerprint)
        let receipt = WorkoutKitHandoffReceipt(
            createdAt: date,
            workoutID: plan.workoutID,
            rowID: plan.rowID.rawValue,
            path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue,
            occurrenceKey: occurrenceKey,
            payloadFingerprint: resolved.payloadFingerprint,
            workoutPlanID: resolved.workoutPlanID,
            outcome: resolved.outcome,
            failureClass: resolved.failureClass
        )
        await attemptStore.save(
            snapshot: WorkoutKitHandoffAttemptSnapshot(
                workoutID: plan.workoutID,
                occurrenceKey: occurrenceKey,
                path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue,
                payloadFingerprint: resolved.payloadFingerprint,
                lastAttemptAt: date,
                outcome: resolved.outcome,
                workoutPlanID: resolved.workoutPlanID,
                failureClass: resolved.failureClass
            ),
            receipt: receipt
        )

        emit(
            resolved.outcome == "scheduled" ? .scheduleSucceeded : .scheduleFailed,
            workoutID: plan.workoutID,
            plan: plan,
            extra: [
                "occurrenceKey": occurrenceKey,
                "payloadFingerprint": resolved.payloadFingerprint,
                "workoutPlanID": resolved.workoutPlanID?.uuidString.lowercased() ?? "",
                "failureClass": resolved.failureClass ?? "",
                "receiptID": receipt.id.uuidString.lowercased(),
            ]
        )

        let presentation = resolved.outcome == "scheduled"
            ? scheduledCopy(date: scheduledDate)
            : WorkoutKitHandoffPresentation(
                state: .failed,
                title: "Apple Workout",
                message: "Scheduling failed: \(resolved.failureClass ?? "unknown").",
                actionTitle: "Watch",
                isActionable: true
        )
        return WorkoutKitHandoffScheduleResult(presentation: presentation, receipt: receipt)
    }

    private func persistBlocked(
        plan: WorkoutKitExportPlan,
        occurrenceKey: String,
        payloadFingerprint: String,
        failureClass: String,
        message: String,
        state: WorkoutKitHandoffPresentationState = .unavailable
    ) async -> WorkoutKitHandoffScheduleResult {
        let date = now()
        let receipt = WorkoutKitHandoffReceipt(
            createdAt: date,
            workoutID: plan.workoutID,
            rowID: plan.rowID.rawValue,
            path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue,
            occurrenceKey: occurrenceKey,
            payloadFingerprint: payloadFingerprint,
            workoutPlanID: nil,
            outcome: "blocked",
            failureClass: failureClass
        )
        await attemptStore.save(
            snapshot: WorkoutKitHandoffAttemptSnapshot(
                workoutID: plan.workoutID,
                occurrenceKey: occurrenceKey,
                path: WorkoutKitDeliveryPath.scheduleOnPhone.rawValue,
                payloadFingerprint: payloadFingerprint,
                lastAttemptAt: date,
                outcome: "blocked",
                workoutPlanID: nil,
                failureClass: failureClass
            ),
            receipt: receipt
        )
        return WorkoutKitHandoffScheduleResult(
            presentation: WorkoutKitHandoffPresentation(
                state: state,
                title: "Apple Workout",
                message: message,
                actionTitle: state == .scheduled ? nil : "Watch",
                isActionable: state != .scheduled
            ),
            receipt: receipt
        )
    }

    private func resolvedOutcome(
        _ outcome: WorkoutKitPushOutcome,
        expectedFingerprint: String
    ) -> (outcome: String, workoutPlanID: UUID?, payloadFingerprint: String, failureClass: String?) {
        switch outcome {
        case .scheduled(let record):
            return ("scheduled", record.workoutPlanID, record.payloadFingerprint.value, nil)
        case .blocked(let assessment):
            return ("blocked", nil, expectedFingerprint, stableClass(assessment.blockingReasons))
        case .unsupportedPlatform(let error), .failed(let error):
            return ("failed", nil, expectedFingerprint, String(describing: error))
        case .opened:
            return ("failed", nil, expectedFingerprint, "unexpected_opened_outcome")
        }
    }

    private func occurrence(for scheduledDate: Date?) -> DateComponents? {
        guard let scheduledDate,
              let earliest = calendar.date(
                byAdding: .day,
                value: -7,
                to: calendar.startOfDay(for: now())
              ),
              let latest = calendar.date(
                byAdding: .day,
                value: 7,
                to: calendar.startOfDay(for: now())
              )
        else {
            return nil
        }
        let scheduledDay = calendar.startOfDay(for: scheduledDate)
        guard scheduledDay >= earliest, scheduledDay <= latest else { return nil }
        return dateOnlyComponents(from: scheduledDate)
    }

    private func dateOnlyComponents(from date: Date) -> DateComponents {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return DateComponents(
            calendar: calendar,
            era: components.era,
            year: components.year,
            month: components.month,
            day: components.day
        )
    }

    private func readyCopy(
        plan: WorkoutKitExportPlan,
        date: Date?
    ) -> WorkoutKitHandoffPresentation {
        let summary = pacerSummary(plan: plan)
            .map { ": \($0)" }
            ?? ""
        return WorkoutKitHandoffPresentation(
            state: .ready,
            title: "Apple Workout",
            message: "Schedule \(date.map(Self.displayDateOnly) ?? "this run") in Apple's Workout app\(summary).",
            actionTitle: "Watch",
            isActionable: true
        )
    }

    private func unavailable(_ message: String) -> WorkoutKitHandoffPresentation {
        WorkoutKitHandoffPresentation(
            state: .unavailable,
            title: "Apple Workout",
            message: message
        )
    }

    private func scheduledCopy(date: Date?) -> WorkoutKitHandoffPresentation {
        WorkoutKitHandoffPresentation(
            state: .scheduled,
            title: "Apple Workout",
            message: "Scheduled in Apple Workout from this phone for \(date.map(Self.displayDateOnly) ?? "the authored date")."
        )
    }

    private static func displayDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = defaultCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public static func occurrenceKey(for components: DateComponents) -> String {
        [
            components.year,
            components.month,
            components.day,
        ]
        .map { String(format: "%02d", $0 ?? 0) }
        .joined(separator: "-")
    }

    private func stableClass(_ reasons: Set<WorkoutKitBlockReason>) -> String {
        reasons.map(\.rawValue).sorted().joined(separator: "+")
    }

    private func emit(
        _ name: TelemetryName,
        workoutID: WorkoutID,
        plan: WorkoutKitExportPlan?,
        extra: [String: String] = [:]
    ) {
        var payload = extra
        payload["rowID"] = plan?.rowID.rawValue ?? ""
        payload["path"] = WorkoutKitDeliveryPath.scheduleOnPhone.rawValue
        payload["proofState"] = proofSource.state().rawValue
        if let pacerFields = plan.flatMap(pacerTelemetryFields(plan:)) {
            payload.merge(pacerFields) { current, _ in current }
        }
        let data = try? JSONEncoder().encode(payload)
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: name.rawValue,
            dataJSON: data.flatMap { String(data: $0, encoding: .utf8) },
            workoutID: workoutID
        ))
    }

    private func pacerSummary(plan: WorkoutKitExportPlan) -> String? {
        guard let pacer = pacerValues(plan: plan) else {
            return nil
        }
        return "\(Self.formatDistance(pacer.distanceMeters)) in \(Self.formatDuration(pacer.timeSeconds)) (\(Self.formatPace(pacer.paceSecondsPerKilometer))/km)"
    }

    private func pacerTelemetryFields(plan: WorkoutKitExportPlan) -> [String: String]? {
        guard let pacer = pacerValues(plan: plan) else {
            return nil
        }
        return [
            "distanceMeters": Self.formatNumber(pacer.distanceMeters),
            "targetTimeSeconds": Self.formatNumber(pacer.timeSeconds),
            "derivedPaceSecondsPerKilometer": Self.formatNumber(pacer.paceSecondsPerKilometer),
        ]
    }

    private func pacerValues(
        plan: WorkoutKitExportPlan
    ) -> (distanceMeters: Double, timeSeconds: Double, paceSecondsPerKilometer: Double)? {
        guard case .resolved(let descriptor) = plan.descriptor,
              case .pacer(let distanceMeters, let timeSeconds) = descriptor.goal,
              distanceMeters > 0
        else {
            return nil
        }
        return (
            distanceMeters: distanceMeters,
            timeSeconds: timeSeconds,
            paceSecondsPerKilometer: timeSeconds / (distanceMeters / 1_000)
        )
    }

    private static func formatDistance(_ meters: Double) -> String {
        let kilometers = meters / 1_000
        return "\(formatNumber(kilometers)) km"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let secondsRemainder = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secondsRemainder)
    }

    private static func formatPace(_ seconds: Double) -> String {
        formatDuration(seconds)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private enum TelemetryName: String {
        case presentationEvaluated = "workoutkit.presentation_evaluated"
        case actionExposed = "workoutkit.action_exposed"
        case actionBlocked = "workoutkit.action_blocked"
        case actionTapped = "workoutkit.action_tapped"
        case blockedBeforeScheduling = "workoutkit.blocked_before_scheduling"
        case schedulerSupportChecked = "workoutkit.scheduler_support_checked"
        case scheduleSucceeded = "workoutkit.schedule_succeeded"
        case scheduleFailed = "workoutkit.schedule_failed"
        case repeatBlocked = "workoutkit.repeat_blocked"
    }
}
