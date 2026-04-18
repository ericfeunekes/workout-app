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
    // body shape (no id, no user_id — server derives both).
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let param = CoreDomain.UserParameter(
        id: UUID(),
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

    // Body must be an array of `{key, value, source, updated_at}` — no
    // id (server generates), no user_id (server derives from bearer).
    guard let body = calls[0].body else {
        try expect(false, "expected body on POST")
        return
    }
    let decoder = JSONDecoder.workoutDB()
    struct WireIn: Decodable {
        let key: String
        let value: String
        let source: String
        let updatedAt: Date?
        enum CodingKeys: String, CodingKey {
            case key, value, source
            case updatedAt = "updated_at"
        }
    }
    let wire = try decoder.decode([WireIn].self, from: body)
    try expectEqual(wire.count, 1)
    try expectEqual(wire[0].key, "bodyweight_kg")
    try expectEqual(wire[0].value, "82.5")
    try expectEqual(wire[0].source, "app_log")
    try expectEqual(wire[0].updatedAt, iso8601("2026-04-17T08:00:00Z"))
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

reportAndExit()
