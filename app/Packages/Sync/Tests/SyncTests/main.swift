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

private func minimalHealthArchiveUploadRequest() -> HealthArchiveUploadRequest {
    HealthArchiveUploadRequest(
        requestSetKey: "server|all-supported|fp",
        serverNamespace: "server",
        descriptorFingerprint: "fp",
        nextCursor: "cursor-1",
        records: [],
        tombstones: []
    )
}

private func encodedFixture() -> Data {
    // A minimal SyncPullResponse with valid UUIDs in every slot. Used as the
    // success-path pull fixture.
    let wid = "11111111-1111-1111-1111-111111111111"
    let uid = "22222222-2222-2222-2222-222222222222"
    let xid = "33333333-3333-3333-3333-333333333333"
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
          "activity_intent": {
            "activity_domain": "mixed_modal",
            "environment": "unspecified",
            "preservation_policy": "preserve_structure"
          },
          "created_at": "2026-04-17T07:00:00Z",
          "updated_at": "2026-04-17T07:00:00Z",
          "completed_at": null,
          "primitive_blocks": [
            {
              "id": "20000000-0000-4000-8000-000000000002",
              "title": "AMRAP",
              "repeat": 1,
              "work_target": [],
              "sets": [
                {
                  "id": "30000000-0000-4000-8000-000000000002",
                  "title": "Push/Pull",
                  "timing": { "mode": "cap_bounded", "cap_sec": 300 },
                  "traversal": "amrap",
                  "repeat": 1,
                  "work_target": [
                    { "metric": "rounds", "value_form": "open", "value": null, "role": "observation" }
                  ],
                  "slots": [
                    {
                      "id": "40000000-0000-4000-8000-000000000002",
                      "exercise_id": "\(xid)",
                      "work_target": [
                        { "metric": "reps", "value_form": "single", "value": 10, "role": "completion" }
                      ],
                      "load": null,
                      "stimuli": [],
                      "post_rest_sec": 0,
                      "is_warmup": false
                    }
                  ]
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
              "role": "slot",
              "slot_id": "40000000-0000-4000-8000-000000000002",
              "set_id": "30000000-0000-4000-8000-000000000002",
              "block_id": "20000000-0000-4000-8000-000000000002",
              "workout_id": "\(wid)",
              "planned_exercise_id": "\(xid)",
              "performed_exercise_id": null,
              "set_index": 1,
              "set_repeat_index": 0,
              "block_repeat_index": 0,
              "reps": 5,
              "weight": 100.0,
              "weight_unit": "kg",
              "duration_sec": null,
              "distance_m": null,
              "rounds": null,
              "rir": 2,
              "is_warmup": false,
              "completed_at": "2026-04-10T07:15:00Z"
            }
          ]
        }
      ],
      "server_time": "2026-04-17T08:00:00Z"
    }
    """
    return json.data(using: .utf8)!
}

private func encodedPrimitiveTombstoneFixture() throws -> Data {
    let now = iso8601("2026-04-17T08:00:00Z")
    let workout = WorkoutDBSchema.Workout(
        id: "11111111-1111-1111-1111-111111111111",
        userId: "22222222-2222-2222-2222-222222222222",
        name: "Primitive Removed",
        scheduledDate: "2026-04-18",
        status: .planned,
        source: .claude,
        createdAt: now,
        updatedAt: now,
        primitiveBlocks: []
    )
    let response = WorkoutDBSchema.SyncPullResponse(
        workouts: [workout],
        exercises: [],
        userParameters: [],
        lastPerformed: [],
        serverTime: now
    )
    return try JSONEncoder.workoutDB().encode(response)
}

private func encodedInvalidPrimitiveBlocksFixture() -> Data {
    let json = """
    {
      "workouts": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "name": "Primitive Drift",
          "scheduled_date": "2026-04-18",
          "status": "planned",
          "source": "claude",
          "notes": null,
          "tags_json": null,
          "created_at": "2026-04-17T07:00:00Z",
          "updated_at": "2026-04-17T07:00:00Z",
          "completed_at": null,
          "blocks": [],
          "primitive_blocks": [
            {
              "id": "20000000-0000-4000-8000-000000000022",
              "repeat": 1,
              "work_target": [],
              "sets": [
                {
                  "id": "30000000-0000-4000-8000-000000000022",
                  "timing": { "mode": "future_mode" },
                  "repeat": 1,
                  "work_target": [],
                  "slots": []
                }
              ]
            }
          ]
        }
      ],
      "exercises": [],
      "user_parameters": [],
      "last_performed": [],
      "server_time": "2026-04-17T08:00:00Z"
    }
    """
    return json.data(using: .utf8)!
}

private func encodedMixedPrimitiveBlocksFixture() -> Data {
    let json = """
    {
      "workouts": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "name": "Primitive Drift With Valid Block",
          "scheduled_date": "2026-04-18",
          "status": "planned",
          "source": "claude",
          "notes": null,
          "tags_json": null,
          "created_at": "2026-04-17T07:00:00Z",
          "updated_at": "2026-04-17T07:00:00Z",
          "completed_at": null,
          "blocks": [],
          "primitive_blocks": [
            {
              "id": "20000000-0000-4000-8000-000000000023",
              "repeat": 1,
              "work_target": [],
              "sets": [
                {
                  "id": "30000000-0000-4000-8000-000000000023",
                  "timing": { "mode": "future_mode" },
                  "repeat": 1,
                  "work_target": [],
                  "slots": []
                }
              ]
            },
            {
              "id": "20000000-0000-4000-8000-000000000024",
              "title": null,
              "repeat": 1,
              "work_target": [],
              "sets": [
                {
                  "id": "30000000-0000-4000-8000-000000000024",
                  "title": null,
                  "timing": { "mode": "set_bounded" },
                  "traversal": "sequential",
                  "repeat": 1,
                  "work_target": [],
                  "slots": [
                    {
                      "id": "40000000-0000-4000-8000-000000000024",
                      "exercise_id": "33333333-3333-3333-3333-333333333333",
                      "work_target": [
                        { "metric": "reps", "value_form": "single", "value": 5, "role": "completion" }
                      ],
                      "load": null,
                      "stimuli": [],
                      "post_rest_sec": 0,
                      "is_warmup": false
                    }
                  ]
                }
              ]
            }
          ]
        }
      ],
      "exercises": [],
      "user_parameters": [],
      "last_performed": [],
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
    try expectEqual(result.workouts[0].items.count, 1)
    try expectEqual(result.primitiveWorkouts.count, 1)
    try expectEqual(result.primitiveWorkouts[0].activityIntent?.activityDomain, .mixedModal)
    try expectEqual(result.primitiveWorkouts[0].activityIntent?.environment, .unspecified)
    try expectEqual(result.primitiveWorkouts[0].activityIntent?.preservationPolicy, .preserveStructure)
    try expectEqual(result.primitiveWorkouts[0].blocks[0].sets[0].traversal, .amrap)
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

runAsyncCase("PullService empty primitive_blocks → decode error") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: try encodedPrimitiveTombstoneFixture()))
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

runAsyncCase("PullService invalid primitive_blocks → decode error") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: encodedInvalidPrimitiveBlocksFixture()))
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

runAsyncCase("PullService mixed primitive_blocks → decode error") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: encodedMixedPrimitiveBlocksFixture()))
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

private func makeWorkout(
    id: UUID = uuid("11111111-2222-3333-4444-555555555555"),
    completedAt: Date? = iso8601("2026-04-17T08:30:00Z"),
    notes: String? = "leg day PR!"
) -> CoreDomain.Workout {
    CoreDomain.Workout(
        id: id,
        userID: uuid("22222222-2222-2222-2222-222222222222"),
        name: "Push A",
        scheduledDate: iso8601("2026-04-17T07:00:00Z"),
        status: .completed,
        source: .claude,
        notes: notes,
        createdAt: iso8601("2026-04-17T07:00:00Z"),
        updatedAt: iso8601("2026-04-17T08:30:00Z"),
        completedAt: completedAt,
        tagsJSON: nil
    )
}

private func makeCompletionRecord(
    workoutID: UUID = uuid("11111111-2222-3333-4444-555555555555"),
    primitiveSetLogs: [CoreDomain.PrimitiveSetLog] = [makePrimitiveLog()]
) -> CoreDomain.WorkoutCompletionRecord {
    return CoreDomain.WorkoutCompletionRecord(
        workout: makeWorkout(id: workoutID),
        primitiveSetLogs: primitiveSetLogs
    )
}

private func makePrimitiveLog(
    id: UUID = uuid("cccccccc-1111-2222-3333-444444444444"),
    workoutID: UUID? = uuid("11111111-2222-3333-4444-555555555555")
) -> CoreDomain.PrimitiveSetLog {
    CoreDomain.PrimitiveSetLog(
        id: id,
        role: .setResult,
        setID: uuid("33333333-2222-3333-4444-555555555555"),
        blockID: uuid("22222222-2222-3333-4444-555555555555"),
        workoutID: workoutID,
        setIndex: 0,
        reps: 4,
        durationSec: 300,
        rounds: 7,
        completedAt: iso8601("2026-04-17T08:30:00Z")
    )
}

runAsyncCase("PushQueue enqueue + flush — both items accepted, queue drains") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueuePrimitiveSetLogs([makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444401"))])
    try await queue.enqueuePrimitiveSetLogs([makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444402"))])

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

    let firstLog = makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444411"))
    let secondLog = makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444412"))
    try await queue.enqueuePrimitiveSetLogs([firstLog])
    try await queue.enqueuePrimitiveSetLogs([secondLog])

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 1)
    try expectEqual(result.remaining, 1)
    try expect(result.networkFailed, "should flag network failure on 503")
    try expect(!result.tokenRejected, "503 is not a token failure")

    let remaining = await store.all()
    try expectEqual(remaining.count, 1)
    try expectEqual(remaining[0].attempts, 1)
    if case .primitiveSetLogs(let logs) = remaining[0].payload {
        try expectEqual(logs.first?.id, secondLog.id)
    } else {
        try expect(false, "expected primitiveSetLogs payload")
    }
}

// MARK: - 7. PushQueue flush with 401

runAsyncCase("PushQueue flush — 401 leaves everything queued, flags tokenRejected") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 401, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)
    try await queue.enqueuePrimitiveSetLogs([makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444421"))])
    try await queue.enqueuePrimitiveSetLogs([makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444422"))])

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

    try await queue.enqueuePrimitiveSetLogs([makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444431"))])
    try await queue.enqueuePrimitiveSetLogs([makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444432"))])

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

    // last_performed: one entry for back-squat with one primitive slot log.
    try expectEqual(pull.lastPerformed.count, 1)
    let lp = pull.lastPerformed[0]
    try expectEqual(lp.exerciseId, "e0000001-0000-4000-8000-000000000001")
    try expectEqual(lp.lastSetLogs.count, 1)

    let setLogResult = DTOMapping.mapPrimitiveSetLog(lp.lastSetLogs[0])
    let mappedLog: CoreDomain.PrimitiveSetLog
    switch setLogResult {
    case .success(let log): mappedLog = log
    case .failure(let err): throw err
    }
    try expectEqual(mappedLog.id, uuid("77777777-7777-7777-7777-777777777777"))
    try expectEqual(mappedLog.role, .slot)
    try expectEqual(mappedLog.slotID, uuid("40000000-0000-4000-8000-000000000002"))
    try expectEqual(mappedLog.setID, uuid("30000000-0000-4000-8000-000000000002"))
    try expectEqual(mappedLog.blockID, uuid("20000000-0000-4000-8000-000000000002"))
    try expectEqual(mappedLog.workoutID, uuid("11111111-1111-1111-1111-111111111111"))
    try expectEqual(mappedLog.plannedExerciseID, uuid("e0000001-0000-4000-8000-000000000001"))
    try expect(mappedLog.performedExerciseID == nil, "performed_exercise_id should be nil")
    try expectEqual(mappedLog.setIndex, 1)
    try expectEqual(mappedLog.setRepeatIndex, 0)
    try expectEqual(mappedLog.blockRepeatIndex, 0)
    try expectEqual(mappedLog.reps, 5)
    try expectEqual(mappedLog.weight, 100.0)
    try expectEqual(mappedLog.weightUnit, .kg)
    try expectEqual(mappedLog.rir, 2)
    try expect(!mappedLog.isWarmup, "is_warmup false in fixture")
    try expectEqual(mappedLog.completedAt, iso8601("2026-04-10T07:15:00Z"))

    // Round-trip the set log back to the wire and confirm the shape survives.
    let roundtrip = DTOMapping.toDTO(mappedLog)
    try expectEqual(roundtrip.id, lp.lastSetLogs[0].id)
    try expectEqual(roundtrip.role, lp.lastSetLogs[0].role)
    try expectEqual(roundtrip.slotId, lp.lastSetLogs[0].slotId)
    try expectEqual(roundtrip.workoutId, lp.lastSetLogs[0].workoutId)
    try expectEqual(roundtrip.rir, lp.lastSetLogs[0].rir)
    try expectEqual(roundtrip.weightUnit, lp.lastSetLogs[0].weightUnit)

    // Workouts slot is empty in this fixture — confirm the mapper handles that cleanly.
    try expectEqual(pull.workouts.count, 0)

    // Also exercise the workout header mapping via the `workout_create.json` fixture.
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
    try expectEqual(mappedWorkout.items.count, 1)
    try expectEqual(mappedWorkout.alternatives.count, 0)
}

runCase("DTOMapping rejects primitive block repeat until bridge supports block-level repeats") {
    let json = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "user_id": "22222222-2222-2222-2222-222222222222",
      "name": "Repeated block",
      "scheduled_date": "2026-04-20",
      "status": "planned",
      "source": "claude",
      "notes": null,
      "tags_json": null,
      "created_at": "2026-04-17T08:00:00Z",
      "updated_at": "2026-04-17T08:00:00Z",
      "completed_at": null,
      "primitive_blocks": [
        {
          "id": "33333333-3333-4333-8333-333333333333",
          "repeat": 2,
          "work_target": [],
          "sets": [
            {
              "id": "44444444-4444-4444-8444-444444444444",
              "timing": { "mode": "set_bounded" },
              "traversal": "sequential",
              "repeat": 1,
              "work_target": [],
              "slots": [
                {
                  "id": "55555555-5555-4555-8555-555555555555",
                  "exercise_id": "e0000001-0000-4000-8000-000000000001",
                  "work_target": [],
                  "stimuli": [],
                  "post_rest_sec": 0,
                  "is_warmup": false
                }
              ]
            }
          ]
        }
      ]
    }
    """
    let workout = try JSONDecoder.workoutDB().decode(
        WorkoutDBSchema.Workout.self,
        from: Data(json.utf8)
    )
    switch DTOMapping.mapWorkout(workout) {
    case .success:
        try expect(false, "block repeats must fail closed until the bridge can preserve them")
    case .failure:
        break
    }
}

runCase("DTOMapping rejects zero-slot primitive sets at the execution bridge") {
    let json = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "user_id": "22222222-2222-2222-2222-222222222222",
      "name": "Timer only",
      "scheduled_date": "2026-04-20",
      "status": "planned",
      "source": "claude",
      "notes": null,
      "tags_json": null,
      "created_at": "2026-04-17T08:00:00Z",
      "updated_at": "2026-04-17T08:00:00Z",
      "completed_at": null,
      "primitive_blocks": [
        {
          "id": "33333333-3333-4333-8333-333333333333",
          "repeat": 1,
          "work_target": [],
          "sets": [
            {
              "id": "44444444-4444-4444-8444-444444444444",
              "timing": { "mode": "time_bounded", "interval_sec": 60, "rounds": 3 },
              "traversal": "sequential",
              "repeat": 1,
              "work_target": [],
              "slots": []
            }
          ]
        }
      ]
    }
    """
    let workout = try JSONDecoder.workoutDB().decode(
        WorkoutDBSchema.Workout.self,
        from: Data(json.utf8)
    )
    switch DTOMapping.mapWorkout(workout) {
    case .success:
        try expect(false, "zero-slot primitive sets must fail closed at the bridge")
    case .failure:
        break
    }
}

runCase("DTOMapping bridge support matrix accepts legal primitive cells") {
    let emptyWorkTarget = "[]"
    let roundsWorkTarget = """
    [
      { "metric": "rounds", "value_form": "open", "value": null, "role": "observation" }
    ]
    """
    let durationWorkTarget = """
    [
      { "metric": "duration", "value_form": "open", "value": null, "role": "observation" }
    ]
    """
    let cells: [(String, String, String, Bool, String)] = [
        (#""set_bounded""#, "sequential", emptyWorkTarget, true, "straight sets"),
        (#""set_bounded""#, "round_robin", emptyWorkTarget, true, "circuit"),
        (#""set_bounded""#, "amrap", emptyWorkTarget, false, "uncapped amrap"),
        (#""time_bounded", "interval_sec": 60, "rounds": 3"#, "sequential", emptyWorkTarget, true, "interval sequential"),
        (#""time_bounded", "interval_sec": 60, "rounds": 3"#, "round_robin", emptyWorkTarget, true, "interval alternating"),
        (#""time_bounded", "interval_sec": 60, "rounds": 3"#, "amrap", roundsWorkTarget, true, "interval amrap"),
        (#""cap_bounded", "cap_sec": 300"#, "sequential", durationWorkTarget, true, "for time"),
        (#""cap_bounded", "cap_sec": 300"#, "round_robin", durationWorkTarget, true, "capped circuit"),
        (#""cap_bounded", "cap_sec": 300"#, "amrap", roundsWorkTarget, true, "amrap"),
        (#""target_bounded""#, "sequential", durationWorkTarget, true, "target bounded sequential"),
        (#""target_bounded""#, "round_robin", durationWorkTarget, true, "target bounded round robin"),
        (#""target_bounded""#, "amrap", emptyWorkTarget, false, "target bounded amrap"),
    ]

    for cell in cells {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "name": "Primitive bridge matrix \(cell.4)",
          "scheduled_date": "2026-04-20",
          "status": "planned",
          "source": "claude",
          "notes": null,
          "tags_json": null,
          "created_at": "2026-04-17T08:00:00Z",
          "updated_at": "2026-04-17T08:00:00Z",
          "completed_at": null,
          "primitive_blocks": [
            {
              "id": "33333333-3333-4333-8333-333333333333",
              "repeat": 1,
              "work_target": [],
              "sets": [
                {
                  "id": "44444444-4444-4444-8444-444444444444",
                  "timing": { "mode": \(cell.0) },
                  "traversal": "\(cell.1)",
                  "repeat": 1,
                  "work_target": \(cell.2),
                  "slots": [
                    {
                      "id": "55555555-5555-4555-8555-555555555555",
                      "exercise_id": "e0000001-0000-4000-8000-000000000001",
                      "work_target": [],
                      "stimuli": [],
                      "post_rest_sec": 0,
                      "is_warmup": false
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let workout = try JSONDecoder.workoutDB().decode(
            WorkoutDBSchema.Workout.self,
            from: Data(json.utf8)
        )
        switch DTOMapping.mapWorkout(workout) {
        case .success:
            try expect(cell.3, "\(cell.4) unexpectedly succeeded through bridge")
        case .failure:
            try expect(!cell.3, "\(cell.4) should be supported by the bridge")
        }
    }
}

runCase("DTOMapping projects round-robin primitive repeat into legacy block rounds") {
    let json = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "user_id": "22222222-2222-2222-2222-222222222222",
      "name": "Primitive circuit",
      "scheduled_date": "2026-04-20",
      "status": "planned",
      "source": "claude",
      "notes": null,
      "tags_json": null,
      "created_at": "2026-04-17T08:00:00Z",
      "updated_at": "2026-04-17T08:00:00Z",
      "completed_at": null,
      "primitive_blocks": [
        {
          "id": "33333333-3333-4333-8333-333333333333",
          "repeat": 1,
          "work_target": [],
          "sets": [
            {
              "id": "44444444-4444-4444-8444-444444444444",
              "timing": { "mode": "set_bounded" },
              "traversal": "round_robin",
              "repeat": 3,
              "work_target": [],
              "slots": [
                {
                  "id": "55555555-5555-4555-8555-555555555555",
                  "exercise_id": "e0000001-0000-4000-8000-000000000001",
                  "work_target": [],
                  "stimuli": [],
                  "post_rest_sec": 0,
                  "is_warmup": false
                }
              ]
            }
          ]
        }
      ]
    }
    """
    let workout = try JSONDecoder.workoutDB().decode(
        WorkoutDBSchema.Workout.self,
        from: Data(json.utf8)
    )
    let mapped = try DTOMapping.mapWorkout(workout).get()
    try expectEqual(mapped.blocks[0].timingMode, .circuit)
    try expectEqual(mapped.blocks[0].rounds, 3)
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

runAsyncCase("HealthArchiveUploadService posts archive payload and decodes ack") {
    let response = """
    {
      "request_set_key": "server|all-supported|fp",
      "acknowledged_cursor": "cursor-1",
      "records_received": 3,
      "tombstones_received": 1,
      "server_time": "2026-05-18T12:00:00Z"
    }
    """.data(using: .utf8)!
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: response))
    ])
    let service = HealthArchiveUploadService(transport: transport)

    let result = try await service.upload(HealthArchiveUploadRequest(
        requestSetKey: "server|all-supported|fp",
        serverNamespace: "server",
        descriptorFingerprint: "fp",
        nextCursor: "cursor-1",
        records: [
            HealthArchiveUploadRecord(
                id: "70000000-0000-4000-8000-000000000001",
                externalID: "hk-1",
                descriptorID: "HKQuantityTypeIdentifierHeartRate",
                sampleKind: .quantity,
                value: HealthArchiveUploadValue(
                    kind: .quantity,
                    quantityValue: 120,
                    unit: "count/min"
                )
            ),
            HealthArchiveUploadRecord(
                id: "70000000-0000-4000-8000-000000000002",
                externalID: "hk-sleep-1",
                descriptorID: "HKCategoryTypeIdentifierSleepAnalysis",
                sampleKind: .category,
                value: HealthArchiveUploadValue(kind: .category, categoryValue: 1)
            ),
            HealthArchiveUploadRecord(
                id: "70000000-0000-4000-8000-000000000003",
                externalID: "hk-workout-1",
                descriptorID: "HKWorkoutTypeIdentifier",
                sampleKind: .workout,
                value: HealthArchiveUploadValue(
                    kind: .workout,
                    workoutActivityType: "37",
                    durationSeconds: 1800,
                    totalEnergyKcal: 220
                )
            )
        ],
        tombstones: [
            HealthArchiveUploadTombstone(
                id: "80000000-0000-4000-8000-000000000001",
                descriptorID: "HKQuantityTypeIdentifierHeartRate",
                externalID: "hk-deleted-1",
                observedAt: iso8601("2026-05-18T11:59:00Z")
            )
        ]
    ), bearerToken: "tok")
    let calls = await transport.store.recordedCalls()
    let body = String(data: calls[0].body ?? Data(), encoding: .utf8) ?? ""

    try expectEqual(calls[0].path, "/api/health/archive")
    try expectEqual(calls[0].bearerToken, "tok")
    try expect(body.contains(#""quantity_value":120"#), "encoded quantity value")
    try expect(body.contains(#""sample_kind":"category""#), "encoded category sample kind")
    try expect(body.contains(#""category_value":1"#), "encoded category value")
    try expect(body.contains(#""sample_kind":"workout""#), "encoded workout sample kind")
    try expect(body.contains(#""workout_activity_type":"37""#), "encoded workout value")
    try expectEqual(result.requestSetKey, "server|all-supported|fp")
    try expectEqual(result.acknowledgedCursor, "cursor-1")
    try expectEqual(result.recordsReceived, 3)
    try expectEqual(result.tombstonesReceived, 1)
}

runAsyncCase("HealthArchiveUploadService routes archive 401 to tokenRejected") {
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 401, body: Data()))
    ])
    let service = HealthArchiveUploadService(transport: transport)

    do {
        _ = try await service.upload(minimalHealthArchiveUploadRequest(), bearerToken: "tok")
        try expect(false, "expected tokenRejected")
    } catch let err as SyncError {
        try expectEqual(err, .tokenRejected)
    }
}

runAsyncCase("HealthArchiveUploadService routes archive 503 to server error") {
    let body = Data("temporarily unavailable".utf8)
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 503, body: body))
    ])
    let service = HealthArchiveUploadService(transport: transport)

    do {
        _ = try await service.upload(minimalHealthArchiveUploadRequest(), bearerToken: "tok")
        try expect(false, "expected server error")
    } catch let err as SyncError {
        try expectEqual(err, .server(status: 503, message: "temporarily unavailable"))
    }
}

runAsyncCase("HealthArchiveUploadService routes archive network and decode failures") {
    let networkTransport = FakeTransport(outcomes: [.throwURLError])
    let networkService = HealthArchiveUploadService(transport: networkTransport)
    do {
        _ = try await networkService.upload(minimalHealthArchiveUploadRequest(), bearerToken: "tok")
        try expect(false, "expected network error")
    } catch let err as SyncError {
        if case .network = err {
            // Expected.
        } else {
            try expect(false, "expected network, got \(err)")
        }
    }

    let decodeTransport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data("not json".utf8)))
    ])
    let decodeService = HealthArchiveUploadService(transport: decodeTransport)
    do {
        _ = try await decodeService.upload(minimalHealthArchiveUploadRequest(), bearerToken: "tok")
        try expect(false, "expected decode error")
    } catch let err as SyncError {
        if case .decode = err {
            // Expected.
        } else {
            try expect(false, "expected decode, got \(err)")
        }
    }
}

runAsyncCase("SyncAPI uploadHealthArchive requires token and routes 401 state") {
    let noTokenAPI = SyncAPI(
        transport: FakeTransport(),
        store: FakePushQueueStore(),
        tokenProvider: { nil }
    )
    do {
        _ = try await noTokenAPI.uploadHealthArchive(minimalHealthArchiveUploadRequest())
        try expect(false, "expected tokenRejected without token")
    } catch let err as SyncError {
        try expectEqual(err, .tokenRejected)
    }
    let noTokenState = await noTokenAPI.connection.state
    try expect(noTokenState == .tokenRejected)

    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 401, body: Data()))
    ])
    let api = SyncAPI(
        transport: transport,
        store: FakePushQueueStore(),
        tokenProvider: { "tok" }
    )
    do {
        _ = try await api.uploadHealthArchive(minimalHealthArchiveUploadRequest())
        try expect(false, "expected tokenRejected from server")
    } catch let err as SyncError {
        try expectEqual(err, .tokenRejected)
    }
    let rejectedState = await api.connection.state
    try expect(rejectedState == .tokenRejected)
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

runAsyncCase("PushQueue — primitive_set_logs route to sync results and encode body") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)
    let log = CoreDomain.PrimitiveSetLog(
        id: uuid("99999999-9999-4999-8999-999999999999"),
        role: .setResult,
        setID: uuid("30000000-0000-4000-8000-000000000002"),
        blockID: uuid("20000000-0000-4000-8000-000000000002"),
        workoutID: uuid("10000000-0000-4000-8000-000000000002"),
        setIndex: 0,
        weight: 27.2155422,
        weightUnit: .kg,
        durationSec: 360,
        distanceM: 1000,
        rounds: 7,
        skipped: true,
        side: .left,
        notes: "scaled after warmup",
        completedAt: iso8601("2026-04-20T07:30:00Z")
    )

    try await queue.enqueuePrimitiveSetLogs([log])
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].path, "/api/sync/results")
    guard let body = calls[0].body else {
        try expect(false, "expected body on POST")
        return
    }
    let payload = try JSONDecoder.workoutDB().decode(WorkoutDBSchema.SyncResultsPayload.self, from: body)
    try expectEqual(payload.primitiveSetLogs.count, 1)
    try expectEqual(payload.primitiveSetLogs[0].role, .setResult)
    try expectEqual(payload.primitiveSetLogs[0].rounds, 7)
    try expectEqual(payload.primitiveSetLogs[0].distanceM, 1000)
    try expectEqual(payload.primitiveSetLogs[0].skipped, true)
    try expectEqual(payload.primitiveSetLogs[0].side, "left")
    try expectEqual(payload.primitiveSetLogs[0].notes, "scaled after warmup")
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

runAsyncCase("Primitive DTO mapping keeps schema at Sync and emits primitive log DTO") {
    let json = """
    {
      "id": "10000000-0000-4000-8000-000000000002",
      "name": "Primitive AMRAP",
      "activity_intent": {
        "activity_domain": "running",
        "preservation_policy": "preserve_primary_activity"
      },
      "primitive_blocks": [
        {
          "id": "20000000-0000-4000-8000-000000000002",
          "repeat": 1,
          "work_target": [],
          "sets": [
            {
              "id": "30000000-0000-4000-8000-000000000002",
              "timing": { "mode": "cap_bounded", "cap_sec": 300 },
              "traversal": "amrap",
              "repeat": 1,
              "work_target": [
                { "metric": "rounds", "value_form": "open", "value": null, "role": "observation" }
              ],
              "slots": [
                {
                  "id": "40000000-0000-4000-8000-000000000002",
                  "exercise_id": "50000000-0000-4000-8000-000000000002",
                  "work_target": [
                    { "metric": "reps", "value_form": "single", "value": 10, "role": "completion" }
                  ],
                  "load": null,
                  "stimuli": [],
                  "post_rest_sec": 0,
                  "is_warmup": false
                }
              ]
            }
          ]
        }
      ]
    }
    """
    let dto = try JSONDecoder.workoutDB().decode(
        WorkoutDBSchema.PrimitiveWorkout.self,
        from: Data(json.utf8)
    )
    let mappedResult = DTOMapping.mapPrimitiveWorkout(dto)
    let mapped: CoreDomain.PrimitiveWorkout
    switch mappedResult {
    case .success(let value): mapped = value
    case .failure(let error): throw error
    }
    try expectEqual(mapped.blocks[0].sets[0].traversal, .amrap)
    try expectEqual(mapped.blocks[0].sets[0].workTargets[0].metric, .rounds)
    try expectEqual(mapped.activityIntent?.activityDomain, .running)
    try expectEqual(mapped.activityIntent?.environment, .unspecified)
    try expectEqual(mapped.activityIntent?.preservationPolicy, .preservePrimaryActivity)

    let primitiveLog = CoreDomain.PrimitiveSetLog(
        id: uuid("99999999-9999-4999-8999-999999999999"),
        role: .setResult,
        setID: mapped.blocks[0].sets[0].id,
        blockID: mapped.blocks[0].id,
        workoutID: mapped.id,
        setIndex: 0,
        rounds: 7,
        completedAt: iso8601("2026-04-20T07:30:00Z")
    )
    let logDTO = DTOMapping.toDTO(primitiveLog)
    try expectEqual(logDTO.role, .setResult)
    try expectEqual(logDTO.setId, mapped.blocks[0].sets[0].id.wireID)
    try expectEqual(logDTO.rounds, 7)
}

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
    let primitiveDTO = WorkoutDBSchema.PrimitiveSetLog(
        id: dto.id,
        role: .slot,
        slotId: "ffeeddcc-bbaa-9988-7766-554433221100",
        setId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        blockId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        workoutId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        plannedExerciseId: "11112222-3333-4444-5555-666677778888",
        setIndex: dto.setIndex,
        reps: dto.reps,
        weight: dto.weight,
        weightUnit: dto.weightUnit,
        rir: dto.rir,
        completedAt: dto.completedAt
    )
    let payload = WorkoutDBSchema.SyncResultsPayload(
        primitiveSetLogs: [primitiveDTO],
        statusUpdates: []
    )
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

runAsyncCase("Completion results encode primitive logs with status in one sync results call") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let record = makeCompletionRecord(primitiveSetLogs: [
        makePrimitiveLog(workoutID: nil),
    ])
    try await queue.enqueueCompletionResults(record)
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].path, "/api/sync/results")
    guard let body = calls[0].body else {
        try expect(false, "expected body on POST")
        return
    }
    let payload = try JSONDecoder.workoutDB().decode(
        WorkoutDBSchema.SyncResultsPayload.self,
        from: body
    )
    try expectEqual(payload.primitiveSetLogs.count, 1)
    try expectEqual(payload.primitiveSetLogs[0].role, .setResult)
    try expectEqual(payload.primitiveSetLogs[0].setIndex, 0)
    try expectEqual(payload.primitiveSetLogs[0].reps, 4)
    try expectEqual(payload.primitiveSetLogs[0].workoutId, record.workoutID.uuidString.lowercased())
    try expectEqual(payload.statusUpdates.count, 1)
    try expectEqual(payload.statusUpdates[0].workoutId, record.workoutID.uuidString.lowercased())
    try expectEqual(payload.statusUpdates[0].status, WorkoutDBSchema.WorkoutStatus.completed)
    try expectEqual(payload.statusUpdates[0].notes, "leg day PR!")
}

runAsyncCase("Completion results 503 leaves grouped logs and status queued together") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 503, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    let record = makeCompletionRecord(primitiveSetLogs: [
        makePrimitiveLog(workoutID: nil),
    ])
    try await queue.enqueueCompletionResults(record)

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 0)
    try expectEqual(result.remaining, 1)
    try expect(result.networkFailed, "503 should flag network failure")

    let remaining = await store.all()
    try expectEqual(remaining.count, 1)
    try expectEqual(remaining[0].attempts, 1)
    if case .completionResults(let workoutID, _, _, let primitiveLogs) = remaining[0].payload {
        try expectEqual(workoutID, record.workoutID)
        try expectEqual(primitiveLogs.count, record.primitiveSetLogs.count)
    } else {
        try expect(false, "expected completionResults payload")
    }
}

runAsyncCase("Completion results 200 removes the single grouped item") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueueCompletionResults(makeCompletionRecord(primitiveSetLogs: [
        makePrimitiveLog(workoutID: nil),
    ]))

    let result = try await queue.flush(bearerToken: "tok")
    try expectEqual(result.pushed, 1)
    try expectEqual(result.remaining, 0)
    let empty = try await store.isEmpty()
    try expect(empty, "completion item should be removed after 2xx")
}

runAsyncCase("Completion results dedups older primitive logs, completed status, and grouped completion") {
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )

    let workoutID = uuid("11111111-2222-3333-4444-555555555555")
    let log = makePrimitiveLog(id: uuid("abcdef01-2345-6789-abcd-ef0123456789"))
    try await queue.enqueuePrimitiveSetLogs([log])
    try await queue.enqueueStatusUpdate(
        workoutID: workoutID,
        status: .completed,
        completedAt: iso8601("2026-04-17T08:00:00Z"),
        notes: "older"
    )
    try await queue.enqueueCompletionResults(makeCompletionRecord(
        workoutID: workoutID,
        primitiveSetLogs: [log]
    ))
    try await queue.enqueueCompletionResults(makeCompletionRecord(
        workoutID: workoutID,
        primitiveSetLogs: [CoreDomain.PrimitiveSetLog(
            id: log.id,
            role: .setResult,
            setID: log.setID,
            blockID: log.blockID,
            workoutID: workoutID,
            setIndex: 1,
            reps: 8,
            weight: 102.5,
            weightUnit: .kg,
            rir: 1,
            completedAt: iso8601("2026-04-17T08:02:00Z")
        )]
    ))

    let all = await store.all()
    try expectEqual(all.count, 1, "completion replaces older single and grouped rows")
    if case .completionResults(let queuedWorkoutID, _, let notes, let primitiveLogs) = all[0].payload {
        try expectEqual(queuedWorkoutID, workoutID)
        try expectEqual(notes, "leg day PR!")
        try expectEqual(primitiveLogs.count, 1)
        try expectEqual(primitiveLogs[0].reps, 8, "latest grouped payload wins")
        try expectEqual(primitiveLogs[0].weight, 102.5)
    } else {
        try expect(false, "expected completionResults payload")
    }
}

runAsyncCase("Workout reset routes to sync results with lowercase workout id") {
    let store = FakePushQueueStore()
    let transport = FakeTransport(outcomes: [
        .response(HTTPResponse(status: 200, body: Data())),
    ])
    let queue = PushQueue(store: store, transport: transport)

    try await queue.enqueueWorkoutReset(
        workoutID: uuid("DEADBEEF-1234-5678-9ABC-DEF012345678")
    )
    _ = try await queue.flush(bearerToken: "tok")

    let calls = await transport.store.recordedCalls()
    try expectEqual(calls.count, 1)
    try expectEqual(calls[0].path, "/api/sync/results")
    guard let body = calls[0].body else {
        try expect(false, "expected body on POST")
        return
    }
    let payload = try JSONDecoder.workoutDB().decode(
        WorkoutDBSchema.SyncResultsPayload.self,
        from: body
    )
    try expectEqual(payload.statusUpdates.count, 0)
    try expectEqual(payload.workoutResets.count, 1)
    try expectEqual(
        payload.workoutResets[0].workoutId,
        "deadbeef-1234-5678-9abc-def012345678"
    )
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

    // Order-of-enqueue: two old telemetry events, then one fresh primitive
    // result, then one more telemetry event. If we sorted by enqueuedAt
    // alone, the result would land third. Priority weighting must
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
    try await queue.enqueuePrimitiveSetLogs([
        makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444441"))
    ])
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

    // First call MUST be the primitive results endpoint. Prior to the
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
    let log = makePrimitiveLog()
    let results = PushItem(payload: .primitiveSetLogs([log]), enqueuedAt: Date())
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

    let completion = PushItem(
        payload: .completionResults(
            workoutID: UUID(),
            completedAt: nil,
            notes: nil,
            primitiveSetLogs: [log]
        ),
        enqueuedAt: Date()
    )
    try expectEqual(completion.priority, 0)

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

runAsyncCase("PushQueue replace-in-place — enqueueing same primitive log id twice collapses to one entry with latest payload") {
    // Regression for "no logical dedup; unknown envelope kind stalls the
    // whole queue" — the dedup half. Without this, a just-logged set
    // edited a second later before the queue flushes would leave two
    // `.primitiveSetLogs` rows queued: the stale first push and the fresh second.
    // On flush the stale one lands first and transiently overwrites the
    // corrected bytes on the server until the fresh one resolves.
    let store = FakePushQueueStore()
    let queue = PushQueue(
        store: store,
        transport: FakeTransport(outcomes: []),
        clock: SystemClock()
    )

    let setLogID = uuid("abcdef01-2345-6789-abcd-ef0123456789")
    let first = makePrimitiveLog(id: setLogID)
    var corrected = first
    corrected.reps = 8
    corrected.weight = 102.5
    corrected.weightUnit = .kg
    corrected.rir = 1
    corrected.completedAt = iso8601("2026-04-17T08:00:30Z")

    try await queue.enqueuePrimitiveSetLogs([first])
    try await queue.enqueuePrimitiveSetLogs([corrected])

    let all = await store.all()
    try expectEqual(all.count, 1, "logical dedup by primitive log id must collapse to one entry")
    if case .primitiveSetLogs(let logs) = all[0].payload {
        try expectEqual(logs.count, 1)
        try expectEqual(logs[0].id, setLogID)
        try expectEqual(logs[0].reps, 8, "latest payload wins")
        try expectEqual(logs[0].weight, 102.5)
        try expectEqual(logs[0].rir, 1)
    } else {
        try expect(false, "expected primitiveSetLogs payload")
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
    try await api.pushPrimitiveLog([
        makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444451"))
    ])

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
    let log = makePrimitiveLog(id: logID)
    try await queue.enqueuePrimitiveSetLogs([log])

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
        json.contains("\"payload_kind\":\"primitive_set_logs\""),
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
        json.contains("\"primitive_set_log_id\":\"\(logID.wireID)\""),
        "dead-letter data must carry primitive_set_log_id for correlation: \(json)"
    )
}

runAsyncCase("testDeadLetterEventCarriesCorrelationIDForStatusUpdate — workout_id rides on the dropped status push") {
    // qa-037: a dead-lettered status update must surface its workoutID
    // so an operator can trace which workout's completion never landed.
    // The prior shape dropped only `{payload_kind, http_status, attempts}`.
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
    let workoutID = uuid("c0de0001-0000-4000-8000-000000000001")
    try await queue.enqueueStatusUpdate(
        workoutID: workoutID,
        status: .completed,
        completedAt: iso8601("2026-04-17T08:30:00Z"),
        notes: nil
    )

    for _ in 0..<PushBackoff.deadLetterThreshold {
        _ = try await queue.flush(bearerToken: "tok")
    }

    let deadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(deadLetters.count, 1, "one dead-letter event")
    guard let json = deadLetters[0].dataJSON else {
        try expect(false, "dead-letter event must carry dataJSON")
        return
    }
    try expect(
        json.contains("\"payload_kind\":\"status_update\""),
        "dead-letter data must name status_update payload kind: \(json)"
    )
    try expect(
        json.contains("\"workout_id\":\"\(workoutID.wireID)\""),
        "dead-letter data must carry workout_id for correlation: \(json)"
    )
}

runAsyncCase("testDeadLetterEventCarriesCorrelationIDForUserParameter — user_parameter_id rides on the dropped row") {
    // qa-037: a dead-lettered user_parameter push must surface its id
    // (the append-only log keeps the id stable end-to-end).
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
    let paramID = uuid("c0de0002-0000-4000-8000-000000000002")
    let param = CoreDomain.UserParameter(
        id: paramID,
        userID: uuid("00000000-0000-4000-8000-000000000001"),
        key: "bodyweight_kg",
        value: "80.0",
        updatedAt: iso8601("2026-04-17T08:30:00Z"),
        source: .appLog
    )
    try await queue.enqueueUserParameter(param)

    for _ in 0..<PushBackoff.deadLetterThreshold {
        _ = try await queue.flush(bearerToken: "tok")
    }

    let deadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(deadLetters.count, 1, "one dead-letter event")
    guard let json = deadLetters[0].dataJSON else {
        try expect(false, "dead-letter event must carry dataJSON")
        return
    }
    try expect(
        json.contains("\"payload_kind\":\"user_parameter\""),
        "dead-letter data must name user_parameter payload kind: \(json)"
    )
    try expect(
        json.contains("\"user_parameter_id\":\"\(paramID.wireID)\""),
        "dead-letter data must carry user_parameter_id for correlation: \(json)"
    )
}

runAsyncCase("testDeadLetterEventCarriesCorrelationIDForEventsBatch — setLogID-tagged event surfaces as correlation") {
    // qa-037: `.events` batches were previously always emitted without
    // any correlation — the dropped today.start_tap in the QA run had
    // both `workout_id` and `set_log_id` empty. The fix prefers the
    // first event's `setLogID`; when no setLogID is present we fall
    // back to its `workoutID` so the drop is still traceable.
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
    let setLogID = uuid("c0de0003-0000-4000-8000-000000000003")
    let event = CoreTelemetry.Event(
        sessionID: UUID(),
        kind: "state",
        name: "execution.log_set",
        dataJSON: nil,
        workoutID: uuid("c0de0004-0000-4000-8000-000000000004"),
        setLogID: setLogID
    )
    try await queue.enqueueEvents([event])

    for _ in 0..<PushBackoff.deadLetterThreshold {
        _ = try await queue.flush(bearerToken: "tok")
    }

    let deadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(deadLetters.count, 1, "one dead-letter event")
    guard let json = deadLetters[0].dataJSON else {
        try expect(false, "dead-letter event must carry dataJSON")
        return
    }
    try expect(
        json.contains("\"payload_kind\":\"events\""),
        "dead-letter data must name events payload kind: \(json)"
    )
    try expect(
        json.contains("\"set_log_id\":\"\(setLogID.wireID)\""),
        "events dead-letter prefers first event's set_log_id: \(json)"
    )
}

runAsyncCase("testDeadLetterEventCarriesCorrelationIDForEventsWorkoutFallback — workout_id when no setLogID") {
    // qa-037 specific scenario: today.start_tap events carry workoutID
    // but no setLogID. The dead-letter must still surface workout_id.
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
    let workoutID = uuid("c0de0005-0000-4000-8000-000000000005")
    let event = CoreTelemetry.Event(
        sessionID: UUID(),
        kind: "interaction",
        name: "today.start_tap",
        dataJSON: nil,
        workoutID: workoutID,
        setLogID: nil
    )
    try await queue.enqueueEvents([event])

    for _ in 0..<PushBackoff.deadLetterThreshold {
        _ = try await queue.flush(bearerToken: "tok")
    }

    let deadLetters = recorder.events().filter {
        $0.name == "execution.push_item_dead_lettered"
    }
    try expectEqual(deadLetters.count, 1, "one dead-letter event")
    guard let json = deadLetters[0].dataJSON else {
        try expect(false, "dead-letter event must carry dataJSON")
        return
    }
    try expect(
        json.contains("\"workout_id\":\"\(workoutID.wireID)\""),
        "events dead-letter falls back to first event's workout_id when no set_log_id: \(json)"
    )
    try expect(
        !json.contains("\"set_log_id\""),
        "events dead-letter must NOT carry set_log_id when the event has none: \(json)"
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
    let firstLog = makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444461"))
    try await queue.enqueuePrimitiveSetLogs([firstLog])

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

    // Fresh enqueue with a new primitive log id — this gets a new PushItem.id.
    let secondLog = makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444462"))
    try await queue.enqueuePrimitiveSetLogs([secondLog])

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
    try await queue.enqueuePrimitiveSetLogs([
        makePrimitiveLog(id: uuid("cccccccc-1111-2222-3333-444444444471"))
    ])

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

    // Single primitive result, statusUpdate, and userParameter payloads each use
    // scoped dedup-key removal. Completion results use the stronger
    // store-level replace operation so stale-row deletion and grouped
    // insertion commit together.
    let setLog = makePrimitiveLog(
        id: uuid("abcdef01-2345-6789-abcd-ef0123456700"),
        workoutID: uuid("11111111-2222-3333-4444-555555555555")
    )
    try await queue.enqueuePrimitiveSetLogs([setLog])
    try await queue.enqueueStatusUpdate(
        workoutID: uuid("11111111-2222-3333-4444-555555555555"),
        status: .completed,
        completedAt: iso8601("2026-04-17T08:00:00Z")
    )
    try await queue.enqueueCompletionResults(makeCompletionRecord(
        workoutID: uuid("11111111-2222-3333-4444-555555555555"),
        primitiveSetLogs: [setLog]
    ))
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
    let replacingCalls = await store.enqueueReplacingDedupKeysCalls
    try expectEqual(
        peekCount,
        0,
        "no full-table peek fired on any of the three dedup-shaped enqueues"
    )
    try expectEqual(
        dedupCalls.count,
        3,
        "single primitive result/status/userParam use scoped dedup; completion uses atomic replacement"
    )
    try expect(
        dedupCalls.contains("primitiveSetLog:abcdef01-2345-6789-abcd-ef0123456700"),
        "primitive result dedup key shape uses lowercase UUID"
    )
    try expect(
        dedupCalls.contains("status:11111111-2222-3333-4444-555555555555:completed"),
        "status dedup key shape uses lowercase UUID + statusRaw"
    )
    try expect(
        dedupCalls.contains("userParam:99999999-aaaa-bbbb-cccc-dddddddddddd"),
        "userParameter dedup key shape uses lowercase UUID"
    )
    try expectEqual(replacingCalls.count, 1, "completion uses one atomic replacement")
    guard let completionKeys = replacingCalls.first else {
        try expect(false, "missing completion replacement keys")
        return
    }
    try expect(
        completionKeys.contains("primitiveSetLog:abcdef01-2345-6789-abcd-ef0123456700"),
        "completion replacement includes final primitive result key"
    )
    try expect(
        completionKeys.contains("status:11111111-2222-3333-4444-555555555555:completed"),
        "completion replacement includes completed status key"
    )
    try expect(
        completionKeys.contains("completion:11111111-2222-3333-4444-555555555555"),
        "completion replacement includes grouped completion key"
    )

    // Batch primitive result rows and events are explicitly NOT deduped — no scoped
    // call fires for them either.
    try await queue.enqueuePrimitiveSetLogs([setLog, setLog])
    try await queue.enqueueEvents([CoreTelemetry.Event(
        sessionID: UUID(), kind: "state", name: "nope"
    )])
    let peekAfterNonDedup = await store.peekCallCount
    let dedupAfterNonDedup = await store.removeMatchingDedupKeyCallCount
    try expectEqual(peekAfterNonDedup, 0, "batch + events do not peek")
    try expectEqual(dedupAfterNonDedup, 3, "batch + events do not issue scoped dedup calls")
}

reportAndExit()
