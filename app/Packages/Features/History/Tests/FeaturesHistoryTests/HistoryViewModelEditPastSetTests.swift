// HistoryViewModelEditPastSetTests.swift
//
// Covers the History session-detail past-set edit path — bug-015. The
// invariants under test:
//
//   - `editPastSet` writes the edited SetLog to the local cache AND
//     fires the `onSetLogEdited` hook so the shell can enqueue the push.
//   - The enqueued SetLog carries the ORIGINAL log's id (so the server
//     upserts in place, not inserts a duplicate row).
//   - A `history.past_set_edited` telemetry event fires, tagged with
//     workoutID + setLogID.
//   - After the edit, `load()` runs — so the session-detail view model
//     re-derives and the UI sees the corrected row without a pull.

import XCTest
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
@testable import FeaturesHistory

@MainActor
final class HistoryViewModelEditPastSetTests: XCTestCase {

    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // Fixed "now" — 2026-04-18 UTC.
    private let now = Date(timeIntervalSince1970: 1_776_384_000)

    func testHistoryEditPastSetEnqueuesPush() async throws {
        // Edit the first set of the only workout → the hook fires with
        // the edited SetLog, and the id matches the ORIGINAL log's id.
        // Same UUID → server upserts in place rather than inserting a
        // second row. This is the server-side contract bug-010 relied
        // on; bug-015 extends it to the History edit path.
        let (cache, firstLog) = try makeSingleLogFixture()
        let recorder = EditRecorder()
        let hook: HistorySetLogEditHook = { [recorder] log in
            await recorder.append(log)
        }
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now },
            onSetLogEdited: hook
        )
        await vm.load()

        await vm.editPastSet(
            workoutID: firstLog.workoutID,
            setLogID: firstLog.setLog.id,
            reps: 4,
            rir: .set(1),
            load: nil
        )

        let pushed = await recorder.pushed
        XCTAssertEqual(pushed.count, 1, "edit must enqueue exactly one push")
        let edited = try XCTUnwrap(pushed.first)
        XCTAssertEqual(edited.id, firstLog.setLog.id,
                       "edit UUID must match original so server upserts in place")
        XCTAssertEqual(edited.reps, 4)
        XCTAssertEqual(edited.rir, 1)
        // Load preserved — edit touched reps and rir only.
        XCTAssertEqual(edited.weight, firstLog.setLog.weight)
    }

    func testHistoryEditUsesExistingSetLogIdForIdempotentUpsert() async throws {
        // Bug-040 regression. If the edit path regenerates a fresh UUID
        // instead of reusing the cached SetLog's id, the server's
        // `sync_results` upsert falls through to INSERT and we end up with
        // two rows for `set_index=1` (original + edit). Pins a SPECIFIC
        // UUID `U1` on the seeded log so a drift of the reuse contract
        // shows up as a concrete id mismatch, not just "some UUID changed."
        // swiftlint:disable:next force_unwrapping
        let knownID = UUID(uuidString: "A1B2C3D4-E5F6-4789-8ABC-DEF012345678")!
        let (cache, firstLog) = try makeSingleLogFixture(setLogID: knownID)
        XCTAssertEqual(firstLog.setLog.id, knownID,
                       "fixture must seed the known id for the assertion to be meaningful")
        let recorder = EditRecorder()
        let hook: HistorySetLogEditHook = { [recorder] log in
            await recorder.append(log)
        }
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now },
            onSetLogEdited: hook
        )
        await vm.load()

        await vm.editPastSet(
            workoutID: firstLog.workoutID,
            setLogID: knownID,
            reps: 5,
            rir: .preserve,
            load: nil
        )

        let pushed = await recorder.pushed
        let edited = try XCTUnwrap(pushed.first)
        XCTAssertEqual(edited.id, knownID,
                       "edit must reuse the ORIGINAL SetLog id (U1) so the server upserts in place")
        XCTAssertEqual(edited.reps, 5, "edit must carry the new reps value")
        // And the invariants that preserve the row's identity beyond id.
        XCTAssertEqual(edited.workoutItemID, firstLog.setLog.workoutItemID)
        XCTAssertEqual(edited.setIndex, firstLog.setLog.setIndex)
        XCTAssertEqual(edited.completedAt, firstLog.setLog.completedAt)
    }

    func testHistoryEditReloadsAfterCommit() async throws {
        // After the edit commits, `load()` reruns so the detail VM sees
        // the corrected row. The FakeHistoryCache's `saveSetLogs` mirrors
        // the edit into `setLogsByWorkout`, so loading re-pulls the
        // post-edit row.
        let (cache, firstLog) = try makeSingleLogFixture()
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        // Pre-edit: detail VM reflects the original log.
        let beforeDetail = try XCTUnwrap(vm.detail(for: firstLog.workoutID))
        XCTAssertEqual(beforeDetail.cards.first?.setRows.first?.display,
                       "1 · 100 kg × 5 · RIR 2")

        await vm.editPastSet(
            workoutID: firstLog.workoutID,
            setLogID: firstLog.setLog.id,
            reps: 4,
            rir: .set(1),
            load: EditPastSetLoadCommit(value: 97.5, unit: .kg)
        )

        // Post-edit: `detail(for:)` builds a fresh VM from `rawSessions`,
        // which `load()` refreshed with the post-edit SetLog. If the
        // reload hadn't happened, the display here would still read
        // "1 · 100 kg × 5 · RIR 2" and this test would fail.
        let afterDetail = try XCTUnwrap(vm.detail(for: firstLog.workoutID))
        let row = try XCTUnwrap(afterDetail.cards.first?.setRows.first)
        XCTAssertEqual(row.display, "1 · 97.5 kg × 4 · RIR 1",
                       "post-edit row must show corrected values")
        // The cache saw exactly one write (the edit batch).
        XCTAssertEqual(cache.savedSetLogBatches.count, 1)
        XCTAssertEqual(cache.savedSetLogBatches.first?.count, 1)
    }

    func testHistoryEditEmitsTelemetry() async throws {
        // Bug-015 parallel to bug-017 (execution.past_set_edited): every
        // History edit emits a dedicated `history.past_set_edited` event
        // tagged with workoutID + setLogID. Payload shape is
        // `{itemID, setIndex, setLogID}` per `docs/features/telemetry.md`
        // — matches `execution.past_set_edited` so the two surfaces'
        // edit trails compose on a single join key. qa-036 fixed a drift
        // where the payload emitted `workoutID` instead of `itemID`; the
        // event's row-level workoutID tag still rides on `Event.workoutID`.
        //
        // Wire-casing (R1.3): ids in the dataJSON payload must be
        // LOWERCASE — the "every id + *_id on the wire is a lowercase
        // UUID" invariant. Pin a known-lowercase setLogID so the
        // assertion can match the payload verbatim (Swift
        // `UUID().uuidString` is uppercase, so a naive
        // `contains(uuidString)` would pass either casing).
        // swiftlint:disable:next force_unwrapping
        let seededSetLogID = UUID(uuidString: "aaaabbbb-1111-4222-8333-444444444444")!
        let (cache, firstLog) = try makeSingleLogFixture(setLogID: seededSetLogID)
        let telemetry = HistoryTelemetryRecorder()
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now },
            telemetry: telemetry
        )
        await vm.load()

        await vm.editPastSet(
            workoutID: firstLog.workoutID,
            setLogID: firstLog.setLog.id,
            reps: 3,
            rir: .preserve,
            load: nil
        )

        let events = telemetry.events.filter { $0.name == "history.past_set_edited" }
        XCTAssertEqual(events.count, 1, "edit must emit exactly one event")
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.workoutID, firstLog.workoutID)
        XCTAssertEqual(event.setLogID, firstLog.setLog.id)
        let payload = event.dataJSON ?? ""
        XCTAssertTrue(payload.contains("\"setIndex\":\(firstLog.setLog.setIndex)"),
                      "payload must carry setIndex — got \(payload)")
        XCTAssertTrue(
            payload.contains("\"setLogID\":\"aaaabbbb-1111-4222-8333-444444444444\""),
            "payload must carry EXACT lowercase setLogID — got \(payload)"
        )
        XCTAssertTrue(
            payload.contains(
                "\"itemID\":\"\(firstLog.setLog.workoutItemID.uuidString.lowercased())\""
            ),
            "payload must carry EXACT lowercase itemID — got \(payload)"
        )
        XCTAssertFalse(
            payload.contains("\"workoutID\""),
            "payload must NOT carry workoutID — the shape is {itemID, setIndex, setLogID}; got \(payload)"
        )
        // Any UUID-shaped substring in the payload must be all-lowercase.
        // Extract every UUID-shaped match, then assert it equals its own
        // `.lowercased()` so a partial-uppercase regression is caught
        // regardless of which UUID leaked.
        let uuidShape = try NSRegularExpression(
            pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        )
        let hits = uuidShape.matches(
            in: payload, range: NSRange(payload.startIndex..., in: payload)
        )
        for hit in hits {
            // swiftlint:disable:next force_unwrapping
            let range = Range(hit.range, in: payload)!
            let substr = String(payload[range])
            XCTAssertEqual(
                substr, substr.lowercased(),
                "payload leaked an uppercase UUID: \(substr) in \(payload)"
            )
        }
    }

    /// qa-036 — pin the payload SHAPE, not just the individual keys.
    /// Runtime QA found a drift where the live payload was
    /// `{setIndex, setLogID, workoutID}` instead of the documented
    /// `{itemID, setIndex, setLogID}`. This test decodes the emitted
    /// dataJSON and asserts the exact three-key shape — any future
    /// drift (extra key, missing key, renamed key) flips the test red.
    func testHistoryPastSetEditedPayloadShape() async throws {
        let (cache, firstLog) = try makeSingleLogFixture()
        let telemetry = HistoryTelemetryRecorder()
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now },
            telemetry: telemetry
        )
        await vm.load()

        await vm.editPastSet(
            workoutID: firstLog.workoutID,
            setLogID: firstLog.setLog.id,
            reps: 7,
            rir: .preserve,
            load: nil
        )

        let event = try XCTUnwrap(
            telemetry.events.first { $0.name == "history.past_set_edited" }
        )
        let payloadString = try XCTUnwrap(event.dataJSON)
        let data = try XCTUnwrap(payloadString.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let obj = try XCTUnwrap(decoded as? [String: Any])

        XCTAssertEqual(
            Set(obj.keys),
            Set(["itemID", "setIndex", "setLogID"]),
            "qa-036: payload must have EXACTLY {itemID, setIndex, setLogID}; got \(obj.keys)"
        )
        XCTAssertEqual(
            obj["itemID"] as? String,
            firstLog.setLog.workoutItemID.uuidString.lowercased(),
            "itemID must be the SetLog's workoutItemID, lowercased"
        )
        XCTAssertEqual(
            obj["setLogID"] as? String,
            firstLog.setLog.id.uuidString.lowercased()
        )
        XCTAssertEqual(obj["setIndex"] as? Int, firstLog.setLog.setIndex)
    }

    // MARK: - Fixtures

    /// Build a cache with one completed workout, one exercise, one
    /// SetLog. Returns the cache and a handle to the first log +
    /// its workout id for the test to target.
    ///
    /// Callers can pass an explicit `setLogID` to pin a known id on the
    /// seeded SetLog — `testHistoryEditUsesExistingSetLogIdForIdempotentUpsert`
    /// uses that to assert the edit push carries the ORIGINAL id rather
    /// than a freshly generated one (bug-040).
    private func makeSingleLogFixture(
        setLogID: UUID = UUID()
    ) throws -> (FakeHistoryCache, LogHandle) {
        let (userID, workoutID, blockID, itemID, exerciseID) =
            (UUID(), UUID(), UUID(), UUID(), UUID())
        let completedAt = now
        let workout = Workout(
            id: workoutID, userID: userID, name: "Push A",
            scheduledDate: completedAt, status: .completed, source: .claude,
            notes: nil,
            createdAt: completedAt, updatedAt: completedAt,
            completedAt: completedAt,
            tagsJSON: #"["push_day"]"#
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":100}"#
        )
        let log = SetLog(
            id: setLogID, workoutItemID: itemID, performedExerciseID: nil,
            setIndex: 1, reps: 5, weight: 100, weightUnit: .kg, rir: 2,
            isWarmup: false,
            startedAt: completedAt.addingTimeInterval(-60),
            completedAt: completedAt,
            notes: nil
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            blocksByWorkout: [workoutID: [block]],
            itemsByBlock: [blockID: [item]],
            exercises: [Exercise(id: exerciseID, name: "Bench Press")],
            setLogsByWorkout: [workoutID: [log]]
        )
        return (cache, LogHandle(workoutID: workoutID, setLog: log))
    }

    private struct LogHandle {
        let workoutID: UUID
        let setLog: SetLog
    }
}

// MARK: - Recorders

/// Actor-isolated recorder for the edit push hook. Parallels Execution's
/// `EnqueueRecorder` but only cares about the edit SetLogs.
private actor EditRecorder {
    private(set) var pushed: [SetLog] = []

    func append(_ log: SetLog) {
        pushed.append(log)
    }
}

/// Synchronous telemetry recorder for History tests. Mirrors
/// Execution's `TelemetryRecorder`. `NSLock`-guarded so a future caller
/// that emits from a background task still sees consistent state.
final class HistoryTelemetryRecorder: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func emit(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(event)
    }
}
