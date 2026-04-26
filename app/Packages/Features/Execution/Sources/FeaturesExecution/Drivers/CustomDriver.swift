// CustomDriver.swift
//
// TimingDriver for `timing_mode = custom` — the catch-all for mixed-
// segment sessions that don't fit another mode (docs/prescription.md
// § "custom"). The block's `timing_config_json` carries a free-form
// `segments` array; items carry whatever prescription the author needs
// at that segment. The app does not impose a state machine — each item
// renders what its prescription describes and the user logs when done.
//
// Scope of this driver (v1, simplified):
//   - `activeContent` resolves the current item's exercise name, reps
//     and load from its prescription. `setIndex` is the cursor's 1-based
//     set counter (matches the seeded SetPlan rows); `totalSets` is the
//     parsed `sets` for the item (or 1 if omitted / not sets-shaped).
//   - `restDuration` returns 0. Custom blocks do not enforce between-set
//     rest — any timing the author wants lives in the segment descriptor
//     (consumed by the VM/segment-walker, not this driver).
//   - `onSetLogged` returns an empty outcome. No autoreg by default
//     (spec: "Usually no — if a segment is a load-based strength piece,
//     add `autoreg` to that item"). v1 leaves autoreg off uniformly;
//     adding per-item autoreg reuses the StraightSets path and lands in
//     a later slice.
//
// Spec latitude note:
//   docs/prescription.md § "custom" is intentionally loose: items can be
//   empty, sets-shaped, or bodyweight, and segments can be work or rest.
//   v1 treats the driver as a thin renderer — the reducer seeds SetPlan
//   rows per the item prescription, and the user ticks through them
//   without app-imposed cadence.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct CustomDriver: TimingDriver {

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    public func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }) else {
            return nil
        }
        // Don't fabricate a "1 of 1" display when there are no SetPlan
        // rows underneath — the user's logSet dispatch would find no
        // matching row and the log would vanish. The seeder normally
        // produces a 1-row placeholder for `.empty` / `.amrapToken`
        // (see SessionSeeder.manualPlaceholder); this guard keeps the
        // driver honest if state is ever handed to it inconsistently
        // (e.g. legacy persisted state seeded before the fix).
        guard !itemLog.sets.isEmpty else {
            return nil
        }

        if let segmentContent = timedSegmentContent(
            state: state,
            context: context,
            item: item,
            itemLog: itemLog
        ) {
            return segmentContent
        }

        let resolved = resolveActive(item: item, itemLog: itemLog, cursor: c)
        return ActiveContent(
            exerciseName: context.exerciseName(
                for: item,
                performedExerciseID: itemLog.performedExerciseID
            ),
            setIndex: c.setIndex,
            totalSets: resolved.totalSets,
            loadDisplay: resolved.loadDisplay,
            repsDisplay: resolved.repsDisplay,
            loadKg: resolved.heroLoadKg,
            reps: resolved.reps,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID],
            kind: resolved.kind
        )
    }

    private func timedSegmentContent(
        state: SessionState,
        context: WorkoutContext,
        item: WorkoutItem,
        itemLog: SessionState.ItemLog
    ) -> ActiveContent? {
        let cursor = state.cursor
        guard let segment = customSegment(state: state, context: context),
              isEmptyPrescription(item),
              isLoadlessPlaceholder(itemLog: itemLog, setIndex: cursor.setIndex) else {
            return nil
        }
        let exerciseName = context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )
        return ActiveContent(
            exerciseName: exerciseName,
            setIndex: cursor.setIndex,
            totalSets: customSegmentCount(state: state, context: context),
            loadDisplay: segmentSecondary(segment),
            repsDisplay: formatSegmentDuration(segment.durationSec),
            loadKg: nil,
            reps: 0,
            adjustGlyph: nil,
            lastTime: context.lastPerformed[item.exerciseID],
            kind: .cardio
        )
    }

    /// Bundle of renderable numeric state at the cursor — everything the
    /// view-level `ActiveContent` needs that is NOT the exercise name or
    /// cursor-derived (setIndex, lastTime).
    private struct ResolvedActive {
        let totalSets: Int
        let loadDisplay: String
        let heroLoadKg: Double?
        let repsDisplay: String
        let reps: Int
        let kind: ActiveContent.Kind
    }

    /// Resolve the renderable numeric state at the cursor. Prefer the live
    /// SetPlan row — the reducer mirrors swap `reps` / `load_kg` /
    /// `weight_unit` overrides onto non-done rows so reading the SetPlan
    /// reflects post-swap state. The prescription parse drives `totalSets`
    /// only; the loadless-ness of a row is carried on the SetPlan itself
    /// (`loadKg == nil`), no separate discriminator needed.
    private func resolveActive(
        item: WorkoutItem,
        itemLog: SessionState.ItemLog,
        cursor: SessionState.Cursor
    ) -> ResolvedActive {
        let parsed = parser.parse(prescriptionJSON: item.prescriptionJSON)
        let totalSets = totalSets(parsed: parsed, itemLog: itemLog)
        let activeSet = itemLog.sets.first(where: { $0.setIndex == cursor.setIndex })
        let (reps, loadKg, unit) = resolveRepsAndLoad(
            for: item,
            parsed: parsed,
            itemLog: itemLog,
            cursor: cursor
        )
        let loadDisplay: String
        let heroLoadKg: Double?
        if let kg = loadKg {
            loadDisplay = formatLoad(weight: kg, unit: LoadUnit(setPlanUnit: unit))
            heroLoadKg = kg
        } else {
            loadDisplay = "BW"
            heroLoadKg = nil
        }
        return ResolvedActive(
            totalSets: totalSets,
            loadDisplay: loadDisplay,
            heroLoadKg: heroLoadKg,
            repsDisplay: activeSet.map(displayText(for:)) ?? String(reps),
            reps: reps,
            kind: activeSet.map(activeKind(for:)) ?? .strength
        )
    }

    // MARK: - Rest duration

    /// Custom does not enforce rest between sets — segments do, and
    /// those are the VM's concern. Returning 0 lets the auto-advance
    /// path collapse the rest straight to the next set / segment.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        0
    }

    // MARK: - Log outcome

    /// No autoreg on custom by default (per spec). The driver never
    /// proposes a change.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }

    // MARK: - Helpers

    /// Resolve `(reps, loadKg, unit)` at the cursor. The SetPlan row is
    /// the source of truth for live numeric values (reps / loadKg / unit)
    /// — the reducer mirrors swap overrides onto non-done rows so reading
    /// the SetPlan reflects the post-swap plan. `set.loadKg == nil` is
    /// the loadless sentinel (BW, loadless AMRAP token, `.empty`) — it
    /// passes straight through so the display renders "BW".
    private func resolveRepsAndLoad(
        for item: WorkoutItem,
        parsed: Result<Prescription, ParseError>,
        itemLog: SessionState.ItemLog,
        cursor: SessionState.Cursor
    ) -> (reps: Int, loadKg: Double?, unit: WeightUnit) {
        if let set = itemLog.sets.first(where: { $0.setIndex == cursor.setIndex }) {
            return (set.reps, set.loadKg, set.unit)
        }
        // Fallback when no SetPlan row matches the cursor (defensive).
        switch parsed {
        case .success(let p):
            return repsAndLoadFromPrescription(p)
        case .failure:
            return (0, nil, .lb)
        }
    }

    /// Extract reps, load, and unit from a prescription for the fallback
    /// path. Normal reads go through `resolveRepsAndLoad`.
    private func repsAndLoadFromPrescription(
        _ prescription: Prescription
    ) -> (reps: Int, loadKg: Double?, unit: WeightUnit) {
        switch prescription {
        case .straightSets(_, let reps, let loadKg, let unit, _, _, _, _):
            return (intReps(from: reps), loadKg, unit)
        case .bodyweight(_, let reps, _):
            return (reps, nil, .lb)
        case .repRange(_, _, let repsMax, let loadKg, let unit, _, _):
            return (repsMax, loadKg, unit)
        case .cluster(_, let reps, let loadKg, let unit, _, _, _, _):
            return (reps, loadKg, unit)
        case .warmup(_, let reps, let loadKg, let unit):
            return (reps, loadKg, unit)
        case .setsDetail:
            return (0, nil, .lb)
        case .percentOf1RM(_, let reps, _, _):
            return (reps, nil, .lb)
        case .amrapToken(let loadKg, let unit, _):
            // AMRAP token renders "reps = 0" (open entry) with the
            // authored load if present.
            return (0, loadKg, unit)
        case .empty:
            return (0, nil, .lb)
        }
    }

    /// Total sets for the item. Drives the "N of M" counter on the Active
    /// screen; falls back to the seeded row count when the prescription
    /// carries no structural set count (`.amrapToken`, `.empty`).
    private func totalSets(
        parsed: Result<Prescription, ParseError>,
        itemLog: SessionState.ItemLog
    ) -> Int {
        let fallbackTotal = max(itemLog.sets.count, 1)
        switch parsed {
        case .success(let p):
            switch p {
            case .straightSets(let sets, _, _, _, _, _, _, _):
                return sets ?? fallbackTotal
            case .bodyweight(let sets, _, _):
                return sets
            case .repRange(let sets, _, _, _, _, _, _):
                return sets
            case .cluster(let sets, _, _, _, _, _, _, _):
                return sets
            case .warmup(let sets, _, _, _):
                return sets
            case .setsDetail(let details, _, _, _):
                return max(details.count, 1)
            case .percentOf1RM(let sets, _, _, _):
                return sets
            case .amrapToken, .empty:
                return fallbackTotal
            }
        case .failure:
            return fallbackTotal
        }
    }

    private func intReps(from rc: RepCount?) -> Int {
        guard let rc else { return 0 }
        if case .count(let n) = rc { return n }
        return 0
    }

    private func customSegment(
        state: SessionState,
        context: WorkoutContext
    ) -> CustomSegment? {
        let cursor = state.cursor
        guard let block = context.block(at: cursor.blockIndex) else { return nil }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(.custom(let segments)):
            let index = cursor.setIndex - 1
            guard index >= 0, index < segments.count else { return nil }
            return segments[index]
        case .success, .failure:
            return nil
        }
    }

    private func customSegmentCount(
        state: SessionState,
        context: WorkoutContext
    ) -> Int {
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return 1
        }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(.custom(let segments)):
            return max(segments.count, 1)
        case .success, .failure:
            return 1
        }
    }

    private func isLoadlessPlaceholder(
        itemLog: SessionState.ItemLog,
        setIndex: Int
    ) -> Bool {
        guard let set = itemLog.sets.first(where: { $0.setIndex == setIndex }) else {
            return false
        }
        return set.reps == 0 && set.loadKg == nil
    }

    private func isEmptyPrescription(_ item: WorkoutItem) -> Bool {
        switch parser.parse(prescriptionJSON: item.prescriptionJSON) {
        case .success(.empty):
            return true
        case .success, .failure:
            return false
        }
    }

    private func segmentSecondary(_ segment: CustomSegment) -> String {
        let type = segment.type == .rest ? "REST" : "WORK"
        if let label = segment.label, !label.isEmpty {
            return "\(type) · \(label)"
        }
        if let zone = segment.targetHrZone {
            return "\(type) · Z\(zone)"
        }
        return type
    }

    private func formatSegmentDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds.rounded())) s"
        }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
