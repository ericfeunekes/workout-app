// main.swift — entry point for `swift run CoreAutoregTests`.
//
// Covers the trigger-rule matrix (13 cases in the brief), the apply-path
// rules (manual-wins + done-is-frozen), and the load-precision invariant.

import Foundation
import CoreAutoreg
import CorePrescription

// A single "default" autoreg config reused across trigger tests. Individual
// tests override fields where the case requires a different threshold or step.
let defaultAutoreg = CorePrescription.Autoreg(
    targetRir: 2,
    overshootAt: 2,
    overshootStepKg: 2.5,
    undershootAt: 2,
    undershootStepKg: 2.5,
    applyTo: .remaining
)

// ===========================================================================
// 1. Overshoot fires.
// ===========================================================================
runCase("overshoot · targetRir=2, logged=4, overshootAt=2 → .up with +step") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 4,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .up)
    try expectEqual(p.newLoadKg, 102.5)
    if case .overshoot(let rirLogged, let target, let threshold) = p.reason {
        try expectEqual(rirLogged, 4)
        try expectEqual(target, 2)
        try expectEqual(threshold, 2)
    } else {
        throw ExpectationFailure(message: "expected .overshoot reason, got \(p.reason)", file: #file, line: #line)
    }
}

// ===========================================================================
// 2. Overshoot threshold edge.
// ===========================================================================
runCase("overshoot · logged=3 with overshootAt=2, target=2 → no fire (logged < target+threshold)") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 3,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    try expectEqual(proposal, nil)
}

runCase("overshoot · logged=4 with overshootAt=2, target=2 → fires") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 4,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .up)
}

// ===========================================================================
// 3. Undershoot-reps fires.
// ===========================================================================
runCase("undershoot · prescribed=5, logged=3, undershootAt=2 → .down with -step") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 3,
        loggedRir: nil,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
    try expectEqual(p.newLoadKg, 97.5)
    if case .undershootReps(let prescribed, let actual, let threshold) = p.reason {
        try expectEqual(prescribed, 5)
        try expectEqual(actual, 3)
        try expectEqual(threshold, 2)
    } else {
        throw ExpectationFailure(message: "expected .undershootReps reason, got \(p.reason)", file: #file, line: #line)
    }
}

// ===========================================================================
// 4. Undershoot-reps threshold edge.
// ===========================================================================
runCase("undershoot · prescribed=5, logged=4, undershootAt=2 → no fire (diff=1 < threshold)") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 4,
        loggedRir: 2,   // hit target — no overshoot, no failure
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    try expectEqual(proposal, nil)
}

runCase("undershoot · prescribed=5, logged=3, undershootAt=2 → fires") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 3,
        loggedRir: 2,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
}

// ===========================================================================
// 5. Hit-failure fires.
// ===========================================================================
runCase("hit-failure · loggedRir=0, targetRir=2 → .hitFailure, .down") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,   // hit the prescribed rep count but to failure
        loggedRir: 0,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
    try expectEqual(p.newLoadKg, 97.5)
    if case .hitFailure(let target) = p.reason {
        try expectEqual(target, 2)
    } else {
        throw ExpectationFailure(message: "expected .hitFailure reason, got \(p.reason)", file: #file, line: #line)
    }
}

// ===========================================================================
// 6. Hit-failure does not fire when target=0.
// ===========================================================================
runCase("hit-failure · loggedRir=0, targetRir=0 → no fire (target was failure)") {
    let zeroTarget = CorePrescription.Autoreg(
        targetRir: 0,
        overshootAt: 2,
        overshootStepKg: 2.5,
        undershootAt: 2,
        undershootStepKg: 2.5,
        applyTo: .remaining
    )
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 0,
        targetRir: 0,
        autoreg: zeroTarget,
        autoregHeld: false))
    try expectEqual(proposal, nil)
}

// ===========================================================================
// 7. Undershoot and hit-failure together → undershoot-reps wins.
// ===========================================================================
runCase("precedence · undershoot-reps + hit-failure → .undershootReps wins") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 3,    // -2 reps → undershoot fires
        loggedRir: 0,     // also 0 → hit-failure would fire alone
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
    if case .undershootReps(let prescribed, let actual, _) = p.reason {
        try expectEqual(prescribed, 5)
        try expectEqual(actual, 3)
    } else {
        throw ExpectationFailure(
            message: "expected .undershootReps (wins over .hitFailure), got \(p.reason)",
            file: #file, line: #line
        )
    }
}

// ===========================================================================
// 8. Autoreg held → no proposal.
// ===========================================================================
runCase("held · trigger condition met + autoregHeld=true → nil") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 4,    // would overshoot
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: true))
    try expectEqual(proposal, nil)
}

runCase("held · undershoot trigger + autoregHeld=true → nil") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 3,   // would undershoot
        loggedRir: nil,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: true))
    try expectEqual(proposal, nil)
}

// ===========================================================================
// 9. RIR null + no rep miss → no proposal.
// ===========================================================================
runCase("rir-null · no rep miss → no proposal") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: nil,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    try expectEqual(proposal, nil)
}

// ===========================================================================
// 10. RIR null + rep miss → undershoot-reps fires (overshoot can't fire on null).
// ===========================================================================
runCase("rir-null · rep miss → .undershootReps fires") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 3,
        loggedRir: nil,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
    if case .undershootReps = p.reason { } else {
        throw ExpectationFailure(message: "expected .undershootReps, got \(p.reason)", file: #file, line: #line)
    }
}

// ===========================================================================
// 11. Apply: overwrites up/down adjust but preserves manual.
// ===========================================================================
runCase("apply · adjusts [.up, nil, .manual, nil] + .down proposal → [.down, .down, .manual, .down]") {
    let sets: [SetPlan] = [
        SetPlan(setIndex: 1, loadKg: 100.0, reps: 5, done: false, adjust: .up),
        SetPlan(setIndex: 2, loadKg: 100.0, reps: 5, done: false, adjust: nil),
        SetPlan(setIndex: 3, loadKg: 110.0, reps: 5, done: false, adjust: .manual),
        SetPlan(setIndex: 4, loadKg: 100.0, reps: 5, done: false, adjust: nil),
    ]
    let proposal = AutoregProposal(
        direction: .down,
        newLoadKg: 97.5,
        reason: .undershootReps(prescribed: 5, actual: 3, threshold: 2)
    )
    let out = Autoreg.apply(proposal: proposal, to: sets)
    try expectEqual(out.count, 4)
    try expectEqual(out[0].adjust, .down)
    try expectEqual(out[0].loadKg, 97.5)
    try expectEqual(out[1].adjust, .down)
    try expectEqual(out[1].loadKg, 97.5)
    try expectEqual(out[2].adjust, .manual)
    try expectEqual(out[2].loadKg, 110.0, "manual set preserved")
    try expectEqual(out[3].adjust, .down)
    try expectEqual(out[3].loadKg, 97.5)
}

// ===========================================================================
// 12. Apply: skips done sets.
// ===========================================================================
runCase("apply · [done=true, done=false, done=false] → only remaining two updated") {
    let sets: [SetPlan] = [
        SetPlan(setIndex: 1, loadKg: 100.0, reps: 5, done: true,  adjust: nil),
        SetPlan(setIndex: 2, loadKg: 100.0, reps: 5, done: false, adjust: nil),
        SetPlan(setIndex: 3, loadKg: 100.0, reps: 5, done: false, adjust: nil),
    ]
    let proposal = AutoregProposal(
        direction: .up,
        newLoadKg: 102.5,
        reason: .overshoot(rirLogged: 4, targetRir: 2, threshold: 2)
    )
    let out = Autoreg.apply(proposal: proposal, to: sets)
    try expectEqual(out[0].loadKg, 100.0, "done set untouched")
    try expectEqual(out[0].adjust, nil, "done set's adjust untouched")
    try expectEqual(out[1].loadKg, 102.5)
    try expectEqual(out[1].adjust, .up)
    try expectEqual(out[2].loadKg, 102.5)
    try expectEqual(out[2].adjust, .up)
}

// ===========================================================================
// 13. Load precision.
// ===========================================================================
runCase("precision · overshootStepKg=2.5, prescribed=100.0 → exactly 102.5") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 4,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    // Exact equality — no epsilon. The step sizes (2.5, 5.0) are
    // representable exactly in binary floating point. If this ever breaks
    // we want to see it immediately, not paper over it with tolerance.
    try expectEqual(p.newLoadKg, 102.5)
    try expect(p.newLoadKg == 102.5, "exact double equality, got \(p.newLoadKg)")
}

runCase("precision · undershootStepKg=2.5, prescribed=100.0 → exactly 97.5") {
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 100.0,
        prescribedReps: 5,
        loggedReps: 3,
        loggedRir: nil,
        targetRir: 2,
        autoreg: defaultAutoreg,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.newLoadKg, 97.5)
    try expect(p.newLoadKg == 97.5, "exact double equality, got \(p.newLoadKg)")
}

// ===========================================================================
// 14. Negative-load clamp (bug-013).
// ===========================================================================
runCase("clamp · undershoot on prescribed=2.5 with step=5.0 → 0.0, not -2.5") {
    let bigStep = CorePrescription.Autoreg(
        targetRir: 2,
        overshootAt: 2,
        overshootStepKg: 5.0,
        undershootAt: 2,
        undershootStepKg: 5.0,
        applyTo: .remaining
    )
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 2.5,
        prescribedReps: 5,
        loggedReps: 3,
        loggedRir: nil,
        targetRir: 2,
        autoreg: bigStep,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
    try expectEqual(p.newLoadKg, 0.0)
    try expect(p.newLoadKg == 0.0, "clamped to zero, got \(p.newLoadKg)")
}

runCase("clamp · hit-failure on prescribed=4.0 with step=5.0 → 0.0, not -1.0") {
    let bigStep = CorePrescription.Autoreg(
        targetRir: 2,
        overshootAt: 2,
        overshootStepKg: 5.0,
        undershootAt: 2,
        undershootStepKg: 5.0,
        applyTo: .remaining
    )
    let proposal = Autoreg.propose(Autoreg.Input(
        prescribedLoadKg: 4.0,
        prescribedReps: 5,
        loggedReps: 5,
        loggedRir: 0,
        targetRir: 2,
        autoreg: bigStep,
        autoregHeld: false))
    guard let p = proposal else {
        throw ExpectationFailure(message: "expected proposal, got nil", file: #file, line: #line)
    }
    try expectEqual(p.direction, .down)
    try expectEqual(p.newLoadKg, 0.0)
    if case .hitFailure = p.reason {
        // ok
    } else {
        throw ExpectationFailure(message: "expected .hitFailure reason, got \(p.reason)", file: #file, line: #line)
    }
}

reportAndExit()
