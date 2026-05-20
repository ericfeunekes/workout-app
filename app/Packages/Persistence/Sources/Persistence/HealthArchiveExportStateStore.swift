import Foundation

public enum HealthArchiveExportScope: Codable, Sendable, Equatable {
    case allSupported
    case explicitDescriptorIDs([String])
}

public enum HealthArchiveExportStatus: String, Codable, Sendable, Equatable {
    case neverRun
    case running
    case succeeded
    case failed
    case alreadyRunning
}

public struct HealthArchiveExportSnapshot: Codable, Sendable, Equatable {
    public let scope: HealthArchiveExportScope
    public let serverNamespace: String?
    public let requestSetKey: String?
    public let descriptorFingerprint: String?
    public let acknowledgedCursor: String?
    public let status: HealthArchiveExportStatus
    public let lastFetchAt: Date?
    public let lastUploadAt: Date?
    public let lastRecordCount: Int
    public let lastTombstoneCount: Int
    public let lastFailureClass: String?
    public let automaticEnabled: Bool
    public let nextAttemptAt: Date?
    public let lastAttemptAt: Date?

    public init(
        scope: HealthArchiveExportScope = .allSupported,
        serverNamespace: String? = nil,
        requestSetKey: String? = nil,
        descriptorFingerprint: String? = nil,
        acknowledgedCursor: String? = nil,
        status: HealthArchiveExportStatus = .neverRun,
        lastFetchAt: Date? = nil,
        lastUploadAt: Date? = nil,
        lastRecordCount: Int = 0,
        lastTombstoneCount: Int = 0,
        lastFailureClass: String? = nil,
        automaticEnabled: Bool = false,
        nextAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil
    ) {
        self.scope = scope
        self.serverNamespace = serverNamespace
        self.requestSetKey = requestSetKey
        self.descriptorFingerprint = descriptorFingerprint
        self.acknowledgedCursor = acknowledgedCursor
        self.status = status
        self.lastFetchAt = lastFetchAt
        self.lastUploadAt = lastUploadAt
        self.lastRecordCount = lastRecordCount
        self.lastTombstoneCount = lastTombstoneCount
        self.lastFailureClass = lastFailureClass
        self.automaticEnabled = automaticEnabled
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
    }
}

public protocol HealthArchiveExportStateStore: Sendable {
    func loadSnapshot(serverNamespace: String?) async -> HealthArchiveExportSnapshot
    func saveSnapshot(_ snapshot: HealthArchiveExportSnapshot) async
    func setScope(_ scope: HealthArchiveExportScope) async
    func setAutomaticEnabled(_ enabled: Bool) async
    func clear() async
}

public struct UserDefaultsHealthArchiveExportStateStore: HealthArchiveExportStateStore {
    private let prefix: String
    private nonisolated(unsafe) let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        prefix: String = "workoutdb.health_archive_export",
        defaults: UserDefaults = .standard
    ) {
        self.prefix = prefix
        self.defaults = defaults
    }

    public func loadSnapshot(serverNamespace: String? = nil) async -> HealthArchiveExportSnapshot {
        let control = loadControl()
        guard let serverNamespace else {
            return HealthArchiveExportSnapshot(
                scope: control.scope,
                automaticEnabled: control.automaticEnabled
            )
        }
        if let data = defaults.data(forKey: statusKey(serverNamespace)),
           let stored = try? decoder.decode(StoredStatus.self, from: data) {
            return stored.snapshot(
                scope: control.scope,
                automaticEnabled: control.automaticEnabled,
                serverNamespace: serverNamespace
            )
        }
        return HealthArchiveExportSnapshot(
            scope: control.scope,
            serverNamespace: serverNamespace,
            automaticEnabled: control.automaticEnabled
        )
    }

    public func saveSnapshot(_ snapshot: HealthArchiveExportSnapshot) async {
        guard let serverNamespace = snapshot.serverNamespace else { return }
        let stored = StoredStatus(snapshot: snapshot)
        if let data = try? encoder.encode(stored) {
            defaults.set(data, forKey: statusKey(serverNamespace))
        }
    }

    public func setScope(_ scope: HealthArchiveExportScope) async {
        var control = loadControl()
        control.scope = scope
        saveControl(control)
    }

    public func setAutomaticEnabled(_ enabled: Bool) async {
        var control = loadControl()
        control.automaticEnabled = enabled
        saveControl(control)
    }

    public func clear() async {
        defaults.removeObject(forKey: controlKey)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("\(prefix).status.") {
            defaults.removeObject(forKey: key)
        }
    }

    private var controlKey: String { "\(prefix).control" }

    private func statusKey(_ serverNamespace: String) -> String {
        "\(prefix).status.\(serverNamespace)"
    }

    private func loadControl() -> StoredControl {
        if let data = defaults.data(forKey: controlKey),
           let stored = try? decoder.decode(StoredControl.self, from: data) {
            return stored
        }
        return StoredControl()
    }

    private func saveControl(_ control: StoredControl) {
        if let data = try? encoder.encode(control) {
            defaults.set(data, forKey: controlKey)
        }
    }

    private struct StoredControl: Codable {
        var scope: HealthArchiveExportScope
        var automaticEnabled: Bool

        init(
            scope: HealthArchiveExportScope = .allSupported,
            automaticEnabled: Bool = false
        ) {
            self.scope = scope
            self.automaticEnabled = automaticEnabled
        }

        private enum CodingKeys: String, CodingKey {
            case scope
            case automaticEnabled
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            scope = try values.decodeIfPresent(
                HealthArchiveExportScope.self,
                forKey: .scope
            ) ?? .allSupported
            automaticEnabled = try values.decodeIfPresent(
                Bool.self,
                forKey: .automaticEnabled
            ) ?? false
        }
    }

    private struct StoredStatus: Codable {
        var requestSetKey: String?
        var descriptorFingerprint: String?
        var acknowledgedCursor: String?
        var status: HealthArchiveExportStatus
        var lastFetchAt: Date?
        var lastUploadAt: Date?
        var lastRecordCount: Int
        var lastTombstoneCount: Int
        var lastFailureClass: String?
        var nextAttemptAt: Date?
        var lastAttemptAt: Date?

        init(snapshot: HealthArchiveExportSnapshot) {
            self.requestSetKey = snapshot.requestSetKey
            self.descriptorFingerprint = snapshot.descriptorFingerprint
            self.acknowledgedCursor = snapshot.acknowledgedCursor
            self.status = snapshot.status
            self.lastFetchAt = snapshot.lastFetchAt
            self.lastUploadAt = snapshot.lastUploadAt
            self.lastRecordCount = snapshot.lastRecordCount
            self.lastTombstoneCount = snapshot.lastTombstoneCount
            self.lastFailureClass = snapshot.lastFailureClass
            self.nextAttemptAt = snapshot.nextAttemptAt
            self.lastAttemptAt = snapshot.lastAttemptAt
        }

        func snapshot(
            scope: HealthArchiveExportScope,
            automaticEnabled: Bool,
            serverNamespace: String
        ) -> HealthArchiveExportSnapshot {
            let snapshot = HealthArchiveExportSnapshot(
                scope: scope,
                serverNamespace: serverNamespace,
                requestSetKey: requestSetKey,
                descriptorFingerprint: descriptorFingerprint,
                acknowledgedCursor: acknowledgedCursor,
                status: status,
                lastFetchAt: lastFetchAt,
                lastUploadAt: lastUploadAt,
                lastRecordCount: lastRecordCount,
                lastTombstoneCount: lastTombstoneCount,
                lastFailureClass: lastFailureClass,
                automaticEnabled: automaticEnabled,
                nextAttemptAt: nextAttemptAt,
                lastAttemptAt: lastAttemptAt
            )
            return Self.reconcileStaleRunning(snapshot)
        }

        private static func reconcileStaleRunning(
            _ snapshot: HealthArchiveExportSnapshot
        ) -> HealthArchiveExportSnapshot {
            guard snapshot.status == .running,
                  let lastAttemptAt = snapshot.lastAttemptAt,
                  Date().timeIntervalSince(lastAttemptAt) > 30 * 60
            else {
                return snapshot
            }
            return HealthArchiveExportSnapshot(
                scope: snapshot.scope,
                serverNamespace: snapshot.serverNamespace,
                requestSetKey: snapshot.requestSetKey,
                descriptorFingerprint: snapshot.descriptorFingerprint,
                acknowledgedCursor: snapshot.acknowledgedCursor,
                status: .failed,
                lastFetchAt: snapshot.lastFetchAt,
                lastUploadAt: snapshot.lastUploadAt,
                lastRecordCount: snapshot.lastRecordCount,
                lastTombstoneCount: snapshot.lastTombstoneCount,
                lastFailureClass: "InterruptedExport",
                automaticEnabled: snapshot.automaticEnabled,
                nextAttemptAt: snapshot.nextAttemptAt,
                lastAttemptAt: snapshot.lastAttemptAt
            )
        }
    }
}
