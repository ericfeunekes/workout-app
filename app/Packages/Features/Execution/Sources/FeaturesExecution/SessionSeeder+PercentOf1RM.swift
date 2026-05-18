// SessionSeeder+PercentOf1RM.swift
//
// qa-045 — percent_1rm resolver. The per-item seeders in
// `SessionSeeder.swift` + `SessionSeeder+RoundBased.swift` intentionally
// stay context-free: they read `item.prescriptionJSON` in isolation,
// which keeps them easy to unit-test and makes the zero-row / autoreg-
// parse-failure edge cases crisp. That isolation means a
// `.percentOf1RM(sets, reps, percent, _)` shape lands with
// `loadKg: nil` — the seeder has no idea what the item's 1RM is.
//
// Post-seed, we have the full `WorkoutContext` in hand (including the
// `userParameters` map AppBootstrap populated from the cache). This
// file walks the seeded `ItemLog`s and, for every `percent_1rm` row
// with a matching `one_rep_max_<exercise_id>_kg` user_parameter, rewrites the load
// via `latest * percent`. Rows without a matching key stay loadless
// so the Active view renders "BW" and the user can type a number.
//
// Key convention (matches the server + `docs/prescription.md` §
// "Percentage-based load"):
//
//   * `one_rep_max_<exercise_id>_kg`
//   * exercise_id is the lowercase UUID string for the exercise.
//
// Value scale: the stored 1RM is always in kg (per the key suffix),
// regardless of the user's weight-unit preference. The resolved
// SetPlan carries `unit = .kg` to match.

import Foundation
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

extension SessionSeeder {

    /// Walk the seeded ItemLogs and resolve `percent_1rm` loads against
    /// `context.userParameters`. Returns a new array — ItemLog is a
    /// value type; we rebuild each row's SetPlan list when any load
    /// resolves.
    static func resolvePercentOf1RM(
        items: [SessionState.ItemLog],
        context: WorkoutContext,
        parser: PrescriptionParser
    ) -> [SessionState.ItemLog] {
        items.map { itemLog in
            guard
                let item = findItem(itemID: itemLog.itemID, in: context),
                let percent = percentOf1RMFactor(
                    for: item,
                    parser: parser
                )
            else {
                return itemLog
            }
            let key = oneRMKey(forExerciseID: item.exerciseID)
            guard let oneRM = context.userParameters[key] else {
                // Key missing. Leave loadKg = nil so the hero shows "BW"
                // and the numpad opens blank.
                return itemLog
            }
            let resolved = (oneRM * percent).rounded(toPlaces: 2)
            let rewritten = itemLog.sets.map { set in
                // Preserve completed rows as-is; the resolver runs at
                // seed time so this is a belt-and-suspenders guard for
                // any future "re-seed after restore" path.
                guard !set.done else { return set }
                return SetPlan(
                    setIndex: set.setIndex,
                    loadKg: resolved,
                    unit: .kg,
                    reps: set.reps,
                    workTarget: set.workTarget,
                    done: set.done,
                    adjust: set.adjust,
                    rir: set.rir,
                    completedAt: set.completedAt,
                    durationSec: set.durationSec,
                    distanceM: set.distanceM,
                    hrAvgBpm: set.hrAvgBpm,
                    cadenceAvgSpm: set.cadenceAvgSpm,
                    startedAt: set.startedAt
                )
            }
            return SessionState.ItemLog(
                itemID: itemLog.itemID,
                autoregHeld: itemLog.autoregHeld,
                sets: rewritten,
                performedExerciseID: itemLog.performedExerciseID,
                overrides: itemLog.overrides
            )
        }
    }

    /// Derive the `one_rep_max_<exercise_id>_kg` user_parameter key.
    /// Exposed `static` + `internal` so tests can pin the contract.
    static func oneRMKey(forExerciseID exerciseID: ExerciseID) -> String {
        "one_rep_max_\(exerciseID.uuidString.lowercased())_kg"
    }

    // MARK: - Private

    /// Pull the percent fraction off an item's prescription, or nil if
    /// the shape isn't `percent_1rm` / the JSON won't parse.
    private static func percentOf1RMFactor(
        for item: WorkoutItem,
        parser: PrescriptionParser
    ) -> Double? {
        switch parser.parseTolerantOfAutoreg(prescriptionJSON: item.prescriptionJSON) {
        case .success(let p):
            if case .percentOf1RM(_, _, let percent, _) = p {
                return percent
            }
            return nil
        case .failure:
            return nil
        }
    }

    /// Find the WorkoutItem for the given id in the context's
    /// per-block item matrix. O(N) over items — fine for session-seed
    /// time; real workouts have <50 items total.
    private static func findItem(
        itemID: UUID,
        in context: WorkoutContext
    ) -> WorkoutItem? {
        for blockItems in context.itemsByBlock {
            if let hit = blockItems.first(where: { $0.id == itemID }) {
                return hit
            }
        }
        return nil
    }

}

private extension Double {
    /// Round to N decimal places. 96.000001 → 96.0; 96.0049 → 96.0;
    /// 96.005 → 96.01. Used to keep the resolved percent_1rm load
    /// display clean ("96 kg" instead of "96.00000001 kg").
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
