// HistoryPreviewSeed+Builders.swift
//
// Set-log / workout-item / tags builders split out of
// `HistoryPreviewSeed.swift` so the parent enum body stays under
// SwiftLint's `type_body_length` cap. Strictly private helpers — the
// enum's public surface (`makePreviewCache`, `makeSeed`, `PreviewSeed`)
// still lives in the main file.

#if DEBUG

import Foundation
import CoreDomain
import WorkoutCoreFoundation

extension HistoryPreviewSeed {

    static func encodeTags(_ tags: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(tags) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deterministic set_log timeline: 4 bench sets 3 minutes apart
    /// starting from `startedAt`, then 3 OHP sets 10 minutes later.
    static func makeSetLogs(
        primaryItemID: UUID,
        secondaryItemID: UUID,
        startedAt: Date
    ) -> [SetLog] {
        var setLogs: [SetLog] = []
        for i in 0..<4 {
            let completedAt = startedAt.addingTimeInterval(TimeInterval(i * 180))
            setLogs.append(SetLog(
                id: UUID(), workoutItemID: primaryItemID,
                performedExerciseID: nil, setIndex: i,
                reps: i == 3 ? 4 : 5, weight: 100, weightUnit: .kg,
                rir: i == 2 ? 1 : 2, isWarmup: false,
                startedAt: completedAt.addingTimeInterval(-60),
                completedAt: completedAt,
                notes: nil
            ))
        }
        let ohpStart = startedAt.addingTimeInterval(TimeInterval(4 * 180 + 600))
        for i in 0..<3 {
            let completedAt = ohpStart.addingTimeInterval(TimeInterval(i * 150))
            setLogs.append(SetLog(
                id: UUID(), workoutItemID: secondaryItemID,
                performedExerciseID: nil, setIndex: i,
                reps: i == 2 ? 6 : 8, weight: 52.5, weightUnit: .kg,
                rir: 2, isWarmup: false,
                startedAt: completedAt.addingTimeInterval(-45),
                completedAt: completedAt,
                notes: nil
            ))
        }
        return setLogs
    }
}

#endif
