// ParseError.swift
//
// Structured errors for the prescription and timing-config parsers. The
// parsers never throw — they return `Result<_, ParseError>`. Callers (the
// session state machine, the execution UI) decide how to surface or recover.
//
// Keep the cases specific enough that failure messages in the log actually
// point at what's wrong with the authored payload. "missingKey(...)" plus the
// shape hint tells us which Claude-authored JSON blob is missing which key.

import Foundation

public enum ParseError: Error, Equatable, Sendable {
    /// The payload was not valid JSON, or the top level was not a JSON object.
    case invalidJSON(String)

    /// A required key was missing. `inShape` is the name of the shape or
    /// timing mode the parser was attempting to build (e.g. "straightSets",
    /// "intervals", "autoreg").
    case missingKey(String, inShape: String)

    /// A key was present but had the wrong JSON type. `expected` is a short
    /// human-readable type name ("int", "double", "string", "bool", "array",
    /// "object").
    case wrongType(key: String, expected: String)

    /// Timing-config parsing got a `timingMode` string that isn't in the
    /// known TimingMode enum.
    case unknownTimingMode(String)

    /// Prescription-shape discrimination could not find a match. `hint`
    /// names the keys that were present so we can see what Claude authored.
    case unknownShape(hint: String)
}
