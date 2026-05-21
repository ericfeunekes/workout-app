// TodayViewModel.swift
//
// `@Observable` view model for the Today screen. Derives the displayable
// shape from a `TodayPlanContext` at construction time and exposes start
// actions for visible planned workouts.
//
// Reload (bug-036): on save & done the shell writes the completed workout
// to the local cache and the session route flips back to `.today`. The
// Today tab must then pick up the NEXT planned workout instead of re-
// rendering the just-completed one. `reload(using:)` re-runs the
// `TodayLoader`, derives a fresh `TodayContext`, and mutates the
// observable fields in place so SwiftUI picks up the new values. When
// the loader returns `nil` (no more planned workouts), the VM flips to
// an empty-shaped state (`isEmpty == true`, `exercises == []`, blank
// program name) — the shell renders the existing S8 "zero-exercise"
// empty glance until the next pull fills the queue.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import CoreTelemetry
import WorkoutCoreFoundation

@Observable
@MainActor
public final class TodayViewModel {

    /// A single row in the exercise list. Pre-formatted for direct
    /// rendering — the view never parses JSON or formats numbers.
    public struct ExerciseSummary: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        /// "4 × 5 @ 102.5 kg" — see `PrescriptionLineFormatter`.
        public let prescriptionLine: String
        /// "5×5 @ 100 kg · RIR 2" when the exercise has prior history,
        /// `nil` when it doesn't.
        public let lastTime: String?

        public init(
            id: UUID,
            name: String,
            prescriptionLine: String,
            lastTime: String?
        ) {
            self.id = id
            self.name = name
            self.prescriptionLine = prescriptionLine
            self.lastTime = lastTime
        }
    }

    public enum PlanSectionKind: String, Equatable, Sendable {
        case missed
        case today
        case upcoming
        case unscheduled
    }

    public struct WorkoutSummary: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let sectionKind: PlanSectionKind
        public let sectionTitle: String
        public let tagLine: String?
        public let cardBlocks: [BlockPreview]
        public let hasMoreBlocks: Bool
        public let badge: String?
        public let isStartable: Bool
        public let isSelected: Bool
    }

    public struct BlockPreview: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let timingLabel: String
        public let timingDetail: String?
        public let exercises: [ExerciseSummary]
        public let hasMoreExercises: Bool
    }

    public struct PlanSection: Identifiable, Equatable, Sendable {
        public let title: String
        public let kind: PlanSectionKind
        public let workouts: [WorkoutSummary]

        public var id: String { "\(kind.rawValue)-\(title)" }
    }

    public struct WorkoutDetail: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let sectionTitle: String
        public let tagLine: String?
        public let notes: String?
        public let preview: PreviewSummary?
        public let workoutKitHandoff: WorkoutKitHandoffSummary?
        public let blocks: [BlockDetail]
    }

    public struct WorkoutKitHandoffSummary: Equatable, Sendable {
        public enum State: String, Equatable, Sendable {
            case hidden
            case unavailable
            case ready
            case pending
            case scheduled
            case failed
        }

        public let state: State
        public let title: String
        public let message: String
        public let actionTitle: String?
        public let isActionable: Bool

        public init(
            state: State,
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

    public struct PreviewSummary: Equatable, Sendable {
        public let currentTitle: String
        public let currentDetail: String?
        public let blockIntent: String?
        public let remainingLine: String?
        public let upcoming: [PreviewUpcoming]
    }

    public struct PreviewUpcoming: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let detail: String?
    }

    public struct BlockDetail: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let timingLabel: String
        public let timingDetail: String?
        public let notes: String?
        public let exercises: [ExerciseSummary]
    }

    public struct AdjustmentDraft: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let body: String
    }

    public enum RefreshState: Equatable, Sendable {
        case idle
        case refreshing
        case failed
    }

    // MARK: - Published (mutated by `reload`)
    //
    // All five of these need `internal(set) var` rather than `let` so a
    // reload can replace them in place. Observers see the change because
    // `@Observable` tracks property access automatically.

    public internal(set) var programName: String
    public internal(set) var programTags: [String]
    public internal(set) var lastSessionSummary: String?
    public internal(set) var exercises: [ExerciseSummary]
    public internal(set) var planSections: [PlanSection]
    public internal(set) var workoutDetails: [UUID: WorkoutDetail]
    public internal(set) var refreshState: RefreshState
    /// `true` when the most recent load found no planned workout. The view
    /// can render a degenerate "nothing scheduled" state; today it falls
    /// through to S8 (header + empty list). Callers that need to flip a
    /// different phase should observe this and act.
    public internal(set) var isEmpty: Bool
    /// The id of the currently-displayed workout. `nil` when `isEmpty`.
    /// Exposed so tests can assert that reload advanced to a different
    /// workout; also convenient for telemetry correlation.
    public internal(set) var workoutID: UUID?

    /// Should the view render the pinned "start workout" button? The
    /// button only makes sense when there's a workout to start — when
    /// `isEmpty == true` (reload found nothing planned, per S11) it
    /// would be a disconnected CTA with nothing to dispatch. Exposed
    /// as a computed property so tests can assert the gate directly
    /// without view-tree inspection. See qa-008.
    public var showsStartButton: Bool { !isEmpty }
    public var canRefresh: Bool { refreshAction != nil }

    public func canStart(_ workout: WorkoutSummary) -> Bool {
        canStart(workoutID: workout.id)
    }

    public func canStart(workoutID targetWorkoutID: WorkoutID) -> Bool {
        guard startableWorkoutIDs.contains(targetWorkoutID) else { return false }
        return targetWorkoutID == workoutID || startWorkoutAction != nil
    }

    // MARK: - Dependencies for reload
    //
    // `sessionStateBinding` survives reload unchanged — the holder it
    // points at is stable across bootstrap (see Shell's
    // `ExecutionVMHolder`). `lastPerformed` / `lastSessionSummary`
    // / `programTags` are pass-through defaults from the original init;
    // they stay `nil` / `[:]` on reload until the history query API lands.

    private let telemetry: TelemetryEmitter
    private let sessionStateBinding: (@Sendable (SessionMutation) -> Void)?
    private var refreshAction: (@Sendable () async -> Bool)?
    private var startWorkoutAction: (@Sendable @MainActor (WorkoutID) async -> Bool)?
    private var workoutKitHandoffAction: (@Sendable @MainActor (WorkoutID) async -> WorkoutKitHandoffSummary?)?
    private var startableWorkoutIDs: Set<WorkoutID>
    private var workoutKitHandoffs: [WorkoutID: WorkoutKitHandoffSummary]

    public init(
        context: TodayContext,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        self.programName = context.workout.name
        self.programTags = context.programTags
        self.lastSessionSummary = context.lastSessionSummary
        self.exercises = Self.deriveExercises(from: context)
        let planContext = TodayPlanContext(selected: context, workouts: [context])
        self.planSections = Self.derivePlanSections(from: planContext, now: Date())
        self.workoutDetails = Self.deriveWorkoutDetails(from: planContext, now: Date())
        self.refreshState = .idle
        self.isEmpty = false
        self.workoutID = context.workout.id
        self.sessionStateBinding = context.sessionStateBinding
        self.telemetry = telemetry
        self.startableWorkoutIDs = Self.startableWorkoutIDs(
            from: planContext
        )
        self.workoutKitHandoffs = [:]
    }

    public init(
        planContext: TodayPlanContext,
        telemetry: TelemetryEmitter = NoopTelemetryEmitter()
    ) {
        let selected = planContext.selected
        self.programName = selected.workout.name
        self.programTags = selected.programTags
        self.lastSessionSummary = selected.lastSessionSummary
        self.exercises = Self.deriveExercises(from: selected)
        self.planSections = Self.derivePlanSections(from: planContext, now: Date())
        self.workoutDetails = Self.deriveWorkoutDetails(from: planContext, now: Date())
        self.refreshState = .idle
        self.isEmpty = false
        self.workoutID = selected.workout.id
        self.sessionStateBinding = selected.sessionStateBinding
        self.telemetry = telemetry
        self.startableWorkoutIDs = Self.startableWorkoutIDs(
            from: planContext
        )
        self.workoutKitHandoffs = [:]
    }

    /// Build a VM that starts in the empty-glance state — no planned
    /// workout is available, but the app is otherwise live (the cache
    /// has completed history, or the user is about to receive a pull).
    /// `showsStartButton` is `false` so Today renders its "no workout
    /// today" prompt; History still resolves via its own load path.
    ///
    /// qa-027 fix: cold-launch with completed workouts in cache but no
    /// planned rows must land on `.ready` with this VM (so the History
    /// tab stays reachable), not on the full-screen `.empty` shell
    /// state that hides History entirely.
    public static func empty(
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)? = nil
    ) -> TodayViewModel {
        TodayViewModel(
            emptyTelemetry: telemetry,
            sessionStateBinding: sessionStateBinding
        )
    }

    /// Private empty-state initializer. Mirrors the fields the public
    /// context init sets, but seeded with the same "nothing scheduled"
    /// shape `apply(nil)` flips to on reload. Kept private so callers
    /// go through `TodayViewModel.empty(...)` — the factory name makes
    /// the intent obvious at the call site.
    private init(
        emptyTelemetry: TelemetryEmitter,
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)?
    ) {
        self.programName = ""
        self.programTags = []
        self.lastSessionSummary = nil
        self.exercises = []
        self.planSections = []
        self.workoutDetails = [:]
        self.refreshState = .idle
        self.isEmpty = true
        self.workoutID = nil
        self.sessionStateBinding = sessionStateBinding
        self.telemetry = emptyTelemetry
        self.startableWorkoutIDs = []
        self.workoutKitHandoffs = [:]
    }

    /// Flip session route to `.active`. No-op when the binding is absent
    /// (previews, tests).
    public func start() {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "interaction",
            name: "today.start_tap",
            workoutID: workoutID
        ))
        sessionStateBinding?(.start)
    }

    /// Start a specific visible planned workout. The selected workout can
    /// use the legacy binding; non-selected cards need the shell-provided
    /// action to rebuild the execution VM before starting.
    public func start(workoutID targetWorkoutID: WorkoutID) async {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "interaction",
            name: "today.start_tap",
            workoutID: targetWorkoutID
        ))
        if let startWorkoutAction,
           await startWorkoutAction(targetWorkoutID) {
            return
        }
        if targetWorkoutID == workoutID {
            sessionStateBinding?(.start)
        }
    }

    public func detail(for workoutID: UUID) -> WorkoutDetail? {
        workoutDetails[workoutID]
    }

    public func adjustmentDraft(for detail: WorkoutDetail) -> AdjustmentDraft {
        AdjustmentDraft(
            id: detail.id,
            title: "Adjustment request",
            body: Self.adjustmentDraftBody(for: detail)
        )
    }

    public func setRefreshAction(_ action: (@Sendable () async -> Bool)?) {
        refreshAction = action
    }

    public func setStartWorkoutAction(
        _ action: (@Sendable @MainActor (WorkoutID) async -> Bool)?
    ) {
        startWorkoutAction = action
    }

    public func setWorkoutKitHandoffs(_ handoffs: [WorkoutID: WorkoutKitHandoffSummary]) {
        workoutKitHandoffs = handoffs
        workoutDetails = workoutDetails.mapValues { detail in
            WorkoutDetail(
                id: detail.id,
                name: detail.name,
                sectionTitle: detail.sectionTitle,
                tagLine: detail.tagLine,
                notes: detail.notes,
                preview: detail.preview,
                workoutKitHandoff: handoffs[detail.id],
                blocks: detail.blocks
            )
        }
    }

    public func setWorkoutKitHandoffAction(
        _ action: (@Sendable @MainActor (WorkoutID) async -> WorkoutKitHandoffSummary?)?
    ) {
        workoutKitHandoffAction = action
    }

    public func scheduleWorkoutKitHandoff(workoutID targetWorkoutID: WorkoutID) async {
        guard let current = workoutKitHandoffs[targetWorkoutID],
              current.isActionable,
              let action = workoutKitHandoffAction
        else { return }
        let pending = WorkoutKitHandoffSummary(
            state: .pending,
            title: current.title,
            message: "Scheduling in Apple Workout...",
            isActionable: false
        )
        updateWorkoutKitHandoff(pending, workoutID: targetWorkoutID)
        guard
              let summary = await action(targetWorkoutID)
        else {
            updateWorkoutKitHandoff(current, workoutID: targetWorkoutID)
            return
        }
        updateWorkoutKitHandoff(summary, workoutID: targetWorkoutID)
    }

    private func updateWorkoutKitHandoff(
        _ summary: WorkoutKitHandoffSummary,
        workoutID targetWorkoutID: WorkoutID
    ) {
        workoutKitHandoffs[targetWorkoutID] = summary
        guard let detail = workoutDetails[targetWorkoutID] else {
            return
        }
        workoutDetails[targetWorkoutID] = WorkoutDetail(
            id: detail.id,
            name: detail.name,
            sectionTitle: detail.sectionTitle,
            tagLine: detail.tagLine,
            notes: detail.notes,
            preview: detail.preview,
            workoutKitHandoff: summary,
            blocks: detail.blocks
        )
    }

    public func refresh() async {
        guard refreshState != .refreshing, let refreshAction else { return }
        refreshState = .refreshing
        refreshState = await refreshAction() ? .idle : .failed
    }

    // MARK: - Reload (bug-036)

    /// Re-run the `TodayLoader` against the current cache and replace the
    /// observable fields. Called by the shell after `saveAndDone` writes
    /// the completed workout locally — the just-completed workout is no
    /// longer `.planned`, so the loader picks the next one. When the
    /// loader returns `nil` (nothing planned left) the VM flips to an
    /// empty-shaped state; `isEmpty` becomes `true`, `exercises` becomes
    /// `[]`, and `workoutID` becomes `nil`.
    ///
    /// Errors thrown by the cache are swallowed — reload is fire-and-
    /// forget from the shell's perspective (matches the rest of the save-
    /// and-done side-effect chain). A failure leaves the previous state
    /// intact so the user at least sees something.
    @discardableResult
    public func reload(using loader: TodayLoader) async -> TodayPlanContext? {
        let context: TodayPlanContext?
        do {
            context = try await loader.loadPlan(
                sessionStateBinding: sessionStateBinding
            )
        } catch {
            // Cache read failed — keep the current rendered state rather
            // than blanking the screen. See `docs/sync.md` § offline.
            return nil
        }
        applyPlan(context)
        return context
    }

    /// Apply a fresh context (or `nil` for empty) to the observable
    /// surface. Split out so tests that want to drive the reload from a
    /// hand-rolled context (without standing up a `TodayLoader`) can
    /// call into it directly.
    func apply(_ context: TodayContext?) {
        guard let context else {
            applyPlan(nil)
            return
        }
        applyPlan(TodayPlanContext(selected: context, workouts: [context]))
    }

    func applyPlan(_ context: TodayPlanContext?) {
        guard let context else {
            programName = ""
            programTags = []
            lastSessionSummary = nil
            exercises = []
            planSections = []
            workoutDetails = [:]
            refreshState = .idle
            isEmpty = true
            workoutID = nil
            startableWorkoutIDs = []
            workoutKitHandoffs = [:]
            return
        }
        programName = context.selected.workout.name
        programTags = context.selected.programTags
        lastSessionSummary = context.selected.lastSessionSummary
        exercises = Self.deriveExercises(from: context.selected)
        planSections = Self.derivePlanSections(from: context, now: Date())
        workoutDetails = Self.deriveWorkoutDetails(from: context, now: Date())
        workoutDetails = workoutDetails.mapValues { detail in
            WorkoutDetail(
                id: detail.id,
                name: detail.name,
                sectionTitle: detail.sectionTitle,
                tagLine: detail.tagLine,
                notes: detail.notes,
                preview: detail.preview,
                workoutKitHandoff: workoutKitHandoffs[detail.id],
                blocks: detail.blocks
            )
        }
        isEmpty = false
        workoutID = context.selected.workout.id
        startableWorkoutIDs = Self.startableWorkoutIDs(
            from: context
        )
    }

    // MARK: - Derivation

    /// Walk the blocks in position order, then items in position order,
    /// assembling one `ExerciseSummary` per item. Items whose block is
    /// missing (data bug) are dropped silently — consistent with the
    /// reducer's no-op-on-invalid posture.
    static func deriveExercises(from context: TodayContext) -> [ExerciseSummary] {
        let parser = PrescriptionParser()
        let sortedBlocks = context.blocks.sorted { $0.position < $1.position }
        var itemsByBlock: [UUID: [WorkoutItem]] = [:]
        for item in context.items {
            itemsByBlock[item.blockID, default: []].append(item)
        }

        var out: [ExerciseSummary] = []
        for block in sortedBlocks {
            let items = (itemsByBlock[block.id] ?? [])
                .sorted { $0.position < $1.position }
            for item in items {
                let exercise = context.exercises[item.exerciseID]
                let name = exercise?.name ?? "(unknown exercise)"
                let prescriptionLine: String
                switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
                case .success(let prescription):
                    prescriptionLine = formatPrescriptionLine(prescription)
                case .failure:
                    // Parse failures are rare on today's pulled data —
                    // render a neutral fallback rather than crashing.
                    prescriptionLine = ""
                }
                out.append(ExerciseSummary(
                    id: item.id,
                    name: name,
                    prescriptionLine: prescriptionLine,
                    lastTime: context.lastPerformed[item.exerciseID]
                ))
            }
        }
        return out
    }

    static func derivePlanSections(
        from context: TodayPlanContext,
        now: Date,
        calendar: Calendar = TodayViewModel.makeScheduledDateCalendar()
    ) -> [PlanSection] {
        let summaries = context.workouts.map {
            workoutSummary(
                from: $0,
                selectedID: context.selected.workout.id,
                now: now,
                calendar: calendar
            )
        }

        var sections: [PlanSection] = []
        for summary in summaries {
            if let index = sections.firstIndex(where: { $0.title == summary.sectionTitle }) {
                let existing = sections[index]
                sections[index] = PlanSection(
                    title: existing.title,
                    kind: existing.kind,
                    workouts: existing.workouts + [summary]
                )
            } else {
                sections.append(PlanSection(
                    title: summary.sectionTitle,
                    kind: summary.sectionKind,
                    workouts: [summary]
                ))
            }
        }
        return sections
    }

    static func deriveWorkoutDetails(
        from context: TodayPlanContext,
        now: Date,
        calendar: Calendar = TodayViewModel.makeScheduledDateCalendar()
    ) -> [UUID: WorkoutDetail] {
        Dictionary(uniqueKeysWithValues: context.workouts.map { workoutContext in
            let section = sectionMetadata(
                scheduledDate: workoutContext.workout.scheduledDate,
                now: now,
                calendar: calendar
            )
            let detail = WorkoutDetail(
                id: workoutContext.workout.id,
                name: workoutContext.workout.name,
                sectionTitle: section.title,
                tagLine: tagLine(from: workoutContext.workout.tagsJSON),
                notes: workoutContext.workout.notes,
                preview: derivePreviewSummary(from: workoutContext),
                workoutKitHandoff: nil,
                blocks: deriveBlockDetails(from: workoutContext)
            )
            return (detail.id, detail)
        })
    }

    private static func workoutSummary(
        from context: TodayContext,
        selectedID: WorkoutID,
        now: Date,
        calendar: Calendar
    ) -> WorkoutSummary {
        let section = sectionMetadata(
            scheduledDate: context.workout.scheduledDate,
            now: now,
            calendar: calendar
        )
        let cardBlocks = deriveCardBlockPreviews(from: context)
        return WorkoutSummary(
            id: context.workout.id,
            name: context.workout.name,
            sectionKind: section.kind,
            sectionTitle: section.title,
            tagLine: tagLine(from: context.workout.tagsJSON),
            cardBlocks: cardBlocks,
            hasMoreBlocks: context.blocks.count > cardBlocks.count,
            badge: badge(for: section.kind, isSelected: context.workout.id == selectedID),
            isStartable: context.workout.id == selectedID && isExecutionStartable(context),
            isSelected: context.workout.id == selectedID
        )
    }

    private static func startableWorkoutIDs(from context: TodayPlanContext) -> Set<WorkoutID> {
        Set(context.workouts.compactMap { workoutContext in
            isExecutionStartable(workoutContext)
                ? workoutContext.workout.id
                : nil
        })
    }

    private static func isExecutionStartable(_ context: TodayContext) -> Bool {
        if context.primitiveWorkout != nil, context.primitiveExecutionPlan == nil {
            return false
        }
        return true
    }

    private static func sectionMetadata(
        scheduledDate: Date?,
        now: Date,
        calendar: Calendar
    ) -> (kind: PlanSectionKind, title: String) {
        guard let scheduledDate else {
            return (.unscheduled, "UNSCHEDULED")
        }
        let day = shortDayMonthDay(scheduledDate)
        if calendar.isDate(scheduledDate, inSameDayAs: now) {
            return (.today, "TODAY · \(day)")
        }
        if scheduledDate < calendar.startOfDay(for: now) {
            return (.missed, "MISSED · \(day)")
        }
        return (.upcoming, "\(relativeFutureLabel(scheduledDate, now: now, calendar: calendar)) · \(day)")
    }

    private static func relativeFutureLabel(
        _ date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "TOMORROW"
        }
        return "UPCOMING"
    }

    private static func shortDayMonthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = makeScheduledDateCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = makeScheduledDateTimeZone()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date).uppercased()
    }

    nonisolated private static func makeScheduledDateTimeZone() -> TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    nonisolated private static func makeScheduledDateCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = makeScheduledDateTimeZone()
        return calendar
    }

    private static func tagLine(from tagsJSON: String?) -> String? {
        guard let tagsJSON,
              let data = tagsJSON.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data),
              !tags.isEmpty else {
            return nil
        }
        return tags
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: " · ")
    }

    private static func timingLabel(_ mode: TimingMode) -> String {
        mode.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private static func deriveBlockDetails(from context: TodayContext) -> [BlockDetail] {
        let sortedBlocks = context.blocks.sorted { $0.position < $1.position }
        var itemsByBlock: [UUID: [WorkoutItem]] = [:]
        for item in context.items {
            itemsByBlock[item.blockID, default: []].append(item)
        }

        return sortedBlocks.map { block in
            let items = (itemsByBlock[block.id] ?? [])
                .sorted { $0.position < $1.position }
            return BlockDetail(
                id: block.id,
                title: blockTitle(block),
                timingLabel: timingLabel(block.timingMode),
                timingDetail: timingDetail(block),
                notes: block.notes,
                exercises: items.map { exerciseSummary(for: $0, in: context) }
            )
        }
    }

    private static func derivePreviewSummary(from context: TodayContext) -> PreviewSummary? {
        guard let plan = context.primitiveExecutionPlan else { return nil }
        let projection = SessionPreviewProjection(plan: plan)
        guard let current = projection.current else { return nil }

        return PreviewSummary(
            currentTitle: previewTitle(for: current, in: context),
            currentDetail: current.metrics.detail,
            blockIntent: projection.currentBlock.flatMap { block in
                context.blocks[safe: block.blockIndex]?.intent
            },
            remainingLine: remainingLine(for: projection.remaining),
            upcoming: projection.upcoming.map { upcoming in
                PreviewUpcoming(
                    id: previewID(for: upcoming),
                    title: previewTitle(for: upcoming, in: context),
                    detail: upcoming.metrics.detail
                )
            }
        )
    }

    private static func previewID(for work: SessionPreviewWork) -> String {
        [
            work.blockID.uuidString,
            work.setID.uuidString,
            work.slotID?.uuidString ?? "timer",
            String(work.setRepeatIndex),
        ].joined(separator: "-")
    }

    private static func previewTitle(for work: SessionPreviewWork, in context: TodayContext) -> String {
        guard let exerciseID = work.exerciseID else {
            return context.blocks[safe: work.blockIndex]?.name ?? "Timed work"
        }
        return exerciseName(for: exerciseID, in: context)
    }

    private static func exerciseName(for exerciseID: ExerciseID, in context: TodayContext) -> String {
        context.exercises[exerciseID]?.name ?? "(unknown exercise)"
    }

    private static func remainingLine(for remaining: SessionPreviewRemaining) -> String? {
        switch remaining {
        case .bounded(_, let total):
            guard let left = remaining.remaining else { return nil }
            return "\(left) \(left == 1 ? "set" : "sets") left in current block of \(total)"
        case .unbounded:
            return "open-ended current block"
        }
    }

    private static func deriveCardBlockPreviews(from context: TodayContext) -> [BlockPreview] {
        let blockDetails = deriveBlockDetails(from: context)
        return blockDetails.prefix(2).map { block in
            BlockPreview(
                id: block.id,
                title: block.title,
                timingLabel: block.timingLabel,
                timingDetail: block.timingDetail,
                exercises: Array(block.exercises.prefix(2)),
                hasMoreExercises: block.exercises.count > 2
            )
        }
    }

    private static func exerciseSummary(
        for item: WorkoutItem,
        in context: TodayContext
    ) -> ExerciseSummary {
        let parser = PrescriptionParser()
        let exercise = context.exercises[item.exerciseID]
        let prescriptionLine: String
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(let prescription):
            prescriptionLine = formatPrescriptionLine(prescription)
        case .failure:
            prescriptionLine = ""
        }
        return ExerciseSummary(
            id: item.id,
            name: exercise?.name ?? "(unknown exercise)",
            prescriptionLine: prescriptionLine,
            lastTime: context.lastPerformed[item.exerciseID]
        )
    }

    private static func blockTitle(_ block: Block) -> String {
        if let name = block.name, !name.isEmpty {
            return name
        }
        return timingLabel(block.timingMode).capitalized
    }

    private static func timingDetail(_ block: Block) -> String? {
        let parser = PrescriptionParser()
        guard case .success(let config) = parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) else {
            return roundsDetail(block.rounds)
        }

        var parts: [String] = []
        if let rounds = block.rounds {
            parts.append("\(rounds) rounds")
        }
        if let roundsRepSchemeJSON = block.roundsRepSchemeJSON,
           !roundsRepSchemeJSON.isEmpty,
           roundsRepSchemeJSON != "[]" {
            parts.append("rep scheme \(roundsRepSchemeJSON)")
        }
        parts.append(contentsOf: timingConfigDetails(config))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func roundsDetail(_ rounds: Int?) -> String? {
        guard let rounds else { return nil }
        return "\(rounds) rounds"
    }

    private static func timingConfigDetails(_ config: TimingConfig) -> [String] {
        switch config {
        case .straightSets(let restBetweenSetsSec, let restBetweenExercisesSec):
            return compactDurationParts([
                ("rest between sets", restBetweenSetsSec),
                ("rest between exercises", restBetweenExercisesSec),
            ])
        case .superset(let restBetweenRoundsSec, _):
            return compactDurationParts([("rest between rounds", restBetweenRoundsSec)])
        case .circuit(let restBetweenExercisesSec, let restBetweenRoundsSec, _):
            return compactDurationParts([
                ("rest between exercises", restBetweenExercisesSec),
                ("rest between rounds", restBetweenRoundsSec),
            ])
        case .emom(let intervalSec, let totalMinutes):
            return ["\(totalMinutes) min total", "every \(formatDuration(seconds: intervalSec))"]
        case .amrap(let timeCapSec):
            return ["cap \(formatDuration(seconds: timeCapSec))"]
        case .forTime(let timeCapSec):
            guard let timeCapSec else { return [] }
            return ["cap \(formatDuration(seconds: timeCapSec))"]
        case .intervals(
            let workSec,
            let restSec,
            let workDistanceM,
            let restDistanceM,
            let intervalCount,
            let targetPaceSecPerKm
        ):
            var parts = ["\(intervalCount) intervals"]
            if let workSec { parts.append("work \(formatDuration(seconds: workSec))") }
            if let restSec { parts.append("rest \(formatDuration(seconds: restSec))") }
            if let workDistanceM { parts.append("work \(distanceLabel(workDistanceM))") }
            if let restDistanceM { parts.append("rest \(distanceLabel(restDistanceM))") }
            if let targetPaceSecPerKm {
                parts.append("pace \(formatDuration(seconds: targetPaceSecPerKm))/km")
            }
            return parts
        case .tabata:
            return ["8 rounds", "20s work / 10s rest"]
        case .continuous(
            let targetDurationSec,
            let targetDistanceM,
            let targetPaceSecPerKm,
            let targetHrZone
        ):
            var parts: [String] = []
            if let targetDurationSec {
                parts.append("duration \(formatDuration(seconds: targetDurationSec))")
            }
            if let targetDistanceM {
                parts.append("distance \(distanceLabel(targetDistanceM))")
            }
            if let targetPaceSecPerKm {
                parts.append("pace \(formatDuration(seconds: targetPaceSecPerKm))/km")
            }
            if let targetHrZone {
                parts.append("zone \(targetHrZone)")
            }
            return parts
        case .accumulate(let targetDurationSec, let targetReps, let targetDistanceM):
            var parts: [String] = []
            if let targetDurationSec {
                parts.append("accumulate \(formatDuration(seconds: targetDurationSec))")
            }
            if let targetReps {
                parts.append("accumulate \(targetReps) reps")
            }
            if let targetDistanceM {
                parts.append("accumulate \(distanceLabel(targetDistanceM))")
            }
            return parts
        case .custom(let segments):
            return ["\(segments.count) segments"]
        case .rest(let durationSec):
            return ["duration \(formatDuration(seconds: durationSec))"]
        }
    }

    private static func compactDurationParts(_ specs: [(String, Double)]) -> [String] {
        specs.compactMap { label, seconds in
            seconds > 0 ? "\(label) \(formatDuration(seconds: seconds))" : nil
        }
    }

    private static func distanceLabel(_ metres: Double) -> String {
        if metres >= 1000 {
            return "\(formatDecimal(metres / 1000)) km"
        }
        return "\(formatDecimal(metres)) m"
    }

    private static func formatDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func adjustmentDraftBody(for detail: WorkoutDetail) -> String {
        var lines: [String] = [
            "Please adjust this planned workout:",
            "",
            "Workout: \(detail.name)",
            "Schedule: \(detail.sectionTitle)",
        ]
        if let tagLine = detail.tagLine {
            lines.append("Tags: \(tagLine)")
        }
        if let notes = detail.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        lines.append("")
        lines.append("Requested change:")
        lines.append("- ")
        lines.append("")
        lines.append("Current plan:")
        for block in detail.blocks {
            lines.append("- \(block.title) (\(block.timingLabel))")
            if let timingDetail = block.timingDetail {
                lines.append("  Timing: \(timingDetail)")
            }
            if let notes = block.notes, !notes.isEmpty {
                lines.append("  Notes: \(notes)")
            }
            for exercise in block.exercises {
                let prescription = exercise.prescriptionLine.isEmpty
                    ? ""
                    : " — \(exercise.prescriptionLine)"
                lines.append("  - \(exercise.name)\(prescription)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func badge(for kind: PlanSectionKind, isSelected: Bool) -> String? {
        if isSelected { return "ready" }
        switch kind {
        case .missed: return "needs reschedule"
        case .today, .upcoming, .unscheduled: return nil
        }
    }
}

private extension Array where Element == String {
    func removingAdjacentDuplicates() -> [String] {
        reduce(into: []) { result, value in
            if result.last != value {
                result.append(value)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
