// AutoregDefaults.swift
//
// Per-user defaults the app holds for autoreg. These are informational today
// — the app's autoreg reducer reads values off the prescription itself, not
// off local defaults — but Eric wants a place to see and reset them so a
// future Claude-side handshake has something to read.
//
// Per `docs/open-questions.md` § "Autoreg defaults", this surface is
// deliberately minimal: show the numbers, offer "reset to defaults", no
// wiring beyond UserDefaults storage.
//
// Units on the step fields are kilograms (per invariant: server is kg;
// local display can switch to lb but the stored value stays kg).

import Foundation

/// Keys the app uses to remember autoreg defaults. Exposed so tests can
/// reach them without replicating strings.
public enum AutoregDefaultsKeys {
    public static let targetRIR = "workoutdb.autoreg.target_rir"
    public static let overshootStepKg = "workoutdb.autoreg.overshoot_step_kg"
    public static let undershootStepKg = "workoutdb.autoreg.undershoot_step_kg"
}

/// The default values shipped with the app. Matches the defaults baked into
/// the prescription shapes Claude uses today.
public enum AutoregDefaultsFactory {
    public static let targetRIR: Double = 2
    public static let overshootStepKg: Double = 2.5
    public static let undershootStepKg: Double = 2.5
}

/// Value snapshot — what the viewModel reads to build its info rows. The
/// store returns one of these; the viewModel formats them for display.
public struct AutoregDefaults: Equatable, Sendable {
    public let targetRIR: Double
    public let overshootStepKg: Double
    public let undershootStepKg: Double

    public init(
        targetRIR: Double = AutoregDefaultsFactory.targetRIR,
        overshootStepKg: Double = AutoregDefaultsFactory.overshootStepKg,
        undershootStepKg: Double = AutoregDefaultsFactory.undershootStepKg
    ) {
        self.targetRIR = targetRIR
        self.overshootStepKg = overshootStepKg
        self.undershootStepKg = undershootStepKg
    }
}

/// Reads + writes the autoreg defaults triple. The default implementation
/// is UserDefaults-backed; tests inject an in-memory conformer.
public protocol AutoregDefaultsStore: Sendable {
    func load() -> AutoregDefaults
    func resetToDefaults()
}

/// UserDefaults-backed implementation. Stores doubles directly.
public struct UserDefaultsAutoregStore: AutoregDefaultsStore {
    // UserDefaults is documented as thread-safe by Apple but does not carry
    // a Sendable conformance. Mirror TokenStoreImpl's posture — the same
    // single instance is used across every call site.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AutoregDefaults {
        // `double(forKey:)` returns 0 for an unset key. We distinguish
        // "unset" from "explicitly zero" via `object(forKey:)` so a user
        // who resets to defaults ends up with the factory values rather
        // than zeros. (Target RIR 0 is nonsensical for training anyway.)
        let rir = (defaults.object(forKey: AutoregDefaultsKeys.targetRIR) as? Double)
            ?? AutoregDefaultsFactory.targetRIR
        let over = (defaults.object(forKey: AutoregDefaultsKeys.overshootStepKg) as? Double)
            ?? AutoregDefaultsFactory.overshootStepKg
        let under = (defaults.object(forKey: AutoregDefaultsKeys.undershootStepKg) as? Double)
            ?? AutoregDefaultsFactory.undershootStepKg
        return AutoregDefaults(
            targetRIR: rir,
            overshootStepKg: over,
            undershootStepKg: under
        )
    }

    public func resetToDefaults() {
        defaults.removeObject(forKey: AutoregDefaultsKeys.targetRIR)
        defaults.removeObject(forKey: AutoregDefaultsKeys.overshootStepKg)
        defaults.removeObject(forKey: AutoregDefaultsKeys.undershootStepKg)
    }
}
