// UnitsPreference.swift
//
// How the app renders weights. The server is always kg (invariant: server
// is kg; local display can switch to lb). `UnitsPreference` is a purely
// local preference — changing it does not rewrite any stored data.

import Foundation

/// What the user wants to see on screen.
public enum UnitsPreference: String, CaseIterable, Sendable {
    case kg
    case lb

    /// Human label shown on the picker and in the info row's value cell.
    public var label: String {
        switch self {
        case .kg: return "kg"
        case .lb: return "lb"
        }
    }
}

/// Keys the app uses to remember the units preference.
public enum UnitsPreferenceKeys {
    public static let units = "workoutdb.device.units"
}

/// Reads + writes the units preference.
public protocol UnitsPreferenceStore: Sendable {
    func load() -> UnitsPreference
    func save(_ units: UnitsPreference)
}

/// UserDefaults-backed implementation.
public struct UserDefaultsUnitsStore: UnitsPreferenceStore {
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> UnitsPreference {
        let raw = defaults.string(forKey: UnitsPreferenceKeys.units) ?? ""
        return UnitsPreference(rawValue: raw) ?? .kg
    }

    public func save(_ units: UnitsPreference) {
        defaults.set(units.rawValue, forKey: UnitsPreferenceKeys.units)
    }
}
