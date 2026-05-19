// HealthArchiveStoreTests.swift
//
// Real SwiftData proof for the HealthKit archive projection store.

import XCTest
@testable import Persistence

final class HealthArchiveStoreTests: XCTestCase {
    private func makeFactory() throws -> PersistenceFactory {
        try PersistenceFactory.makeInMemory(
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    private func makeOnDiskFactory(storeURL: URL) throws -> PersistenceFactory {
        try PersistenceFactory.makeOnDisk(
            storeURL: storeURL,
            tokenServiceName: "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
        )
    }

    func testRecordUpsertDeduplicatesByDescriptorAndExternalID() async throws {
        let factory = try makeFactory()
        let first = HealthArchiveRecord(
            externalID: "sample-1",
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            sampleKindRaw: "quantity",
            start: Date(timeIntervalSince1970: 10),
            value: .quantity(120, unit: "count/min"),
            metadata: ["source": "first"]
        )
        let replacement = HealthArchiveRecord(
            externalID: "sample-1",
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            sampleKindRaw: "quantity",
            start: Date(timeIntervalSince1970: 10),
            value: .quantity(122, unit: "count/min"),
            metadata: ["source": "replacement"]
        )

        try await factory.healthArchiveStore.save(records: [first], deletions: [], cursors: [])
        try await factory.healthArchiveStore.save(records: [replacement], deletions: [], cursors: [])

        let records = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].externalID, "sample-1")
        XCTAssertEqual(records[0].value, .quantity(122, unit: "count/min"))
        XCTAssertEqual(records[0].metadata, ["source": "replacement"])
    }

    func testCursorIsScopedByRequestSet() async throws {
        let factory = try makeFactory()
        try await factory.healthArchiveStore.save(records: [], deletions: [], cursors: [
            HealthArchiveCursor(
                requestSetKey: "archive-all",
                cursor: "cursor-1"
            ),
            HealthArchiveCursor(
                requestSetKey: "post-workout",
                cursor: "cursor-2"
            ),
        ])
        try await factory.healthArchiveStore.save(records: [], deletions: [], cursors: [
            HealthArchiveCursor(
                requestSetKey: "archive-all",
                cursor: "cursor-3"
            ),
        ])

        let archiveCursor = try await factory.healthArchiveStore.loadCursor(requestSetKey: "archive-all")
        let workoutCursor = try await factory.healthArchiveStore.loadCursor(requestSetKey: "post-workout")
        XCTAssertEqual(archiveCursor?.cursor, "cursor-3")
        XCTAssertEqual(workoutCursor?.cursor, "cursor-2")
    }

    func testDeletionsArePersistedAndDeduplicated() async throws {
        let factory = try makeFactory()
        let deletion = HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierStepCount",
            externalID: "deleted-sample",
            observedAt: Date(timeIntervalSince1970: 20)
        )
        let laterDeletion = HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierStepCount",
            externalID: "deleted-sample",
            observedAt: Date(timeIntervalSince1970: 30)
        )

        try await factory.healthArchiveStore.save(records: [], deletions: [deletion], cursors: [])
        try await factory.healthArchiveStore.save(records: [], deletions: [laterDeletion], cursors: [])

        let deletions = try await factory.healthArchiveStore.loadDeletions(
            descriptorID: "HKQuantityTypeIdentifierStepCount"
        )
        XCTAssertEqual(deletions.count, 1)
        XCTAssertEqual(deletions[0].externalID, "deleted-sample")
        XCTAssertEqual(deletions[0].observedAt, Date(timeIntervalSince1970: 30))
    }

    func testDeletedRecordsAreSuppressedFromLiveProjectionButTombstoneRemains() async throws {
        let factory = try makeFactory()
        let record = HealthArchiveRecord(
            externalID: "sample-to-delete",
            descriptorID: "HKQuantityTypeIdentifierStepCount",
            sampleKindRaw: "quantity",
            start: Date(timeIntervalSince1970: 10),
            value: .quantity(42, unit: "count")
        )
        let deletion = HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierStepCount",
            externalID: "sample-to-delete",
            observedAt: Date(timeIntervalSince1970: 20)
        )
        let duplicateDeletion = HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierStepCount",
            externalID: "sample-to-delete",
            observedAt: Date(timeIntervalSince1970: 30)
        )

        try await factory.healthArchiveStore.save(records: [record], deletions: [], cursors: [])
        try await factory.healthArchiveStore.save(records: [], deletions: [deletion], cursors: [])
        try await factory.healthArchiveStore.save(records: [], deletions: [duplicateDeletion], cursors: [])

        let records = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertTrue(records.isEmpty)

        let deletions = try await factory.healthArchiveStore.loadDeletions(
            descriptorID: "HKQuantityTypeIdentifierStepCount"
        )
        XCTAssertEqual(deletions.count, 1)
        XCTAssertEqual(deletions[0].externalID, "sample-to-delete")
        XCTAssertEqual(deletions[0].observedAt, Date(timeIntervalSince1970: 30))
    }

    func testDeletionWithDifferentDescriptorDoesNotSuppressRecord() async throws {
        let factory = try makeFactory()
        let record = HealthArchiveRecord(
            externalID: "same-external-id",
            descriptorID: "HKQuantityTypeIdentifierStepCount",
            sampleKindRaw: "quantity",
            value: .quantity(42, unit: "count")
        )
        let deletion = HealthArchiveDeletion(
            descriptorID: "HKQuantityTypeIdentifierHeartRate",
            externalID: "same-external-id"
        )

        try await factory.healthArchiveStore.save(records: [record], deletions: [], cursors: [])
        try await factory.healthArchiveStore.save(records: [], deletions: [deletion], cursors: [])

        let records = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertEqual(records.map(\.externalID), ["same-external-id"])
        XCTAssertEqual(records.map(\.descriptorID), ["HKQuantityTypeIdentifierStepCount"])
    }

    func testRecordValuesPreserveUnitsAndPayloads() async throws {
        let factory = try makeFactory()
        try await factory.healthArchiveStore.save(records: [
            HealthArchiveRecord(
                externalID: "sleep-1",
                descriptorID: "HKCategoryTypeIdentifierSleepAnalysis",
                sampleKindRaw: "category",
                value: .category(3)
            ),
            HealthArchiveRecord(
                externalID: "workout-1",
                descriptorID: "HKWorkoutTypeIdentifier",
                sampleKindRaw: "workout",
                value: .workout(
                    activityType: "50",
                    durationSeconds: 60,
                    totalEnergyKcal: 8
                )
            ),
        ], deletions: [], cursors: [])

        let records = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertTrue(records.map(\.value).contains(.category(3)))
        XCTAssertTrue(records.map(\.value).contains(.workout(
            activityType: "50",
            durationSeconds: 60,
            totalEnergyKcal: 8
        )))
    }

    func testClearRemovesRecordsDeletionsAndCursors() async throws {
        let factory = try makeFactory()
        try await factory.healthArchiveStore.save(
            records: [
                HealthArchiveRecord(
                    externalID: "sample-1",
                    descriptorID: "HKQuantityTypeIdentifierHeartRate",
                    sampleKindRaw: "quantity",
                    value: .quantity(120, unit: "count/min")
                ),
            ],
            deletions: [
                HealthArchiveDeletion(
                    descriptorID: "HKQuantityTypeIdentifierHeartRate",
                    externalID: "deleted-sample"
                ),
            ],
            cursors: [
                HealthArchiveCursor(
                    requestSetKey: "archive-all",
                    cursor: "cursor-1"
                ),
            ]
        )

        try await factory.healthArchiveStore.clear()

        let records = try await factory.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertTrue(records.isEmpty)
        let deletions = try await factory.healthArchiveStore.loadDeletions(descriptorID: nil)
        XCTAssertTrue(deletions.isEmpty)
        let cursor = try await factory.healthArchiveStore.loadCursor(requestSetKey: "archive-all")
        XCTAssertNil(cursor)
    }

    func testOnDiskArchiveStoreReopensRecordsDeletionsAndCursors() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutDBHealthArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent("default.store")

        do {
            let factory = try makeOnDiskFactory(storeURL: storeURL)
            try await factory.healthArchiveStore.save(
                records: [
                    HealthArchiveRecord(
                        externalID: "disk-heart-rate-1",
                        descriptorID: "HKQuantityTypeIdentifierHeartRate",
                        sampleKindRaw: "quantity",
                        start: Date(timeIntervalSince1970: 10),
                        value: .quantity(144, unit: "count/min"),
                        metadata: ["source": "disk-proof"]
                    ),
                ],
                deletions: [
                    HealthArchiveDeletion(
                        descriptorID: "HKQuantityTypeIdentifierStepCount",
                        externalID: "disk-deleted-1",
                        observedAt: Date(timeIntervalSince1970: 20)
                    ),
                ],
                cursors: [
                    HealthArchiveCursor(
                        requestSetKey: "archive-all",
                        cursor: "disk-cursor-1"
                    ),
                ]
            )
        }

        let reopened = try makeOnDiskFactory(storeURL: storeURL)
        let records = try await reopened.healthArchiveStore.loadRecords(descriptorID: nil)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].externalID, "disk-heart-rate-1")
        XCTAssertEqual(records[0].value, .quantity(144, unit: "count/min"))
        XCTAssertEqual(records[0].metadata, ["source": "disk-proof"])

        let deletions = try await reopened.healthArchiveStore.loadDeletions(
            descriptorID: "HKQuantityTypeIdentifierStepCount"
        )
        XCTAssertEqual(deletions.count, 1)
        XCTAssertEqual(deletions[0].externalID, "disk-deleted-1")

        let cursor = try await reopened.healthArchiveStore.loadCursor(requestSetKey: "archive-all")
        XCTAssertEqual(cursor?.cursor, "disk-cursor-1")
    }
}
