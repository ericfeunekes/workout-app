// Section 2 — 9 other timing modes

// Shared small chrome
function ModePhone({ mode, children, right }) {
  return (
    <Phone>
      <StatusRow/>
      <div className="nav">
        <span className="back">‹ End</span>
        <span className="pill accent" style={{fontSize: 9}}>{mode}</span>
        <span>{right || "•••"}</span>
      </div>
      {children}
      <TabBar active="Workout"/>
    </Phone>
  );
}

// ─── Superset ─────────────────────────────────────────────
function Superset() {
  return (
    <ModePhone mode="SUPERSET · A/B">
      <div style={{padding: "0 16px"}}>
        <div className="submeta" style={{padding: 0}}>Round 2 of 4</div>
      </div>

      <div style={{padding: "8px 16px 4px", borderLeft: "3px solid var(--accent)", margin: "4px 16px"}}>
        <div className="tiny">Now · A</div>
        <div className="hand" style={{fontSize: 24}}>DB Bench Press</div>
        <div className="small">60 lb × 10 · RPE 8</div>
      </div>

      <div style={{padding: "8px 16px 4px", margin: "10px 16px 0", opacity: 0.6}}>
        <div className="tiny">Next · B</div>
        <div className="hand" style={{fontSize: 18}}>Chest-supported Row</div>
        <div className="small">50 lb × 12 · RPE 8</div>
      </div>

      <div className="divider dashed"/>
      <div style={{padding: "0 16px", display:"flex", gap: 10, alignItems:"baseline"}}>
        <div className="big-num" style={{fontSize: 28}}>0:45</div>
        <div className="tiny">rest between exercises</div>
      </div>

      <LastTime summary="A: 55×10  B: 50×12  ·  3d ago"/>

      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Log A · Start B</div>
      </div>
    </ModePhone>
  );
}

// ─── Circuit ──────────────────────────────────────────────
function Circuit() {
  return (
    <ModePhone mode="CIRCUIT · 4 stations">
      <div style={{padding: "0 16px 4px"}}>
        <div className="submeta" style={{padding:0}}>Round 1 of 3</div>
      </div>

      <div style={{padding: "0 16px"}}>
        {[
          {i: 1, n: "Goblet Squat", r: "12 reps", on: false, done: true},
          {i: 2, n: "Push-Up", r: "AMRAP", on: true, done: false},
          {i: 3, n: "Ring Row", r: "12 reps", on: false, done: false},
          {i: 4, n: "Plank", r: ":45", on: false, done: false},
        ].map(s => (
          <div key={s.i} style={{
            display: "flex", gap: 10, alignItems: "center",
            padding: "10px 12px", margin: "6px 0",
            border: s.on ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
            borderRadius: 8,
            opacity: s.done ? 0.5 : 1,
          }}>
            <span className="tiny" style={{width: 14}}>{s.done ? "✓" : s.i}</span>
            <div style={{flex: 1}}>
              <div className="hand" style={{fontSize: s.on ? 18 : 15}}>{s.n}</div>
              <div className="small">{s.r}</div>
            </div>
            {s.on && <span className="pill accent">NOW</span>}
          </div>
        ))}
      </div>

      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Finish Push-Up →</div>
      </div>
    </ModePhone>
  );
}

// ─── EMOM ────────────────────────────────────────────────
function Emom() {
  return (
    <ModePhone mode="EMOM · 12 min">
      <div style={{padding: "0 16px"}}>
        <div className="submeta" style={{padding:0}}>Minute 5 of 12</div>
      </div>
      <Ring pct={0.72} t=":43" s="this minute"/>
      <div style={{textAlign: "center", padding: "0 16px"}}>
        <div className="hand" style={{fontSize: 22}}>10 Power Cleans @ 95</div>
        <div className="small">then rest remainder</div>
      </div>
      <div className="divider dashed"/>
      <div className="set-row head"><span>min</span><span>reps</span><span>finish</span><span>RPE</span><span/></div>
      <div className="set-row done"><span className="num-cell">1</span><span>10</span><span>:38</span><span>6</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">2</span><span>10</span><span>:42</span><span>7</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">3</span><span>10</span><span>:45</span><span>7</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">4</span><span>10</span><span>:48</span><span>8</span><span className="check"/></div>
      <div className="set-row current"><span className="num-cell">5</span><span>—</span><span>—</span><span>—</span><span className="check"/></div>
    </ModePhone>
  );
}

// ─── AMRAP ───────────────────────────────────────────────
function Amrap() {
  return (
    <ModePhone mode="AMRAP · 15 min">
      <div style={{padding: "12px 16px 0", textAlign: "center"}}>
        <div className="big-num" style={{fontSize: 56}}>8:24</div>
        <div className="tiny">remaining</div>
      </div>
      <div className="divider dashed"/>
      <div style={{textAlign: "center"}}>
        <div className="tiny">rounds completed</div>
        <div className="megareps" style={{fontSize: 80}}>4</div>
        <div className="small" style={{marginTop: -4}}>+ 6 reps</div>
      </div>
      <div style={{padding: "12px 16px"}}>
        <div className="small hand" style={{color: "var(--ink)"}}>1 round =</div>
        <div className="small">10 Pull-Ups · 15 Push-Ups · 20 Air Squats</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px", display: "flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>+ rep</div>
        <div className="btn accent" style={{flex: 2}}>+ 1 round</div>
      </div>
    </ModePhone>
  );
}

// ─── For Time ────────────────────────────────────────────
function ForTime() {
  return (
    <ModePhone mode="FOR TIME · 21-15-9">
      <div style={{padding: "12px 16px 0", textAlign: "center"}}>
        <div className="big-num" style={{fontSize: 56}}>4:12</div>
        <div className="tiny">elapsed</div>
      </div>
      <div className="divider dashed"/>
      <div style={{padding: "0 16px"}}>
        {[
          {r: "21", a: "Thrusters @ 95", on: false, done: true},
          {r: "21", a: "Pull-Ups", on: false, done: true},
          {r: "15", a: "Thrusters @ 95", on: true, done: false, left: 7},
          {r: "15", a: "Pull-Ups", on: false, done: false},
          {r: "9", a: "Thrusters @ 95", on: false, done: false},
          {r: "9", a: "Pull-Ups", on: false, done: false},
        ].map((s, i) => (
          <div key={i} style={{
            display: "flex", padding: "6px 0", gap: 10, alignItems: "center",
            borderTop: i === 0 ? "none" : "1px dashed var(--ink-4)",
            opacity: s.done ? 0.4 : 1,
          }}>
            <span className="big-num" style={{fontSize: 20, width: 30, color: s.on ? "var(--accent)" : "var(--ink-2)"}}>{s.r}</span>
            <span className="hand" style={{flex: 1, fontSize: s.on ? 17 : 14}}>{s.a}</span>
            {s.on && <span className="pill accent">{s.left} left</span>}
            {s.done && <span className="small">✓</span>}
          </div>
        ))}
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Tap reps (7 left)</div>
      </div>
    </ModePhone>
  );
}

// ─── Intervals (time-based) ──────────────────────────────
function Intervals() {
  return (
    <ModePhone mode="INTERVALS · 5 × 3:00 / 1:30">
      <div style={{padding: "0 16px 4px"}}>
        <div className="submeta" style={{padding: 0}}>Interval 3 of 5 · WORK</div>
      </div>
      <Ring pct={0.4} t="1:48" s="work"/>
      <div style={{textAlign: "center"}}>
        <div className="hand" style={{fontSize: 18}}>Target pace 6:40 /mi</div>
        <div className="tiny">then 1:30 easy</div>
      </div>
      <div className="divider dashed"/>
      <div style={{padding: "4px 16px"}}>
        <div className="set-row head"><span>#</span><span>time</span><span>dist</span><span>HR</span><span/></div>
        <div className="set-row done"><span className="num-cell">1</span><span>3:00</span><span>0.45mi</span><span>164</span><span className="check"/></div>
        <div className="set-row done"><span className="num-cell">2</span><span>3:00</span><span>0.44mi</span><span>171</span><span className="check"/></div>
        <div className="set-row current"><span className="num-cell">3</span><span>1:12</span><span>0.18</span><span>168</span><span className="check">—</span></div>
      </div>
    </ModePhone>
  );
}

// ─── Tabata ──────────────────────────────────────────────
function Tabata() {
  return (
    <ModePhone mode="TABATA · 8 × :20/:10">
      <div style={{padding: "12px 16px 0", textAlign: "center"}}>
        <div className="tiny">REST</div>
        <div className="megareps" style={{color: "var(--accent)"}}>0:07</div>
        <div className="tiny" style={{marginTop: 6}}>then :20 work · round 4 of 8</div>
      </div>

      <div style={{padding: "12px 16px"}}>
        <div style={{display: "flex", gap: 4}}>
          {[1,2,3,4,5,6,7,8].map(i => (
            <div key={i} style={{
              flex: 1, height: 28, borderRadius: 4,
              border: "1px solid var(--ink-4)",
              background: i < 4 ? "var(--accent)" : i === 4 ? "var(--ink-4)" : "transparent",
            }}/>
          ))}
        </div>
        <div className="small hand" style={{textAlign: "center", marginTop: 8}}>Burpees</div>
      </div>

      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="small" style={{textAlign: "center"}}>watch buzzes at every transition</div>
      </div>
    </ModePhone>
  );
}

// ─── Continuous ──────────────────────────────────────────
function Continuous() {
  return (
    <ModePhone mode="CONTINUOUS · Z2 ride">
      <div style={{padding: "12px 16px 0"}}>
        <div className="tiny">ELAPSED</div>
        <div className="big-num" style={{fontSize: 48}}>42:18</div>
        <div className="small">of 60:00 target</div>
      </div>
      <div style={{padding: "12px 16px"}}>
        <div style={{display:"flex", justifyContent:"space-between", padding:"6px 0", borderBottom:"1px dashed var(--ink-4)"}}>
          <span className="tiny">avg HR</span><span className="big-num" style={{fontSize: 18}}>138</span>
        </div>
        <div style={{display:"flex", justifyContent:"space-between", padding:"6px 0", borderBottom:"1px dashed var(--ink-4)"}}>
          <span className="tiny">zone</span><span className="hand">Z2 · 128–148</span>
        </div>
        <div style={{display:"flex", justifyContent:"space-between", padding:"6px 0"}}>
          <span className="tiny">distance</span><span className="big-num" style={{fontSize: 18}}>12.4 mi</span>
        </div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px", display: "flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Pause</div>
        <div className="btn accent" style={{flex: 1}}>End</div>
      </div>
    </ModePhone>
  );
}

// ─── Custom (arbitrary segments) ─────────────────────────
function Custom() {
  return (
    <ModePhone mode="CUSTOM · 4 segments">
      <div style={{padding: "0 16px 4px"}}>
        <div className="submeta" style={{padding: 0}}>Segment 2 of 4</div>
      </div>
      <div style={{padding: "0 16px"}}>
        {[
          {n: "Warmup spin", d: ":10:00", done: true},
          {n: "3 × 5 @ Z4 /2 easy", d: ":25:00", on: true},
          {n: "Tempo :15:00", d: ":15:00"},
          {n: "Cooldown", d: ":10:00"},
        ].map((s, i) => (
          <div key={i} style={{
            display: "flex", gap: 10, padding: "8px 10px", margin: "4px 0",
            border: s.on ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
            borderRadius: 8, alignItems: "center",
            opacity: s.done ? 0.45 : 1,
          }}>
            <span className="tiny" style={{width: 14}}>{s.done ? "✓" : i+1}</span>
            <div style={{flex: 1}}>
              <div className="hand" style={{fontSize: s.on ? 16 : 14}}>{s.n}</div>
              <div className="small">{s.d}</div>
            </div>
          </div>
        ))}
      </div>
      <div style={{padding: "4px 16px"}}>
        <Ring pct={0.25} t="6:08" s="in segment"/>
      </div>
    </ModePhone>
  );
}

// ─── Rest block ──────────────────────────────────────────
function RestBlock() {
  return (
    <ModePhone mode="REST BLOCK · 3:00">
      <div style={{textAlign: "center", padding: "20px 16px 0"}}>
        <div className="megareps" style={{fontSize: 110, color: "var(--accent)"}}>2:14</div>
        <div className="tiny">between blocks</div>
      </div>
      <div style={{padding: "16px 16px 0"}}>
        <div className="tiny" style={{marginBottom: 4}}>Up next</div>
        <div className="hand" style={{fontSize: 20}}>Block 3 · Accessory superset</div>
        <div className="small">DB Row + Face Pull · 3 rounds</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Start early</div>
      </div>
    </ModePhone>
  );
}

function ModesSection() {
  const items = [
    { num: "2.1", name: "Superset", tag: "A → B paired, shared round count.", pros: ["Current+Next always visible", "Logs per exercise"], cons: ["Dense when >2 paired"], cmp: <Superset/> },
    { num: "2.2", name: "Circuit", tag: "List of stations, current one lit.", pros: ["Clear position in sequence", "Any station count"], cons: ["Timer not hero — add inline if rest is timed"], cmp: <Circuit/> },
    { num: "2.3", name: "EMOM", tag: "Per-minute ring + history ledger.", pros: ["Shows if you're keeping pace", "Finish-time per minute is the signal"], cons: ["Needs buzz when minute flips"], cmp: <Emom/> },
    { num: "2.4", name: "AMRAP", tag: "Count-up clock, counter the hero.", pros: ["One tap = one round", "Manual rep fallback"], cons: ["Easy to miscount under fatigue"], cmp: <Amrap/> },
    { num: "2.5", name: "For Time", tag: "Chipper list with remaining reps.", pros: ["Works for 21-15-9 natively", "See what's left at a glance"], cons: ["Tap-to-decrement needs big targets"], cmp: <ForTime/> },
    { num: "2.6", name: "Intervals", tag: "Work ring, then rest ring, with HR.", pros: ["Pace target inline", "Past splits visible"], cons: ["Cover both time- and distance-based variants"], cmp: <Intervals/> },
    { num: "2.7", name: "Tabata", tag: "Huge timer, 8-round pips, nothing else.", pros: ["Sub-second glance", "Haptic at every transition"], cons: ["No per-round logging mid-flight"], cmp: <Tabata/> },
    { num: "2.8", name: "Continuous", tag: "Steady state; HR + zone + dist.", pros: ["Ambient data, no set concept", "Long-session friendly"], cons: ["Need zone-drift nudge later"], cmp: <Continuous/> },
    { num: "2.9", name: "Custom", tag: "Named segments, per-segment timer.", pros: ["Escape hatch for weird sessions", "Each segment is a mini mode"], cons: ["Most generic → least glanceable"], cmp: <Custom/> },
    { num: "2.10", name: "Rest block", tag: "Between-block countdown screen.", pros: ["What's next is prominent", "Start-early is one tap"], cons: ["Skip-with-haptic only"], cmp: <RestBlock/> },
  ];

  return (
    <Section
      title="2. The other 9 timing modes"
      kicker="stress-testing one layout system"
      intro="Each mode gets its own active-set screen. The shared pattern: nav bar tells you WHAT you're in, body is the glanceable state, bottom is the primary action. Mode name sits in an accent pill so you never forget what context you're in."
    >
      <div className="row">
        {items.map(it => (
          <Variant key={it.num} num={it.num} name={it.name} tagline={it.tag}
            notes={<Notes pros={it.pros} cons={it.cons}/>}>
            {it.cmp}
          </Variant>
        ))}
      </div>
    </Section>
  );
}

Object.assign(window, { ModesSection });
