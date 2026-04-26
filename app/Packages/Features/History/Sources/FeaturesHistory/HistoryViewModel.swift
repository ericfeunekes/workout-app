// HistoryViewModel.swift
//
// Observable view model for the History tab. Owns three derived shapes —
// grouped rows for the list view, exercise summaries for the by-exercise
// picker, and a per-session detail shape — all loaded from
// `Persistence.WorkoutCache`. The view switches between them without
// holding business logic of its own.
//
// Why one VM: the three surfaces share data (same completed workouts,
// same set_logs). Splitting into three VMs would require each to do its
// own load. A single VM with three query methods reads the cache once per
// tab switch and keeps the view layer dumb.
//
// Filters live here (`activeSplit`) so the chip row the view renders is
// purely presentational — tapping a chip dispatches through the VM and
// observers re-read `filteredSessions`.

import Foundation
import CoreDomain
import CoreTelemetry
import Persistence
import WorkoutCoreFoundation

/// Fire-and-forget hook invoked when the user corrects a past set from
/// the History detail view. Shell wires this to `SyncAPI.pushLog([log])`
/// so the edit propagates to the server via the standard set_log push
/// path — same idempotent UUID as the original log, so the server
/// upserts in place. Matches `ExecutionPushHooks.onSetLogged` semantics.
///
/// `nil` (the default) preserves the pure-offline test path — History
/// still writes locally via `WorkoutCache.saveSetLogs` and reloads; the
/// server round-trip is skipped.
public typealias HistorySetLogEditHook = @Sendable (SetLog) async -> Void

/// Fire-and-forget hook invoked when the user resets an accidentally
/// logged workout from History. Shell wires this to `SyncAPI.resetWorkout`
/// so server state matches the local cache before the next pull.
public typealias HistoryWorkoutResetHook = @Sendable (WorkoutID) async -> Void

@Observable
@MainActor
public final class HistoryViewModel {

    // MARK: - Public nested types

    /// One session row in the list view.
    public struct SessionRow: Identifiable, Equatable, Sendable {
        public let id: WorkoutID
        /// Program name as authored ("Push A").
        public let programName: String
        /// Short date: "MON APR 14" / "FRI".
        public let shortDate: String
        /// Formatted duration: "54 MIN". Nil when the workout has no
        /// `completedAt`/`startedAt` pair we can diff.
        public let duration: String?
        /// Average RIR across all sets that logged RIR, rendered to one
        /// decimal: "RIR 1.5". Nil when no set recorded RIR.
        public let avgRIR: String?
        /// Body weight recorded with the completion, if any.
        public let bodyweight: String?
        /// True when the workout has a note or any set has one.
        public let hasNote: Bool
        /// Matched tags — push_day / pull_day / leg_day, lower-case, for
        /// filtering. Empty set → row only appears in ALL.
        public let tags: Set<SplitTag>

        public init(
            id: WorkoutID,
            programName: String,
            shortDate: String,
            duration: String?,
            avgRIR: String?,
            bodyweight: String?,
            hasNote: Bool,
            tags: Set<SplitTag>
        ) {
            self.id = id
            self.programName = programName
            self.shortDate = shortDate
            self.duration = duration
            self.avgRIR = avgRIR
            self.bodyweight = bodyweight
            self.hasNote = hasNote
            self.tags = tags
        }
    }

    /// A week grouping in the list view.
    public struct WeekGroup: Identifiable, Equatable, Sendable {
        public var id: String { header }
        /// ALL CAPS header: "THIS WEEK", "LAST WEEK", "APR · WEEK 15".
        public let header: String
        public let rows: [SessionRow]

        public init(header: String, rows: [SessionRow]) {
            self.header = header
            self.rows = rows
        }
    }

    /// Split chips surfaced above the list.
    public enum SplitFilter: String, Sendable, CaseIterable, Hashable {
        case all, push, pull, legs

        /// User-facing chip label, ALL CAPS.
        public var chipLabel: String {
            switch self {
            case .all: return "ALL"
            case .push: return "PUSH"
            case .pull: return "PULL"
            case .legs: return "LEGS"
            }
        }
    }

    /// Tab-bar pivot inside the History surface.
    public enum Tab: Sendable, Equatable {
        case list
        case byExercise
    }

    /// One row in the exercise picker.
    public struct ExercisePickerRow: Identifiable, Equatable, Sendable {
        public let id: ExerciseID
        public let name: String
        /// Session count summary — "12 SESSIONS".
        public let sessionSummary: String
        /// Top-load summary — "TOP 102.5 KG". Nil when no load recorded.
        public let topLoadSummary: String?
        /// True when the exercise is part of a planned (future/current)
        /// workout; false = "past programs" group.
        public let isInCurrentProgram: Bool

        public init(
            id: ExerciseID,
            name: String,
            sessionSummary: String,
            topLoadSummary: String?,
            isInCurrentProgram: Bool
        ) {
            self.id = id
            self.name = name
            self.sessionSummary = sessionSummary
            self.topLoadSummary = topLoadSummary
            self.isInCurrentProgram = isInCurrentProgram
        }
    }

    // MARK: - Public observable state

    /// Active tab — list vs by-exercise.
    public var tab: Tab = .list

    /// Active split filter. Tapping a chip flips this; the VM re-derives
    /// `filteredSessions` immediately.
    public var activeSplit: SplitFilter = .all

    /// Grouped rows for the list view, filtered by `activeSplit`.
    /// `internal(set)` so sibling extensions can write through
    /// derivation; external consumers are read-only.
    public internal(set) var groups: [WeekGroup] = []

    /// Current-program-first picker rows for the by-exercise view.
    public internal(set) var pickerRows: [ExercisePickerRow] = []

    /// True while `load()` is in flight.
    public internal(set) var isLoading: Bool = false

    // MARK: - Dependencies
    //
    // Declared `internal` (default) rather than `private` so the
    // load + derivation extensions in sibling files can read them.
    // External consumers only see the `public` surface.

    let cache: WorkoutCache
    let calendar: Calendar
    let now: @Sendable () -> Date

    /// Telemetry sink. Default is noop so production callers can omit
    /// wiring until the shell injects a real emitter. `history.*` events
    /// emit from `editPastSet` today; additional surfaces (tab switch,
    /// filter tap) are watchlist.
    let telemetry: TelemetryEmitter

    /// Hook fired after a past-set edit has been written to the local
    /// cache. The shell wires it to `SyncAPI.pushLog([log])` so the edit
    /// flows through the standard set_log push (deterministic UUID →
    /// server upsert-in-place). `nil` means local-only; safe for tests.
    ///
    /// `internal` (default) + `var` so `WorkoutDBApp` can construct the
    /// VM at RootView init (before bootstrap gives us a `SyncAPI`) and
    /// set the hook after AppBootstrap returns. See
    /// `setSetLogEditHook(_:)` below.
    var onSetLogEdited: HistorySetLogEditHook?
    var onWorkoutReset: HistoryWorkoutResetHook?

    /// How many completed workouts to pull for the list view. 200 is
    /// comfortably past the single-user v1 horizon.
    let workoutFetchLimit: Int = 200

    /// Cached raw data — we load once per `load()` and then re-derive on
    /// every filter change.
    var rawSessions: [SessionDetail] = []

    /// Exercise IDs from planned workouts — used by the picker to rank
    /// "current program" exercises above past ones.
    var currentProgramExerciseIDs: Set<ExerciseID> = []

    /// Exercise name lookup. Populated from `cache.loadExercises()`.
    var exerciseName: [ExerciseID: String] = [:]

    public init(
        cache: WorkoutCache,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        telemetry: TelemetryEmitter = NoopTelemetryEmitter(),
        onSetLogEdited: HistorySetLogEditHook? = nil,
        onWorkoutReset: HistoryWorkoutResetHook? = nil
    ) {
        self.cache = cache
        self.calendar = calendar
        self.now = now
        self.telemetry = telemetry
        self.onSetLogEdited = onSetLogEdited
        self.onWorkoutReset = onWorkoutReset
    }

    // MARK: - Intent
    //
    // `load()` and the derivation helpers live in sibling extension
    // files (`HistoryViewModel+Load.swift`,
    // `HistoryViewModel+Derivation.swift`) so the main body stays under
    // SwiftLint's type_body_length cap.

    /// Wire the shell-supplied push hook AFTER init — AppBootstrap
    /// builds the `SyncAPI` instance inside the bootstrap pipeline,
    /// but RootView constructs `HistoryViewModel` at init time so the
    /// VM survives SwiftUI body rebuilds (bug-016 fix, the "hoist to
    /// @State" change). Calling this from the shell's bootstrap
    /// success path is the narrow plumbing needed to close bug-015.
    public func setSetLogEditHook(_ hook: HistorySetLogEditHook?) {
        self.onSetLogEdited = hook
    }

    public func setWorkoutResetHook(_ hook: HistoryWorkoutResetHook?) {
        self.onWorkoutReset = hook
    }

    /// Change the split chip and re-derive groups.
    public func setSplit(_ filter: SplitFilter) {
        guard activeSplit != filter else { return }
        activeSplit = filter
        groups = filteredGroups()
    }

    /// Switch tab. No re-load; derived shapes are kept in sync.
    public func setTab(_ tab: Tab) {
        guard self.tab != tab else { return }
        self.tab = tab
    }

    /// Produce a detail VM for a given session. Returns nil when the
    /// session isn't in the loaded slice.
    public func detail(for id: WorkoutID) -> SessionDetailViewModel? {
        guard let session = rawSessions.first(where: { $0.workout.id == id }) else {
            return nil
        }
        return SessionDetailViewModel(
            session: session,
            exerciseName: exerciseName,
            calendar: calendar
        )
    }

    /// Produce the per-exercise detail VM for a given exercise. The
    /// detail VM loads its own set_logs via the cache on `.task`, so we
    /// only pass the identity and dependencies here.
    public func exerciseDetail(for id: ExerciseID) -> ExerciseDetailViewModel? {
        guard let name = exerciseName[id] else { return nil }
        return ExerciseDetailViewModel(
            exerciseID: id,
            exerciseName: name,
            cache: cache,
            calendar: calendar
        )
    }
}
