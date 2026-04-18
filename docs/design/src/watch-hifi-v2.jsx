// WorkoutDB Watch hi-fi v2 — face specs + app
// Every face below is a plain JSON object. The backend could push these.

const { Face, FaceShell, Widgets, Slot } = window.WatchGrammar;
const { useState, useEffect } = React;

// ─── HELPERS ──────────────────────────────────────────────

const swipeEndPause = (onEnd, onPause) => ([
  { label: "Pause", icon: "II", tone: "muted", onClick: onPause },
  { label: "End", icon: "■", tone: "danger", onClick: onEnd },
]);

// ─── STRENGTH FACE SPECS ──────────────────────────────────

const specReady = (onTap) => ({
  header: [
    { kind: "kicker", text: "SET 3 / 4" },
    { kind: "exname", text: "Barbell Bench" },
  ],
  hero: { kind: "number", value: "102.5", unit: "kg", size: "mid" },
  stats: [
    { kind: "sub", text: "×5 · RIR 2" },
  ],
  footer: [
    { kind: "hr", bpm: 62 },
    { kind: "taphint", text: "Tap › start" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specActive = (elapsed, onTap) => ({
  header: [
    { kind: "kicker", text: "SET 3 / 4" },
    { kind: "exname", text: "Barbell Bench" },
  ],
  hero: { kind: "timer", seconds: elapsed, mode: "mmss", size: "big" },
  stats: [{ kind: "sub", text: "102.5 ×5 · target RIR 2" }],
  footer: [
    { kind: "hr", bpm: 138, zone: 4 },
    { kind: "taphint", text: "Tap › done" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specRirPick = (rir) => ({
  header: [
    { kind: "kicker", text: "SET 3 / 4 · RIR?" },
    { kind: "exname", text: "Barbell Bench" },
  ],
  hero: { kind: "number", value: rir, size: "big", tone: "accent" },
  stats: [{ kind: "sub", text: "Crown to adjust", tone: "muted" }],
  footer: [
    { kind: "taphint", text: "Tap › log" },
  ],
});

const specRest = (remaining, total) => ({
  layout: "ring",
  progress: { kind: "ring", pct: remaining / total },
  header: [{ kind: "kicker", text: "REST" }],
  hero: { kind: "timer", seconds: remaining, mode: "mmss", size: "big", tone: "accent" },
  footer: [
    { kind: "hr", bpm: 102 },
    { kind: "taphint", text: "Tap › skip" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specUpNext = () => ({
  header: [
    { kind: "kicker", text: "UP NEXT · 2 / 4" },
    { kind: "exname", text: "Barbell Row" },
  ],
  stats: [
    { kind: "sub", text: "3 sets · 77.5 kg × 8" },
    { kind: "sub", text: "Last · 75 × 8 · RIR 1", tone: "muted" },
  ],
  footer: [
    { kind: "hr", bpm: 82 },
    { kind: "taphint", text: "Tap › start" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specComplete = () => ({
  layout: "center",
  header: [{ kind: "kicker", text: "DONE", tone: "ok" }],
  hero: { kind: "number", value: "Push A", size: "mid" },
  stats: [
    { kind: "sub", text: "4 exercises · 54 min" },
    { kind: "sub", text: "RIR 1.5 avg", tone: "muted" },
  ],
  footer: [{ kind: "hr", bpm: 84 }],
});

const specSuperset = () => ({
  header: [
    { kind: "kicker", text: "SUPERSET · 2/4" },
    { kind: "exname", text: "DB Bench" },
  ],
  hero: { kind: "number", value: "60", unit: "× 10", size: "mid" },
  stats: [{ kind: "sub", text: "then · Row 50 × 12", tone: "muted" }],
  footer: [
    { kind: "hr", bpm: 148, zone: 4 },
    { kind: "taphint", text: "Tap › next" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specEmom = (seconds) => ({
  header: [
    { kind: "kicker", text: "EMOM · 5 / 12" },
    { kind: "exname", text: "10 Power Cleans @ 95" },
  ],
  hero: { kind: "timer", seconds, mode: "mmss", size: "big", tone: seconds < 15 ? "warn" : "ink" },
  stats: [{ kind: "sub", text: "next min → rest" }],
  footer: [
    { kind: "hr", bpm: 168, zone: 5 },
    { kind: "taphint", text: "Tap › done" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specAmrap = (round) => ({
  layout: "center",
  header: [
    { kind: "kicker", text: "AMRAP · 15 MIN" },
    { kind: "exname", text: "5 pull · 10 push · 15 sq" },
  ],
  hero: { kind: "number", value: round, size: "huge", tone: "accent" },
  stats: [{ kind: "sub", text: "rounds · 8:42 left" }],
  footer: [
    { kind: "hr", bpm: 158, zone: 4 },
    { kind: "taphint", text: "Tap › +1" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

const specForTime = () => ({
  header: [
    { kind: "kicker", text: "FOR TIME · 21-15-9" },
    { kind: "exname", text: "Round 2 · Thrusters" },
  ],
  hero: { kind: "timer", seconds: 12*60+4, mode: "mmss", size: "big", tone: "accent" },
  stats: [{ kind: "sub", text: "15 left this round" }],
  footer: [
    { kind: "hr", bpm: 152, zone: 4 },
    { kind: "taphint", text: "Tap › next" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// ─── RUNNING FACE SPECS ───────────────────────────────────
// Top metric priorities (per user): pace, distance, HR, elapsed, cadence

// Outdoor run — steady state, data-dense but legible
const specRunOutdoor = () => ({
  header: [{ kind: "kicker", text: "OUTDOOR RUN" }],
  hero: { kind: "pace", value: "5:12", unit: "/km", size: "big", tone: "accent" },
  stats: [
    { kind: "stat", label: "DIST", value: "3.6", unit: "km" },
    { kind: "stat", label: "TIME", value: "18:42" },
    { kind: "stat", label: "CAD", value: "176" },
  ],
  footer: [
    { kind: "hr", bpm: 158, zone: 3 },
    { kind: "taphint", text: "Tap › lap", tone: "muted" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// Treadmill — no GPS, manual pace entry · cadence + HR are the real signal
const specRunTreadmill = () => ({
  header: [{ kind: "kicker", text: "TREADMILL" }],
  hero: { kind: "pace", value: "5:30", unit: "/km", size: "big" },
  stats: [
    { kind: "stat", label: "DIST", value: "2.2", unit: "km" },
    { kind: "stat", label: "TIME", value: "12:00" },
    { kind: "stat", label: "CAD", value: "172" },
  ],
  footer: [
    { kind: "hr", bpm: 152, zone: 3 },
    { kind: "taphint", text: "Tap › lap", tone: "muted" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// Intervals · work phase
const specRunIntervalWork = (remaining = 45) => ({
  layout: "ring",
  progress: { kind: "ring", pct: remaining / 180, tone: "warn" },
  header: [
    { kind: "kicker", text: "INTERVAL 3 / 5 · WORK", tone: "warn" },
    { kind: "exname", text: "1 km @ 4:30" },
  ],
  hero: { kind: "pace", value: "4:28", unit: "/km", size: "big", tone: "warn" },
  stats: [
    { kind: "stat", label: "LEFT", value: "0.42", unit: "km" },
    { kind: "stat", label: "HR", value: "168" },
  ],
  footer: [
    { kind: "hr", bpm: 168, zone: 4 },
    { kind: "taphint", text: "Tap › skip" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// Intervals · recovery phase
const specRunIntervalRest = (remaining = 72) => ({
  layout: "ring",
  progress: { kind: "ring", pct: remaining / 120 },
  header: [
    { kind: "kicker", text: "INTERVAL 3 / 5 · REST" },
  ],
  hero: { kind: "timer", seconds: remaining, mode: "mmss", size: "big", tone: "accent" },
  stats: [{ kind: "sub", text: "next · 1 km @ 4:30", tone: "muted" }],
  footer: [
    { kind: "hr", bpm: 132, zone: 2 },
    { kind: "taphint", text: "Tap › skip" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// AMRAP run — max distance in X min
const specRunAmrap = () => ({
  header: [{ kind: "kicker", text: "AMRAP RUN · 20 MIN" }],
  hero: { kind: "number", value: "2.86", unit: "km", size: "big", tone: "accent" },
  stats: [
    { kind: "stat", label: "LEFT", value: "7:48" },
    { kind: "stat", label: "PACE", value: "5:18" },
    { kind: "stat", label: "HR", value: "162" },
  ],
  footer: [
    { kind: "hr", bpm: 162, zone: 4 },
    { kind: "taphint", text: "Tap › lap", tone: "muted" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// For-distance — 5K for time
const specRunForDistance = () => ({
  header: [{ kind: "kicker", text: "5K FOR TIME" }],
  hero: { kind: "timer", seconds: 18*60 + 42, mode: "mmss", size: "big" },
  stats: [
    { kind: "stat", label: "DIST", value: "3.74", unit: "km" },
    { kind: "stat", label: "PACE", value: "5:01" },
    { kind: "stat", label: "GOAL", value: "25:00", tone: "muted" },
  ],
  footer: [
    { kind: "hr", bpm: 164, zone: 4 },
    { kind: "taphint", text: "Tap › split", tone: "muted" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// Mixed block transition — "cardio up next"
const specBlockTransition = () => ({
  header: [
    { kind: "kicker", text: "UP NEXT · CARDIO" },
    { kind: "exname", text: "Zone 2 cool-down" },
  ],
  stats: [
    { kind: "sub", text: "20 min · HR 130–145" },
    { kind: "sub", text: "Treadmill or outdoor", tone: "muted" },
  ],
  footer: [
    { kind: "hr", bpm: 112 },
    { kind: "taphint", text: "Tap › start" },
  ],
  swipe: swipeEndPause(() => {}, () => {}),
});

// ─── FACE CATALOG (for switcher + gallery) ───────────────────

const CATALOG = [
  { group: "Strength · straight sets", items: [
    { id: "ready",    label: "Ready",    spec: () => specReady() },
    { id: "active",   label: "Active",   spec: (t) => specActive(t.elapsed || 24) },
    { id: "rir",      label: "RIR pick", spec: (t) => specRirPick(t.rir ?? 2) },
    { id: "rest",     label: "Rest",     spec: (t) => specRest(t.restRemaining ?? 84, 180) },
    { id: "upnext",   label: "Up next",  spec: () => specUpNext() },
    { id: "complete", label: "Complete", spec: () => specComplete() },
  ]},
  { group: "Strength · other schemes", items: [
    { id: "superset", label: "Superset", spec: () => specSuperset() },
    { id: "emom",     label: "EMOM",     spec: () => specEmom(43) },
    { id: "amrap",    label: "AMRAP",    spec: () => specAmrap(7) },
    { id: "fortime",  label: "For time", spec: () => specForTime() },
  ]},
  { group: "Cardio · running", items: [
    { id: "run_outdoor",    label: "Outdoor run",    spec: () => specRunOutdoor() },
    { id: "run_treadmill",  label: "Treadmill run",  spec: () => specRunTreadmill() },
    { id: "run_iv_work",    label: "Intervals · work", spec: () => specRunIntervalWork() },
    { id: "run_iv_rest",    label: "Intervals · rest", spec: () => specRunIntervalRest() },
    { id: "run_amrap",      label: "AMRAP run",      spec: () => specRunAmrap() },
    { id: "run_fordist",    label: "5K for time",    spec: () => specRunForDistance() },
  ]},
  { group: "Mixed workout", items: [
    { id: "block_next", label: "Block transition", spec: () => specBlockTransition() },
  ]},
];

const FLAT = CATALOG.flatMap(g => g.items.map(i => ({...i, group: g.group})));

// ─── INTERACTIVE WATCH + JSON INSPECTOR ──────────────────────

function InteractiveWatch() {
  const [id, setId] = useState(() => localStorage.getItem("watch2_id") || "ready");
  const [elapsed, setElapsed] = useState(0);
  const [restRemaining, setRestRemaining] = useState(90);
  const [rir, setRir] = useState(2);
  const [showJson, setShowJson] = useState(false);

  useEffect(() => { localStorage.setItem("watch2_id", id); }, [id]);

  // Active: elapsed ticks up
  useEffect(() => {
    if (id !== "active") { setElapsed(0); return; }
    const t = setInterval(() => setElapsed(e => e + 1), 1000);
    return () => clearInterval(t);
  }, [id]);

  // Rest: counts down
  useEffect(() => {
    if (id !== "rest") { setRestRemaining(90); return; }
    const t = setInterval(() => setRestRemaining(r => Math.max(0, r - 1)), 1000);
    return () => clearInterval(t);
  }, [id]);

  const item = FLAT.find(f => f.id === id) || FLAT[0];
  const spec = item.spec({ elapsed, restRemaining, rir });

  const specPretty = JSON.stringify(spec, null, 2);

  return (
    <div className="watch-wrap">
      <div className="watch">
        <span className="crown-hint">Crown ↕ adjust</span>
        <span className="button-hint">Swipe ← end/pause</span>
        <div className="screen">
          <FaceShell spec={spec} onTap={() => {
            // cycle to next in same group for demo
            const i = FLAT.findIndex(f => f.id === id);
            setId(FLAT[(i+1) % FLAT.length].id);
          }}/>
        </div>
      </div>

      <div className="state-label"><strong>{item.group} · {item.label}</strong></div>

      <div className="face-picker">
        {CATALOG.map(g => (
          <div key={g.group} className="face-picker-group">
            <div className="face-picker-groupname">{g.group}</div>
            <div className="face-picker-btns">
              {g.items.map(it => (
                <button key={it.id} className={id === it.id ? "active" : ""}
                  onClick={() => setId(it.id)}>{it.label}</button>
              ))}
            </div>
          </div>
        ))}
      </div>

      <div className="json-toggle">
        <button onClick={() => setShowJson(s => !s)}>
          {showJson ? "▼" : "▶"} Backend spec (JSON)
        </button>
        {showJson && (
          <pre className="json-inspector">{specPretty}</pre>
        )}
      </div>
    </div>
  );
}

// ─── GALLERY ────────────────────────────────────────────────

function Gallery() {
  return (
    <div className="gallery-v2">
      {CATALOG.map(g => (
        <React.Fragment key={g.group}>
          <div className="gallery-section">{g.group}</div>
          {g.items.map(it => {
            const spec = it.spec({ elapsed: 24, restRemaining: 72, rir: 2 });
            return (
              <div key={it.id} className="gallery-card">
                <div className="gallery-watch">
                  <div className="screen">
                    <Face spec={spec}/>
                  </div>
                </div>
                <div className="label">
                  <strong>{it.label}</strong>
                </div>
              </div>
            );
          })}
        </React.Fragment>
      ))}
    </div>
  );
}

// ─── APP ─────────────────────────────────────────────────────

function App() {
  return (
    <div className="layout-v2">
      <InteractiveWatch/>
      <div>
        <div className="gallery-header">
          <h1>All faces</h1>
          <p>Reference gallery · each is a JSON spec</p>
        </div>
        <Gallery/>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App/>);
