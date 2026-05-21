import Foundation
import WorkoutCoreFoundation

public struct WorkoutKitHandoffAttemptSnapshot: Sendable, Hashable, Codable {
    public var workoutID: WorkoutID
    public var occurrenceKey: String
    public var path: String
    public var payloadFingerprint: String
    public var lastAttemptAt: Date
    public var outcome: String
    public var workoutPlanID: UUID?
    public var failureClass: String?

    public init(
        workoutID: WorkoutID,
        occurrenceKey: String,
        path: String,
        payloadFingerprint: String,
        lastAttemptAt: Date,
        outcome: String,
        workoutPlanID: UUID? = nil,
        failureClass: String? = nil
    ) {
        self.workoutID = workoutID
        self.occurrenceKey = occurrenceKey
        self.path = path
        self.payloadFingerprint = payloadFingerprint
        self.lastAttemptAt = lastAttemptAt
        self.outcome = outcome
        self.workoutPlanID = workoutPlanID
        self.failureClass = failureClass
    }
}

public struct WorkoutKitHandoffReceipt: Sendable, Hashable, Codable {
    public var id: UUID
    public var createdAt: Date
    public var workoutID: WorkoutID
    public var rowID: String
    public var path: String
    public var occurrenceKey: String
    public var payloadFingerprint: String
    public var workoutPlanID: UUID?
    public var outcome: String
    public var failureClass: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        workoutID: WorkoutID,
        rowID: String,
        path: String,
        occurrenceKey: String,
        payloadFingerprint: String,
        workoutPlanID: UUID?,
        outcome: String,
        failureClass: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.workoutID = workoutID
        self.rowID = rowID
        self.path = path
        self.occurrenceKey = occurrenceKey
        self.payloadFingerprint = payloadFingerprint
        self.workoutPlanID = workoutPlanID
        self.outcome = outcome
        self.failureClass = failureClass
    }
}

public protocol WorkoutKitHandoffAttemptStore: Sendable {
    func latest(
        workoutID: WorkoutID,
        occurrenceKey: String,
        path: String
    ) async -> WorkoutKitHandoffAttemptSnapshot?
    func save(
        snapshot: WorkoutKitHandoffAttemptSnapshot,
        receipt: WorkoutKitHandoffReceipt
    ) async
    func receipts() async -> [WorkoutKitHandoffReceipt]
}

public actor UserDefaultsWorkoutKitHandoffAttemptStore: WorkoutKitHandoffAttemptStore {
    private let defaults: UserDefaults
    private let latestKey = "workoutkit-handoff.latest.v1"
    private let receiptsKey = "workoutkit-handoff.receipts.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func latest(
        workoutID: WorkoutID,
        occurrenceKey: String,
        path: String
    ) async -> WorkoutKitHandoffAttemptSnapshot? {
        latestSnapshots()[Self.snapshotKey(
            workoutID: workoutID,
            occurrenceKey: occurrenceKey,
            path: path
        )]
    }

    public func save(
        snapshot: WorkoutKitHandoffAttemptSnapshot,
        receipt: WorkoutKitHandoffReceipt
    ) async {
        var latest = latestSnapshots()
        latest[Self.snapshotKey(
            workoutID: snapshot.workoutID,
            occurrenceKey: snapshot.occurrenceKey,
            path: snapshot.path
        )] = snapshot
        write(latest, key: latestKey)

        var existingReceipts = receiptsFromDefaults()
        existingReceipts.append(receipt)
        write(existingReceipts, key: receiptsKey)
    }

    public func receipts() async -> [WorkoutKitHandoffReceipt] {
        receiptsFromDefaults()
    }

    private static func snapshotKey(
        workoutID: WorkoutID,
        occurrenceKey: String,
        path: String
    ) -> String {
        "\(workoutID.uuidString.lowercased())|\(occurrenceKey)|\(path)"
    }

    private func latestSnapshots() -> [String: WorkoutKitHandoffAttemptSnapshot] {
        decode([String: WorkoutKitHandoffAttemptSnapshot].self, key: latestKey) ?? [:]
    }

    private func receiptsFromDefaults() -> [WorkoutKitHandoffReceipt] {
        decode([WorkoutKitHandoffReceipt].self, key: receiptsKey) ?? []
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
