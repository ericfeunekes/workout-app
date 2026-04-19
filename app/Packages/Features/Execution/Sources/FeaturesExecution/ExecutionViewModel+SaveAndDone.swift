// ExecutionViewModel+SaveAndDone.swift
//
// Houses the public `saveAndDone` entry point and its re-entrancy guard,
// split out of `ExecutionViewModel.swift` so the class body stays under
// SwiftLint's `type_body_length` cap AND so this guard lands adjacent to
// the function it protects. The actual work (enqueue status update,
// write local cache, enqueue bodyweight, dispatch `.save`) still lives
// in `performSaveAndDone` on the `+Push.swift` extension — this file is
// strictly the guard layer.
//
// Bug fix: a fast double-tap on the "save & done" button (or a SwiftUI
// re-render that fires the tap action twice before the reducer's `.save`
// collapses the Complete screen) previously invoked `saveAndDone` twice,
// which enqueued two terminal `status_update` pushes AND two bodyweight
// `UserParameter` rows. With `UserParameters` being append-only on the
// server, the duplicate bodyweight would live forever. The guard drops
// the second (and any further) invocation once the first has fired.
//
// Why an `@MainActor` module-level `NSMapTable` instead of a stored
// property on the class: the view model's stored properties live in the
// main class body in `ExecutionViewModel.swift`, and a parallel subagent
// is currently editing adjacent extensions there. Keeping the flag
// module-local avoids a merge collision while still giving SwiftUI a
// `@MainActor`-reachable check for `.disabled()` bindings. `NSMapTable`
// with weak keys auto-evicts entries when the view model deallocates,
// so `ObjectIdentifier` reuse (a new VM reusing the memory address of a
// just-deallocated one) cannot leak a stale `true` across instances.

import Foundation

/// Sentinel value parked in the in-flight table. The table maps weakly
/// from a view model to this marker; presence of the mapping ⇒ the
/// flag is set. We use a reference type rather than `Bool` because
/// `NSMapTable<AnyObject, NSNumber>` would erase type information and
/// the sentinel pattern reads more explicitly at the call site.
private final class SaveAndDoneMarker {}

/// `@MainActor`-isolated table of in-flight guards. Keys are weakly
/// retained view models so a deallocated VM's entry is evicted
/// automatically; that's what keeps the guard from leaking across VM
/// instances when `ObjectIdentifier` recycles memory addresses.
@MainActor
private let saveAndDoneInFlightTable: NSMapTable<AnyObject, SaveAndDoneMarker> =
    NSMapTable.weakToStrongObjects()

extension ExecutionViewModel {

    /// Whether a `saveAndDone` call is currently mid-flight for this view
    /// model. Views can bind `.disabled(viewModel.saveAndDoneInFlight)`
    /// on the save & done button so the user can't get a second tap in
    /// during the brief window before the reducer's `.save` flips the
    /// route back to `.today` and unmounts the Complete screen.
    ///
    /// This is a plain computed property (not an `@Observable` stored
    /// field) because the stored field would have to live on the main
    /// class body and the double-tap race happens entirely inside a
    /// single @MainActor synchronous run-loop turn — there is no async
    /// boundary for SwiftUI to observe across. The `.disabled()` binding
    /// is belt-and-suspenders defense; the guard in `saveAndDone` is
    /// the correctness-critical check.
    public var saveAndDoneInFlight: Bool {
        saveAndDoneInFlightTable.object(forKey: self) != nil
    }

    /// Save & done. Clears the persisted session and returns to Today.
    ///
    /// Before the reducer's `.save` wipes the in-memory log, we hand the
    /// completed workout + set_logs to `localCompletionWriter` (if wired).
    /// That writes them into the local `WorkoutCache` so the History tab
    /// sees the workout immediately — the push queue is the authoritative
    /// server-side path, but the user shouldn't have to wait for a pull
    /// to see their own just-completed workout. See
    /// `docs/open-questions.md` § "Execution `save & done` doesn't persist
    /// the completed workout to local cache".
    ///
    /// Capture inputs from the Complete screen (bug-011 / bug-012):
    ///   - `note`: workout-level note. Trimmed + empty-collapsed; when
    ///     present it replaces the in-memory state's `note` and lands on
    ///     the completed `Workout.notes` in the local cache.
    ///   - `bodyweightKg`: optional body weight captured at completion.
    ///     When present, a fresh `UserParameter` is fired through the
    ///     `onUserParameterChanged` push hook (the push queue routes it
    ///     to `POST /api/user-parameters`). Nil means no capture, no
    ///     enqueue.
    ///
    /// Re-entrancy: the first call sets `saveAndDoneInFlight = true` and
    /// runs the full committed path; a concurrent second call (double-
    /// tap, SwiftUI re-render firing the tap action twice) sees the flag
    /// already set and returns silently. The flag is NOT cleared on the
    /// happy path — by the time `performSaveAndDone` returns, the reducer
    /// has flipped the route to `.today` and the Complete screen is
    /// unmounted, so the view model is effectively single-use for the
    /// rest of this session. The flag IS cleared for the same
    /// `ObjectIdentifier` when the view model is deinit'd, via the
    /// `Self.releaseSaveAndDoneGuard` helper the test suite can call if
    /// it re-uses an ObjectIdentifier.
    ///
    /// Defaulted parameters preserve the existing call-sites in tests
    /// that predate the capture inputs.
    public func saveAndDone(
        note: String? = nil,
        bodyweightKg: Double? = nil
    ) {
        if saveAndDoneInFlightTable.object(forKey: self) != nil {
            return
        }
        saveAndDoneInFlightTable.setObject(SaveAndDoneMarker(), forKey: self)
        performSaveAndDone(note: note, bodyweightKg: bodyweightKg)
    }

    /// Test hook: drop the in-flight entry for this view model so a test
    /// that re-uses the same VM instance across scenarios can reset the
    /// guard. Production never calls this — the VM is unmounted after
    /// `saveAndDone` by the route flip to `.today`. Kept `internal` so
    /// the test target (`@testable import FeaturesExecution`) reaches
    /// it; invisible to shell callers.
    func releaseSaveAndDoneGuardForTests() {
        saveAndDoneInFlightTable.removeObject(forKey: self)
    }
}
