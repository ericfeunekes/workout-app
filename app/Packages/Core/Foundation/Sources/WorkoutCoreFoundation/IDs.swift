// IDs.swift
//
// Per-entity ID aliases over `UUID`.
//
// Design call: typealiases, not newtypes. A newtype (`struct WorkoutID`) is
// safer — the compiler stops you from passing a `BlockID` where a `WorkoutID`
// is expected — but it costs a thin wrapper and boilerplate at every call site
// (Codable, Equatable, Hashable, construction from strings, etc.). For a
// single-user app where IDs are read straight out of the server DTOs and fed
// into SwiftData, the extra type-safety is not worth the ergonomic tax. If
// mixing IDs ever becomes a concrete bug class we flip these to newtypes; the
// call sites are the same since both expose `UUID`-shaped initializers.

import Foundation

public typealias WorkoutID = UUID
public typealias BlockID = UUID
public typealias WorkoutItemID = UUID
public typealias ExerciseID = UUID
public typealias ExerciseAlternativeID = UUID
public typealias SetLogID = UUID
public typealias UserParameterID = UUID
public typealias UserID = UUID
