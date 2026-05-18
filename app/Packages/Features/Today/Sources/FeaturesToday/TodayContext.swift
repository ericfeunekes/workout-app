// TodayContext.swift
//
// Read-only snapshot the Today screen needs to render. Assembled by
// `TodayLoader` from pulled data (Persistence.WorkoutCache) and handed to
// `TodayViewModel`. The view model derives display strings from this
// context — it never reads persistence or prescription JSON directly.
//
// `sessionStateBinding` is the wire the "start workout" button uses to
// flip the session route to `.active`. Optional because previews and
// tests run without a live session store. `@Sendable` + value-type
// mutation keeps this hand-off concurrency-safe.

import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

/// Shape handed to `TodayViewModel` at construction time.
public struct TodayContext: Sendable {
    /// The workout to be executed today. `status == .planned` by design —
    /// the loader filters before handing off.
    public let workout: Workout

    /// Intact primitive authoring shape for this workout, when available.
    public let primitiveWorkout: PrimitiveWorkout?

    /// Runtime plan seeded from `primitiveWorkout` through CoreSession.
    public let primitiveExecutionPlan: ExecutionPlan?

    /// Blocks in position order.
    public let blocks: [Block]

    /// Items in (block, position) order. `blockID` on each item links
    /// back to `blocks`.
    public let items: [WorkoutItem]

    /// Exercise catalog lookup by `exerciseID`. The loader pulls only the
    /// exercises that appear on `items`, so a missing entry is a data
    /// bug — the view model renders "(unknown)" instead of crashing.
    public let exercises: [UUID: Exercise]

    /// Pre-formatted "last time" string per exercise id. The loader
    /// resolves this from historical set_logs (when that data lands);
    /// for now it comes pre-filled from the preview seed.
    public let lastPerformed: [UUID: String]

    /// Pre-formatted "last session" chip value — e.g. "FRI · Push A ·
    /// RIR 1.6 avg". Optional: renders the "no prior session" state
    /// when nil.
    public let lastSessionSummary: String?

    /// Human-readable session tags. Rendered below the program name.
    /// Example: `["week 3", "push day"]` → "week 3 · push day".
    public let programTags: [String]

    /// Latest-per-key numeric user parameters used at seed time.
    public let userParameters: [String: Double]

    /// Dispatch sink for session mutations. Optional so previews /
    /// tests can pass nil. The Today screen only dispatches `.start`.
    public let sessionStateBinding: (@Sendable (SessionMutation) -> Void)?

    public init(
        workout: Workout,
        primitiveWorkout: PrimitiveWorkout? = nil,
        primitiveExecutionPlan: ExecutionPlan? = nil,
        blocks: [Block],
        items: [WorkoutItem],
        exercises: [UUID: Exercise],
        lastPerformed: [UUID: String],
        lastSessionSummary: String? = nil,
        programTags: [String] = [],
        userParameters: [String: Double] = [:],
        sessionStateBinding: (@Sendable (SessionMutation) -> Void)? = nil
    ) {
        self.workout = workout
        self.primitiveWorkout = primitiveWorkout
        self.primitiveExecutionPlan = primitiveExecutionPlan
        self.blocks = blocks
        self.items = items
        self.exercises = exercises
        self.lastPerformed = lastPerformed
        self.lastSessionSummary = lastSessionSummary
        self.programTags = programTags
        self.userParameters = userParameters
        self.sessionStateBinding = sessionStateBinding
    }
}

/// Multi-workout read model for the Today plan queue. The selected context
/// is the default execution target; sibling contexts are still read-only
/// previews, but the shell may rebuild execution for any visible planned
/// workout when the user explicitly starts that card.
public struct TodayPlanContext: Sendable {
    public let selected: TodayContext
    public let workouts: [TodayContext]

    public init(selected: TodayContext, workouts: [TodayContext]) {
        self.selected = selected
        self.workouts = workouts
    }
}
