import Foundation
import WorkoutKitExportProfile

public struct WorkoutKitPayloadFingerprint: Sendable, Hashable, Codable, CustomStringConvertible {
    public var value: String

    public init(value: String) {
        self.value = value
    }

    public var description: String { value }

    static func make(
        plan: WorkoutKitExportPlan,
        descriptor: WorkoutKitPlanDescriptor,
        occurrence: DateComponents?
    ) throws -> WorkoutKitPayloadFingerprint {
        let normalized = FingerprintPayload(
            workoutID: plan.workoutID.uuidString.lowercased(),
            rowID: plan.rowID,
            supportState: plan.supportState,
            pushIdentity: plan.pushIdentity,
            degradation: plan.degradation,
            descriptor: descriptor,
            occurrence: occurrence.map(NormalizedOccurrence.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(normalized)
        return WorkoutKitPayloadFingerprint(value: fnv1a64Hex(data))
    }
}

private struct FingerprintPayload: Encodable {
    var workoutID: String
    var rowID: WorkoutKitMatrixRowID
    var supportState: WorkoutKitSupportState
    var pushIdentity: WorkoutKitPushIdentity
    var degradation: WorkoutKitDegradation?
    var descriptor: WorkoutKitPlanDescriptor
    var occurrence: NormalizedOccurrence?
}

private struct NormalizedOccurrence: Encodable {
    var calendarIdentifier: String?
    var timeZoneIdentifier: String?
    var era: Int?
    var year: Int?
    var month: Int?
    var day: Int?
    var hour: Int?
    var minute: Int?
    var second: Int?

    init(_ components: DateComponents) {
        self.calendarIdentifier = components.calendar.map { String(describing: $0.identifier) }
        self.timeZoneIdentifier = components.timeZone?.identifier
        self.era = components.era
        self.year = components.year
        self.month = components.month
        self.day = components.day
        self.hour = components.hour
        self.minute = components.minute
        self.second = components.second
    }
}

private func fnv1a64Hex(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return String(format: "%016llx", hash)
}
