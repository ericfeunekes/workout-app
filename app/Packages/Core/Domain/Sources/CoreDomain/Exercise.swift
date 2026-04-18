// Exercise.swift
//
// See docs/specs/v2-architecture.md § "Data model · exercise".

import Foundation
import WorkoutCoreFoundation

/// An atomic movement. Minimal metadata — the app does not reason about
/// exercises, just displays them. Muscle groups / movement patterns are not
/// modeled here; Claude owns that taxonomy in conversation.
///
/// `demoURL` is upgraded from the wire `demo_url: String?` to a proper `URL?`
/// at the Domain layer. The DTO layer in `schema/` keeps it as `String?`; the
/// Sync mapper is responsible for parsing and logging rows with malformed
/// URLs.
public struct Exercise: Sendable, Hashable {
    public var id: ExerciseID
    public var name: String
    public var notes: String?
    public var demoURL: URL?
    /// Library-level prescription defaults merged into every workout_item
    /// referencing this exercise (unless the item overrides). Round-tripped
    /// through Domain/Persistence but not used at runtime — the merge is
    /// server-side. See `docs/decisions/ADR-2026-04-18-smart-defaults.md`.
    public var defaultPrescriptionJSON: String?
    /// Library-level alternatives array (`[{exercise_id, reason,
    /// parameter_overrides_json}]`). Same runtime story as
    /// `defaultPrescriptionJSON`.
    public var defaultAlternativesJSON: String?

    public init(
        id: ExerciseID,
        name: String,
        notes: String? = nil,
        demoURL: URL? = nil,
        defaultPrescriptionJSON: String? = nil,
        defaultAlternativesJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.demoURL = demoURL
        self.defaultPrescriptionJSON = defaultPrescriptionJSON
        self.defaultAlternativesJSON = defaultAlternativesJSON
    }
}
