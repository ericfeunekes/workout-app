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
// Lifetime model: the guard is a stored `Bool` on the VM
// (`saveAndDoneInFlightStorage`), owned by the main class body in
// `ExecutionViewModel.swift`. Each workout gets a FRESH VM — the shell
// rebuilds one in the post-save completion writer via
// `AppBootstrap.buildExecutionViewModel(for:...)`. A per-instance stored
// flag is therefore naturally reset between workouts.
//
// A previous version of this file kept the flag in a process-global
// `NSMapTable` keyed weakly on the VM, on the assumption that the VM
// died after save. That assumption was false — the shell retained the
// same VM for the entire `.ready` phase — and the resulting dangling
// map was the source of the `NSMapGet: map table argument is NULL`
// crash captured in the QA-01 recording. The rebuild-per-workout
// change makes the side table unnecessary (fresh VM ⇒ fresh flag).

import Foundation

extension ExecutionViewModel {

    /// Whether a `saveAndDone` call is currently mid-flight for this view
    /// model. Views can bind `.disabled(viewModel.saveAndDoneInFlight)`
    /// on the save & done button so the user can't get a second tap in
    /// during the brief window before the reducer's `.save` flips the
    /// route back to `.today` and unmounts the Complete screen.
    ///
    /// Computed over the stored `saveAndDoneInFlightStorage` so the
    /// `@Observable` macro tracks changes through this accessor — SwiftUI
    /// picks up the `.disabled(...)` flip automatically when the guard
    /// flips it.
    public var saveAndDoneInFlight: Bool {
        saveAndDoneInFlightStorage
    }

    /// Save & done. Clears the persisted session and returns to Today.
    ///
    /// Before the reducer's `.save` wipes the in-memory log, we hand the
    /// completed workout + set_logs to `localCompletionWriter` (if wired).
    /// That writes them into the local `WorkoutCache` so the History tab
    /// sees them immediately — the push queue is the authoritative
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
    /// Re-entrancy: the first call flips `saveAndDoneInFlightStorage`
    /// `true` and runs the full committed path; a concurrent second call
    /// (double-tap, SwiftUI re-render firing the tap action twice) sees
    /// the flag already set and returns silently. The flag is NOT cleared
    /// on the happy path — by the time `performSaveAndDone` returns, the
    /// reducer has flipped the route to `.today` and the Complete screen
    /// is unmounted. For the next workout the shell constructs a FRESH
    /// VM (see `AppBootstrap.buildExecutionViewModel(for:)`) so the flag
    /// starts `false` there.
    ///
    /// Defaulted parameters preserve the existing call-sites in tests
    /// that predate the capture inputs.
    public func saveAndDone(
        note: String? = nil,
        bodyweightKg: Double? = nil
    ) {
        if saveAndDoneInFlightStorage {
            return
        }
        saveAndDoneInFlightStorage = true
        performSaveAndDone(note: note, bodyweightKg: bodyweightKg)
    }

    /// Test hook: drop the in-flight flag so a test that re-uses the
    /// same VM instance across scenarios can reset the guard. Production
    /// never calls this — each workout's VM is single-use and the shell
    /// builds a fresh one for the next workout. Kept `internal` so the
    /// test target (`@testable import FeaturesExecution`) reaches it;
    /// invisible to shell callers.
    func releaseSaveAndDoneGuardForTests() {
        saveAndDoneInFlightStorage = false
    }
}
