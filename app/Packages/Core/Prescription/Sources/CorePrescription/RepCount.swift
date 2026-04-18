// RepCount.swift
//
// A rep count field is either an integer ("do 10") or the string token
// "amrap" ("do as many as possible"). Per docs/prescription.md § "AMRAP
// token", the literal string `"amrap"` is the only valid non-numeric value.
//
// Modeled as a small enum so the execution UI switches on it directly
// instead of sniffing `String` vs `Int` at runtime.

import Foundation

public enum RepCount: Equatable, Sendable, Hashable {
    case count(Int)
    case amrap
}
