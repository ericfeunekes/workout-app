// Setmark — Execution Flow v2
// Today (block grouping) → Warmup → Working → Log Sheet → Rest → Rest Overtime
// Superset/circuit blocks render as grouped cards.
// Rest timer starts on "done" tap — not on log submit.

const { useState, useEffect, useRef } = React;

// ─── Data ───────────────────────────────────────────────────────────────
const WORKOUT = {
  name: "Push A — Chest & Shoulders",
  tags: ["push", "hypertrophy", "week 1"],
  blocks: [
    {
      id: "bench",
      mode: "straight_sets",
      exercises: [
        { id: "bench-ex", name: "Bench Press", sets: 4, reps: 8, load: 80, unit: "kg", targetRir: 2 },
      ],
      rest: 150,
    },
    {
      id: "superset-1",
      mode: "superset",
      rounds: 3,
      exercises: [
        { id: "incline-db", name: "Incline DB Press", sets: 3, reps: 10, load: 28, unit: "kg", targetRir: 2 },
        { id: "lateral-raise", name: "Lateral Raise", sets: 3, reps: 15, load: 10, unit: "kg", targetRir: 1 },
      ],
      rest: 90,
    },
    {
      id: "superset-2",
      mode: "superset",
      rounds: 3,
      exercises: [
        { id: "ohp", name: "OHP", sets: 3, reps: 8, load: 50, unit: "kg", targetRir: 2 },
        { id: "tricep-pushdown", name: "Tricep Pushdown", sets: 3, reps: 12, load: 25, unit: "kg", targetRir: 1 },
      ],
      rest: 90,
    },
  ],
};

// Flatten blocks into a sequence of (blockIdx, exerciseIdx, setNum) steps
// for the execution cursor. Superset rounds alternate exercises.
function buildExecutionSteps(blocks) {
  const steps = [];
  blocks.forEach((block, bi) => {
    if (block.mode === "straight_sets") {
      const ex = block.exercises[0];
      for (let s = 0; s < ex.sets; s++) {
        steps.push({ bi, ei: 0, setNum: s + 1, totalSets: ex.sets });
      }
    } else {
      // superset / circuit: interleave exercises across rounds
      for (let round = 0; round < block.rounds; round++) {
        block.exercises.forEach((ex, ei) => {
          steps.push({ bi, ei, setNum: round + 1, totalSets: block.rounds });
        });
      }
    }
  });
  return steps;
}

const STEPS = buildExecutionSteps(WORKOUT.blocks);

function fmtMmss(totalSeconds) {
  const abs = Math.abs(totalSeconds);
  const m = Math.floor(abs / 60);
  const s = abs % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function fmtSessionTime(totalSeconds) {
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

// ─── Root ────────────────────────────────────────────────────────────────
function App() {
  // "today" | "warmup" | "working" | "log" | "rest" | "overtime"
  const [screen, setScreen] = useState("today");
  const [stepIdx, setStepIdx] = useState(0);

  // Log: for each step, { load, reps, rir }
  const [stepLogs, setStepLogs] = useState({});

  // Session wall-clock (counts up from workout start, never stops)
  const [sessionSecs, setSessionSecs] = useState(0);
  const sessionStartRef = useRef(null);
  const sessionIntervalRef = useRef(null);

  // Warmup / working timer (counts up from state entry)
  const [phaseSecs, setPhaseSecs] = useState(0);
  const phaseStartRef = useRef(null);
  const phaseIntervalRef = useRef(null);

  // Rest timer: counts down from block.rest. Starts on "done" tap.
  const [restSecs, setRestSecs] = useState(0);
  const restStartRef = useRef(null);
  const restIntervalRef = useRef(null);
  const restTotalRef = useRef(0);

  // Log sheet state
  const [logReps, setLogReps] = useState(null);
  const [logRir, setLogRir] = useState(null);

  // Autoreg banner (shown on rest screen)
  const [autoregBanner, setAutoregBanner] = useState(null);

  const step = STEPS[stepIdx];
  const block = step ? WORKOUT.blocks[step.bi] : null;
  const ex = step ? block.exercises[step.ei] : null;

  // ── Session timer (starts once, never stops after workout begins) ──────
  const startSessionTimer = () => {
    if (sessionIntervalRef.current) return;
    sessionStartRef.current = Date.now() - sessionSecs * 1000;
    sessionIntervalRef.current = setInterval(() => {
      setSessionSecs(Math.floor((Date.now() - sessionStartRef.current) / 1000));
    }, 500);
  };

  // ── Phase timer (warmup / working) ────────────────────────────────────
  const startPhaseTimer = () => {
    clearInterval(phaseIntervalRef.current);
    setPhaseSecs(0);
    phaseStartRef.current = Date.now();
    phaseIntervalRef.current = setInterval(() => {
      setPhaseSecs(Math.floor((Date.now() - phaseStartRef.current) / 1000));
    }, 200);
  };

  const stopPhaseTimer = () => {
    clearInterval(phaseIntervalRef.current);
    phaseIntervalRef.current = null;
  };

  // ── Rest timer (starts on "done" tap) ─────────────────────────────────
  const startRestTimer = (totalSecs) => {
    clearInterval(restIntervalRef.current);
    restTotalRef.current = totalSecs;
    restStartRef.current = Date.now();
    setRestSecs(totalSecs);
    restIntervalRef.current = setInterval(() => {
      const elapsed = Math.floor((Date.now() - restStartRef.current) / 1000);
      setRestSecs(totalSecs - elapsed);
    }, 200);
  };

  const stopRestTimer = () => {
    clearInterval(restIntervalRef.current);
    restIntervalRef.current = null;
  };

  // ── Screen transitions ────────────────────────────────────────────────
  const goToToday = () => {
    stopPhaseTimer();
    stopRestTimer();
    clearInterval(sessionIntervalRef.current);
    sessionIntervalRef.current = null;
    setSessionSecs(0);
    setStepIdx(0);
    setStepLogs({});
    setAutoregBanner(null);
    setScreen("today");
  };

  const startWorkout = () => {
    startSessionTimer();
    setStepIdx(0);
    startPhaseTimer();
    setScreen("warmup");
  };

  const startSet = () => {
    startPhaseTimer();
    setScreen("working");
  };

  // "done" tap: stop phase timer, start rest timer, open log sheet
  const tapDone = () => {
    stopPhaseTimer();
    startRestTimer(block.rest);
    // Pre-fill log sheet with prescription
    setLogReps(ex.reps);
    setLogRir(null);
    setScreen("log");
  };

  // "save" in log sheet: commit log, go to rest
  const saveLog = () => {
    const key = `${stepIdx}`;
    setStepLogs(prev => ({
      ...prev,
      [key]: { load: ex.load, reps: logReps ?? ex.reps, rir: logRir ?? ex.targetRir },
    }));
    // Simple autoreg check: if RIR >= target+2, suggest bump
    if (logRir !== null && logRir - ex.targetRir >= 2) {
      setAutoregBanner({
        direction: "up",
        newLoad: ex.load + 2.5,
        reason: `RIR ${logRir} logged · target was ${ex.targetRir}`,
      });
    } else {
      setAutoregBanner(null);
    }
    setScreen("rest");
  };

  // Monitor rest timer: flip to overtime when it hits 0
  useEffect(() => {
    if (screen === "rest" && restSecs <= 0) {
      setScreen("overtime");
    }
  }, [restSecs, screen]);

  // "start set N" from rest/overtime
  const startNextSet = () => {
    stopRestTimer();
    const nextIdx = stepIdx + 1;
    if (nextIdx >= STEPS.length) {
      // Done
      stopPhaseTimer();
      setScreen("today");
      return;
    }
    setStepIdx(nextIdx);
    setAutoregBanner(null);
    startPhaseTimer();
    setScreen("working");
  };

  // The rest-screen rest value in seconds (negative when overtime)
  const restRemaining = restSecs; // already goes negative via the interval

  return (
    <>
      <div className="header">
        <h1>Setmark — Execution Flow v2</h1>
        <p>Today (block groups) · Warmup · Working · Log Sheet · Rest · Overtime</p>
      </div>

      <div className="device">
        <div className="island"></div>
        <div className="home"></div>
        <div className="screen">
          <StatusBar sessionSecs={sessionSecs} showSession={screen !== "today"} />
          {screen === "today" && (
            <TodayScreen onStart={startWorkout} />
          )}
          {screen === "warmup" && (
            <WarmupScreen
              ex={ex} block={block} step={step}
              phaseSecs={phaseSecs}
              onStartSet={startSet}
              onBack={goToToday}
            />
          )}
          {screen === "working" && (
            <WorkingScreen
              ex={ex} block={block} step={step}
              phaseSecs={phaseSecs}
              onDone={tapDone}
              onBack={goToToday}
            />
          )}
          {screen === "log" && (
            <LogScreen
              ex={ex} block={block} step={step}
              restSecs={restSecs}
              restTotal={block ? block.rest : 0}
              logReps={logReps} setLogReps={setLogReps}
              logRir={logRir} setLogRir={setLogRir}
              onSave={saveLog}
              onBack={() => setScreen("working")}
            />
          )}
          {(screen === "rest" || screen === "overtime") && (
            <RestScreen
              ex={ex} block={block} step={step}
              restSecs={restRemaining}
              restTotal={block ? block.rest : 0}
              overtime={screen === "overtime"}
              autoregBanner={autoregBanner}
              onDismissAutoreg={() => setAutoregBanner(null)}
              onNextSet={startNextSet}
              onBack={goToToday}
              stepIdx={stepIdx}
              totalSteps={STEPS.length}
              savedLog={stepLogs[String(stepIdx)]}
            />
          )}
        </div>
      </div>

      <button className="reset-btn" onClick={goToToday}>reset demo</button>
      <div className="stage-caption">
        today → warmup → working → log sheet → rest → overtime · rest timer starts on "done"
      </div>
    </>
  );
}

// ─── Status bar ──────────────────────────────────────────────────────────
function StatusBar({ sessionSecs, showSession }) {
  return (
    <div className="status">
      <span>9:41</span>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        {showSession && (
          <span style={{
            fontFamily: "var(--mono)", fontSize: 13, color: "var(--ink-3)",
            letterSpacing: 0, fontVariantNumeric: "tabular-nums",
          }}>
            {fmtSessionTime(sessionSecs)}
          </span>
        )}
        <span className="right">
          <span style={{ letterSpacing: 1 }}>•••</span>
          <span>􀙇</span>
          <span>􀛨</span>
        </span>
      </div>
    </div>
  );
}

// ─── Today screen ─────────────────────────────────────────────────────────
function TodayScreen({ onStart }) {
  const totalStraight = WORKOUT.blocks
    .filter(b => b.mode === "straight_sets")
    .reduce((acc, b) => acc + b.exercises[0].sets, 0);
  const supersetRounds = WORKOUT.blocks
    .filter(b => b.mode !== "straight_sets")
    .reduce((acc, b) => acc + b.rounds * b.exercises.length, 0);
  const totalSets = totalStraight + supersetRounds;

  return (
    <div className="content scroll">
      <div className="nav">
        <span className="back">Programs</span>
        <span className="title">Today</span>
        <span className="right">···</span>
      </div>
      <div className="large-title">
        <h1 style={{ fontSize: 26 }}>{WORKOUT.name}</h1>
        <div className="sub">
          {WORKOUT.tags.join(" · ")}
        </div>
      </div>

      {/* Block list */}
      <div style={{ display: "flex", flexDirection: "column", gap: 12, padding: "0 0 12px" }}>
        {WORKOUT.blocks.map((block, bi) => (
          <BlockCard key={block.id} block={block} index={bi} />
        ))}
      </div>

      <div style={{ flex: 1 }} />

      <div style={{ padding: "12px 16px 0" }}>
        <button className="btn primary tall" onClick={onStart}>
          start workout
        </button>
      </div>

      <TabBar active="today" />
    </div>
  );
}

// ─── Block card ───────────────────────────────────────────────────────────
// Straight sets: single row. Superset/circuit: grouped card with label.
function BlockCard({ block, index }) {
  const isGrouped = block.mode !== "straight_sets";
  const modeLabel = block.mode === "superset"
    ? `SUPERSET · ${block.rounds} ROUNDS`
    : `CIRCUIT · ${block.rounds} ROUNDS`;

  if (!isGrouped) {
    const ex = block.exercises[0];
    return (
      <div className="card">
        <div className="wl-row">
          <div className="num">{String(index + 1).padStart(2, "0")}</div>
          <div className="name">
            {ex.name}
            <div className="sub">
              {ex.sets} × {ex.reps} @ {ex.load} {ex.unit}
              <span style={{ color: "var(--ink-4)", marginLeft: 6 }}>
                · RIR {ex.targetRir}
              </span>
            </div>
          </div>
          <div className="chev">›</div>
        </div>
      </div>
    );
  }

  return (
    <div className="card" style={{ borderLeft: "3px solid var(--accent)" }}>
      {/* Superset header */}
      <div style={{
        padding: "10px 16px 8px",
        display: "flex", alignItems: "center", justifyContent: "space-between",
        borderBottom: "1px solid var(--stroke)",
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div className="num" style={{ color: "var(--ink-3)" }}>
            {String(index + 1).padStart(2, "0")}
          </div>
          <span style={{
            fontFamily: "var(--mono)", fontSize: 10, textTransform: "uppercase",
            letterSpacing: 1.5, color: "var(--accent-ink)",
            background: "var(--accent-soft)", padding: "3px 8px", borderRadius: 100,
          }}>
            {modeLabel}
          </span>
        </div>
        <div className="chev">›</div>
      </div>
      {/* Exercises within the group */}
      {block.exercises.map((ex, ei) => (
        <div key={ex.id} style={{
          padding: "11px 16px 11px 22px",
          borderTop: ei === 0 ? "none" : "1px solid var(--stroke)",
          display: "flex", alignItems: "center", gap: 10,
        }}>
          {/* vertical connector */}
          <div style={{
            width: 2, alignSelf: "stretch", minHeight: 20,
            background: "var(--stroke)", borderRadius: 2, flexShrink: 0,
          }} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 15, fontWeight: 500, letterSpacing: "-0.2px" }}>
              {ex.name}
            </div>
            <div style={{
              fontFamily: "var(--mono)", fontSize: 11, color: "var(--ink-3)", marginTop: 3,
            }}>
              {block.rounds} × {ex.reps} @ {ex.load} {ex.unit}
              <span style={{ color: "var(--ink-4)", marginLeft: 6 }}>· RIR {ex.targetRir}</span>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── Warmup screen ────────────────────────────────────────────────────────
// Counting-up "warmup" timer, prescription shown, "start set 1" CTA
function WarmupScreen({ ex, block, step, phaseSecs, onStartSet, onBack }) {
  return (
    <div className="content">
      <div className="nav">
        <button className="back" onClick={onBack}>‹ Today</button>
        <span className="title">
          {String(step.bi + 1).padStart(2, "0")} of {WORKOUT.blocks.length}
        </span>
        <span className="right" style={{ color: "var(--ink-3)", fontSize: 15 }}>End</span>
      </div>

      <div className="as-head">
        <div className="name">{ex.name}</div>
        <div className="meta">
          SET 1 OF {step.totalSets} · REST {fmtMmss(block.rest)}
        </div>
      </div>

      {/* Hero timer — counting up, accent color */}
      <div className="rest-hero" style={{ paddingTop: 24 }}>
        <div className="t-big" style={{ color: "var(--accent-ink)" }}>
          {fmtMmss(phaseSecs)}
        </div>
        <div className="t-of">warmup</div>
      </div>

      {/* Prescription */}
      <div className="rx-block" style={{ paddingTop: 8 }}>
        <div className="load" style={{ fontSize: 64 }}>{ex.load}</div>
        <div className="load-unit">{ex.unit}</div>
        <div className="reps-line">{ex.reps} reps · RIR {ex.targetRir}</div>
      </div>

      <div style={{ flex: 1 }} />

      <div className="footer-action">
        <button className="btn primary tall" style={{ flex: 1 }} onClick={onStartSet}>
          start set 1
        </button>
      </div>
    </div>
  );
}

// ─── Working screen ───────────────────────────────────────────────────────
// Counting-up "set time" timer, progress pips, "done" CTA
function WorkingScreen({ ex, block, step, phaseSecs, onDone, onBack }) {
  // Build pips across all sets for this exercise in this block
  const pips = Array.from({ length: step.totalSets }, (_, i) => {
    if (i < step.setNum - 1) return "done";
    if (i === step.setNum - 1) return "current";
    return "";
  });

  return (
    <div className="content">
      <div className="nav">
        <button className="back" onClick={onBack}>‹ Today</button>
        <span className="title">
          {String(step.bi + 1).padStart(2, "0")} of {WORKOUT.blocks.length}
        </span>
        <span className="right" style={{ color: "var(--ink-3)", fontSize: 15 }}>End</span>
      </div>

      <div className="as-head">
        <div className="name">{ex.name}</div>
        <div className="meta">
          SET {step.setNum} OF {step.totalSets} · REST {fmtMmss(block.rest)}
        </div>
      </div>

      <div className="progress-pips" style={{ marginTop: 14 }}>
        {pips.map((state, i) => (
          <span key={i} className={`pip ${state}`} />
        ))}
      </div>

      {/* Hero timer — counting up */}
      <div className="rest-hero" style={{ paddingTop: 20 }}>
        <div className="t-big" style={{ color: "var(--accent-ink)" }}>
          {fmtMmss(phaseSecs)}
        </div>
        <div className="t-of">set time</div>
      </div>

      {/* Prescription */}
      <div className="rx-block" style={{ paddingTop: 4 }}>
        <div className="load" style={{ fontSize: 64 }}>{ex.load}</div>
        <div className="load-unit">{ex.unit}</div>
        <div className="reps-line">{ex.reps} reps · RIR {ex.targetRir}</div>
      </div>

      <div style={{ flex: 1 }} />

      <div className="footer-action">
        <button className="btn primary tall" style={{ flex: 1 }} onClick={onDone}>
          done
        </button>
      </div>
    </div>
  );
}

// ─── Log sheet screen ─────────────────────────────────────────────────────
// Rest timer running in "background" (shown as a rest pill above the sheet).
// Reps numpad pre-filled, RIR picker, "save" CTA.
function LogScreen({
  ex, block, step,
  restSecs, restTotal,
  logReps, setLogReps,
  logRir, setLogRir,
  onSave, onBack,
}) {
  const overtime = restSecs < 0;
  const pips = Array.from({ length: step.totalSets }, (_, i) => {
    if (i < step.setNum - 1) return "done";
    if (i === step.setNum - 1) return "current";
    return "";
  });

  return (
    <div className="content" style={{ position: "relative" }}>
      <div className="nav">
        <button className="back" onClick={onBack}>‹ Back</button>
        <span className="title">Log set {step.setNum}</span>
        <span className="right" style={{ color: "var(--ink-3)", fontSize: 15 }}>End</span>
      </div>

      {/* Rest pill visible behind/above the sheet showing rest is counting */}
      <div style={{ padding: "4px 16px 0" }}>
        <div className="rest-pill">
          <span className="label">rest running</span>
          <span className="time" style={{
            color: overtime ? "var(--warn)" : "var(--accent-ink)",
          }}>
            {overtime ? "-" : ""}{fmtMmss(Math.abs(restSecs))}
          </span>
          <span className="of">of {fmtMmss(restTotal)}</span>
        </div>
      </div>

      <div style={{ padding: "6px 20px 0" }}>
        <div className="as-head" style={{ padding: 0 }}>
          <div className="name" style={{ fontSize: 22 }}>{ex.name}</div>
        </div>
        <div className="progress-pips" style={{ padding: 0, marginTop: 10 }}>
          {pips.map((state, i) => (
            <span key={i} className={`pip ${state}`} />
          ))}
        </div>
      </div>

      {/* Sheet-style log form — inlined (not overlay, simpler for this prototype) */}
      <div style={{
        margin: "14px 16px 0",
        background: "var(--surface)",
        border: "1px solid var(--stroke)",
        borderRadius: 20,
        padding: "16px 16px 20px",
      }}>
        <div className="grab" style={{ marginBottom: 14 }} />

        {/* Reps display + numpad */}
        <div style={{
          fontFamily: "var(--mono)", fontSize: 10, textTransform: "uppercase",
          letterSpacing: 1.5, color: "var(--ink-3)", marginBottom: 6,
        }}>
          reps
        </div>
        <div style={{
          textAlign: "center", fontFamily: "var(--mono)", fontSize: 56,
          fontWeight: 200, letterSpacing: -2, color: "var(--ink)",
          marginBottom: 12, fontVariantNumeric: "tabular-nums",
        }}>
          {logReps ?? ex.reps}
        </div>

        {/* Mini numpad — just +/- nudge and keys for the prototype */}
        <div style={{ display: "flex", gap: 8, marginBottom: 10 }}>
          <button className="btn ghost" onClick={() => setLogReps(r => Math.max(1, (r ?? ex.reps) - 1))}>
            − 1
          </button>
          <button className="btn ghost" onClick={() => setLogReps(r => (r ?? ex.reps) + 1)}>
            + 1
          </button>
        </div>
        <div className="keypad" style={{ marginBottom: 16 }}>
          {["1","2","3","4","5","6","7","8","9","","0","⌫"].map((k, i) => (
            k === "" ? <div key={i} /> :
            <div key={k + i} className="key" onClick={() => {
              if (k === "⌫") {
                setLogReps(r => {
                  const s = String(r ?? ex.reps).slice(0, -1);
                  return s ? parseInt(s, 10) : 0;
                });
              } else {
                setLogReps(r => {
                  const cur = r ?? ex.reps;
                  const s = cur === 0 ? k : String(cur) + k;
                  return parseInt(s, 10) || 0;
                });
              }
            }}>{k}</div>
          ))}
        </div>

        {/* RIR picker */}
        <div style={{
          fontFamily: "var(--mono)", fontSize: 10, textTransform: "uppercase",
          letterSpacing: 1.5, color: "var(--ink-3)", marginBottom: 8,
        }}>
          reps in reserve
        </div>
        <div className="rir-picker" style={{ marginBottom: 16 }}>
          {[{v:0,l:"failure"},{v:1,l:"grinder"},{v:2,l:"hard"},{v:3,l:"moderate"},{v:4,l:"easy"}].map(o => (
            <div key={o.v}
                 className={`rk ${logRir === o.v ? "on" : ""}`}
                 onClick={() => setLogRir(o.v)}>
              {o.v}
              <span className="sub">{o.l}</span>
            </div>
          ))}
        </div>

        <button className="btn primary" onClick={onSave}>
          save
        </button>
      </div>

      <div style={{ height: 24 }} />
    </div>
  );
}

// ─── Rest screen (+ overtime) ─────────────────────────────────────────────
function RestScreen({
  ex, block, step,
  restSecs, restTotal, overtime,
  autoregBanner, onDismissAutoreg,
  onNextSet, onBack,
  stepIdx, totalSteps,
  savedLog,
}) {
  const isLast = stepIdx + 1 >= totalSteps;

  const justLoad = savedLog?.load ?? ex.load;
  const justReps = savedLog?.reps ?? ex.reps;
  const justRir  = savedLog?.rir  ?? ex.targetRir;

  const pips = Array.from({ length: step.totalSets }, (_, i) => {
    if (i < step.setNum) return "done";
    if (i === step.setNum) return "current";
    return "";
  });

  const nextLabel = isLast
    ? "finish workout"
    : `start set ${step.setNum + 1}`;

  return (
    <div className="content">
      <div className="nav">
        <button className="back" onClick={onBack}>‹ Today</button>
        <span className="title">{ex.name}</span>
        <span className="right" style={{ color: "var(--ink-3)", fontSize: 15 }}>End</span>
      </div>

      <div className="as-head" style={{ paddingTop: 4 }}>
        <div className="name" style={{ fontSize: 22 }}>{ex.name}</div>
        <div className="meta">SET {step.setNum} LOGGED</div>
      </div>

      {/* Autoreg banner */}
      {autoregBanner && (
        <div className="autoreg-banner">
          <div className="ab-icon">{autoregBanner.direction === "up" ? "+" : "-"}</div>
          <div style={{ flex: 1 }}>
            <div className="ab-title">
              next sets → {autoregBanner.newLoad} {ex.unit}
            </div>
            <div className="ab-sub">{autoregBanner.reason}</div>
          </div>
          <button className="ab-undo" onClick={onDismissAutoreg}>undo</button>
          <button className="ab-dismiss" onClick={onDismissAutoreg}>✓</button>
        </div>
      )}

      {/* Rest hero timer */}
      <div className="rest-hero">
        <div className="t-big" style={{
          color: overtime ? "var(--warn)" : "var(--accent-ink)",
        }}>
          {overtime ? "-" : ""}{fmtMmss(Math.abs(restSecs))}
        </div>
        <div className="t-of" style={{ color: overtime ? "var(--warn)" : undefined }}>
          {overtime ? "over target" : `of ${fmtMmss(restTotal)}`}
        </div>
      </div>

      {/* Progress pips */}
      <div className="progress-pips">
        {pips.map((state, i) => (
          <span key={i} className={`pip ${state}`} />
        ))}
      </div>

      {/* Just-logged row */}
      <div className="just-did" style={{ marginTop: 14 }}>
        <div className="lbl">just logged · tap to edit</div>
        <div className="cells">
          <div className="editable">
            <span className="k">load {ex.unit}</span>
            <span className="v">{justLoad}</span>
          </div>
          <div className="editable">
            <span className="k">reps</span>
            <span className="v">{justReps}</span>
          </div>
          <div className="editable">
            <span className="k">RIR</span>
            <span className="v">{justRir}</span>
          </div>
        </div>
      </div>

      <div style={{ flex: 1 }} />

      <div className="footer-action">
        <button className="btn primary" style={{ flex: 1 }} onClick={onNextSet}>
          {nextLabel}
        </button>
      </div>
    </div>
  );
}

// ─── Tab bar ──────────────────────────────────────────────────────────────
function TabBar({ active }) {
  const tabs = [
    { k: "today",    g: "◉", l: "Today"    },
    { k: "programs", g: "▤", l: "Programs" },
    { k: "history",  g: "◷", l: "History"  },
    { k: "profile",  g: "○", l: "You"      },
  ];
  return (
    <div className="tabbar">
      {tabs.map(t => (
        <div key={t.k} className={`tab ${active === t.k ? "active" : ""}`}>
          <span className="glyph">{t.g}</span>{t.l}
        </div>
      ))}
    </div>
  );
}

// ─── Mount ────────────────────────────────────────────────────────────────
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
