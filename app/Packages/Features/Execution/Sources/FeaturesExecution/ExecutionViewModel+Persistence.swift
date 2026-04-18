// ExecutionViewModel+Persistence.swift
//
// Persistence helpers and the private `apply` / `findItem` plumbing, split
// out of `ExecutionViewModel.swift` so the class body stays under
// SwiftLint's `type_body_length` cap. The methods remain module-internal.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession

extension ExecutionViewModel {

    /// Restore state from the session store, if any. Called by the
    /// app shell on launch. A missing/garbled payload silently returns
    /// the seeded state — offline-first + never-crash posture.
    public func restoreIfPossible() async {
        guard let store = sessionStore else { return }
        do {
            guard let data = try await store.load() else { return }
            if let restored = try? JSONDecoder().decode(SessionStateCodable.self, from: data) {
                self.state = restored.state
            }
        } catch {
            // Silent — a failed load means "no saved state", not "crash".
        }
    }

    func apply(_ mutations: [SessionMutation]) {
        var next = state
        for m in mutations {
            next = SessionReducer.reduce(next, m)
        }
        state = next
        persist()
    }

    func persist() {
        guard let store = sessionStore else { return }
        let snapshot = SessionStateCodable(state: state)
        // Fire-and-forget session persistence. The in-memory state is
        // authoritative for this session; async completion does not gate
        // any UI update, so there is no async parent to await from.
        // swiftlint:disable:next no_direct_task_unstructured
        Task { [snapshot, store] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                try await store.save(data)
            } catch {
                // Persistence failure is not user-fatal — the in-memory
                // state is authoritative for this session. A next tick
                // will retry.
            }
        }
    }

    func findItem(id: UUID, in context: WorkoutContext) -> WorkoutItem? {
        for row in context.itemsByBlock {
            if let hit = row.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    /// If the cursor now sits on a zero-item block (standalone `rest`),
    /// dispatch `.enterRest` with the driver's rest duration so the view
    /// goes to `.rest` instead of the (defensive empty) `.active`. No-op
    /// for work blocks. Called after `start()` and `advance()` — see
    /// `RestBlockDriver` for the cursor-model rationale. Lives here rather
    /// than on the main class so the class body stays under
    /// SwiftLint's `type_body_length` cap.
    func enterRestIfZeroItemBlock() {
        let b = state.cursor.blockIndex
        guard b < state.structure.itemsPerBlock.count,
              state.structure.itemsPerBlock[b] == 0 else {
            return
        }
        let duration = driver.restDuration(state: state, context: context)
        apply([.enterRest(durationSec: duration, now: clock.now)])
    }

    /// When entering a time-capped block (AMRAP / ForTime / EMOM / Tabata),
    /// set `blockEndsAt` on the session state so the VM can auto-route to
    /// `.complete` on expiry. Called on every cursor transition where the
    /// block may have changed — `start()`, `advance()`, and the post-log
    /// auto-advance path. No-op when `blockEndsAt` is already set for the
    /// current block (re-entering the same block mid-session during resume)
    /// or when the block isn't time-capped.
    ///
    /// For Tabata, also sets `workEndsAt = now + 20` at entry into each
    /// round's work window (the active phase). The 10s rest window is
    /// handled via the existing `.enterRest` path in `buildLogMutations`.
    func enterBlockTimerIfNeeded() {
        let b = state.cursor.blockIndex
        guard b < state.structure.itemsPerBlock.count else { return }
        guard let block = context.block(at: b) else { return }
        // Skip zero-item blocks entirely — rest blocks handle themselves.
        if state.structure.itemsPerBlock[b] == 0 { return }

        let now = clock.now

        // Tabata: per-round 20s work window. Set on every block entry;
        // when the VM's round advances (round-robin cursor bumps
        // `setIndex`), the VM re-enters .active and calls this helper
        // again — so work windows refresh per round. Also set the total
        // block cap (8 × 30s = 240s) so it terminates on time even if
        // the user never logs (defensive).
        if block.timingMode == .tabata {
            if state.workEndsAt == nil {
                state.workEndsAt = now.addingTimeInterval(TabataDriver.workSec)
            }
            if state.blockEndsAt == nil {
                let total = Double(TabataDriver.rounds)
                    * (TabataDriver.workSec + TabataDriver.restSec)
                state.blockEndsAt = now.addingTimeInterval(total)
            }
            persist()
            return
        }

        // AMRAP / ForTime / EMOM: parse the time cap from the block's
        // timing config. The cap is a property of the block — once set
        // it stays set until advanceFromRest clears it (which it does on
        // block change in the reducer).
        if state.blockEndsAt == nil,
           let cap = timeCapSeconds(for: block) {
            state.blockEndsAt = now.addingTimeInterval(cap)
            persist()
        }
    }

    /// On entering `.active` inside a Tabata block (new round), refresh
    /// `workEndsAt = now + 20s`. `enterBlockTimerIfNeeded` only sets
    /// when the field is nil (block entry), so per-round refresh needs
    /// its own helper. No-op outside Tabata or when route isn't active.
    func enterTabataWorkWindowIfNeeded() {
        guard state.route == .active else { return }
        let b = state.cursor.blockIndex
        guard let block = context.block(at: b),
              block.timingMode == .tabata else { return }
        state.workEndsAt = clock.now.addingTimeInterval(TabataDriver.workSec)
        persist()
    }

    /// Called from the ActiveView + RestView `.onReceive(tickTimer)` every
    /// second (bug-042). Checks `blockEndsAt` and `workEndsAt` against
    /// `clock.now`. If the block cap elapsed, dispatches `.complete`. If
    /// the Tabata work window elapsed, auto-logs a placeholder 0-rep set
    /// and enters the 10s rest.
    ///
    /// Safe to call at any tempo — no-ops when nothing is due. The view-
    /// side guard on `state.blockEndsAt != nil` is an optimization (don't
    /// wake the VM on non-time-capped blocks) but not a correctness
    /// requirement; this method is idempotent and cheap.
    public func tickBlockTimer() {
        tickCallCount &+= 1
        let now = clock.now
        // Block cap expired → route to complete.
        if let ends = state.blockEndsAt, now >= ends,
           state.route != .complete, state.route != .today {
            apply([.complete])
            return
        }
        // Tabata work window expired → log placeholder + enter rest.
        if let workEnds = state.workEndsAt, now >= workEnds, state.route == .active {
            autoLogAndRestForTabata()
        }
    }

    /// Helper invoked from `tickBlockTimer` when the Tabata work window
    /// elapses. v1 logs a placeholder `(reps: 0, rir: nil)` — a later
    /// slice can prompt the user for a real per-round count.
    private func autoLogAndRestForTabata() {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return
        }
        apply([
            .logSet(itemID: item.id, setIndex: c.setIndex, loggedReps: 0, loggedRir: nil),
            .enterRest(durationSec: TabataDriver.restSec, now: clock.now),
        ])
    }

    /// Pull the authored `time_cap_sec` (or EMOM `total_minutes * 60`)
    /// from a block's `timing_config_json`. Returns nil when the block
    /// isn't time-capped or parsing fails.
    private func timeCapSeconds(for block: Block) -> TimeInterval? {
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            switch config {
            case .amrap(let cap):
                return cap
            case .forTime(let cap):
                return cap
            case .emom(let intervalSec, let totalMinutes):
                _ = intervalSec  // not used here — cap is total, not interval
                return Double(totalMinutes) * 60
            default:
                return nil
            }
        case .failure:
            return nil
        }
    }

    /// Compose the ordered mutation list for a set-log event. Kept separate
    /// so `logSet` stays under SwiftLint's `function_body_length` cap.
    func buildLogMutations(
        logMutation: SessionMutation,
        outcome: DriverLogOutcome,
        item: WorkoutItem,
        postLogState: SessionState
    ) -> [SessionMutation] {
        var mutations: [SessionMutation] = [logMutation]
        // Accept-by-default: if the driver surfaced a proposal, apply
        // it immediately. User can Undo from the banner.
        if let proposal = outcome.proposal {
            mutations.append(.applyAutoregProposal(itemID: item.id, proposal: proposal))
        }
        let restSec = driver.restDuration(state: postLogState, context: context)
        if restSec > 0 {
            mutations.append(.enterRest(durationSec: restSec, now: clock.now))
        } else {
            // No rest configured — advance straight to the next active
            // position. Edge case for straight_sets (rests are authored).
            mutations.append(.advanceFromRest)
        }
        mutations.append(contentsOf: outcome.mutations)
        return mutations
    }
}
