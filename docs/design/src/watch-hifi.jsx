// Setmark — Watch hi-fi
// Left: interactive watch cycling through a workout.
// Right: gallery of every face statically, for visual reference.

const { useState, useEffect, useRef } = React;

// ─── SHARED FACE PRIMITIVES ──────────────────────────────

function HRPulse({ bpm = 112, color }) {
  return (
    <span className="hr" style={color ? { color } : {}}>{bpm}</span>
  );
}

function Clock({ t = "9:41" }) {
  return <span className="time">{t}</span>;
}

// Countdown ring for rest
function RestRing({ pct, size = 260, stroke = 4 }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const dash = c * pct;
  return (
    <div className="ring-wrap">
      <svg viewBox={`0 0 ${size} ${size}`}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke="#242018" strokeWidth={stroke}/>
        <circle cx={size/2} cy={size/2} r={r} fill="none"
          stroke="var(--accent)" strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={`${dash} ${c}`}
          transform={`rotate(-90 ${size/2} ${size/2})`}/>
      </svg>
    </div>
  );
}

// ─── FACES ───────────────────────────────────────────────

// Set face · ready · "tap to start"
function FaceSetReady({ onTap, bpm = 62 }) {
  return (
    <div className="face" onClick={onTap}>
      <Clock/>
      <div className="kicker">SET 3 / 4</div>
      <div className="exname">Barbell Bench</div>
      <div className="hero mid">102.5<span className="unit">kg</span></div>
      <div className="sub">× 5 · RIR 2</div>
      <div className="footer">
        <HRPulse bpm={bpm}/>
        <span className="tap-hint accent">Tap › start</span>
      </div>
    </div>
  );
}

// Set face · active · in the set, HR climbing
function FaceSetActive({ onTap, elapsed = 18, bpm = 138 }) {
  return (
    <div className="face" onClick={onTap}>
      <Clock/>
      <div className="kicker">SET 3 / 4</div>
      <div className="exname">Barbell Bench</div>
      <div className="hero big">{Math.floor(elapsed/60)}:{String(elapsed%60).padStart(2,"0")}</div>
      <div className="sub">102.5 × 5 · target RIR 2</div>
      <div className="footer">
        <HRPulse bpm={bpm}/>
        <span className="tap-hint accent">Tap › done</span>
      </div>
    </div>
  );
}

// RIR picker — crown scrolls, tap confirms
function FaceRirPick({ onPick, rir = 2 }) {
  return (
    <div className="face">
      <Clock/>
      <div className="kicker">SET 3 / 4 · RIR?</div>
      <div className="exname" style={{opacity: 0.4}}>Barbell Bench</div>
      <div className="hero mid" style={{fontSize: 72, marginTop: 18, color: "var(--accent)"}}>{rir}</div>
      <div className="rir-dots">
        {[0,1,2,3,4,5].map(n => (
          <div key={n} className={"dot " + (n === rir ? "selected" : "")}
            onClick={() => onPick(n)}>{n}</div>
        ))}
      </div>
      <div className="footer">
        <span className="tap-hint">Crown to adjust</span>
        <span className="tap-hint accent">Tap › log</span>
      </div>
    </div>
  );
}

// Rest face · big countdown + ring
function FaceRest({ remaining = 90, total = 180, onSkip, bpm = 102 }) {
  const mm = Math.floor(remaining / 60);
  const ss = String(remaining % 60).padStart(2, "0");
  return (
    <div className="face" onClick={onSkip}>
      <RestRing pct={remaining/total}/>
      <Clock/>
      <div className="kicker" style={{position: "relative", zIndex: 2}}>REST</div>
      <div className="hero big" style={{textAlign: "center", marginTop: "auto", marginBottom: "auto", fontSize: 64, color: "var(--accent)", position: "relative", zIndex: 2}}>
        {mm}:{ss}
      </div>
      <div className="footer" style={{position: "relative", zIndex: 2}}>
        <HRPulse bpm={bpm}/>
        <span className="tap-hint">Tap › skip</span>
      </div>
    </div>
  );
}

// Autoreg nudge — came from last set RIR
function FaceAutoreg({ onAccept, onHold, delta = "+2.5 kg", reason = "RIR 4 → bumping" }) {
  return (
    <div className="face">
      <Clock/>
      <div className="kicker">NEXT SET · BUMP</div>
      <div className="exname" style={{marginTop: 10, fontSize: 14}}>Barbell Bench</div>
      <div className="hero mid" style={{fontSize: 48, color: "var(--accent)", marginTop: 14}}>105<span className="unit">kg</span></div>
      <div className="sub" style={{color: "var(--ink-3)"}}>{reason}</div>
      <div className="dual" style={{marginTop: 16}}>
        <button className="primary" onClick={onAccept}>OK</button>
        <button className="secondary" onClick={onHold}>Hold</button>
      </div>
    </div>
  );
}

// Superset face · dual action
function FaceSuperset({ onNext, onEnd, bpm = 148 }) {
  return (
    <div className="face">
      <Clock/>
      <div className="kicker">SUPERSET · 2/4</div>
      <div className="exname">DB Bench</div>
      <div className="hero mid" style={{fontSize: 40}}>60<span className="unit">× 10</span></div>
      <div className="sub" style={{marginTop: 8, color: "var(--ink-3)"}}>then · Row 50 × 12</div>
      <div style={{marginTop: "auto", display: "flex", flexDirection: "column", gap: 8}}>
        <div style={{display: "flex", justifyContent: "flex-start"}}>
          <HRPulse bpm={bpm}/>
        </div>
        <div className="dual" style={{marginTop: 0}}>
          <button className="primary" onClick={onNext}>Next ›</button>
          <button className="secondary" onClick={onEnd}>End ››</button>
        </div>
      </div>
    </div>
  );
}

// EMOM face · current minute + rep target
function FaceEmom({ seconds = 43, bpm = 168, onTap }) {
  return (
    <div className="face" onClick={onTap}>
      <Clock/>
      <div className="kicker">EMOM · 5 / 12</div>
      <div className="exname">10 Power Cleans @ 95</div>
      <div className="hero big" style={{fontSize: 60, color: seconds < 15 ? "var(--warn)" : "var(--ink)"}}>:{String(seconds).padStart(2,"0")}</div>
      <div className="sub">next min → rest</div>
      <div className="footer">
        <HRPulse bpm={bpm} color="var(--warn)"/>
        <span className="tap-hint">Tap › done</span>
      </div>
    </div>
  );
}

// AMRAP — round counter, +1
function FaceAmrap({ round = 7, onBump, bpm = 158 }) {
  return (
    <div className="face" onClick={onBump}>
      <Clock/>
      <div className="kicker">AMRAP · 15 MIN</div>
      <div className="exname">5 pull · 10 push · 15 sq</div>
      <div className="hero huge" style={{fontSize: 92, color: "var(--accent)", textAlign: "center"}}>{round}</div>
      <div className="sub" style={{textAlign: "center"}}>rounds · 8:42 left</div>
      <div className="footer">
        <HRPulse bpm={bpm}/>
        <span className="tap-hint accent">Tap › +1</span>
      </div>
    </div>
  );
}

// For-time face · big NEXT
function FaceForTime({ elapsed = "12:04", onNext, bpm = 152 }) {
  return (
    <div className="face" onClick={onNext}>
      <Clock/>
      <div className="kicker">FOR TIME · 21-15-9</div>
      <div className="exname">Round 2 · Thrusters</div>
      <div className="hero big" style={{fontSize: 52, color: "var(--accent)"}}>{elapsed}</div>
      <div className="sub">15 left this round</div>
      <div className="footer">
        <HRPulse bpm={bpm}/>
        <span className="tap-hint accent">Tap › next</span>
      </div>
    </div>
  );
}

// Between-exercise / summary
function FaceUpNext({ onStart }) {
  return (
    <div className="face" onClick={onStart}>
      <Clock/>
      <div className="kicker">UP NEXT · 2 / 4</div>
      <div className="exname" style={{fontSize: 16, marginTop: 14}}>Barbell Row</div>
      <div className="sub" style={{marginTop: 8}}>3 sets · 77.5 kg × 8</div>
      <div className="sub" style={{color: "var(--ink-3)", marginTop: 6}}>Last time · 75 × 8 · RIR 1</div>
      <div className="footer">
        <HRPulse bpm={82}/>
        <span className="tap-hint accent">Tap › start</span>
      </div>
    </div>
  );
}

// Workout complete
function FaceComplete() {
  return (
    <div className="face complete">
      <Clock/>
      <div className="kicker" style={{color: "var(--ok)"}}>DONE</div>
      <div className="big">Push A</div>
      <div className="sub" style={{marginTop: 6}}>4 exercises · 54 min</div>
      <div className="sub" style={{marginTop: 16, color: "var(--ink-3)"}}>RIR 1.5 avg</div>
      <div className="footer" style={{borderTop: "none", justifyContent: "center"}}>
        <HRPulse bpm={84}/>
      </div>
    </div>
  );
}

// ─── INTERACTIVE FLOW ────────────────────────────────────

const FLOW = [
  { id: "ready", label: "Ready · pre-set" },
  { id: "active", label: "Active · in set" },
  { id: "rir", label: "RIR picker" },
  { id: "autoreg", label: "Autoreg nudge" },
  { id: "rest", label: "Rest" },
  { id: "upnext", label: "Up next" },
  { id: "complete", label: "Complete" },
];

function InteractiveWatch() {
  const [step, setStep] = useState(() => {
    return localStorage.getItem("watch_step") || "ready";
  });
  const [rir, setRir] = useState(2);
  const [restRemaining, setRestRemaining] = useState(90);
  const [setElapsed, setSetElapsed] = useState(0);

  useEffect(() => { localStorage.setItem("watch_step", step); }, [step]);

  // Advance elapsed during active
  useEffect(() => {
    if (step !== "active") { setSetElapsed(0); return; }
    const t = setInterval(() => setSetElapsed(e => e + 1), 1000);
    return () => clearInterval(t);
  }, [step]);

  // Tick rest countdown
  useEffect(() => {
    if (step !== "rest") { setRestRemaining(90); return; }
    const t = setInterval(() => setRestRemaining(r => Math.max(0, r - 1)), 1000);
    return () => clearInterval(t);
  }, [step]);

  const goto = (s) => setStep(s);

  let faceEl;
  if (step === "ready")   faceEl = <FaceSetReady onTap={() => goto("active")}/>;
  else if (step === "active")  faceEl = <FaceSetActive elapsed={setElapsed} onTap={() => goto("rir")}/>;
  else if (step === "rir")     faceEl = <FaceRirPick rir={rir} onPick={(n) => { setRir(n); setTimeout(() => goto("autoreg"), 120); }}/>;
  else if (step === "autoreg") faceEl = <FaceAutoreg onAccept={() => goto("rest")} onHold={() => goto("rest")}/>;
  else if (step === "rest")    faceEl = <FaceRest remaining={restRemaining} onSkip={() => goto("upnext")}/>;
  else if (step === "upnext")  faceEl = <FaceUpNext onStart={() => goto("complete")}/>;
  else if (step === "complete") faceEl = <FaceComplete/>;

  return (
    <div className="watch-wrap">
      <div className="watch">
        <span className="crown-hint">Crown ↕ adjust</span>
        <span className="button-hint">Side · menu</span>
        <div className="screen">{faceEl}</div>
      </div>
      <div className="state-label"><strong>{FLOW.find(f => f.id === step)?.label}</strong></div>
      <div className="controls">
        {FLOW.map(f => (
          <button key={f.id} className={step === f.id ? "active" : ""} onClick={() => goto(f.id)}>
            {f.label.split(" · ")[0]}
          </button>
        ))}
      </div>
    </div>
  );
}

// ─── GALLERY ─────────────────────────────────────────────

function GalleryCard({ label, sublabel, children }) {
  return (
    <div className="gallery-card">
      <div className="gallery-watch">
        <div className="screen">{children}</div>
      </div>
      <div className="label">
        <strong>{label}</strong>
        {sublabel}
      </div>
    </div>
  );
}

function Gallery() {
  return (
    <div className="gallery">

      <div className="gallery-section">Straight sets</div>

      <GalleryCard label="Ready" sublabel="Pre-set · tap starts">
        <FaceSetReady onTap={() => {}}/>
      </GalleryCard>

      <GalleryCard label="Active" sublabel="In set · HR climbing">
        <FaceSetActive elapsed={24} bpm={142}/>
      </GalleryCard>

      <GalleryCard label="RIR pick" sublabel="Crown scrolls · tap logs">
        <FaceRirPick rir={2} onPick={() => {}}/>
      </GalleryCard>

      <GalleryCard label="Autoreg" sublabel="RIR 4 → +2.5 kg next set">
        <FaceAutoreg onAccept={() => {}} onHold={() => {}}/>
      </GalleryCard>

      <GalleryCard label="Rest" sublabel="Countdown · ring depletes">
        <FaceRest remaining={84} total={180} onSkip={() => {}}/>
      </GalleryCard>

      <GalleryCard label="Up next" sublabel="Between exercises">
        <FaceUpNext onStart={() => {}}/>
      </GalleryCard>

      <GalleryCard label="Complete" sublabel="End of workout">
        <FaceComplete/>
      </GalleryCard>

      <div className="gallery-section">Other schemes</div>

      <GalleryCard label="Superset" sublabel="NEXT (primary) + END (skip-to-end)">
        <FaceSuperset onNext={() => {}} onEnd={() => {}}/>
      </GalleryCard>

      <GalleryCard label="EMOM" sublabel="Minute countdown · HR-led">
        <FaceEmom seconds={43} bpm={168} onTap={() => {}}/>
      </GalleryCard>

      <GalleryCard label="AMRAP" sublabel="Tap = +1 round">
        <FaceAmrap round={7} onBump={() => {}}/>
      </GalleryCard>

      <GalleryCard label="For time" sublabel="Tap = next round/exercise">
        <FaceForTime elapsed="12:04" onNext={() => {}}/>
      </GalleryCard>

    </div>
  );
}

// ─── APP ─────────────────────────────────────────────────

function App() {
  return (
    <div className="layout">
      <InteractiveWatch/>
      <div>
        <div className="header" style={{marginBottom: 28, marginTop: 0}}>
          <h1 style={{fontSize: 18}}>All faces</h1>
          <p>Reference gallery · static</p>
        </div>
        <Gallery/>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App/>);
