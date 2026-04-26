// SetEditSheetContract.swift
//
// Shared edit intent contract for workout value sheets. The concrete call
// site owns persistence, sync, and any autoreg side effects; this model only
// records which fields the user actually touched.

import Foundation

public enum SetEditField: String, CaseIterable, Sendable, Equatable {
    case load
    case reps
    case rir
    case bodyweight
    case side
    case distance
    case duration
    case carryLoad
    case carryDistance
}

public enum SetEditSide: String, CaseIterable, Sendable, Equatable {
    case left
    case right
    case bilateral
}

public enum SetEditRIR: Sendable, Equatable {
    case preserve
    case clear
    case set(Int)
}

public enum SetEditScope: String, CaseIterable, Sendable, Equatable {
    case current
    case remaining
}

public struct SetEditIntent: Sendable, Equatable {
    public let scope: SetEditScope
    public let load: Double?
    public let loadUnit: String?
    public let reps: Int?
    public let rir: SetEditRIR
    public let bodyweight: Double?
    public let bodyweightUnit: String?
    public let side: SetEditSide?
    public let distance: Double?
    public let distanceUnit: String?
    public let durationSeconds: Double?
    public let carryLoad: Double?
    public let carryLoadUnit: String?
    public let carryDistance: Double?
    public let carryDistanceUnit: String?

    public init(
        scope: SetEditScope,
        load: Double?,
        loadUnit: String?,
        reps: Int?,
        rir: SetEditRIR,
        bodyweight: Double?,
        bodyweightUnit: String?,
        side: SetEditSide?,
        distance: Double?,
        distanceUnit: String?,
        durationSeconds: Double?,
        carryLoad: Double?,
        carryLoadUnit: String?,
        carryDistance: Double?,
        carryDistanceUnit: String?
    ) {
        self.scope = scope
        self.load = load
        self.loadUnit = loadUnit
        self.reps = reps
        self.rir = rir
        self.bodyweight = bodyweight
        self.bodyweightUnit = bodyweightUnit
        self.side = side
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.durationSeconds = durationSeconds
        self.carryLoad = carryLoad
        self.carryLoadUnit = carryLoadUnit
        self.carryDistance = carryDistance
        self.carryDistanceUnit = carryDistanceUnit
    }
}

public final class SetEditSheetModel {
    public let availableFields: Set<SetEditField>
    public private(set) var scope: SetEditScope

    private var loadValue: Double?
    private var loadUnitValue: String?
    private var repsValue: Int?
    private var rirValue: SetEditRIR = .preserve
    private var bodyweightValue: Double?
    private var bodyweightUnitValue: String?
    private var sideValue: SetEditSide?
    private var distanceValue: Double?
    private var distanceUnitValue: String?
    private var durationSecondsValue: Double?
    private var carryLoadValue: Double?
    private var carryLoadUnitValue: String?
    private var carryDistanceValue: Double?
    private var carryDistanceUnitValue: String?

    public init(
        availableFields: Set<SetEditField>,
        scope: SetEditScope = .current
    ) {
        self.availableFields = availableFields
        self.scope = scope
    }

    public func setScope(_ scope: SetEditScope) {
        self.scope = scope
    }

    public func setLoad(_ value: Double, unit: String) {
        guard availableFields.contains(.load) else { return }
        loadValue = value
        loadUnitValue = unit
    }

    public func setReps(_ value: Int) {
        guard availableFields.contains(.reps) else { return }
        repsValue = max(0, value)
    }

    public func setRIR(_ value: Int) {
        guard availableFields.contains(.rir) else { return }
        rirValue = .set(max(0, min(5, value)))
    }

    public func clearRIR() {
        guard availableFields.contains(.rir) else { return }
        rirValue = .clear
    }

    public func setBodyweight(_ value: Double, unit: String) {
        guard availableFields.contains(.bodyweight) else { return }
        bodyweightValue = value
        bodyweightUnitValue = unit
    }

    public func setSide(_ side: SetEditSide) {
        guard availableFields.contains(.side) else { return }
        sideValue = side
    }

    public func setDistance(_ value: Double, unit: String) {
        guard availableFields.contains(.distance) else { return }
        distanceValue = value
        distanceUnitValue = unit
    }

    public func setDuration(seconds: Double) {
        guard availableFields.contains(.duration) else { return }
        durationSecondsValue = max(0, seconds)
    }

    public func setCarry(load: Double, loadUnit: String, distance: Double, distanceUnit: String) {
        guard availableFields.contains(.carryLoad),
              availableFields.contains(.carryDistance) else { return }
        carryLoadValue = load
        carryLoadUnitValue = loadUnit
        carryDistanceValue = distance
        carryDistanceUnitValue = distanceUnit
    }

    public func commit() -> SetEditIntent {
        SetEditIntent(
            scope: scope,
            load: loadValue,
            loadUnit: loadUnitValue,
            reps: repsValue,
            rir: rirValue,
            bodyweight: bodyweightValue,
            bodyweightUnit: bodyweightUnitValue,
            side: sideValue,
            distance: distanceValue,
            distanceUnit: distanceUnitValue,
            durationSeconds: durationSecondsValue,
            carryLoad: carryLoadValue,
            carryLoadUnit: carryLoadUnitValue,
            carryDistance: carryDistanceValue,
            carryDistanceUnit: carryDistanceUnitValue
        )
    }
}
