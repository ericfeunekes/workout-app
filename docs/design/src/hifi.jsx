// Setmark — hi-fi straight_sets flow
// Phase: today → active → rest (edit-last, longpress swap) → complete → ledger

const { useState, useEffect, useRef, useMemo } = React;

// ─── Data ──────────────────────────────────────────────────────────────
// NOTE: The app is a dumb renderer. Thresholds + autoreg rules are set upstream
// in the program (backend). The client just applies them and notifies the user.
const WORKOUT = {
  name: "Push A",
  note: "Heavy upper — bench focus",
  blocks: [
    { id: "bench", name: "Barbell Bench Press", scheme: "straight_sets",
      sets: 4, reps: 5, load: 102.5, unit: "kg", rest: 180,
      targetRir: 2,
      autoreg: {
        overshootAt: 2,      // RIR ≥ target + 2 → bump
        overshootStep: 2.5,  // kg per trigger
        undershootAt: 2,     // reps missed by ≥ 2 OR failure → drop
        undershootStep: 2.5,
        applyTo: "remaining",
      },
      last: "5×5 @ 100 kg · RIR 2" },
    { id: "row", name: "Barbell Row", scheme: "straight_sets",
      sets: 3, reps: 8, load: 80, unit: "kg", rest: 120,
      targetRir: 1,
      autoreg: { overshootAt: 2, overshootStep: 2.5, undershootAt: 2, undershootStep: 2.5, applyTo: "remaining" },
      last: "3×8 @ 77.5 kg · RIR 1" },
    { id: "ohp", name: "Overhead Press", scheme: "straight_sets",
      sets: 3, reps: 6, load: 55, unit: "kg", rest: 150,
      targetRir: 2,
      autoreg: { overshootAt: 2, overshootStep: 2.5, undershootAt: 2, undershootStep: 2.5, applyTo: "remaining" },
      last: "3×6 @ 52.5 kg · RIR 2" },
    { id: "dip", name: "Weighted Dip", scheme: "straight_sets",
      sets: 3, reps: 10, load: 15, unit: "kg", rest: 120,
      targetRir: 1,
      autoreg: { overshootAt: 2, overshootStep: 2.5, undershootAt: 2, undershootStep: 2.5, applyTo: "remaining" },
      last: "3×10 @ BW+12.5 · RIR 1" },
  ],
};

// Mock session history — most recent first.
const HISTORY = [
  { date: "Fri Apr 11", program: "Push A", avgRir: 1.5, bw: 82.1, duration: 54,
    blocks: {
      bench: [{load:100,reps:5,rir:2},{load:100,reps:5,rir:2},{load:100,reps:5,rir:1},{load:100,reps:4,rir:0}],
      row:   [{load:77.5,reps:8,rir:1},{load:77.5,reps:8,rir:1},{load:77.5,reps:7,rir:0}],
      ohp:   [{load:52.5,reps:6,rir:2},{load:52.5,reps:6,rir:2},{load:52.5,reps:6,rir:1}],
      dip:   [{load:12.5,reps:10,rir:1},{load:12.5,reps:10,rir:1},{load:12.5,reps:9,rir:0}],
    } },
  { date: "Mon Apr 7", program: "Push A", avgRir: 2.0, bw: 81.9, duration: 51,
    blocks: {
      bench: [{load:97.5,reps:5,rir:2},{load:97.5,reps:5,rir:2},{load:97.5,reps:5,rir:2},{load:97.5,reps:5,rir:1}],
      row:   [{load:77.5,reps:8,rir:2},{load:77.5,reps:8,rir:1},{load:77.5,reps:8,rir:1}],
      ohp:   [{load:50,reps:6,rir:2},{load:50,reps:6,rir:2},{load:50,reps:6,rir:2}],
      dip:   [{load:12.5,reps:10,rir:2},{load:12.5,reps:10,rir:1},{load:12.5,reps:10,rir:1}],
    } },
  { date: "Fri Apr 4", program: "Push A", avgRir: 1.8, bw: 82.0, duration: 53,
    blocks: {
      bench: [{load:97.5,reps:5,rir:3},{load:97.5,reps:5,rir:2},{load:97.5,reps:5,rir:2},{load:97.5,reps:5,rir:2}],
      row:   [{load:75,reps:8,rir:2},{load:75,reps:8,rir:2},{load:75,reps:8,rir:1}],
      ohp:   [{load:50,reps:6,rir:2},{load:50,reps:6,rir:2},{load:50,reps:6,rir:1}],
      dip:   [{load:10,reps:10,rir:2},{load:10,reps:10,rir:2},{load:10,reps:10,rir:1}],
    } },
];

// Initial set-log state
const mkInitialLog = () => WORKOUT.blocks.map(b => ({
  id: b.id,
  autoregHeld: false, // user "undo" sets this and prevents further auto-adjusts
  sets: Array.from({length: b.sets}, (_, i) => ({
    i: i + 1, load: b.load, reps: b.reps, rir: null, done: false,
    // adjust is non-null only if this set's prescribed load/reps was changed
    // by autoreg or manual edit from a previous set. "up" | "down" | "manual"
    adjust: null,
  })),
}));

// Compute autoreg proposal for a just-completed set.
// Returns { direction, newLoad, reason } or null if no action needed.
function autoregProposal(block, justSet) {
  if (!block.autoreg) return null;
  const { targetRir } = block;
  const { overshootAt, overshootStep, undershootAt, undershootStep } = block.autoreg;
  // Compare against the set's *current* prescribed reps, not the original block
  // prescription — earlier autoreg/manual edits may have already changed it,
  // and "did you hit what was asked of you" is the question we care about.
  const prescribedReps = justSet.reps;

  // Overshoot: RIR is our strongest signal that the load was too light.
  // Check this FIRST — even if reps came in below original block reps, a high
  // RIR means the set was easy, not that the lifter failed.
  if (justSet.rir !== null && justSet.rir - targetRir >= overshootAt) {
    const steps = Math.floor((justSet.rir - targetRir) / overshootAt);
    return {
      direction: "up",
      newLoad: roundToPlate(justSet.load + overshootStep * steps),
      reason: `RIR ${justSet.rir} logged · target was ${targetRir}`,
    };
  }

  // Undershoot: failed to hit prescribed reps, OR hit failure when target > 0
  const repsMissed = prescribedReps - justSet.reps;
  if (repsMissed >= undershootAt || (justSet.rir === 0 && targetRir > 0)) {
    return {
      direction: "down",
      newLoad: roundToPlate(justSet.load - undershootStep),
      reason: repsMissed >= undershootAt
        ? `Missed ${repsMissed} reps (target ${prescribedReps})`
        : `Hit failure · target was RIR ${targetRir}`,
    };
  }

  return null;
}

function roundToPlate(kg) {
  return Math.round(kg / 2.5) * 2.5;
}

// ─── Root ──────────────────────────────────────────────────────────────
function App() {
  // Tweaks (persisted)
  const [tweaks, setTweaks] = useState(() => {
    try { return JSON.parse(localStorage.getItem("hifi_tweaks")) || DEFAULT_TWEAKS; }
    catch { return DEFAULT_TWEAKS; }
  });
  useEffect(() => { localStorage.setItem("hifi_tweaks", JSON.stringify(tweaks)); }, [tweaks]);

  // Route (persisted — matches system instructions)
  const [route, setRoute] = useState(() => localStorage.getItem("hifi_route") || "today");
  useEffect(() => { localStorage.setItem("hifi_route", route); }, [route]);

  // Log state (persisted)
  const [log, setLog] = useState(() => {
    try { return JSON.parse(localStorage.getItem("hifi_log")) || mkInitialLog(); }
    catch { return mkInitialLog(); }
  });
  useEffect(() => { localStorage.setItem("hifi_log", JSON.stringify(log)); }, [log]);

  // Active pointer (which block / which set)
  const [cursor, setCursor] = useState(() => {
    try { return JSON.parse(localStorage.getItem("hifi_cursor")) || {b: 0, s: 0}; }
    catch { return {b: 0, s: 0}; }
  });
  useEffect(() => { localStorage.setItem("hifi_cursor", JSON.stringify(cursor)); }, [cursor]);

  // Workout note
  const [workoutNote, setWorkoutNote] = useState(() =>
    localStorage.getItem("hifi_note") || "");
  useEffect(() => { localStorage.setItem("hifi_note", workoutNote); }, [workoutNote]);

  // Tweak listener protocol
  useEffect(() => {
    const handler = (e) => {
      const msg = e.data;
      if (!msg || typeof msg !== "object") return;
      if (msg.type === "__activate_edit_mode") setTweaksOpen(true);
      if (msg.type === "__deactivate_edit_mode") setTweaksOpen(false);
    };
    window.addEventListener("message", handler);
    window.parent.postMessage({type: "__edit_mode_available"}, "*");
    return () => window.removeEventListener("message", handler);
  }, []);

  const [tweaksOpen, setTweaksOpen] = useState(false);

  // Cross-screen modals
  const [planSheet, setPlanSheet] = useState(null); // block index
  const [historyDrawer, setHistoryDrawer] = useState(null); // "all" | block id

  const reset = () => {
    localStorage.removeItem("hifi_log");
    localStorage.removeItem("hifi_cursor");
    localStorage.removeItem("hifi_route");
    localStorage.removeItem("hifi_note");
    setLog(mkInitialLog());
    setCursor({b: 0, s: 0});
    setRoute("today");
    setWorkoutNote("");
  };

  const ctx = { tweaks, setTweaks, route, setRoute, log, setLog,
    cursor, setCursor, workoutNote, setWorkoutNote,
    planSheet, setPlanSheet, historyDrawer, setHistoryDrawer };

  return (
    <>
      <div className="header">
        <h1>Setmark — straight_sets hi-fi</h1>
        <p>Start → Active → Rest → Complete · Interactive</p>
      </div>

      <div className="device">
        <div className="island"></div>
        <div className="home"></div>
        <div className="screen">
          <StatusBar />
          <Router ctx={ctx} />
          <PlanSheet ctx={ctx} />
          <HistoryDrawer ctx={ctx} />
        </div>
      </div>

      <button className="reset-btn" onClick={reset}>↺ Reset demo</button>
      <div className="stage-caption">Real timer · Tap-editable cells · Longpress the primary action to swap</div>

      <Tweaks open={tweaksOpen} tweaks={tweaks} setTweaks={setTweaks}
        close={() => setTweaksOpen(false)} />
    </>
  );
}

const DEFAULT_TWEAKS = /*EDITMODE-BEGIN*/{
  "restStyle": "hero",
  "loadDisplay": "big",
  "rirInput": "picker",
  "showLastTime": true,
  "accent": "terracotta"
}/*EDITMODE-END*/;

// ─── Status bar ────────────────────────────────────────────────────────
function StatusBar() {
  return (
    <div className="status">
      <span>9:41</span>
      <span className="right">
        <span style={{letterSpacing: 1}}>•••</span>
        <span>􀙇</span>
        <span>􀛨</span>
      </span>
    </div>
  );
}

// ─── Router ────────────────────────────────────────────────────────────
function Router({ ctx }) {
  switch (ctx.route) {
    case "today":    return <Today ctx={ctx} />;
    case "active":   return <Active ctx={ctx} />;
    case "rest":     return <Rest ctx={ctx} />;
    case "complete": return <Complete ctx={ctx} />;
    default:         return <Today ctx={ctx} />;
  }
}

// ─── Today screen ──────────────────────────────────────────────────────
function Today({ ctx }) {
  const totalSets = WORKOUT.blocks.reduce((s, b) => s + b.sets, 0);
  return (
    <div className="content scroll">
      <div className="nav">
        <span className="back">Programs</span>
        <span className="title">Today</span>
        <span className="right">􀍡</span>
      </div>
      <div className="large-title">
        <h1>{WORKOUT.name}</h1>
        <div className="sub">Mon · 4 exercises · {totalSets} sets · ~58 min</div>
      </div>

      <div className="card">
        {WORKOUT.blocks.map((b, i) => {
          const planned = ctx.log[i].sets;
          const firstPend = planned.find(s => !s.done) || planned[0];
          return (
            <div className="wl-row" key={b.id} onClick={() => ctx.setPlanSheet(i)}>
              <div className="num">{String(i + 1).padStart(2, "0")}</div>
              <div className="name">
                {b.name}
                <div className="sub">{planned.length} × {firstPend.reps} @ {firstPend.load} {b.unit}</div>
              </div>
              <div className="chev">›</div>
            </div>
          );
        })}
      </div>

      <div style={{marginTop: 16}}>
        <div className="last-time tappable" style={{margin: "0 16px"}}
             onClick={() => ctx.setHistoryDrawer("all")}>
          <span className="lbl">Last session ›</span>
          Fri · Push A · RIR 1.5 avg · body 82.1 kg
        </div>
      </div>

      <div style={{flex: 1}}></div>

      <div style={{padding: "12px 16px 0"}}>
        <button className="btn primary tall" onClick={() => {
          ctx.setCursor({b: 0, s: 0});
          ctx.setRoute("active");
        }}>Start workout</button>
      </div>

      <TabBar active="today" />
    </div>
  );
}

function firstPending(log, bi) {
  const idx = log[bi].sets.findIndex(s => !s.done);
  return idx < 0 ? log[bi].sets.length - 1 : idx;
}

// ─── Active set screen ─────────────────────────────────────────────────
function Active({ ctx }) {
  const { b: bi, s: si } = ctx.cursor;
  const block = WORKOUT.blocks[bi];
  const setRow = ctx.log[bi].sets[si];
  const [lp, setLp] = useState(false);
  const [editSheet, setEditSheet] = useState(null); // "load" | "reps"
  const [pastEdit, setPastEdit] = useState(null); // { bi, si, field }
  const pressTimer = useRef(null);
  const pressedRef = useRef(false);

  const logSet = () => {
    pressedRef.current = false;
    // Mark the set done with its currently-prescribed values (which may have
    // been adjusted by autoreg or a prior manual edit).
    const next = structuredClone(ctx.log);
    next[bi].sets[si] = {
      ...next[bi].sets[si],
      rir: null,
      done: true,
    };
    ctx.setLog(next);
    ctx.setRoute("rest");
  };

  // Apply a manual edit with a scope selector
  const applyManualEdit = (field, value, scope) => {
    const next = structuredClone(ctx.log);
    const sets = next[bi].sets;
    if (scope === "this") {
      sets[si][field] = value;
      sets[si].adjust = "manual";
    } else { // "remaining" — includes current set
      for (let k = si; k < sets.length; k++) {
        if (!sets[k].done) {
          sets[k][field] = value;
          sets[k].adjust = "manual";
        }
      }
    }
    ctx.setLog(next);
    setEditSheet(null);
  };

  const startPress = () => {
    pressedRef.current = true;
    pressTimer.current = setTimeout(() => {
      if (pressedRef.current) setLp(true);
    }, 500);
  };
  const endPress = () => {
    pressedRef.current = false;
    clearTimeout(pressTimer.current);
  };

  const setsDone = ctx.log[bi].sets.filter(s => s.done).length;

  return (
    <div className="content">
      <div className="nav">
        <button className="back" onClick={() => ctx.setRoute("today")}>‹ Today</button>
        <span className="title">{String(bi + 1).padStart(2, "0")} of {WORKOUT.blocks.length}</span>
        <span className="right" onClick={() => ctx.setRoute("complete")}>End</span>
      </div>

      <div className="as-head">
        <div className="name">{block.name}</div>
        <div className="meta">Set {si + 1} of {block.sets} · Rest {Math.round(block.rest/60)}:{String(block.rest%60).padStart(2,"0")}</div>
      </div>

      <div className="progress-pips" style={{margin: "14px 0 0"}}>
        {ctx.log[bi].sets.map((s, i) => (
          <span key={i} className={`pip ${s.done ? "done" : i === si ? "current" : ""}`}></span>
        ))}
      </div>

      <div className="rx-block">
        <div className="load tap-edit" onClick={() => setEditSheet("load")}>
          {setRow.load}
          {setRow.adjust && (
            <span className={`adj-glyph ${setRow.adjust}`}>
              {setRow.adjust === "up" ? "↑" : setRow.adjust === "down" ? "↓" : "✎"}
            </span>
          )}
        </div>
        <div className="load-unit">{block.unit} · tap to edit</div>
        <div className="reps-line tap-edit" onClick={() => setEditSheet("reps")}>
          {setRow.reps} reps
        </div>
      </div>

      {ctx.tweaks.showLastTime && (
        <div className="last-time tappable" onClick={() => ctx.setHistoryDrawer(block.id)}>
          <span className="lbl">Last time — Fri ›</span>
          {block.last}
        </div>
      )}

      <div style={{flex: 1}}></div>

      <SetLedger block={block} log={ctx.log[bi]} current={si}
        onEditSet={(idx, field) => setPastEdit({bi, si: idx, field})} />

      <div className="footer-action">
        <button
          className="btn primary tall"
          style={{flex: 1}}
          onMouseDown={startPress}
          onMouseUp={endPress}
          onMouseLeave={endPress}
          onTouchStart={startPress}
          onTouchEnd={endPress}
          onClick={logSet}>
          Log set {si + 1}
        </button>
      </div>

      {lp && <LongpressMenu close={() => setLp(false)} block={block} ctx={ctx} />}

      {editSheet === "load" && (
        <ScopedNumPad title="Load" unit={block.unit} value={setRow.load} step={2.5}
          remainingCount={block.sets - si - 1}
          onSet={(v, scope) => applyManualEdit("load", v, scope)}
          close={() => setEditSheet(null)} />
      )}
      {editSheet === "reps" && (
        <ScopedNumPad title="Reps" value={setRow.reps} step={1}
          remainingCount={block.sets - si - 1}
          onSet={(v, scope) => applyManualEdit("reps", v, scope)}
          close={() => setEditSheet(null)} />
      )}

      <PastSetSheet ctx={ctx} edit={pastEdit} close={() => setPastEdit(null)} />
    </div>
  );
}

// Per-exercise mini ledger. Done rows are tappable: tap any cell to edit it.
// `onEditSet(setIdx, field)` is fired on cell tap.
function SetLedger({ block, log, current, onEditSet }) {
  return (
    <div className="ledger">
      <div className="head">
        <span>#</span><span>LOAD</span><span>REPS</span><span>RIR</span><span></span>
      </div>
      {log.sets.map((s, i) => {
        const cls = s.done ? "done" : i === current ? "current" : "pending";
        const glyph = s.adjust === "up" ? "↑"
          : s.adjust === "down" ? "↓"
          : s.adjust === "manual" ? "✎" : "";
        const canEdit = !!onEditSet;
        const canEditRir = canEdit && s.done; // RIR only exists after logging
        const cellClass = canEdit ? "lg-cell tappable" : "lg-cell";
        const rirClass = canEditRir ? "lg-cell tappable" : "lg-cell";
        return (
          <div key={i} className={`row ${cls}`}>
            <span>{i + 1}</span>
            <span className={cellClass}
                  onClick={canEdit ? () => onEditSet(i, "load") : undefined}>
              {s.load}
              {glyph && <span className={`adj-inline ${s.adjust}`}>{glyph}</span>}
            </span>
            <span className={cellClass}
                  onClick={canEdit ? () => onEditSet(i, "reps") : undefined}>
              {s.reps}
            </span>
            <span className={rirClass}
                  onClick={canEditRir ? () => onEditSet(i, "rir") : undefined}>
              {s.rir ?? "—"}
            </span>
            <span className="check">{s.done ? "✓" : ""}</span>
          </div>
        );
      })}
    </div>
  );
}

// ─── Scoped NumPad ─────────────────────────────────────────────────────
// Same as NumPadSheet but asks whether the edit applies to just this set
// or the remaining sets in this exercise.
function ScopedNumPad({ title, unit, value, step, remainingCount, onSet, close }) {
  const [val, setVal] = useState(String(value));
  const [scope, setScope] = useState(remainingCount > 0 ? "remaining" : "this");
  const press = (k) => {
    if (k === "⌫") setVal(v => v.slice(0, -1) || "0");
    else if (k === ".") { if (!val.includes(".")) setVal(v => v + "."); }
    else setVal(v => v === "0" ? k : v + k);
  };
  const nudge = (d) => setVal(v => String(+((+v + d).toFixed(2))));
  return (
    <>
      <div className="sheet-backdrop" onClick={close}></div>
      <div className="sheet">
        <div className="grab"></div>
        <div className="sheet-title">{title} {unit ? `(${unit})` : ""}</div>
        <div className="sheet-sub">Manual edit · will not autoreg further</div>
        <div style={{textAlign: "center", fontFamily: "var(--mono)",
          fontSize: 56, fontWeight: 200, letterSpacing: -2, margin: "4px 0 12px"}}>
          {val}
        </div>

        {remainingCount > 0 && (
          <div className="scope-row">
            <button className={`scope-btn ${scope === "this" ? "on" : ""}`}
              onClick={() => setScope("this")}>
              <span className="sc-t">This set only</span>
              <span className="sc-s">set in progress</span>
            </button>
            <button className={`scope-btn ${scope === "remaining" ? "on" : ""}`}
              onClick={() => setScope("remaining")}>
              <span className="sc-t">Remaining sets</span>
              <span className="sc-s">{remainingCount + 1} sets incl. this one</span>
            </button>
          </div>
        )}

        <div style={{display: "flex", gap: 8, margin: "10px 0"}}>
          <button className="btn ghost" onClick={() => nudge(-step)}>− {step}</button>
          <button className="btn ghost" onClick={() => nudge(step)}>+ {step}</button>
        </div>
        <div className="keypad">
          {["1","2","3","4","5","6","7","8","9",".","0","⌫"].map(k => (
            <div key={k} className="key" onClick={() => press(k)}>{k}</div>
          ))}
        </div>
        <div style={{marginTop: 10}}>
          <button className="btn primary" onClick={() => onSet(+val || 0, scope)}>
            Confirm · {scope === "this" ? "this set" : `${remainingCount + 1} sets`}
          </button>
        </div>
      </div>
    </>
  );
}

// ─── Longpress menu (swap / adjust load / skip) ────────────────────────
function LongpressMenu({ close, block, ctx }) {
  const skip = () => {
    const { b: bi, s: si } = ctx.cursor;
    const next = structuredClone(ctx.log);
    next[bi].sets[si].done = true;
    next[bi].sets[si].skipped = true;
    ctx.setLog(next);
    advance(ctx);
    close();
  };
  return (
    <>
      <div className="lp-backdrop" onClick={close}></div>
      <div className="lp-menu">
        <div className="head">{block.name}</div>
        <div className="item" onClick={() => { alert("Swap sheet opens here"); close(); }}>
          <span>Swap exercise</span><span className="meta">3 subs</span>
        </div>
        <div className="item" onClick={() => { alert("Load editor opens here"); close(); }}>
          <span>Adjust load for remaining sets</span>
        </div>
        <div className="item" onClick={() => { alert("Rest editor opens here"); close(); }}>
          <span>Change rest duration</span><span className="meta">{Math.round(block.rest/60)}:00</span>
        </div>
        <div className="item" onClick={skip}>
          <span>Skip this set</span>
        </div>
        <div className="item cancel" onClick={close}>Cancel</div>
      </div>
    </>
  );
}

// ─── Rest screen ───────────────────────────────────────────────────────
function Rest({ ctx }) {
  const { b: bi, s: si } = ctx.cursor;
  const block = WORKOUT.blocks[bi];
  // The set *just logged* is at si (we don't advance until they continue)
  const justSet = ctx.log[bi].sets[si];
  const [elapsed, setElapsed] = useState(0);
  const [sheet, setSheet] = useState(null); // "load" | "reps" | "rir"
  const [pastEdit, setPastEdit] = useState(null); // { bi, si, field }
  const startRef = useRef(Date.now());

  useEffect(() => {
    startRef.current = Date.now();
    setElapsed(0);
    const int = setInterval(() => {
      setElapsed(Math.floor((Date.now() - startRef.current) / 1000));
    }, 200);
    return () => clearInterval(int);
  }, [si, bi]);

  const remaining = Math.max(block.rest - elapsed, 0);
  const mmss = (s) => `${Math.floor(s/60)}:${String(Math.abs(s)%60).padStart(2,"0")}`;
  const overtime = elapsed > block.rest;

  const [autoreg, setAutoreg] = useState(null);
  // { direction, newLoad, reason, prevLoads: [...] }

  const updateLast = (patch) => {
    const next = structuredClone(ctx.log);
    next[bi].sets[si] = { ...next[bi].sets[si], ...patch };
    ctx.setLog(next);
  };

  // When RIR is picked, run the backend-supplied autoreg rule.
  const onPickRir = (v) => {
    const next = structuredClone(ctx.log);
    next[bi].sets[si] = { ...next[bi].sets[si], rir: v };

    const hasRemaining = si + 1 < block.sets;
    const held = next[bi].autoregHeld;
    const proposal = autoregProposal(block, next[bi].sets[si]);

    if (proposal && hasRemaining && !held) {
      // Apply immediately; user can Undo from banner.
      const prev = [];
      for (let k = si + 1; k < block.sets; k++) {
        if (!next[bi].sets[k].done) {
          prev.push({ i: k, load: next[bi].sets[k].load, adjust: next[bi].sets[k].adjust });
          next[bi].sets[k].load = proposal.newLoad;
          next[bi].sets[k].adjust = proposal.direction;
        }
      }
      setAutoreg({ ...proposal, prevLoads: prev });
    }

    ctx.setLog(next);
    setSheet(null);
  };

  const undoAutoreg = () => {
    if (!autoreg) return;
    const next = structuredClone(ctx.log);
    autoreg.prevLoads.forEach(p => {
      next[bi].sets[p.i].load = p.load;
      next[bi].sets[p.i].adjust = p.adjust;
    });
    next[bi].autoregHeld = true; // don't auto-adjust again this exercise
    ctx.setLog(next);
    setAutoreg(null);
  };

  const nextStep = () => {
    // If RIR not given, force the sheet
    if (justSet.rir === null) { setSheet("rir"); return; }
    advance(ctx);
  };

  return (
    <div className="content">
      <div className="nav">
        <button className="back" onClick={() => ctx.setRoute("active")}>‹ Back</button>
        <span className="title">Rest</span>
        <span className="right" onClick={() => ctx.setRoute("complete")}>End</span>
      </div>

      <div className="as-head" style={{paddingTop: 4}}>
        <div className="name" style={{fontSize: 22}}>{block.name}</div>
        <div className="meta">Set {si + 1} logged · Next up in ↓</div>
      </div>

      {autoreg && (
        <div className="autoreg-banner">
          <div className="ab-icon">{autoreg.direction === "up" ? "↑" : "↓"}</div>
          <div className="ab-body">
            <div className="ab-title">
              Next sets → {autoreg.newLoad} {block.unit}
            </div>
            <div className="ab-sub">{autoreg.reason}</div>
          </div>
          <button className="ab-undo" onClick={undoAutoreg}>Undo</button>
          <button className="ab-dismiss" onClick={() => setAutoreg(null)}>✓</button>
        </div>
      )}

      <div className="rest-hero">
        <div className="t-big" style={{color: overtime ? "var(--warn)" : undefined}}>
          {overtime ? "+" : ""}{mmss(overtime ? elapsed - block.rest : remaining)}
        </div>
        <div className="t-of">{overtime ? "over target" : `of ${mmss(block.rest)}`}</div>
      </div>

      <div className="just-did">
        <div className="lbl">Just did — tap to edit</div>
        <div className="cells">
          <div className={`editable ${sheet === "load" ? "active" : ""}`}
               onClick={() => setSheet("load")}>
            <span className="k">Load {block.unit}</span>
            <span className="v">{justSet.load}</span>
          </div>
          <div className={`editable ${sheet === "reps" ? "active" : ""}`}
               onClick={() => setSheet("reps")}>
            <span className="k">Reps</span>
            <span className="v">{justSet.reps}</span>
          </div>
          <div className={`editable ${sheet === "rir" ? "active" : ""}`}
               onClick={() => setSheet("rir")}>
            <span className="k">RIR</span>
            <span className="v" style={{color: justSet.rir === null ? "var(--ink-4)" : undefined}}>
              {justSet.rir ?? "—"}
            </span>
          </div>
        </div>
      </div>

      <SetLedger block={block} log={ctx.log[bi]} current={si + 1 < block.sets ? si + 1 : -1}
        onEditSet={(idx, field) => setPastEdit({bi, si: idx, field})} />

      <div style={{flex: 1}}></div>

      <div className="footer-action">
        <button className="btn ghost" style={{flex: 1}} onClick={() => setSheet("rir")}>
          {justSet.rir === null ? "Log RIR" : `RIR ${justSet.rir} ✓`}
        </button>
        <button className="btn primary" style={{flex: 2}} onClick={nextStep}>
          {isLastSetOverall(ctx) ? "Finish workout" : si + 1 >= block.sets ? `Next: ${WORKOUT.blocks[bi+1]?.name.split(" ")[0] ?? ""}` : `Start set ${si + 2}`}
        </button>
      </div>

      {sheet === "rir" && (
        <RirSheet
          value={justSet.rir}
          onPick={onPickRir}
          close={() => setSheet(null)}
          tweaks={ctx.tweaks}
        />
      )}
      {sheet === "load" && (
        <NumPadSheet
          title="Load"
          unit={block.unit}
          value={justSet.load}
          step={2.5}
          onSet={(v) => { updateLast({load: v}); setSheet(null); }}
          close={() => setSheet(null)}
        />
      )}
      {sheet === "reps" && (
        <NumPadSheet
          title="Reps"
          value={justSet.reps}
          step={1}
          onSet={(v) => { updateLast({reps: v}); setSheet(null); }}
          close={() => setSheet(null)}
        />
      )}

      <PastSetSheet ctx={ctx} edit={pastEdit} close={() => setPastEdit(null)} />
    </div>
  );
}

// ─── RIR Sheet ─────────────────────────────────────────────────────────
function RirSheet({ value, onPick, close, tweaks, title, subtitle }) {
  const opts = [
    {v: 0, l: "Failure"},
    {v: 1, l: "Grinder"},
    {v: 2, l: "Hard"},
    {v: 3, l: "Moderate"},
    {v: 4, l: "Easy"},
    {v: 5, l: "Very easy"},
  ];
  return (
    <>
      <div className="sheet-backdrop" onClick={close}></div>
      <div className="sheet">
        <div className="grab"></div>
        <div className="sheet-title">{title || "How hard was that set?"}</div>
        <div className="sheet-sub">{subtitle || "Reps in reserve · tap to confirm"}</div>
        <div className="rir-picker">
          {opts.map(o => (
            <div key={o.v}
                 className={`rk ${value === o.v ? "on" : ""}`}
                 onClick={() => onPick(o.v)}>
              {o.v}
              <span className="sub">{o.l}</span>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

// ─── NumPad Sheet ──────────────────────────────────────────────────────
function NumPadSheet({ title, unit, value, step, onSet, close }) {
  const [val, setVal] = useState(String(value));
  const press = (k) => {
    if (k === "⌫") setVal(v => v.slice(0, -1) || "0");
    else if (k === ".") { if (!val.includes(".")) setVal(v => v + "."); }
    else setVal(v => v === "0" ? k : v + k);
  };
  const nudge = (d) => setVal(v => String(+((+v + d).toFixed(2))));
  return (
    <>
      <div className="sheet-backdrop" onClick={close}></div>
      <div className="sheet">
        <div className="grab"></div>
        <div className="sheet-title">{title} {unit ? `(${unit})` : ""}</div>
        <div style={{textAlign: "center", fontFamily: "var(--mono)",
          fontSize: 56, fontWeight: 200, letterSpacing: -2, margin: "8px 0 14px"}}>
          {val}
        </div>
        <div style={{display: "flex", gap: 8, marginBottom: 10}}>
          <button className="btn ghost" onClick={() => nudge(-step)}>− {step}</button>
          <button className="btn ghost" onClick={() => nudge(step)}>+ {step}</button>
        </div>
        <div className="keypad">
          {["1","2","3","4","5","6","7","8","9",".","0","⌫"].map(k => (
            <div key={k} className="key" onClick={() => press(k)}>{k}</div>
          ))}
        </div>
        <div style={{marginTop: 10}}>
          <button className="btn primary" onClick={() => onSet(+val || 0)}>Confirm</button>
        </div>
      </div>
    </>
  );
}

// ─── Advance logic ─────────────────────────────────────────────────────
function advance(ctx) {
  const { b: bi, s: si } = ctx.cursor;
  const block = WORKOUT.blocks[bi];
  if (si + 1 < block.sets) {
    ctx.setCursor({b: bi, s: si + 1});
    ctx.setRoute("active");
  } else if (bi + 1 < WORKOUT.blocks.length) {
    ctx.setCursor({b: bi + 1, s: 0});
    ctx.setRoute("active");
  } else {
    ctx.setRoute("complete");
  }
}

function isLastSetOverall(ctx) {
  const { b: bi, s: si } = ctx.cursor;
  const block = WORKOUT.blocks[bi];
  return si + 1 >= block.sets && bi + 1 >= WORKOUT.blocks.length;
}

// Edit a previously-logged set. Corrective only — does NOT retrigger autoreg.
function editPastSet(ctx, bi, si, field, value) {
  const next = structuredClone(ctx.log);
  next[bi].sets[si][field] = value;
  // Mark as manually corrected (unless already marked with a stronger adjust).
  // We don't override autoreg up/down — those stay as-is to preserve history;
  // we only add "manual" if the set wasn't already adjust-tagged.
  if (!next[bi].sets[si].adjust) {
    next[bi].sets[si].adjust = "manual";
  }
  ctx.setLog(next);
}

// ─── Plan sheet (pre-workout exercise editor) ──────────────────────────
// Tap an exercise on Today → edit sets × reps × load for THIS session.
// Edits write to ctx.log (not the WORKOUT template) so they're session-local.
function PlanSheet({ ctx }) {
  const bi = ctx.planSheet;
  const [field, setField] = useState(null); // { si, key }
  if (bi === null || bi === undefined) return null;
  const block = WORKOUT.blocks[bi];
  const sets = ctx.log[bi].sets;
  const close = () => ctx.setPlanSheet(null);

  const edit = (si, key, v) => {
    const next = ctx.log.map((b, i) => {
      if (i !== bi) return b;
      return { ...b, sets: b.sets.map((s, j) =>
        j === si ? { ...s, [key]: v, adjust: s.done ? s.adjust : "manual" } : s) };
    });
    ctx.setLog(next);
  };

  const addSet = () => {
    const last = sets[sets.length - 1];
    const next = ctx.log.map((b, i) => {
      if (i !== bi) return b;
      return { ...b, sets: [...b.sets, {
        i: b.sets.length + 1, load: last.load, reps: last.reps,
        rir: null, done: false, adjust: "manual",
      }] };
    });
    ctx.setLog(next);
  };

  const removeSet = () => {
    if (sets.length <= 1) return;
    const next = ctx.log.map((b, i) => {
      if (i !== bi) return b;
      // Remove last set; if it's done, skip (shouldn't hit here pre-workout)
      if (b.sets[b.sets.length - 1].done) return b;
      return { ...b, sets: b.sets.slice(0, -1) };
    });
    ctx.setLog(next);
  };

  const startHere = () => {
    ctx.setCursor({b: bi, s: firstPending(ctx.log, bi)});
    ctx.setRoute("active");
    close();
  };

  return (
    <>
      <div className="sheet-backdrop" onClick={close}></div>
      <div className="sheet tall" style={{animation: "none", transform: "none", maxHeight: "82%", overflowY: "auto"}}>
        <div className="grab"></div>
        <div className="sheet-title">{block.name}</div>
        <div className="sheet-sub">Edit plan · {block.unit} · this session only</div>

        <div className="plan-row head">
          <span>#</span><span>LOAD</span><span>REPS</span><span>RIR</span>
        </div>
        {sets.map((s, i) => (
          <div key={i} className="plan-row">
            <span className="num">{i + 1}</span>
            <span className="lg-cell tappable"
                  onClick={() => !s.done && setField({si: i, key: "load"})}>
              {s.load}
            </span>
            <span className="lg-cell tappable"
                  onClick={() => !s.done && setField({si: i, key: "reps"})}>
              {s.reps}
            </span>
            <span className="lg-cell"
                  style={{color: s.done ? "var(--ink)" : "var(--ink-4)",
                          background: "transparent", border: "none"}}>
              {s.done ? s.rir ?? "—" : "—"}
            </span>
          </div>
        ))}

        <div style={{display: "flex", gap: 8, margin: "14px 0 6px"}}>
          <button className="btn ghost" onClick={removeSet}
                  disabled={sets.length <= 1 || sets[sets.length-1].done}>
            − set
          </button>
          <button className="btn ghost" onClick={addSet}>+ set</button>
        </div>

        <div style={{display: "flex", gap: 8, marginTop: 10}}>
          <button className="btn ghost" style={{flex: 1}} onClick={close}>Done</button>
          <button className="btn primary" style={{flex: 2}} onClick={startHere}>
            Start this exercise
          </button>
        </div>
      </div>

      {field && (
        <SimpleNumPad
          title={`Set ${field.si + 1} — ${field.key === "load" ? "Load" : "Reps"}`}
          subtitle="Editing plan · this session"
          unit={field.key === "load" ? block.unit : ""}
          value={sets[field.si][field.key]}
          step={field.key === "load" ? 2.5 : 1}
          onSet={(v) => { edit(field.si, field.key, v); setField(null); }}
          close={() => setField(null)}
        />
      )}
    </>
  );
}

// ─── History drawer ────────────────────────────────────────────────────
// Shows prior sessions. If scope is a block id, filters to that exercise.
function HistoryDrawer({ ctx }) {
  const scope = ctx.historyDrawer;
  const [expanded, setExpanded] = useState(0); // session index
  if (!scope) return null;
  const close = () => ctx.setHistoryDrawer(null);
  const blockFilter = scope === "all" ? null : scope;
  const block = blockFilter ? WORKOUT.blocks.find(b => b.id === blockFilter) : null;

  return (
    <>
      <div className="sheet-backdrop" onClick={close}></div>
      <div className="sheet tall" style={{animation: "none", transform: "none", maxHeight: "82%", overflowY: "auto"}}>
        <div className="grab"></div>
        <div className="sheet-title">{block ? block.name : "Recent sessions"}</div>
        <div className="sheet-sub">
          {block ? `History · ${HISTORY.length} sessions` : "Tap a session to expand"}
        </div>

        <div style={{margin: "0 -16px"}}>
          {HISTORY.map((ses, i) => {
            const isOpen = expanded === i;
            const exBlocks = blockFilter
              ? (ses.blocks[blockFilter] ? [[blockFilter, ses.blocks[blockFilter]]] : [])
              : Object.entries(ses.blocks);
            return (
              <div key={i} className={`hist-session ${isOpen ? "expanded" : ""}`}
                   onClick={() => setExpanded(isOpen ? -1 : i)}>
                <div className="date">{ses.date}</div>
                <div className="meta">
                  <b>{ses.program}</b> · RIR {ses.avgRir} avg · {ses.duration} min · body {ses.bw} kg
                </div>
                {isOpen && (
                  <div className="hist-detail" onClick={e => e.stopPropagation()}>
                    {exBlocks.length === 0 && (
                      <div className="hist-empty">Not performed</div>
                    )}
                    {exBlocks.map(([bid, rows]) => {
                      const bk = WORKOUT.blocks.find(b => b.id === bid);
                      return (
                        <div key={bid} className="ex-block">
                          <div className="ex-name">{bk?.name ?? bid}</div>
                          <div className="ex-sets">
                            {rows.map((r, j) => (
                              <div key={j}>
                                {j + 1}. {r.load} {bk?.unit} × {r.reps}
                                {r.rir != null ? ` · RIR ${r.rir}` : ""}
                              </div>
                            ))}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div style={{marginTop: 14}}>
          <button className="btn ghost" style={{width: "100%"}} onClick={close}>Close</button>
        </div>
      </div>
    </>
  );
}

// Sheet for editing a single past-set field. Chooses RIR picker or numpad.
function PastSetSheet({ ctx, edit, close }) {
  if (!edit) return null;
  const { bi, si, field } = edit;
  const block = WORKOUT.blocks[bi];
  const setRow = ctx.log[bi].sets[si];
  const subtitle = setRow.done
    ? "Correcting log · no autoreg"
    : "Editing plan · just this set";

  if (field === "rir") {
    return (
      <RirSheet
        value={setRow.rir}
        onPick={(v) => { editPastSet(ctx, bi, si, "rir", v); close(); }}
        close={close}
        tweaks={ctx.tweaks}
        title={`Set ${si + 1} — RIR`}
        subtitle={subtitle}
      />
    );
  }

  const unit = field === "load" ? block.unit : "";
  const step = field === "load" ? 2.5 : 1;
  return (
    <SimpleNumPad
      title={`Set ${si + 1} — ${field === "load" ? "Load" : "Reps"}`}
      subtitle={subtitle}
      unit={unit}
      value={setRow[field]}
      step={step}
      onSet={(v) => { editPastSet(ctx, bi, si, field, v); close(); }}
      close={close}
    />
  );
}

// NumPad without scope selector — used for corrective past-set edits.
function SimpleNumPad({ title, subtitle, unit, value, step, onSet, close }) {
  const [val, setVal] = useState(String(value));
  const press = (k) => {
    if (k === "⌫") setVal(v => v.slice(0, -1) || "0");
    else if (k === ".") { if (!val.includes(".")) setVal(v => v + "."); }
    else setVal(v => v === "0" ? k : v + k);
  };
  const nudge = (d) => setVal(v => String(+((+v + d).toFixed(2))));
  return (
    <>
      <div className="sheet-backdrop" onClick={close}></div>
      <div className="sheet">
        <div className="grab"></div>
        <div className="sheet-title">{title} {unit ? `(${unit})` : ""}</div>
        <div className="sheet-sub">{subtitle}</div>
        <div style={{textAlign: "center", fontFamily: "var(--mono)",
          fontSize: 56, fontWeight: 200, letterSpacing: -2, margin: "4px 0 12px"}}>
          {val}
        </div>
        <div style={{display: "flex", gap: 8, margin: "10px 0"}}>
          <button className="btn ghost" onClick={() => nudge(-step)}>− {step}</button>
          <button className="btn ghost" onClick={() => nudge(step)}>+ {step}</button>
        </div>
        <div className="keypad">
          {["1","2","3","4","5","6","7","8","9",".","0","⌫"].map(k => (
            <div key={k} className="key" onClick={() => press(k)}>{k}</div>
          ))}
        </div>
        <div style={{marginTop: 10}}>
          <button className="btn primary" onClick={() => onSet(+val || 0)}>Save</button>
        </div>
      </div>
    </>
  );
}

// ─── Completion ledger ─────────────────────────────────────────────────
function Complete({ ctx }) {
  const [recording, setRecording] = useState(false);
  const [open, setOpen] = useState(null); // block id
  const [pastEdit, setPastEdit] = useState(null); // { bi, si, field }
  const allDone = ctx.log.every(b => b.sets.every(s => s.done));

  const transcribe = () => {
    const samples = [
      "bench felt fast on the first two — bar speed off the chest is back",
      "left shoulder warmed up fine after set 1, no issues",
      "dips were the limiter, might drop to 10kg next time",
      "sleep was short last night, rir 1 felt like rir 0",
    ];
    return samples[Math.floor(Math.random() * samples.length)];
  };

  return (
    <div className="content scroll">
      <div className="nav">
        <button className="back" onClick={() => ctx.setRoute("today")}>‹ Today</button>
        <span className="title">Summary</span>
        <span className="right">Share</span>
      </div>

      <div className="large-title">
        <h1>{allDone ? "Workout complete" : "Workout ended"}</h1>
        <div className="sub">
          {WORKOUT.name} · 52 min · RIR 1.7 avg · {ctx.log.flatMap(b=>b.sets).filter(s=>s.done).length} sets logged
        </div>
      </div>

      <div className="card">
        {WORKOUT.blocks.map((b, i) => {
          const sets = ctx.log[i].sets;
          const done = sets.filter(s => s.done);
          const avgRir = done.length && done.every(s => s.rir !== null)
            ? (done.reduce((s, x) => s + x.rir, 0) / done.length).toFixed(1)
            : "—";
          const isOpen = open === b.id;
          return (
            <div key={b.id}>
              <div className="cl-group" onClick={() => setOpen(isOpen ? null : b.id)}>
                <div className="name">
                  <div className="title">{b.name}</div>
                  <div className="sets">
                    {done.map((s, j) => (
                      <span key={j}>
                        {s.load}×{s.reps}{s.rir !== null ? ` · ${s.rir}` : ""}
                        {j < done.length - 1 ? "   " : ""}
                      </span>
                    ))}
                    {!done.length && <span style={{color:"var(--ink-4)"}}>no sets logged</span>}
                  </div>
                </div>
                <div className="rir">
                  <div className="v">{avgRir}</div>
                  <div className="k">avg RIR</div>
                </div>
              </div>
              {isOpen && (
                <div style={{padding: "0 16px 14px"}}>
                  <SetLedger block={b} log={ctx.log[i]} current={-1}
                    onEditSet={(idx, field) => setPastEdit({bi: i, si: idx, field})} />
                </div>
              )}
            </div>
          );
        })}
      </div>

      <div className="voice-card" style={{marginTop: 16}}>
        <div className="row">
          <textarea
            placeholder="How did it feel? (tap mic to dictate)"
            value={ctx.workoutNote}
            onChange={(e) => ctx.setWorkoutNote(e.target.value)}
          />
          <div className={`mic ${recording ? "recording" : ""}`}
               onClick={() => {
                 if (recording) {
                   setRecording(false);
                   ctx.setWorkoutNote(n => (n ? n + " " : "") + transcribe());
                 } else setRecording(true);
               }}>
            {recording ? "■" : "●"}
          </div>
        </div>
        {recording && <div style={{fontFamily: "var(--mono)", fontSize: 10,
          color: "var(--accent-ink)", letterSpacing: 1.5,
          textTransform: "uppercase", marginTop: 8}}>Listening…</div>}
      </div>

      <div style={{padding: "16px 16px 0"}}>
        <button className="btn primary tall" onClick={() => {
          localStorage.removeItem("hifi_log");
          localStorage.removeItem("hifi_cursor");
          localStorage.removeItem("hifi_note");
          ctx.setRoute("today");
          ctx.setLog(mkInitialLog());
          ctx.setCursor({b: 0, s: 0});
          ctx.setWorkoutNote("");
        }}>Save & done</button>
      </div>

      <div style={{height: 24}}></div>

      <PastSetSheet ctx={ctx} edit={pastEdit} close={() => setPastEdit(null)} />
    </div>
  );
}

// ─── Tab bar (decorative) ──────────────────────────────────────────────
function TabBar({ active }) {
  const tabs = [
    {k:"today", g:"◉", l:"Today"},
    {k:"programs", g:"▤", l:"Programs"},
    {k:"history", g:"◷", l:"History"},
    {k:"profile", g:"○", l:"You"},
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

// ─── Tweaks panel ──────────────────────────────────────────────────────
function Tweaks({ open, tweaks, setTweaks, close }) {
  const set = (k, v) => {
    const next = {...tweaks, [k]: v};
    setTweaks(next);
    window.parent.postMessage({type: "__edit_mode_set_keys", edits: {[k]: v}}, "*");
  };
  return (
    <div className={`tweaks ${open ? "open" : ""}`}>
      <h3>Tweaks</h3>
      <div className="row-t">
        <span>Show "last time"</span>
        <input type="checkbox" checked={tweaks.showLastTime}
          onChange={e => set("showLastTime", e.target.checked)} />
      </div>
      <div className="row-t">
        <span>Accent</span>
        <select value={tweaks.accent} onChange={e => set("accent", e.target.value)}>
          <option value="terracotta">Terracotta</option>
          <option value="amber">Amber</option>
          <option value="chartreuse">Chartreuse</option>
          <option value="indigo">Indigo</option>
        </select>
      </div>
      <div className="row-t">
        <span>Load display</span>
        <select value={tweaks.loadDisplay} onChange={e => set("loadDisplay", e.target.value)}>
          <option value="big">Big numeral</option>
          <option value="inline">Inline with reps</option>
        </select>
      </div>
      <div style={{marginTop: 10, display: "flex", justifyContent: "flex-end"}}>
        <button onClick={close}>Close</button>
      </div>
    </div>
  );
}

// Apply accent tweak at runtime
function applyAccent(tweaks) {
  const map = {
    terracotta: "oklch(0.72 0.14 35)",
    amber: "oklch(0.78 0.14 75)",
    chartreuse: "oklch(0.82 0.17 110)",
    indigo: "oklch(0.68 0.16 265)",
  };
  document.documentElement.style.setProperty("--accent", map[tweaks.accent] || map.terracotta);
}

// Mount
const root = ReactDOM.createRoot(document.getElementById("root"));
function Mounted() {
  const [t, setT] = useState(() => {
    try { return JSON.parse(localStorage.getItem("hifi_tweaks")) || DEFAULT_TWEAKS; }
    catch { return DEFAULT_TWEAKS; }
  });
  useEffect(() => {
    const h = () => {
      try { setT(JSON.parse(localStorage.getItem("hifi_tweaks")) || DEFAULT_TWEAKS); } catch {}
    };
    window.addEventListener("storage", h);
    const int = setInterval(h, 400);
    return () => { window.removeEventListener("storage", h); clearInterval(int); };
  }, []);
  useEffect(() => applyAccent(t), [t]);
  return <App />;
}
root.render(<Mounted />);
