// main.swift — entry point for `swift run SyncTests`.
//
// Covers the ten required cases in the chunk spec:
//   1. PullService success
//   2. PullService 401 → SyncError.tokenRejected + ConnectionManager state
//   3. PullService network error
//   4. PullService decode error
//   5. PushQueue enqueue + flush success
//   6. PushQueue flush with transient 503
//   7. PushQueue flush with 401
//   8. PushQueue idempotency
//   9. DTOMapping round-trip from sync_pull_response.json fixture
//  10. ConnectionState transitions

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
import WorkoutDBSchema
import Sync

// MARK: - Shared helpers

private func uuid(_ hex: String) -> UUID {
    guard let u = UUID(uuidString: hex) else {
        fatalError("bad UUID literal: \(hex)")
    }
    return u
}

private func iso8601(_ string: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: string) { return d }
    let g = ISO8601DateFormatter()
    g.formatOptions = [.withInternetDateTime]
    return g.date(from: string) ?? Date(timeIntervalSince1970: 0)
}

private func encodedFixture() -> Data {
    // A minimal SyncPullResponse with valid UUIDs in every slot. Used as the
    // success-path pull fixture.
    let wid = "11111111-1111-1111-1111-111111111111"
    let uid = "22222222-2222-2222-2222-222222222222"
    let xid = "33333333-3333-3333-3333-333333333333"
    let bid = "44444444-4444-4444-4444-444444444444"
    let iid = "55555555-5555-5555-5555-555555555555"
    let pid = "66666666-6666-6666-6666-666666666666"
    let sid = "77777777-7777-7777-7777-777777777777"
    let json = """
    {
      "workouts": [
        {
          "id": "\(wid)",
          "user_id": "\(uid)",
          "name": "Pull A",
          "scheduled_date": "2026-04-18",
          "status": "planned",
          "source": "claude",
          "notes": null,
          "tags_json": null,
          "created_at": "2026-04-17T07:00:00Z",
          "updated_at": "2026-04-17T07:00:00Z",
          "completed_at": null,
          "blocks": [
            {
              "id": "\(bid)",
              "position": 0,
              "parent_block_id": null,
              "name": "Main",
              "timing_mode": "straight_sets",
              "timing_config_json": "{}",
              "rounds": null,
              "rounds_rep_scheme_json": null,
              "notes": null,
              "workout_items": [
                {
                  "id": "\(iid)",
                  "position": 0,
                  "exercise_id": "\(xid)",
                  "prescription_json": "{\\"sets\\":5,\\"reps\\":5}",
                  "alternatives": []
                }
              ]
            }
          ]
        }
      ],
      "exercises": [
        {
          "id": "\(xid)",
          "name": "Back Squat",
          "notes": null,
          "demo_url": null
        }
      ],
      "user_parameters": [
        {
          "id": "\(pid)",
          "user_id": "\(uid)",
          "key": "bodyweight_kg",
          "value": "81.5",
          "updated_at": "2026-04-17T07:00:00Z",
          "source": "claude"
        }
      ],
      "last_performed": [
        {
          "exercise_id": "\(xid)",
          "last_set_logs": [
            {
              "id": "\(sid)",
              "workout_item_id": "\(iid)",
              "performed_exercise_id": null,
              "set_index": 1,
              "reps": 5,
              "weight": 100.0,
              "weight_unit": "kg",
              "duration_sec": null,
              "distance_m": null,
              "rir": 2,
              "is_warmup": false,
              "started_at": null,
              "completed_at": "2026-04-10T07:15:00Z",
              "hr_avg_bpm": 142,
              "hr_max_bpm": 168,
              "cadence_avg_spm": null,
              "motion_samples_ref": null,
              "notes": null
            }
          ],
          "prescription_json": "{\\"sets\\":5}"
        }
      ],
      "server_time": "2026-04-17T08:00:00Z"
    }
    """
    return json.data(using: .utf8)!
}

// MARK: - 1. PullService success

runAsyncCase("PullService success — maps DTOs to Domain") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: encodedFixture()))
    ])
    let service = PullService(transport: transport)
    let result = try await service.pull(since: nil, bearerToken: "tok")

    try expectEqual(result.exercises.count, 1)
    try expectEqual(result.exercises[0].name, "Back Squat")
    try expectEqual(result.userParameters.count, 1)
    try expectEqual(result.userParameters[0].key, "bodyweight_kg")
    try expectEqual(result.workouts.count, 1)
    try expectEqual(result.workouts[0].workout.name, "Pull A")
    try expectEqual(result.workouts[0].blocks.count, 1)
    try expectEqual(result.workouts[0].blocks[0].timingMode, .straightSets)
    try expectEqual(result.workouts[0].items.count, 1)
    try expectEqual(result.lastPerformed.count, 1)
    try expectEqual(result.lastPerformed[0].lastSetLogs.count, 1)
    try expectEqual(result.lastPerformed[0].lastSetLogs[0].rir, 2)
    try expectEqual(result.serverTime, iso8601("2026-04-17T08:00:00Z"))

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].method, "GET")
    try expectEqual(calls[0].path, "/api/sync/pull")
    try expectEqual(calls[0].bearerToken, "tok")
}

// MARK: - 2. PullService 401

runAsyncCase("PullService 401 → SyncError.tokenRejected and ConnectionManager transitions") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 401, body: Data()))
    ])
    let connection = ConnectionManager()
    let service = PullService(transport: transport)

    do {
        _ = try await service.pull(since: nil, bearerToken: "tok")
        try expect(false, "expected tokenRejected throw")
    } catch let err as SyncError {
        try expect(err == .tokenRejected, "expected .tokenRejected, got \(err)")
    }

    // Wire the error through to the manager (what SyncAPI does in production).
    await connection.observe(.tokenRejected)
    let state = await connection.state
    try expect(state == .tokenRejected, "state should be .tokenRejected, got \(state)")
    let allowed = await connection.allowsRequests
    try expect(!allowed, "tokenRejected should block further requests")
}

// MARK: - 3. PullService network error

runAsyncCase("PullService network error → SyncError.network + .offline state") {
    let transport = FakeTransport(outcomes: [.throwURLError])
    let connection = ConnectionManager()
    let service = PullService(transport: transport)

    do {
        _ = try await service.pull(since: nil, bearerToken: "tok")
        try expect(false, "expected network throw")
    } catch let err as SyncError {
        if case .network = err {} else {
            try expect(false, "expected .network, got \(err)")
        }
    }

    await connection.observe(.networkFailed)
    let state = await connection.state
    try expect(state == .offline, "state should be .offline")
}

// MARK: - 4. PullService decode error

runAsyncCase("PullService decode error — garbage 200 body") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data("not json".utf8)))
    ])
    let service = PullService(transport: transport)
    do {
        _ = try await service.pull(since: nil, bearerToken: "tok")
        try expect(false, "expected decode throw")
    } catch let err as SyncError {
        if case .decode = err {} else {
            try expect(false, "expected .decode, got \(err)")
        }
    }
}

// MARK: - 5. PushQueue enqueue + flush success

private func makeLog(id: UUID = UUID(), setIndex: Int = 1) -> CoreDomain.SetLog {
    CoreDomain.SetLog(
        id: id,
        workoutItemID: uuid("44444444-4444-4444-4444-444444444444"),
        performedExerciseID: nil,
        setIndex: setIndex,
        reps: 5,
        weight: 100,
        weightUnit: .kg,
        rir: 2,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
}

runAsyncCase("PushQueue enqueue + flush — both items accepted, queue drains") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueueSetLogs([makeLog(setIndex: 1)])
    try await queue.enqueueSetLogs([makeLog(setIndex: 2)])

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 2)
    try expectEqual(result.remaining, 0)
    try expect(!result.tokenRejected, "no 401 expected")
    try expect(!result.networkFailed, "no network failure expected")
    let isEmpty = try await store.isEmpty()
    try expect(isEmpty, "queue should be empty after successful flush")
}

// MARK: - 6. PushQueue flush with transient 503

runAsyncCase("PushQueue flush — first 200, second 503: first removed, second retained") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
        .response(HTTPResponse(status: 503, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let firstLog = makeLog(setIndex: 1)
    let secondLog = makeLog(setIndex: 2)
    try await queue.enqueueSetLogs([firstLog])
    try await queue.enqueueSetLogs([secondLog])

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 1)
    try expectEqual(result.remaining, 1)
    try expect(result.networkFailed, "should flag network failure on 503")
    try expect(!result.tokenRejected, "503 is not a token failure")

    let remaining = await store.all()
    try expectEqual(remaining.count, 1)
    try expectEqual(remaining[0].attempts, 1)
    if case .setLogs(let logs) = remaining[0].payload {
        try expectEqual(logs.first?.setIndex, 2)
    } else {
        try expect(false, "expected setLogs payload")
    }
}

// MARK: - 7. PushQueue flush with 401

runAsyncCase("PushQueue flush — 401 leaves everything queued, flags tokenRejected") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 401, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)
    try await queue.enqueueSetLogs([makeLog(setIndex: 1)])
    try await queue.enqueueSetLogs([makeLog(setIndex: 2)])

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 0)
    try expect(result.tokenRejected, "expected tokenRejected=true")
    let all = await store.all()
    try expectEqual(all.count, 2, "401 must not drop any items")
}

// MARK: - 8. PushQueue idempotency

runAsyncCase("PushQueue idempotency — re-flushing against accepting transport is stable") {
    let store = FakePushQueueStore()
    // Give plenty of slots — more than we need. The queue will drain in one
    // call; a second flush has nothing to do.
    let transport = FakeTransport(outcomes: Array(
        repeating: FakeOutcome.response(HTTPResponse(status: 200, body: Data())),
        count: 4
    ))
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueueSetLogs([makeLog(setIndex: 1)])
    try await queue.enqueueSetLogs([makeLog(setIndex: 2)])

    let first = try await queue.flush(bearerToken: "tok")
    try expectEqual(first.pushed, 2)
    let emptyAfterFirst = try await store.isEmpty()
    try expect(emptyAfterFirst, "queue drained after first flush")

    let second = try await queue.flush(bearerToken: "tok")
    try expectEqual(second.pushed, 0, "nothing to push on second flush")
    try expectEqual(second.remaining, 0)
    let emptyAfterSecond = try await store.isEmpty()
    try expect(emptyAfterSecond, "still empty after second flush")
}

// MARK: - 9. DTOMapping round-trip from fixture

runAsyncCase("DTOMapping — full sync_pull_response.json fixture maps with full fidelity") {
    // With UUID-shaped ids throughout the fixture (per Chunk 9), we can now
    // push the entire pull response through the DTO → Domain mapper via
    // `PullService.mapResponse`'s logic. That used to be blocked by slug-shaped
    // exercise ids in the fixture.
    let raw = try FixtureLoader.loadData("sync_pull_response.json")
    let decoder = JSONDecoder.workoutDB()
    let pull = try decoder.decode(WorkoutDBSchema.SyncPullResponse.self, from: raw)

    // Exercises: canonical "back-squat" UUID is the one we seeded in the fixture.
    try expectEqual(pull.exercises.count, 1)
    let exerciseResult = DTOMapping.mapExercise(pull.exercises[0])
    let mappedExercise: CoreDomain.Exercise
    switch exerciseResult {
    case .success(let ex): mappedExercise = ex
    case .failure(let err): throw err
    }
    try expectEqual(mappedExercise.id, uuid("e0000001-0000-4000-8000-000000000001"))
    try expectEqual(mappedExercise.name, "Back Squat")

    // User parameters: single bodyweight row.
    try expectEqual(pull.userParameters.count, 1)
    let paramResult = DTOMapping.mapUserParameter(pull.userParameters[0])
    let mappedParam: CoreDomain.UserParameter
    switch paramResult {
    case .success(let p): mappedParam = p
    case .failure(let err): throw err
    }
    try expectEqual(mappedParam.id, uuid("66666666-6666-6666-6666-666666666666"))
    try expectEqual(mappedParam.userID, uuid("22222222-2222-2222-2222-222222222222"))
    try expectEqual(mappedParam.key, "bodyweight_kg")
    try expectEqual(mappedParam.value, "81.5")
    try expectEqual(mappedParam.source, .claude)

    // last_performed: one entry for back-squat with one SetLog.
    try expectEqual(pull.lastPerformed.count, 1)
    let lp = pull.lastPerformed[0]
    try expectEqual(lp.exerciseId, "e0000001-0000-4000-8000-000000000001")
    try expectEqual(lp.lastSetLogs.count, 1)

    let setLogResult = DTOMapping.mapSetLog(lp.lastSetLogs[0])
    let mappedLog: CoreDomain.SetLog
    switch setLogResult {
    case .success(let log): mappedLog = log
    case .failure(let err): throw err
    }
    try expectEqual(mappedLog.id, uuid("77777777-7777-7777-7777-777777777777"))
    try expectEqual(mappedLog.workoutItemID, uuid("44444444-4444-4444-4444-444444444444"))
    try expect(mappedLog.performedExerciseID == nil, "performed_exercise_id should be nil")
    try expectEqual(mappedLog.setIndex, 1)
    try expectEqual(mappedLog.reps, 5)
    try expectEqual(mappedLog.weight, 100.0)
    try expectEqual(mappedLog.weightUnit, .kg)
    try expectEqual(mappedLog.rir, 2)
    try expect(!mappedLog.isWarmup, "is_warmup false in fixture")
    try expectEqual(mappedLog.completedAt, iso8601("2026-04-10T07:15:00Z"))
    try expectEqual(mappedLog.hrAvgBpm, 142)
    try expectEqual(mappedLog.hrMaxBpm, 168)
    try expect(mappedLog.cadenceAvgSpm == nil)
    try expect(mappedLog.notes == nil)

    // Round-trip the set log back to the wire and confirm the shape survives.
    let roundtrip = DTOMapping.toDTO(mappedLog)
    try expectEqual(roundtrip.id, lp.lastSetLogs[0].id)
    try expectEqual(roundtrip.workoutItemId, lp.lastSetLogs[0].workoutItemId)
    try expectEqual(roundtrip.rir, lp.lastSetLogs[0].rir)
    try expectEqual(roundtrip.weightUnit, lp.lastSetLogs[0].weightUnit)

    // Workouts slot is empty in this fixture — confirm the mapper handles that cleanly.
    try expectEqual(pull.workouts.count, 0)

    // Also exercise the full-workout mapping via the `workout_create.json` fixture,
    // which has nested blocks / items / alternatives — the code path that used to
    // be blocked by slug-shaped exercise ids.
    let workoutRaw = try FixtureLoader.loadData("workout_create.json")
    let workoutDTO = try decoder.decode(WorkoutDBSchema.Workout.self, from: workoutRaw)
    let workoutResult = DTOMapping.mapWorkout(workoutDTO)
    let mappedWorkout: MappedWorkout
    switch workoutResult {
    case .success(let mw): mappedWorkout = mw
    case .failure(let err): throw err
    }
    try expectEqual(mappedWorkout.workout.id, uuid("11111111-1111-1111-1111-111111111111"))
    try expectEqual(mappedWorkout.workout.userID, uuid("22222222-2222-2222-2222-222222222222"))
    try expectEqual(mappedWorkout.workout.name, "Tuesday Legs")
    try expectEqual(mappedWorkout.workout.status, .planned)
    try expectEqual(mappedWorkout.workout.source, .claude)
    try expectEqual(mappedWorkout.blocks.count, 1)
    try expectEqual(mappedWorkout.blocks[0].id, uuid("33333333-3333-3333-3333-333333333333"))
    try expectEqual(mappedWorkout.blocks[0].timingMode, .straightSets)
    try expectEqual(mappedWorkout.items.count, 1)
    try expectEqual(mappedWorkout.items[0].id, uuid("44444444-4444-4444-4444-444444444444"))
    try expectEqual(mappedWorkout.items[0].exerciseID, uuid("e0000001-0000-4000-8000-000000000001"))
    try expectEqual(mappedWorkout.alternatives.count, 1)
    try expectEqual(mappedWorkout.alternatives[0].id, uuid("55555555-5555-5555-5555-555555555555"))
    try expectEqual(mappedWorkout.alternatives[0].exerciseID, uuid("e0000002-0000-4000-8000-000000000002"))
    try expectEqual(mappedWorkout.alternatives[0].workoutItemID, uuid("44444444-4444-4444-4444-444444444444"))
}

// MARK: - 10. ConnectionState transitions

runAsyncCase("ConnectionManager transitions — AsyncStream yields each change") {
    let manager = ConnectionManager()
    let stream = await manager.states()
    var iterator = stream.makeAsyncIterator()

    // Initial value yielded on subscribe.
    let initial = await iterator.next()
    try expect(initial == .offline, "initial should be .offline, got \(String(describing: initial))")

    // syncStarted → .syncing
    await manager.observe(.syncStarted)
    let syncing = await iterator.next()
    try expect(syncing == .syncing, "expected .syncing, got \(String(describing: syncing))")

    // pullSucceeded → .online(...)
    let successAt = iso8601("2026-04-17T08:00:00Z")
    await manager.observe(.pullSucceeded(at: successAt))
    let online = await iterator.next()
    if case .online(let at) = online {
        try expectEqual(at, successAt)
    } else {
        try expect(false, "expected .online, got \(String(describing: online))")
    }

    // networkFailed → .offline
    await manager.observe(.networkFailed)
    let offline = await iterator.next()
    try expect(offline == .offline, "expected .offline, got \(String(describing: offline))")

    // tokenRejected → .tokenRejected (terminal until reauthorized)
    await manager.observe(.tokenRejected)
    let tok = await iterator.next()
    try expect(tok == .tokenRejected, "expected .tokenRejected")

    // Subsequent networkFailed ignored while tokenRejected.
    await manager.observe(.networkFailed)
    let after = await manager.state
    try expect(after == .tokenRejected, "networkFailed must not clear tokenRejected")

    // reauthorized → .offline (fresh baseline).
    await manager.observe(.reauthorized)
    let reauth = await iterator.next()
    try expect(reauth == .offline, "reauthorized should drop back to offline")
}

// MARK: - Extra: SyncAPI facade smoke test

runAsyncCase("SyncAPI pullLatest wires success through ConnectionManager") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: encodedFixture()))
    ])
    let store = FakePushQueueStore()
    let api = SyncAPI(
        transport: transport,
        store: store,
        tokenProvider: { "tok" }
    )
    let result = try await api.pullLatest(since: nil)
    try expectEqual(result.exercises.count, 1)
    let state = await api.connection.state
    if case .online(let at) = state {
        try expectEqual(at, iso8601("2026-04-17T08:00:00Z"))
    } else {
        try expect(false, "expected .online, got \(state)")
    }
}

runAsyncCase("SyncAPI pullLatest routes 401 to tokenRejected") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 401, body: Data()))
    ])
    let store = FakePushQueueStore()
    let api = SyncAPI(
        transport: transport,
        store: store,
        tokenProvider: { "tok" }
    )
    do {
        _ = try await api.pullLatest(since: nil)
        try expect(false, "expected tokenRejected throw")
    } catch let err as SyncError {
        try expect(err == .tokenRejected)
    }
    let state = await api.connection.state
    try expect(state == .tokenRejected)
}

// MARK: - Telemetry push routing

runAsyncCase("PushQueue — telemetry events route to /api/telemetry/events") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let event = CoreTelemetry.Event(
        sessionID: UUID(),
        kind: "interaction",
        name: "today.start_tap"
    )
    try await queue.enqueueEvents([event])

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 1)
    try expectEqual(result.remaining, 0)

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].method, "POST")
    try expectEqual(calls[0].path, "/api/telemetry/events")
}

runAsyncCase("PushQueue — set_logs still route to /api/sync/results after event case added") {
    // Regression guard: adding `.events` must not misroute `.setLogs`.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueueSetLogs([makeLog(setIndex: 1)])
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].path, "/api/sync/results")
}

// MARK: - User parameter push routing

runAsyncCase("PushQueue — userParameter routes to /api/user-parameters") {
    // Mirrors the `.events` routing test: an enqueued .userParameter
    // must POST to /api/user-parameters with the server's UserParameterIn
    // body shape. The client owns `id` end-to-end so retries upsert on
    // id; `user_id` still stays server-derived (from the bearer token).
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let paramID = uuid("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    let param = CoreDomain.UserParameter(
        id: paramID,
        userID: uuid("22222222-2222-2222-2222-222222222222"),
        key: "bodyweight_kg",
        value: "82.5",
        updatedAt: iso8601("2026-04-17T08:00:00Z"),
        source: .appLog
    )
    try await queue.enqueueUserParameter(param)

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 1)
    try expectEqual(result.remaining, 0)

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].method, "POST")
    try expectEqual(calls[0].path, "/api/user-parameters")
    try expectEqual(calls[0].bearerToken, "tok")

    // Body must be an array of `{id, key, value, source, updated_at}` —
    // the client-owned id is REQUIRED (retry idempotency); no user_id
    // (server derives from bearer).
    guard let body = calls[0].body else {
        try expect(false, "expected body on POST")
        return
    }
    let decoder = JSONDecoder.workoutDB()
    struct WireIn: Decodable {
        let id: String
        let key: String
        let value: String
        let source: String
        let updatedAt: Date?
        enum CodingKeys: String, CodingKey {
            case id, key, value, source
            case updatedAt = "updated_at"
        }
    }
    let wire = try decoder.decode([WireIn].self, from: body)
    try expectEqual(wire.count, 1)
    try expectEqual(wire[0].id, paramID.uuidString.lowercased())
    try expectEqual(wire[0].key, "bodyweight_kg")
    try expectEqual(wire[0].value, "82.5")
    try expectEqual(wire[0].source, "app_log")
    try expectEqual(wire[0].updatedAt, iso8601("2026-04-17T08:00:00Z"))
}

// MARK: - User parameter push idempotency

runAsyncCase("UserParameter push is idempotent — same id ships twice across independent flush cycles") {
    // Replay scenario: the app commits a bodyweight row to the push
    // queue, the server responds 2xx, but the process dies before the
    // queue-remove is persisted. On next launch the queue replays the
    // same row. The DTO shipped on both calls MUST carry the same id
    // so the server's upsert-on-id path collapses the replay into a
    // no-op. Without this, the append-only `user_parameters` table
    // would carry a duplicate row forever.
    //
    // Shape of the test: enqueue → flush (succeeds, row removed) →
    // re-enqueue → flush again. Two independent flush cycles, same
    // logical id on the wire both times. This mirrors the real
    // dies-before-remove flow; two back-to-back enqueues without a flush
    // in between now collapse via the in-queue dedup (see
    // `PushQueue replace-in-place — userParameter dedup on id`), which
    // is a separate, complementary invariant.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let paramID = uuid("99999999-8888-7777-6666-555555555555")
    let param = CoreDomain.UserParameter(
        id: paramID,
        userID: uuid("22222222-2222-2222-2222-222222222222"),
        key: "bodyweight_kg",
        value: "82.5",
        updatedAt: iso8601("2026-04-17T08:00:00Z"),
        source: .appLog
    )
    // Cycle 1: enqueue → flush → server 2xx → row removed from queue.
    try await queue.enqueueUserParameter(param)
    _ = try await queue.flush(bearerToken: "tok")
    let afterFirstFlush = try await store.isEmpty()
    try expect(afterFirstFlush, "first flush drains the queue")

    // Cycle 2: the "process died before remove was persisted" replay —
    // the server already accepted this id once, but the client's queue
    // didn't know, so it re-enqueues on next launch.
    try await queue.enqueueUserParameter(param)
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 2, "both flush cycles must push")

    let decoder = JSONDecoder.workoutDB()
    struct WireIn: Decodable {
        let id: String
        let key: String
    }
    let first = try decoder.decode([WireIn].self, from: calls[0].body ?? Data())
    let second = try decoder.decode([WireIn].self, from: calls[1].body ?? Data())
    try expectEqual(first.count, 1)
    try expectEqual(second.count, 1)
    try expectEqual(first[0].id, second[0].id, "both pushes must carry same id")
    try expectEqual(first[0].id, paramID.uuidString.lowercased())
}

// MARK: - SetLog wire-id lowercasing

runAsyncCase("SetLog DTO wireID is lowercase even when Swift UUID is uppercase") {
    // Swift's `UUID.uuidString` returns UPPERCASE by default. The
    // project invariant is lowercase on the wire (server accepts either
    // via `_UuidInputBase` but the app must not drift). Regression guard
    // for bug: `DTOMapping+SetLog.swift` previously used `.uuidString`
    // directly, so outbound SetLog pushes shipped uppercase ids — the
    // class of drift that produced prior 404s on /api/telemetry before
    // `.lowercased()` was added there.
    let upperID = UUID(uuidString: "AABBCCDD-EEFF-0011-2233-445566778899")!
    try expectEqual(upperID.uuidString, "AABBCCDD-EEFF-0011-2233-445566778899")

    let log = CoreDomain.SetLog(
        id: upperID,
        workoutItemID: UUID(uuidString: "FFEEDDCC-BBAA-9988-7766-554433221100")!,
        performedExerciseID: UUID(uuidString: "11112222-3333-4444-5555-666677778888")!,
        setIndex: 1,
        reps: 5,
        weight: 100,
        weightUnit: .kg,
        rir: 2,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
    let dto = DTOMapping.toDTO(log)
    try expectEqual(dto.id, "aabbccdd-eeff-0011-2233-445566778899")
    try expectEqual(dto.workoutItemId, "ffeeddcc-bbaa-9988-7766-554433221100")
    try expectEqual(dto.performedExerciseId, "11112222-3333-4444-5555-666677778888")

    // Also round-trip the DTO through JSON encode so any future codec
    // re-casing layer would be caught. The encoded body's `id` field
    // must be lowercase.
    let encoder = JSONEncoder.workoutDB()
    let payload = WorkoutDBSchema.SyncResultsPayload(setLogs: [dto], statusUpdates: [])
    let data = try encoder.encode(payload)
    guard let json = String(data: data, encoding: .utf8) else {
        try expect(false, "expected utf8-decodable body")
        return
    }
    try expect(
        !json.contains("AABBCCDD"),
        "encoded JSON must not carry uppercase id substring: \(json)"
    )
    try expect(
        json.contains("aabbccdd-eeff-0011-2233-445566778899"),
        "encoded JSON should carry the lowercase id: \(json)"
    )
}

// MARK: - Status update wire-id lowercasing

runAsyncCase("Status update DTO workoutId is lowercase") {
    // Same invariant check as SetLog — status updates were the other
    // outbound site that emitted uppercase. Drive it through the queue
    // so we also verify the encode-for-push path routes correctly.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let upperID = UUID(uuidString: "DEADBEEF-1234-5678-9ABC-DEF012345678")!
    try await queue.enqueueStatusUpdate(
        workoutID: upperID,
        status: .completed,
        completedAt: iso8601("2026-04-17T08:30:00Z")
    )
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    guard let body = calls[0].body,
          let json = String(data: body, encoding: .utf8) else {
        try expect(false, "expected body on POST")
        return
    }
    try expect(
        !json.contains("DEADBEEF"),
        "status update must not carry uppercase id: \(json)"
    )
    try expect(
        json.contains("deadbeef-1234-5678-9abc-def012345678"),
        "status update must carry lowercase id: \(json)"
    )
}

runAsyncCase("Status update carries notes on the wire so the server persists them") {
    // Regression: the terminal status push previously dropped the user's
    // post-workout note. The local cache held it, but the workout's
    // `updated_at` bumped (status flipped), so the next sync/pull
    // overwrote the note with the server's stale nil value. The fix
    // rides `notes` on `WorkoutStatusUpdate` so the server persists.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueueStatusUpdate(
        workoutID: uuid("11111111-2222-3333-4444-555555555555"),
        status: .completed,
        completedAt: iso8601("2026-04-17T08:30:00Z"),
        notes: "leg day PR!"
    )
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    guard let body = calls[0].body else {
        try expect(false, "expected body on POST")
        return
    }
    let decoder = JSONDecoder.workoutDB()
    let payload = try decoder.decode(WorkoutDBSchema.SyncResultsPayload.self, from: body)
    try expectEqual(payload.statusUpdates.count, 1)
    try expectEqual(payload.statusUpdates[0].notes, "leg day PR!")
}

// MARK: - Priority ordering (telemetry ≻ results isolation)

runAsyncCase("PushQueue drains results (priority 0) before telemetry (priority 1) in one flush") {
    // Regression guard: a verbose-mode telemetry burst enqueued BEFORE
    // a set log used to shove the log behind a long chronological tail.
    // The PushItem `priority` field + sort-by-priority-then-enqueuedAt
    // in `peek` now guarantees result payloads flush first. Telemetry
    // still ships the same cycle — just after every queued result.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: Array(
        repeating: FakeOutcome.response(HTTPResponse(status: 200, body: Data())),
        count: 4
    ))
    let queue = PushQueue(store: store, transport: transport)

    // Order-of-enqueue: two old telemetry events, then one fresh set
    // log, then one more telemetry event. If we sorted by enqueuedAt
    // alone, the set log would land third. Priority weighting must
    // pull it to position one.
    try await queue.enqueueEvents([
        CoreTelemetry.Event(
            timestamp: iso8601("2026-04-17T07:00:00Z"),
            sessionID: UUID(),
            kind: "state",
            name: "debug.verbose.1"
        )
    ])
    try await queue.enqueueEvents([
        CoreTelemetry.Event(
            timestamp: iso8601("2026-04-17T07:00:01Z"),
            sessionID: UUID(),
            kind: "state",
            name: "debug.verbose.2"
        )
    ])
    try await queue.enqueueSetLogs([makeLog(setIndex: 1)])
    try await queue.enqueueEvents([
        CoreTelemetry.Event(
            timestamp: iso8601("2026-04-17T07:00:02Z"),
            sessionID: UUID(),
            kind: "state",
            name: "debug.verbose.3"
        )
    ])

    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 4, "all four items must flush")

    // First call MUST be the set_log results endpoint. Prior to the
    // priority fix this was position 3 (chronological after the two
    // older telemetry events).
    try expectEqual(calls[0].path, "/api/sync/results", "result pushed first")
    // The remaining three calls are all telemetry — they trail in
    // enqueuedAt order among themselves (FIFO within a priority class).
    try expectEqual(calls[1].path, "/api/telemetry/events")
    try expectEqual(calls[2].path, "/api/telemetry/events")
    try expectEqual(calls[3].path, "/api/telemetry/events")
}

runAsyncCase("PushItem.priority derived from payload case") {
    // Shape check: every results-class payload is priority 0; telemetry
    // is priority 1. Codifies the contract so a future payload case
    // added without touching `PushItem.Payload.priority` would fail
    // loudly here — the switch is exhaustive.
    let log = makeLog()
    let results = PushItem(payload: .setLogs([log]), enqueuedAt: Date())
    try expectEqual(results.priority, 0)

    let status = PushItem(
        payload: .statusUpdate(
            workoutID: UUID(),
            status: .completed,
            completedAt: nil,
            notes: nil
        ),
        enqueuedAt: Date()
    )
    try expectEqual(status.priority, 0)

    let param = PushItem(
        payload: .userParameter(CoreDomain.UserParameter(
            id: UUID(),
            userID: UUID(),
            key: "k",
            value: "v",
            updatedAt: Date(),
            source: .appLog
        )),
        enqueuedAt: Date()
    )
    try expectEqual(param.priority, 0)

    let event = PushItem(
        payload: .events([CoreTelemetry.Event(sessionID: UUID(), kind: "x", name: "y")]),
        enqueuedAt: Date()
    )
    try expectEqual(event.priority, 1)
}

runAsyncCase("PushQueue — telemetry body decodes as TelemetryEventsPayload with events in it") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let sessionID = UUID()
    let event = CoreTelemetry.Event(
        sessionID: sessionID,
        kind: "state",
        name: "execution.session_mutation",
        dataJSON: #"{"mutation":"start"}"#
    )
    try await queue.enqueueEvents([event])
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    guard let body = calls.first?.body else {
        try expect(false, "expected body on POST")
        return
    }
    let decoder = JSONDecoder.workoutDB()
    let payload = try decoder.decode(WorkoutDBSchema.TelemetryEventsPayload.self, from: body)
    try expectEqual(payload.events.count, 1)
    try expectEqual(payload.events[0].name, "execution.session_mutation")
    try expectEqual(payload.events[0].kind, "state")
    try expectEqual(payload.events[0].sessionId, sessionID.uuidString.lowercased())
    try expectEqual(payload.events[0].dataJson, #"{"mutation":"start"}"#)
}

// MARK: - Replace-in-place on enqueue (logical dedup)

runAsyncCase("PushQueue replace-in-place — enqueueing same SetLog id twice collapses to one entry with latest payload") {
    // Regression for "no logical dedup; unknown envelope kind stalls the
    // whole queue" — the dedup half. Without this, a just-logged set
    // edited a second later before the queue flushes would leave two
    // `.setLogs` rows queued: the stale first push and the fresh second.
    // On flush the stale one lands first and transiently overwrites the
    // corrected bytes on the server until the fresh one resolves.
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )

    let setLogID = uuid("abcdef01-2345-6789-abcd-ef0123456789")
    let first = CoreDomain.SetLog(
        id: setLogID,
        workoutItemID: uuid("44444444-4444-4444-4444-444444444444"),
        performedExerciseID: nil,
        setIndex: 3,
        reps: 5,
        weight: 100,
        weightUnit: .kg,
        rir: 2,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
    let corrected = CoreDomain.SetLog(
        id: setLogID,  // SAME id — logical identity
        workoutItemID: first.workoutItemID,
        performedExerciseID: nil,
        setIndex: 3,
        reps: 8,       // corrected rep count
        weight: 102.5, // corrected load
        weightUnit: .kg,
        rir: 1,
        completedAt: iso8601("2026-04-17T08:00:30Z")
    )

    try await queue.enqueueSetLogs([first])
    try await queue.enqueueSetLogs([corrected])

    let all = await store.all()
    try expectEqual(all.count, 1, "logical dedup by SetLog id must collapse to one entry")
    if case .setLogs(let logs) = all[0].payload {
        try expectEqual(logs.count, 1)
        try expectEqual(logs[0].id, setLogID)
        try expectEqual(logs[0].reps, 8, "latest payload wins")
        try expectEqual(logs[0].weight, 102.5)
        try expectEqual(logs[0].rir, 1)
    } else {
        try expect(false, "expected setLogs payload")
    }
}

runAsyncCase("PushQueue replace-in-place — statusUpdate dedup on (workoutID, status)") {
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )

    let workoutID = uuid("11111111-2222-3333-4444-555555555555")
    try await queue.enqueueStatusUpdate(
        workoutID: workoutID, status: .completed,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
    try await queue.enqueueStatusUpdate(
        workoutID: workoutID, status: .completed,
        completedAt: iso8601("2026-04-17T08:01:00Z")  // newer completedAt
    )

    let all = await store.all()
    try expectEqual(all.count, 1, "status update dedup must collapse to one entry")
    if case .statusUpdate(_, let status, let completedAt, _) = all[0].payload {
        try expectEqual(status, .completed)
        try expectEqual(completedAt, iso8601("2026-04-17T08:01:00Z"))
    } else {
        try expect(false, "expected statusUpdate payload")
    }
}

runAsyncCase("PushQueue replace-in-place — userParameter dedup on id") {
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )

    let paramID = uuid("99999999-aaaa-bbbb-cccc-dddddddddddd")
    let v1 = CoreDomain.UserParameter(
        id: paramID,
        userID: uuid("22222222-2222-2222-2222-222222222222"),
        key: "bodyweight_kg",
        value: "81.0",
        updatedAt: iso8601("2026-04-17T08:00:00Z"),
        source: .appLog
    )
    let v2 = CoreDomain.UserParameter(
        id: paramID,  // SAME id
        userID: v1.userID,
        key: "bodyweight_kg",
        value: "82.5",  // updated value
        updatedAt: iso8601("2026-04-17T08:05:00Z"),
        source: .appLog
    )

    try await queue.enqueueUserParameter(v1)
    try await queue.enqueueUserParameter(v2)

    let all = await store.all()
    try expectEqual(all.count, 1, "userParameter dedup must collapse to one entry")
    if case .userParameter(let param) = all[0].payload {
        try expectEqual(param.value, "82.5", "latest payload wins")
    } else {
        try expect(false, "expected userParameter payload")
    }
}

// MARK: - PushFlusher / PushQueue backoff + dead-letter (2026-04-18 P2)

/// Test-only emitter that captures every event synchronously. Backed by a
/// `DispatchQueue` lock because `TelemetryEmitter.emit` is non-async.
final class RecordingTelemetryEmitter: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [CoreTelemetry.Event] = []

    func emit(_ event: CoreTelemetry.Event) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(event)
    }

    func events() -> [CoreTelemetry.Event] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}

runCase("PushBackoff.nextDelay — scheduled backoff, plateau at 300s") {
    // Regression for "PushFlusher fixed 60s cadence": each retry must
    // wait longer than the last until the plateau. This is the unit-level
    // shape of the fix that `testPushFlusherBackoffAfterTransientFailure`
    // leans on: the flusher's loop reads these values to size its sleep.
    try expectEqual(PushBackoff.nextDelay(forAttempts: 0), 10)
    try expectEqual(PushBackoff.nextDelay(forAttempts: 1), 30)
    try expectEqual(PushBackoff.nextDelay(forAttempts: 2), 60)
    try expectEqual(PushBackoff.nextDelay(forAttempts: 3), 120)
    try expectEqual(PushBackoff.nextDelay(forAttempts: 4), 300)
    try expectEqual(PushBackoff.nextDelay(forAttempts: 5), 300, "plateau")
    try expectEqual(PushBackoff.nextDelay(forAttempts: 100), 300, "plateau holds")
    // Strict monotonic until the plateau.
    try expect(
        PushBackoff.nextDelay(forAttempts: 1) > PushBackoff.nextDelay(forAttempts: 0),
        "second attempt must wait longer than first"
    )
    try expect(
        PushBackoff.nextDelay(forAttempts: 2) > PushBackoff.nextDelay(forAttempts: 1),
        "third attempt must wait longer than second"
    )
}

runAsyncCase("PushFlusherBackoffAfterTransientFailure — 503 extends the next sleep") {
    // Scripted transport returns 503. Drive two flush cycles with the
    // same enqueued item and read the counter-driven next-sleep off
    // `PushBackoff`: it must strictly grow from attempt 1 to attempt 2.
    // This is the queue-wide backoff lever the loop reads.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 503, body: Data())),
        .response(HTTPResponse(status: 503, body: Data())),
    ])
    let api = SyncAPI(
        transport: transport,
        store: store,
        tokenProvider: { "tok" }
    )
    try await api.pushLog([makeLog(setIndex: 1)])

    let first = try await api.flushPushQueue()
    try expect(first.networkFailed, "first 503 must flag networkFailed")
    let delayAfterFirst = PushBackoff.nextDelay(forAttempts: 1)

    let second = try await api.flushPushQueue()
    try expect(second.networkFailed, "second 503 must also fail")
    let delayAfterSecond = PushBackoff.nextDelay(forAttempts: 2)

    try expect(
        delayAfterSecond > delayAfterFirst,
        "second attempt must wait longer than first: \(delayAfterFirst) vs \(delayAfterSecond)"
    )
}

runAsyncCase("PushFlusherDeadLettersPersistent4xxAfter5Attempts — 422 drops + telemetry fires") {
    // The core of the fix: a persistent 4xx (e.g. 422 validation) must
    // not park the item forever. After `PushBackoff.deadLetterThreshold`
    // consecutive 422s the queue drops the row and emits a
    // `execution.push_item_dead_lettered` event. This guards the "head
    // of queue stuck on a bad body" failure mode.
    //
    // The event must also carry a correlation id (`set_log_id` here)
    // so an operator can trace the dropped row back to the specific
    // SetLog; `payload_kind` + `http_status` + `attempts` alone aren't
    // enough to find the body that broke.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: Array(
        repeating: FakeOutcome.response(HTTPResponse(status: 422, body: Data())),
        count: 6
    ))
    let recorder = RecordingTelemetryEmitter()
    let queue = PushQueue(
        store: store,
        transport: transport,
        telemetry: recorder
    )
    let logID = uuid("cafe0001-0000-4000-8000-000000000001")
    let log = makeLog(id: logID, setIndex: 1)
    try await queue.enqueueSetLogs([log])

    // Flush N times — the queue retries the same item each call because
    // the fake transport keeps feeding 422s. After 5 attempts the row
    // must be gone.
    for _ in 0..<5 {
        _ = try await queue.flush(bearerToken: "tok")
    }

    let isEmpty = try await store.isEmpty()
    try expect(isEmpty, "dead-lettered item must be dropped from the store")

    let events = recorder.events()
    let deadLetters = events.filter { $0.name == "execution.push_item_dead_lettered" }
    try expectEqual(deadLetters.count, 1, "exactly one dead-letter event")
    let deadLetter = deadLetters[0]
    try expectEqual(deadLetter.kind, "state")
    guard let json = deadLetter.dataJSON else {
        try expect(false, "dead-letter event must carry dataJSON")
        return
    }
    try expect(
        json.contains("\"payload_kind\":\"set_logs\""),
        "dead-letter data must name the payload kind: \(json)"
    )
    try expect(
        json.contains("\"http_status\":422"),
        "dead-letter data must record the HTTP status: \(json)"
    )
    try expect(
        json.contains("\"attempts\":5"),
        "dead-letter data must record the attempt count: \(json)"
    )
    try expect(
        json.contains("\"set_log_id\":\"\(logID.wireID)\""),
        "dead-letter data must carry set_log_id for correlation: \(json)"
    )
}

runAsyncCase("PushFlusherResetsBackoffOnFreshEnqueue — new item starts with a fresh counter") {
    // After several 422s on one item, enqueue a fresh item. The new item
    // has its own PushItem.id, so its dead-letter counter starts at 0 —
    // a stuck bad body must not poison the first try of a new log.
    //
    // Tested via behavior (not by peeking internal state): after the
    // first item dead-letters at attempt 5, a subsequently enqueued
    // second item that also gets a 422 must NOT dead-letter on its
    // first flush — which would be the observable symptom of a shared /
    // queue-wide counter. The second dead-letter (if any) must be a
    // distinct event for a distinct item.
    let store = FakePushQueueStore()
    // Enough 422s to burn through one full dead-letter cycle on the
    // first item (5 attempts) plus one attempt on the second item.
    let transport = FakeTransport(outcomes: Array(
        repeating: FakeOutcome.response(HTTPResponse(status: 422, body: Data())),
        count: 6
    ))
    let recorder = RecordingTelemetryEmitter()
    let queue = PushQueue(
        store: store,
        transport: transport,
        telemetry: recorder
    )
    let firstLog = makeLog(setIndex: 1)
    try await queue.enqueueSetLogs([firstLog])

    // Burn through the full dead-letter cycle on the first item.
    for _ in 0..<PushBackoff.deadLetterThreshold {
        _ = try await queue.flush(bearerToken: "tok")
    }

    // First item should have dead-lettered and been removed.
    let isEmptyAfterFirst = try await store.isEmpty()
    try expect(isEmptyAfterFirst, "first item dead-lettered out of the queue")
    let firstDeadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(firstDeadLetters.count, 1, "one dead-letter so far")

    // Fresh enqueue with a new SetLog id — this gets a new PushItem.id.
    let secondLog = makeLog(setIndex: 2)
    try await queue.enqueueSetLogs([secondLog])

    // One 422 attempt on the second item.
    _ = try await queue.flush(bearerToken: "tok")

    // Behavioral assertion: the second item must still be in the queue
    // after a single failed attempt. A queue-wide counter (which the
    // fix rejects) would dead-letter immediately because the shared
    // counter was already at threshold.
    let stillQueued = try await store.isEmpty()
    try expect(
        !stillQueued,
        "second item must survive its first 422 — counter is per-item, not queue-wide"
    )

    // And the telemetry record must still show exactly one dead-letter
    // (the original item), not two.
    let laterDeadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(
        laterDeadLetters.count, 1,
        "fresh item at 1 attempt must not trigger a second dead-letter"
    )
}

runAsyncCase("PushFlusher401StillTriggersTokenRejected — not a dead-letter path") {
    // 401 must keep its existing `.tokenRejected` semantics and never
    // dead-letter the row. Reauth replaces the bearer and the same row
    // ships again — we must not drop the user's data because the token
    // expired.
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: Array(
        repeating: FakeOutcome.response(HTTPResponse(status: 401, body: Data())),
        count: 10
    ))
    let recorder = RecordingTelemetryEmitter()
    let queue = PushQueue(
        store: store,
        transport: transport,
        telemetry: recorder
    )
    try await queue.enqueueSetLogs([makeLog(setIndex: 1)])

    // Run a batch of flushes well past the dead-letter threshold.
    for _ in 0..<PushBackoff.deadLetterThreshold + 2 {
        let result = try await queue.flush(bearerToken: "tok")
        try expect(result.tokenRejected, "401 must surface as tokenRejected")
    }

    // The row must still be in the queue — 401 preserves data.
    let isEmpty = try await store.isEmpty()
    try expect(!isEmpty, "401 must not dead-letter the item")

    // And no dead-letter event must have fired.
    let deadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(deadLetters.count, 0, "401 must not emit dead-letter telemetry")
}

runAsyncCase("PushQueue replace-in-place — does NOT touch telemetry events") {
    // Events are append-only diagnostics — a telemetry replay is just
    // another event row on the server. Guarding this explicitly so a
    // future change that hands a logical id to events doesn't
    // accidentally silence duplicate events.
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )
    let event = CoreTelemetry.Event(
        sessionID: UUID(),
        kind: "state",
        name: "test.event"
    )
    try await queue.enqueueEvents([event])
    try await queue.enqueueEvents([event])

    let all = await store.all()
    try expectEqual(all.count, 2, "events are not deduped — two enqueues produce two rows")
}

// MARK: - perf-002: dedup uses a scoped predicate, not a full peek

runAsyncCase("PushQueue dedup uses scoped removeMatchingDedupKey — no full-table peek on enqueue") {
    // perf-002 regression: the pre-fix code's dedup pass called
    // `store.peek(max: 10_000)` before every enqueue, decoded every
    // row, and matched in memory. The fix routes dedup through
    // `removeMatchingDedupKey` which the production SwiftData store
    // resolves via a scoped FetchDescriptor predicate on a persisted
    // column — zero full-table peeks per enqueue.
    //
    // We prove this by wiring the FakePushQueueStore's instrumentation
    // counters (`peekCallCount` / `removeMatchingDedupKeyCallCount`)
    // and counting what dedup-shaped enqueues trigger. The Fake
    // mirrors the production behaviour: dedup ⇒ scoped remove, no
    // incidental peek.
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )

    // One single-log setLog, one statusUpdate, one userParameter —
    // these are the three payload shapes that dedup. Each should
    // generate exactly one scoped dedup call and zero full-table peeks.
    let setLog = CoreDomain.SetLog(
        id: uuid("abcdef01-2345-6789-abcd-ef0123456700"),
        workoutItemID: uuid("44444444-4444-4444-4444-444444444444"),
        performedExerciseID: nil,
        setIndex: 1,
        reps: 5,
        weight: 100,
        weightUnit: .lb,
        rir: 2,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
    try await queue.enqueueSetLogs([setLog])
    try await queue.enqueueStatusUpdate(
        workoutID: uuid("11111111-2222-3333-4444-555555555555"),
        status: .completed,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
    let param = CoreDomain.UserParameter(
        id: uuid("99999999-aaaa-bbbb-cccc-dddddddddddd"),
        userID: uuid("22222222-2222-2222-2222-222222222222"),
        key: "bodyweight_lb",
        value: "185.0",
        updatedAt: iso8601("2026-04-17T08:00:00Z"),
        source: .appLog
    )
    try await queue.enqueueUserParameter(param)

    let peekCount = await store.peekCallCount
    let dedupCalls = await store.removeMatchingDedupKeyCalls
    try expectEqual(
        peekCount,
        0,
        "no full-table peek fired on any of the three dedup-shaped enqueues"
    )
    try expectEqual(
        dedupCalls.count,
        3,
        "one scoped dedup call per dedup-shaped enqueue (setLog, status, userParam)"
    )
    try expect(
        dedupCalls.contains("setLog:abcdef01-2345-6789-abcd-ef0123456700"),
        "setLog dedup key shape uses lowercase UUID"
    )
    try expect(
        dedupCalls.contains("status:11111111-2222-3333-4444-555555555555:completed"),
        "status dedup key shape uses lowercase UUID + statusRaw"
    )
    try expect(
        dedupCalls.contains("userParam:99999999-aaaa-bbbb-cccc-dddddddddddd"),
        "userParameter dedup key shape uses lowercase UUID"
    )

    // Batch setLogs and events are explicitly NOT deduped — no scoped
    // call fires for them either.
    try await queue.enqueueSetLogs([setLog, setLog])
    try await queue.enqueueEvents([CoreTelemetry.Event(
        sessionID: UUID(), kind: "state", name: "nope"
    )])
    let peekAfterNonDedup = await store.peekCallCount
    let dedupAfterNonDedup = await store.removeMatchingDedupKeyCallCount
    try expectEqual(peekAfterNonDedup, 0, "batch + events do not peek")
    try expectEqual(dedupAfterNonDedup, 3, "batch + events do not issue scoped dedup calls")
}

reportAndExit()
